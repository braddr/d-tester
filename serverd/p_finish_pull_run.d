module p_finish_pull_run;

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
    if (!sql_exec(text("select id, host_id, end_time from pull_test_runs where id = ", runid)))
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

bool validateInput(ref string raddr, ref string runid, ref string hostid, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(runid, "runid", outstr))
        return false;

    if (!validate_runState(runid, hostid, outstr))
        return false;

    return true;
}

bool updateGithub(string runid, Appender!string outstr)
{
    if (!sql_exec(text("select r.name, ptr.sha, r.id, ghp.pull_id, ghp.id from github_pulls ghp, repositories r, repo_branches rb, pull_test_runs ptr where ptr.id = ", runid, " and ptr.g_p_id = ghp.id and ghp.r_b_id = rb.id and rb.repository_id = r.id")))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow[] rows = sql_rows();
    if (rows == [])
    {
        formattedWrite(outstr, "failed to find the associated pull, check error log\n");
        return false;
    }
    if (rows.length > 1)
    {
        formattedWrite(outstr, "found more than one associated pull? runid=", runid, "\n");
        return false;
    }

    string reponame = rows[0][0];
    string sha = rows[0][1];
    string repoid = rows[0][2];
    string pullid = rows[0][3];
    string ghp_id = rows[0][4];

    if (!sql_exec(text("select rc from pull_test_runs where g_p_id = ", ghp_id, " and deleted = 0")))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    rows = sql_rows();

    int numpass, numfail, numinprogress, numpending;
    foreach(row; rows)
    {
        if (row[0] == "1")
            ++numfail;
        else if (row[0] == "0")
            ++numpass;
        else
            ++numinprogress;
    }
    numpending = 10 - numpass - numfail - numinprogress;
    if (numpending < 0) numpending = 0;

    string url = text("https://api.github.com/repos/D-Programming-Language/", reponame, "/statuses/", sha);
    string payload;
    string[] headers;

    string desc;
    void appenddesc(string s)
    {
        if (!desc.empty) desc ~= ", ";
        desc ~= s;
    }

    string status;
    if (numpass > 0)       { status = "success"; appenddesc(text("Pass: ",        numpass));       }
    if (numfail > 0)       { status = "failure"; appenddesc(text("Fail: ",        numfail));       }
    if (numinprogress > 0) { status = "pending"; appenddesc(text("In Progress: ", numinprogress)); }
    if (numpending > 0)    { status = "pending"; appenddesc(text("Pending: ",     numpending));    }
    if (numfail > 0)       { status = "failure"; }

    string requestpayload = text(
        `{`
            `"description" : "`, desc, `",`
            `"state" : "`, status, `",`
            `"target_url" : "http://d.puremagic.com/test-results/pull-history.ghtml?`
                `repoid=`, repoid, `&pullid=`, pullid, `"`
        `}`);

    writelog("  request body: %s", requestpayload);

    if (!runCurlPOST(curl, payload, headers, url, requestpayload, c.github_user, c.github_passwd))
    {
        writelog("  failed to update github");
        return false;
    }

    return true;
}

bool updateStore(string runid, Appender!string outstr)
{
    sql_exec(text("select rc from pull_test_data where test_run_id=", runid));
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

    sql_exec(text("update pull_test_runs set end_time=now(), rc=", rc, " where id=", runid));

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string hostid;
    string runid = lookup(userhash, "runid");

    if (!validateInput(raddr, runid, hostid, outstr))
        return;

    updateHostLastCheckin(hostid);
    updateStore(runid, outstr);
    updateGithub(runid, outstr);
}

