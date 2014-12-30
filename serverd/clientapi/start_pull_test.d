module clientapi.start_pull_test;

import mysql;
import serverd;
import utils;
import validate;

import clientapi.sql;

import std.conv;
import std.format;
import std.range;

bool validate_testRunable(string clientver, string runid, string type, string repoid, ref string hostid, Appender!string outstr)
{
    sql_exec(text("select id, end_time, host_id from pull_test_runs where id=", runid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        formattedWrite(outstr, "bad input: should be exactly one row, runid: %s\n", runid);
        return false;
    }

    if (rows[0][1] != "")
    {
        formattedWrite(outstr, "bad input: run already complete: %s\n", runid);
        return false;
    }

    hostid = rows[0][2];

    sql_exec(text("select id from pull_test_data where test_run_id=", runid, " and test_type_id=", type, " and repository_id=", repoid));
    sqlrow[] testids = sql_rows();

    if (testids.length != 0)
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

    sql_exec(text("select r.id from repositories r where r.project_id = (select pr.project_id from repositories r, project_repositories pr, github_pulls ghp, pull_test_runs tr where tr.id = ", runid, " and tr.g_p_id = ghp.id and ghp.repo_id = r.id and r.id = pr.repository_id) and r.id = ", repoid));

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        formattedWrite(outstr, "invalid repoid: %s\n", repoid);
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

    if (isPullRunAborted(runid))
    {
        writelog("  aborting in progress pull test, runid: %s", runid);
        outstr.put("abort");
    }
    else
    {
        sql_exec(text("insert into pull_test_data (test_run_id, test_type_id, repository_id, start_time) values (", runid, ", ", type, ", ", repoid, ", now())"));
        sql_exec("select last_insert_id()");
        sqlrow liid = sql_row();
        formattedWrite(outstr, "%s\n", liid[0]);
    }
}

