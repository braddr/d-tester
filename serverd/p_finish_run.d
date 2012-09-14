module p_finish_run;

import mysql;
import serverd;
import utils;

import std.conv;
import std.format;
import std.range;

alias string[] sqlrow;

bool validNumber(string rid)
{
    try
    {
        size_t id = to!size_t(rid);
        return true;
    }
    catch(ConvException)
    {}

    return false;
}

bool validate(ref string raddr, ref string rid, Appender!string outstr)
{
    if (!auth_check(raddr, outstr)) return false;

    if (rid.empty)
    {
        formattedWrite(outstr, "bad input: missing runid\n");
        return false;
    }

    if (!validNumber(rid))
    {
        formattedWrite(outstr, "bad input: %s is not a valid runid\n", sql_quote(rid));
        return false;
    }

    // no longer need in it's raw form, so let's sql_quote it.  That it passes the number
    // validation means this really ought to be a complete no-op, but doesn't hurt.

    rid = sql_quote(rid);

    if (!sql_exec(text("select id from test_runs where id=", rid)))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow row = sql_row();
    if (row == [])
    {
        formattedWrite(outstr, "error: no such runid: ", rid);
        return false;
    }

    return true;
}

bool storeResults(string rid, Appender!string outstr)
{
    if (!sql_exec(text("update test_runs set end_time=now() where id=", rid)))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    formattedWrite(outstr, "Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rid = lookup(userhash, "runid");

    if (!validate(raddr, rid, outstr))
        return;

    if (!storeResults(rid, outstr))
        return;
}
