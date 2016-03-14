module validate;

import std.format : formattedWrite;
import std.range : Appender;

import mysql_client : sql_quote;

bool validateNonEmpty(string str, string label, Appender!string outstr)
{
    import std.range : empty;
    if (str.empty)
    {
        formattedWrite(outstr, "bad input: missing %s\n", label);
        return false;
    }

    return true;
}

bool validateNumber(string strid)
{
    import std.conv : to;
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
    import utils : getAccessTokenFromCookie, lookup;

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
    import utils : auth_check;
    import std.range : appender;

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
    import mysql_client;
    import std.conv : text;

    if (!validateNonEmpty(raddr, "hostname", outstr)) return false;

    rname = sql_quote(rname);

    Results r = mysql.query(text("select id from build_hosts where enabled=1 and name='", rname, "' and ipaddr='", raddr, "'"));

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        outstr.put("bad input: hostname and ipaddr not recognized\n");
        return false;
    }

    hostid = row[0];

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
    import std.conv : to;

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

