module loggedin.logout;

import mysql;
import utils;
import validate;

import std.conv;
import std.range;

bool validateInput(ref string cookie, ref string csrf, Appender!string outstr)
{
    // must be sql safe, but may not actually have a value, and that's ok
    cookie = sql_quote(cookie);
    csrf = sql_quote(csrf);

    return true;
}

string parsestate(string state)
{
    string parts[] = split(state, "|");

    return parts[0] ~ "?" ~ join(parts[1 .. $], "&");
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string cookie = lookup(userhash, "testerlogin");
    string csrf = lookup(userhash, "csrf");
    string state = lookup(userhash, "state");

    string urldata = parsestate(state);

    auto tmpstr = appender!string();
    if (!validateInput(cookie, csrf, tmpstr))
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(tmpstr.data);
        return;
    }

    string sn = lookup(hash, "SERVER_NAME");
    string ret;

    // nothing we can do without a cookie and should not do anything without a csrf
    if (!cookie || !csrf)
        goto Lsend;

    // get the related data only if cookie and csrf exist and match
    string access_token, userid, username;
    if (!getAccessTokenFromCookie(cookie, csrf, access_token, userid, username))
        goto Lsend;

    sql_exec(text("update github_users set access_token = null, cookie = null, csrf = null where cookie = \"", cookie, "\" and csrf = \"", csrf, "\""));

    ret = text("Set-Cookie: testerlogin=; domain=", sn, "; path=/test-results; Expires=Sat, 01 Jan 2000 00:00:00 GMT; HttpOnly; ", (getURLProtocol(hash) == "https" ? "Secure" : ""), "\n");

Lsend:
    outstr.put(text("Location: ", getURLProtocol(hash) , "://", sn, "/test-results/", urldata, "\n"));
    if (ret != "") outstr.put(ret);
    outstr.put("\n");
}

