module clientapi.finish_master_test;

import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_testState(string testid, ref string hostid, Appender!string outstr)
{
    if (!sql_exec(text("select td.id, tr.host_id, tr.end_time, td.end_time from test_runs tr, test_data td where td.id = ", testid, " and td.test_run_id = tr.id")))
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

    return true;
}

bool validateInput(ref string raddr, ref string hostid, ref string testid, ref string rc, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(testid, "testid", outstr))
        return false;
    if (!validate_id(rc, "rc", outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    if (!validate_testState(testid, hostid, outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string hostid;
    string testid = lookup(userhash, "testid");
    string rc = lookup(userhash, "rc");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, hostid, testid, rc, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    sql_exec(text("update test_data set end_time=now(), rc=", rc, " where id=", testid));
    outstr.put("ok");
}

