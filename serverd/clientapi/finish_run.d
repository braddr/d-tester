module clientapi.finish_run;

import mysql_client;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_runState(string runid, ref string hostid, Appender!string outstr)
{
    Results r = mysql.query(text("select id, hostid, end_time from test_runs where id=", runid));
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

bool validateInput(ref string raddr, ref string hostid, ref string runid, ref string clientver, Appender!string outstr)
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

bool storeResults(string runid, Appender!string outstr)
{
    Results r = mysql.query(text("update test_runs set end_time=now() where id=", runid));
    if (!r)
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
    string runid = lookup(userhash, "runid");
    string clientver = lookup(userhash, "clientver");
    string hostid;

    if (!validateInput(raddr, hostid, runid, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    if (!storeResults(runid, outstr))
        return;
}
