module p_finish_master_run;

import config;
import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_runState(string runid, ref string hostid, Appender!string outstr)
{
    if (!sql_exec(text("select id, host_id, end_time from test_runs where id = ", runid)))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, runid: ", runid, "\n");
        return false;
    }

    if (rows[0][2] != "")
    {
        formattedWrite(outstr, "bad input: run already complete, runid: ", runid, "\n");
        return false;
    }

    hostid = rows[0][1];

    return true;
}

bool validateInput(ref string raddr, ref string runid, ref string hostid, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(runid, "runid", outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    if (!validate_runState(runid, hostid, outstr))
        return false;

    return true;
}

bool updateStore(string runid, Appender!string outstr)
{
    sql_exec(text("select rc from test_data where test_run_id=", runid));
    sqlrow[] rows = sql_rows();

    int rc = 0;
    foreach(row; rows)
    {
        if (row[0] == "1")
        {
            rc = 1;
            break;
        }
    }

    sql_exec(text("update test_runs set end_time=now(), rc=", rc, " where id=", runid));

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string hostid;
    string runid = lookup(userhash, "runid");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, runid, hostid, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    updateStore(runid, outstr);
}

