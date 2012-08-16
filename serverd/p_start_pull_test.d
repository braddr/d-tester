module p_start_pull_test;

import mysql;
import serverd;
import utils;

import std.conv;
import std.format;
import std.range;

alias string[] sqlrow;

bool validate(string strid)
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

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    auto tmpout = appender!string();
    if (!auth_check(raddr, tmpout))
    {
        outstr.put(tmpout.data);
        return;
    }

    string runid = lookup(userhash, "runid");
    if (runid.empty)
    {
        outstr.put("bad input: no runid\n");
        return;
    }
    if (!validate(runid))
    {
        outstr.put("bad input: invalid runid\n");
        return;
    }

    string type = lookup(userhash, "type");
    if (type.empty)
    {
        outstr.put("bad input: no type\n");
        return;
    }
    if (!validate(type))
    {
        outstr.put("bad input: invalid type\n");
        return;
    }

    auto q_runid = sql_quote(runid);
    auto q_type  = sql_quote(type);

    sql_exec(text("select id, end_time from pull_test_runs where id=", q_runid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        outstr.put("bad input: should be exactly one row\n");
        return;
    }

    if (rows[0][1] != "")
    {
        outstr.put("bad input: run already complete\n");
        return;
    }

    sql_exec(text("select id from pull_test_data where test_run_id=", q_runid, " and test_type_id=", q_type));
    sqlrow[] testids = sql_rows();

    if (testids.length != 0)
    {
        outstr.put("bad input: test already exists\n");
        return;
    }

    sql_exec(text("insert into pull_test_data (test_run_id, test_type_id, start_time) values (", q_runid, ", ", q_type, ", now())"));
    sql_exec("select last_insert_id()");
    sqlrow liid = sql_row();
    formattedWrite(outstr, "%s\n", liid[0]);
}

