module clientapi.start_master_test;

import mysql_client;
import utils;
import validate;

import std.conv;
import std.format;
import std.range;

bool validate_testRunable(string clientver, string runid, string type, string repoid, ref string hostid, Appender!string outstr)
{
    Results r = mysql.query(text("select id, end_time, host_id from test_runs where id=", runid));

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, runid: %s\n", runid);
        return false;
    }

    if (row[1] != "")
    {
        formattedWrite(outstr, "bad input: run already complete: %s\n", runid);
        return false;
    }

    hostid = row[2];

    r = mysql.query(text("select id from test_data where test_run_id=", runid, " and test_type_id=", type, " and repository_id=", repoid));

    if (!r.empty)
    {
        formattedWrite(outstr, "bad input: test already exists, type: %s\n", type);
        return false;
    }

    return true;
}

bool validate_repoid(string runid, string repoid, Appender!string outstr)
{
    if (!validate_id(repoid, "repoid", outstr))
        return false;

    Results r = mysql.query(text("select tr.id, tr.project_id, r.id, r.name from test_runs tr, repositories r, project_repositories pr where tr.id = ", runid, " and r.id = ", repoid ," and tr.project_id = pr.project_id and pr.repository_id = r.id"));

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        formattedWrite(outstr, "invalid repoid: %s, runid: %s\n", repoid, runid);
        return false;
    }

    return true;
}

bool validateInput(ref string raddr, ref string hostid, ref string runid, ref string type, ref string repoid, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(runid, "runid", outstr))
        return false;
    if (!validate_testtype(type, clientver, outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;
    if (!validate_repoid(runid, repoid, outstr))
        return false;

    if (!validate_testRunable(clientver, runid, type, repoid, hostid, outstr))
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
    string repoid = lookup(userhash, "repoid");

    if (!validateInput(raddr, hostid, runid, type, repoid, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);

    mysql.query(text("insert into test_data (test_run_id, test_type_id, repository_id, start_time) values (", runid, ", ", type, ", ", repoid, ", now())"));

    Results r = mysql.query("select last_insert_id()");
    sqlrow liid = r.front;
    formattedWrite(outstr, "%s\n", liid[0]);
}

