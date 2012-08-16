module p_finish_pull_test;

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

    string testid = lookup(userhash, "testid");
    if (testid.empty)
    {
        outstr.put("bad input: no testid\n");
        return;
    }
    if (!validate(testid))
    {
        outstr.put("bad input: invalid testid\n");
        return;
    }

    string rc = lookup(userhash, "rc");
    if (rc.empty)
    {
        outstr.put("bad input: no rc\n");
        return;
    }
    if (!validate(rc))
    {
        outstr.put("bad input: invalid rc\n");
        return;
    }

    auto q_testid = sql_quote(testid);
    auto q_rc     = sql_quote(rc);

    sql_exec(text("select id, end_time from pull_test_data where id=", q_testid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        outstr.put("bad input: should be exactly one row\n");
        return;
    }

    if (rows[0][1] != "")
    {
        outstr.put("bad input: test already complete\n");
        return;
    }

    sql_exec(text("update pull_test_data set end_time=now(), rc=", q_rc, " where id=", q_testid));
}

