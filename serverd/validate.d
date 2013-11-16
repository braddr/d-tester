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

bool validate_testtype(ref string type, Appender!string outstr)
{
    if (!validateNonEmpty(type, "type", outstr)) return false;
    if (!validateNumber(type))
    {
        outstr.put("bad input: invalid type\n");
        return false;
    }

    type = sql_quote(type);

    // TODO: bounce the type against the db to make sure it's a known type

    return true;
}

bool validate_clientver(ref string clientver, Appender!string outstr)
{
    if (!validate_id(clientver, "clientver", outstr))
        return false;

    switch (clientver)
    {
        case "1":
        case "2":
        case "3":
            return true;
        default:
            formattedWrite(outstr, "bad input: unknown clientver: %s\n", clientver);
            return false;
    }
}

