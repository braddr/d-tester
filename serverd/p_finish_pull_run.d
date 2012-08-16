module p_finish_pull_run;

import mysql;
import serverd;
import utils;

import std.conv;
import std.format;
import std.range;

alias string[] sqlrow;

bool validate(string runid)
{
    try
    {
        auto id = to!size_t(runid);
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
        formattedWrite(outstr, "bad input: missing runid\n");
        return;
    }
    if (!validate(runid))
    {
        outstr.put("bad input: runid invalid\n");
        return;
    }

    auto quotedid = sql_quote(runid);

    sql_exec(text("select id, end_time from pull_test_runs where id=", quotedid));
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

    sql_exec(text("select rc from pull_test_data where test_run_id=", quotedid));
    rows = sql_rows();

    int rc = 0;
    foreach(row; rows)
    {
        if (row[0] == "1")
            rc = 1;
    }

    sql_exec(text("update pull_test_runs set end_time=now(), rc=", rc, " where id=", quotedid));
}

