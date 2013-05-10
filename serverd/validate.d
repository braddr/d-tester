module validate;

import std.conv;
import std.format;
import std.range;

import mysql;
import utils;

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
    if (rname.empty)
    {
        outstr.put("bad input: missing hostname\n");
        return false;
    }

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
    if (platform.empty)
    {
        outstr.put("bad input: missing os\n");
        return false;
    }

    platform = sql_quote(platform);

    // TODO: validate that the platform exists
    // TODO: validate host supports the platform

    return true;
}

bool validate_id(ref string id, string idname, Appender!string outstr)
{
    if (id.empty)
    {
        formattedWrite(outstr, "bad input: no ", idname, "\n");
        return false;
    }
    if (!validateNumber(id))
    {
        formattedWrite(outstr, "bad input: invalid ", idname, "\n");
        return false;
    }

    id = sql_quote(id);

    return true;
}

bool validate_testtype(ref string type, Appender!string outstr)
{
    if (type.empty)
    {
        outstr.put("bad input: no type\n");
        return false;
    }
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
    if (clientver is null || clientver == "")
        clientver = "0";

    if (!validate_id(clientver, "clientver", outstr))
        return false;

    switch (clientver)
    {
        case "0":
        case "1":
        case "2":
            return true;
        default:
            return false;
    }
}

