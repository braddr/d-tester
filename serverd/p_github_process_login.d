module p_github_process_login;

import config;
import github_apis;
import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.json;
import std.range;

bool validateInput(ref string raddr, string code, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validateNonEmpty(code, "code", outstr))
        return false;

    return true;
}

bool getGithubAccessToken(string code, ref string access_token, Appender!string outstr)
{
    JSONValue jv;
    if (!getAccessToken(code, jv)) return false;

    JSONValue* jv_ptr;

    jv_ptr = "error" in jv.object;
    string error = (jv_ptr && jv_ptr.type == JSON_TYPE.STRING) ? jv_ptr.str : null;
    if (error)
    {
        writelog("  github access_token api returned error: %s", error);
        return false;
    }

    jv_ptr = "token_type" in jv.object;
    if (!jv_ptr || jv_ptr.type != JSON_TYPE.STRING || jv_ptr.str != "bearer")
    {
        writelog("  github token_type not 'bearer' as expected: %s",
                (!jv_ptr ? "null" : (jv_ptr.type != JSON_TYPE.STRING ? "non-string" : jv_ptr.str)));
        return false;
    }

    jv_ptr = "access_token" in jv.object;
    if (!jv_ptr || jv_ptr.type != JSON_TYPE.STRING)
    {
        writelog("  github response doesn't include access_token: %s",
                (!jv_ptr ? "null" : "non-string"));
        return false;
    }

    access_token = jv_ptr.str;
    //string scopestr = jv.object["scope"].str;

    return true;
}

bool getGithubTranslation(string access_token, ref string cookievalue, Appender!string outstr)
{
    JSONValue jv;
    if (!getAccessTokenDetails(access_token, jv)) return false;

    string id = to!string(jv.object["user"].object["id"].integer);
    string login = jv.object["user"].object["login"].str;

    access_token = sql_quote(access_token);
    sql_exec(text("insert into github_users values (", id, ", \"", login, "\", false, \"", access_token, "\") on duplicate key update access_token = \"", access_token, "\""));

    cookievalue = id;

    return true;
}

// TODO: replace ip address validation with something else
// cookie contents needs to be much safer than just github uid
void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string raddr = lookup(hash, "REMOTE_ADDR");
    string sn = lookup(hash, "SERVER_NAME");
    string code = lookup(userhash, "code");

    auto tmpstr = appender!string();
    if (!validateInput(raddr, code, tmpstr))
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(tmpstr.data);
        return;
    }

    string ret;

    // TODO: use state to pass a unique string to prevent spoofing.  not terrible as is
    // since we turn around and ask github to expand the token right away and fail if
    // that doesn't work.

    string access_token;
    if (!getGithubAccessToken(code, access_token, tmpstr))
        goto Lsend;

    string cookievalue;
    if (!getGithubTranslation(access_token, cookievalue, tmpstr))
        goto Lsend;

    ret = text("Set-Cookie: testerlogin=", cookievalue, "; domain=", sn, "; path=/test-results; HttpOnly; ", (getURLProtocol(hash) == "https" ? "Secure" : ""), "\n");
    writelog("  login returning: %s", ret);

Lsend:
    outstr.put(text("Location: ", getURLProtocol(hash) , "://", sn, "/test-results/\n"));
    if (ret != "") outstr.put(ret);
    outstr.put("\n");
}

