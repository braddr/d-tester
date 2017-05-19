module clientapi.finish_pull_test;

import mysql;
import globals;
import utils;
import validate;

import clientapi.sql;

import std.conv;
import std.format;
import std.range;

bool validate_testState(string testid, ref string hostid, ref string runid, Appender!string outstr)
{
    if (!sql_exec(text("select ptd.id, ptr.host_id, ptr.end_time, ptd.end_time, ptd.test_run_id from pull_test_runs ptr, pull_test_data ptd where ptd.id = ", testid, " and ptd.test_run_id = ptr.id")))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, testid: %s\n", testid);
        return false;
    }

    if (rows[0][2] != "" || rows[0][3] != "")
    {
        formattedWrite(outstr, "bad input: test or run already complete, testid: %s\n", testid);
        return false;
    }

    hostid = rows[0][1];
    runid = rows[0][4];

    return true;
}

bool validateInput(ref string raddr, ref string runid, ref string hostid, ref string testid, ref string rc, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(testid, "testid", outstr))
        return false;
    if (!validate_id(rc, "rc", outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    if (!validate_testState(testid, hostid, runid, outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string hostid;
    string runid;
    string testid = lookup(userhash, "testid");
    string rc = lookup(userhash, "rc");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, runid, hostid, testid, rc, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);

    // temporarily made rc be just 0 and 1
    if (rc != "0") rc = "1";

    sql_exec(text("update pull_test_data set end_time=now(), rc=", rc, " where id=", testid));

    if (isPullRunAborted(runid))
    {
        writelog("  aborting in progress pull test, runid: %s", runid);
        outstr.put("abort");
    }
    else
        outstr.put("ok");
}

