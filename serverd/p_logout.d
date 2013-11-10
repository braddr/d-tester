module p_logout;

import mysql;
import utils;
import validate;

import std.conv;
import std.range;

bool validateInput(ref string raddr, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;

    return true;
}

// TODO: replace ip address validation with something else
void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string raddr = lookup(hash, "REMOTE_ADDR");

    auto tmpstr = appender!string();
    if (!validateInput(raddr, tmpstr))
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(tmpstr.data);
        return;
    }

    // should exist, but don't fatal out if it doesn't
    string login = lookup(userhash, "testerlogin");
    if (validate_id(login, "testerlogin", tmpstr))
    {
        sql_exec(text("update github_users set access_token = null where id = ", login));
    }

    string sn = lookup(hash, "SERVER_NAME");
    outstr.put(text("Location: ", getURLProtocol(hash) , "://", sn, "/test-results/\n"));
    outstr.put(text("Set-Cookie: testerlogin=; domain=", sn, "; path=/test-results; Expires=Sat, 01 Jan 2000 00:00:00 GMT; HttpOnly; ", (getURLProtocol(hash) == "https" ? "Secure" : ""), "\n"));
    outstr.put("\n");
}

