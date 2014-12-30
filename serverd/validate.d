module validate;

import std.conv;
import std.format;
import std.range;

import mysql;
import utils;

bool validateNonEmpty(string str, string label, Appender!string outstr)
{
    if (str.empty)
    {
        formattedWrite(outstr, "bad input: missing %s\n", label);
        return false;
    }

    return true;
}

bool validateNumber(string strid)
{
    try
    {
        auto id = to!size_t(strid);
        return true;
    }
    catch(Throwable)
    {
        return false;
    }
}

bool validateAuthenticated(const ref string[string] userhash, ref string access_token, ref string userid, ref string username, Appender!string outstr)
{
    string cookie = lookup(userhash, "testerlogin");
    string csrf = lookup(userhash, "csrf");

    if (!validateNonEmpty(cookie, "testerlogin", outstr))
        return false;
    if (!validateNonEmpty(csrf, "csrf", outstr))
        return false;

    cookie = sql_quote(cookie);
    csrf = sql_quote(csrf);

    if (!getAccessTokenFromCookie(cookie, csrf, access_token, userid, username))
        return false;

    return true;
}

bool validate_raddr(ref string raddr, Appender!string outstr)
{
    auto tmpout = appender!string();
    if (!auth_check(raddr, tmpout))
    {
        outstr.put(tmpout.data);
        return false;
    }

    raddr = sql_quote(raddr);

    return true;
}

bool validate_knownhost(string raddr, ref string rname, ref string hostid, Appender!string outstr)
{
    if (!validateNonEmpty(raddr, "hostname", outstr)) return false;

    rname = sql_quote(rname);

    if (!sql_exec(text("select id from build_hosts where enabled=1 and name='", rname, "' and ipaddr='", raddr, "'")))
    {
        outstr.put("error executing sql, check error log\n");
        return false;
    }

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        outstr.put("bad input: hostname and ipaddr not recognized\n");
        return false;
    }

    hostid = rows[0][0];

    return true;
}

bool validate_platform(ref string platform, Appender!string outstr)
{
    if (!validateNonEmpty(platform, "os", outstr)) return false;

    platform = sql_quote(platform);

    // TODO: validate that the platform exists
    // TODO: validate host supports the platform

    return true;
}

bool validate_id(ref string id, string idname, Appender!string outstr)
{
    if (!validateNonEmpty(id, idname, outstr)) return false;
    if (!validateNumber(id))
    {
        formattedWrite(outstr, "bad input: invalid %s\n", idname);
        return false;
    }

    id = sql_quote(id);

    return true;
}

bool validate_testtype(ref string type, string clientver, Appender!string outstr)
{
    if (!validateNonEmpty(type, "type", outstr)) return false;
    if (!validateNumber(type))
    {
        outstr.put("bad input: invalid type\n");
        return false;
    }

    type = sql_quote(type);

    // TODO: bounce the type against the db to make sure it's a known type
    auto tt = to!ulong(type);
    if (clientver == "5")
    {
        if (!(tt == 1 || (tt >= 15 && tt <= 17)))
        {
            formattedWrite(outstr, "type must be 1, 15 .. 17");
            return false;
        }
        return true;
    }

    return false;
}

bool validate_clientver(ref string clientver, Appender!string outstr)
{
    if (!validate_id(clientver, "clientver", outstr))
        return false;

    switch (clientver)
    {
        case "5":
            return true;
        default:
            formattedWrite(outstr, "bad input: unknown clientver: %s\n", clientver);
            return false;
    }
}

