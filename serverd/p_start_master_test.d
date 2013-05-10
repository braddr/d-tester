module p_start_master_test;

import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_testRunable(string runid, string type, ref string hostid, Appender!string outstr)
{
    sql_exec(text("select id, end_time, host_id from test_runs where id=", runid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, runid: ", runid, "\n");
        return false;
    }

    if (rows[0][1] != "")
    {
        formattedWrite(outstr, "bad input: run already complete: ", runid, "\n");
        return false;
    }

    hostid = rows[0][2];

    sql_exec(text("select id from test_data where test_run_id=", runid, " and test_type_id=", type));
    sqlrow[] testids = sql_rows();

    if (testids.length != 0)
    {
        formattedWrite(outstr, "bad input: test already exists, type: ", type, "\n");
        return false;
    }

    return true;
}

bool validateInput(ref string raddr, ref string hostid, ref string runid, ref string type, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(runid, "runid", outstr))
        return false;
    if (!validate_testtype(type, outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    if (!validate_testRunable(runid, type, hostid, outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string hostid;
    string runid = lookup(userhash, "runid");
    string type = lookup(userhash, "type");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, hostid, runid, type, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    sql_exec(text("insert into test_data (test_run_id, test_type_id, start_time) values (", runid, ", ", type, ", now())"));
    sql_exec("select last_insert_id()");
    sqlrow liid = sql_row();
    formattedWrite(outstr, "%s\n", liid[0]);
}

