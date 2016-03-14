module clientapi.finish_master_run;

import config;
import mysql_client;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_runState(string runid, ref string hostid, Appender!string outstr)
{
    Results r = mysql.query(text("select id, host_id, end_time from test_runs where id = ", runid));
    if (!r)
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, runid: %s\n", runid);
        return false;
    }

    if (row[2] != "")
    {
        formattedWrite(outstr, "bad input: run already complete, runid: %s\n", runid);
        return false;
    }

    hostid = row[1];

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
    Results r = mysql.query(text("select rc from test_data where test_run_id=", runid));

    int rc = 0;
    foreach(row; r)
    {
        if (row[0] == "1")
        {
            rc = 1;
            break;
        }
    }

    mysql.query(text("update test_runs set end_time=now(), rc=", rc, " where id=", runid));

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

