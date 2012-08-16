module p_finish_run;

import mysql;
import utils;

import std.conv;
import std.format;
import std.range;

alias string[] sqlrow;

bool valid(string rid)
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

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    formattedWrite(outstr, "Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    if (!auth_check(raddr, outstr)) return;

    string rid = lookup(userhash, "runid");
    if (rid.empty)
    {
        formattedWrite(outstr, "bad input: missing runid\n");
        return;
    }

    if (!valid(rid))
    {
        formattedWrite(outstr, "bad input: %s is not a valid runid\n", sql_quote(rid));
        return;
    }

    if (!sql_exec(text("select id from test_runs where id=", sql_quote(rid))))
        formattedWrite(outstr, "error executing sql, check error log\n");

    sqlrow row = sql_row();
    if (row == [])
    {
        formattedWrite(outstr, "error: no such runid");
        return;
    }

    if (!sql_exec(text("update test_runs set end_time=now() where id=", sql_quote(rid))))
        formattedWrite(outstr, "error executing sql, check error log\n");
}
