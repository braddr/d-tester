module p_github_process_login;

import config;
import github_apis;
import mysql;
import serverd;
import utils;
import validate;

import std.base64;
import std.conv;
import std.json;
import std.range;

bool validateInput(string code, Appender!string outstr)
{
    if (!validateNonEmpty(code, "code", outstr))
        return false;

    return true;
}

bool getGithubAccessToken(string code, ref string access_token, Appender!string outstr)
{
    JSONValue jv;
    if (!github.getAccessToken(code, jv)) return false;

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

bool getGithubTranslation(string access_token, ref string username, ref long userid, Appender!string outstr)
{
    JSONValue jv;
    if (!github.getAccessTokenDetails(access_token, jv)) return false;

    userid = jv.object["user"].object["id"].integer;
    username = jv.object["user"].object["login"].str;

    return true;
}

extern(C) { int RAND_bytes(ubyte* buf, int num); }

bool createSession(string access_token, string username, long userid, ref string cookie)
{
    access_token = sql_quote(access_token);
    username = sql_quote(username);

    ubyte[(128 + 64) / 8] rawdata;
    if (RAND_bytes(rawdata.ptr, rawdata.length) != 1)
        return false;

    cookie = cast(string)Base64URL.encode(rawdata[0 .. (128/8)]);
    string csrf = cast(string)Base64URL.encode(rawdata[(128/8) .. $]);

    string redirect = "";

    sql_exec(text("insert into github_users values (", userid, ", \"", username, "\", false, \"", access_token, "\", \"", cookie, "\", \"", csrf, "\", null) on duplicate key update access_token = \"", access_token, "\", cookie = \"", cookie, "\", csrf = \"", csrf, "\", redirect = null"));

    return true;
}

string parsestate(string state)
{
    string parts[] = split(state, "|");

    return parts[0] ~ "?" ~ join(parts[1 .. $], "&");
}

// NOTE: expected to only be called by github's login processor
// TODO: replace ip address validation with something else
// TODO: use state to pass a unique string to prevent spoofing.  not terrible as is
//       since we turn around and ask github to expand the token right away and fail
//       if that doesn't work.
void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string sn = lookup(hash, "SERVER_NAME");
    string code = lookup(userhash, "code");
    string state = lookup(userhash, "state");

    auto tmpstr = appender!string();
    if (!validateInput(code, tmpstr))
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(tmpstr.data);
        return;
    }

    string ret;
    string urldata;

    string access_token;
    if (!getGithubAccessToken(code, access_token, tmpstr))
        goto Lsend;

    string username;
    long userid;
    if (!getGithubTranslation(access_token, username, userid, tmpstr))
        goto Lsend;

    string cookievalue;
    if (!createSession(access_token, username, userid, cookievalue))
        goto Lsend;

    ret = text("Set-Cookie: testerlogin=", cookievalue, "; domain=", sn, "; path=/test-results; HttpOnly; ", (getURLProtocol(hash) == "https" ? "Secure" : ""), "\n");
    writelog("  login returning: %s", ret);

    urldata = parsestate(state);

Lsend:
    outstr.put(text("Location: ", getURLProtocol(hash) , "://", sn, "/test-results/", urldata, "\n"));
    if (ret != "") outstr.put(ret);
    outstr.put("\n");
}

