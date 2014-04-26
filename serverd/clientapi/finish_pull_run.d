module clientapi.finish_pull_run;

import config;
import github_apis;
import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.json;
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
        formattedWrite(outstr, "bad input: should be exactly one row, runid: %s\n", runid);
        return false;
    }

    if (rows[0][2] != "")
    {
        formattedWrite(outstr, "bad input: run already complete, runid: %s\n", runid);
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

bool getRelatedData(string runid, ref string reponame, ref string repoid, ref string sha, ref string pullid, ref string ghp_id, ref string projectid, ref string projectname, ref string merge_authorizing_id, Appender!string outstr)
{
    if (!sql_exec(text("select r.name, ptr.sha, r.id, ghp.pull_id, ghp.id, r.project_id, p.name, p.allow_auto_merge, ghp.auto_pull from github_pulls ghp, repositories r, repo_branches rb, pull_test_runs ptr, projects p where ptr.id = ", runid, " and ptr.g_p_id = ghp.id and ghp.r_b_id = rb.id and rb.repository_id = r.id and p.id = r.project_id")))
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
        formattedWrite(outstr, "found more than one associated pull? runid=%s\n", runid);
        return false;
    }

    reponame = rows[0][0];
    sha = rows[0][1];
    repoid = rows[0][2];
    pullid = rows[0][3];
    ghp_id = rows[0][4];
    projectid = rows[0][5];
    projectname = rows[0][6];

    // if project allows merging, return the pull merge state, otherwise null
    merge_authorizing_id = (rows[0][7] == "1") ? rows[0][8] : "";

    return true;
}

// called by p_get_runnable_pull -- can it provide these values itself?
bool updateGithubPullStatus(string runid, Appender!string outstr)
{
    string projectname, projectid;
    string reponame, repoid;
    string sha, pullid, ghp_id;
    string merge_authorizing_id;
    if (!getRelatedData(runid, reponame, repoid, sha, pullid, ghp_id, projectid, projectname, merge_authorizing_id, outstr))
        return false;

    return updateGithubPullStatus(runid, ghp_id, sha, pullid, projectname, projectid, reponame, repoid, outstr);
}

bool updateGithubPullStatus(string runid, string ghp_id, string sha, string pullid, string projectname, string projectid, string reponame, string repoid, Appender!string outstr)
{
    if (!sql_exec(text("select rc from pull_test_runs where g_p_id = ", ghp_id, " and deleted = 0")))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow[] rows = sql_rows();

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

    string targeturl = text(`https://auto-tester.puremagic.com/pull-history.ghtml?`
                `projectid=`, projectid, `&repoid=`, repoid, `&pullid=`, pullid);

    if (!github.setSHAStatus(projectname, reponame, sha, desc, status, targeturl))
        return false;

    return true;
}

bool updateStore(string runid, Appender!string outstr)
{
    sql_exec(text("select rc from pull_test_data where test_run_id=", runid));
    sqlrow[] rows = sql_rows();

    int maxrc = 0;
    foreach(row; rows)
    {
        int rc = to!int(row[0]);
        if (rc > maxrc)
        {
            maxrc = rc;
        }
    }

    sql_exec(text("update pull_test_runs set end_time=now(), rc=", maxrc, " where id=", runid));

    return true;
}

bool mergeGithubPull(string projectname, string reponame, string pullid, string ghp_id, string merge_authorizing_id, Appender!string outstr)
{
    sql_exec(text("select count(*) from pull_test_runs where g_p_id = ", ghp_id, " and deleted = false and rc = 0"));
    sqlrow[] rows = sql_rows();

    // if there aren't 10 completed tests (one for each platform), do nothing
    // TODO: num platforms really ought to come from the db
    if (to!int(rows[0][0]) != 10)
        return true;

    sql_exec(text("select access_token, username from github_users where id = ", merge_authorizing_id));
    rows = sql_rows();
    string access_token = rows[0][0];
    string username = rows[0][1];

    if (!github.userIsCollaborator(username, projectname, reponame, access_token))
    {
        writelog("  WARNING: user no longer is authorized to merge pull, skipping");
        formattedWrite(outstr, "%s is not authorized to perform merges", username);
        sql_exec(text("update github_pulls set auto_pull = null where id = ", ghp_id));
        return false;
    }

    JSONValue jv;
    if (!github.getPull(projectname, reponame, pullid, jv)) return true;

    sql_exec(text("select head_sha from github_pulls where id = ", ghp_id));
    rows = sql_rows();
    if (rows[0][0] != jv.object["head"].object["sha"].str)
    {
        writelog("  github has a newer sha than we do, skipping merge");
        return true;
    }

    string commit_message; // = text("auto-merge authorized by ", rows[0][1]);
    github.performPullMerge(projectname, reponame, pullid, access_token, commit_message);
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

    string projectname, projectid;
    string reponame, repoid;
    string sha, pullid, ghp_id;
    string merge_authorizing_id;
    if (!getRelatedData(runid, reponame, repoid, sha, pullid, ghp_id, projectid, projectname, merge_authorizing_id, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    updateStore(runid, outstr);
    updateGithubPullStatus(runid, ghp_id, sha, pullid, projectname, projectid, reponame, repoid, outstr);

    if (merge_authorizing_id != "")
        mergeGithubPull(projectname, reponame, pullid, ghp_id, merge_authorizing_id, outstr);
}

