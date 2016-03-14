module clientapi.finish_pull_run;

import config;
import github_apis;
import log;
import mysql_client;
import serverd;
import utils;
import validate;

import std.conv;
import std.json;
import std.format;
import std.range;

bool validate_runState(string runid, ref string hostid, Appender!string outstr)
{
    Results r = mysql.query(text("select id, host_id, end_time from pull_test_runs where id = ", runid));
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

bool getRelatedData(string runid, ref string reponame, ref string repoid, ref string sha, ref string pullid, ref string ghp_id, ref string projectid, ref string owner, ref string merge_authorizing_id, Appender!string outstr)
{
    Results r = mysql.query(text("select r.name, ptr.sha, r.id, ghp.pull_id, ghp.id, p.id, r.owner, p.allow_auto_merge, ghp.auto_pull from github_pulls ghp, repositories r, pull_test_runs ptr, projects p, project_repositories pr where ptr.id = ", runid, " and ptr.g_p_id = ghp.id and ghp.repo_id = r.id and p.id = pr.project_id and pr.repository_id = r.id"));
    if (!r)
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        formattedWrite(outstr, "expected exactly one row, runid=%s\n", runid);
        return false;
    }

    reponame = row[0];
    sha = row[1];
    repoid = row[2];
    pullid = row[3];
    ghp_id = row[4];
    projectid = row[5];
    owner = row[6];

    // if project allows merging, return the pull merge state, otherwise null
    merge_authorizing_id = (row[7] == "1") ? row[8] : "";

    return true;
}

// called by p_get_runnable_pull -- can it provide these values itself?
bool updateGithubPullStatus(string runid, Appender!string outstr)
{
    string projectid;
    string owner, reponame, repoid;
    string sha, pullid, ghp_id;
    string merge_authorizing_id;
    if (!getRelatedData(runid, reponame, repoid, sha, pullid, ghp_id, projectid, owner, merge_authorizing_id, outstr))
        return false;

    return updateGithubPullStatus(runid, ghp_id, sha, pullid, projectid, repoid, owner, reponame, outstr);
}

bool updateGithubPullStatus(string runid, string ghp_id, string sha, string pullid, string projectid, string repoid, string owner, string reponame, Appender!string outstr)
{
    Results r = mysql.query(text("select rc from pull_test_runs where g_p_id = ", ghp_id, " and deleted = 0"));
    if (!r)
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    int numpass, numfail, numinprogress, numpending;
    foreach(row; r)
    {
        if (row[0] == "1")
            ++numfail;
        else if (row[0] == "0")
            ++numpass;
        else
            ++numinprogress;
    }
    // TODO: remove hardcoded 10, should be number of supported platforms
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

    if (!github.setSHAStatus(owner, reponame, sha, desc, status, targeturl))
        return false;

    return true;
}

bool updateStore(string runid, Appender!string outstr)
{
    Results r = mysql.query(text("select rc from pull_test_data where test_run_id=", runid));

    int maxrc = 0;
    foreach(row; r)
    {
        int rc = to!int(row[0]);
        if (rc > maxrc)
        {
            maxrc = rc;
        }
    }

    mysql.query(text("update pull_test_runs set end_time=now(), rc=", maxrc, " where id=", runid));

    return true;
}

bool mergeGithubPull(string owner, string reponame, string pullid, string ghp_id, string merge_authorizing_id, Appender!string outstr)
{
    Results r = mysql.query(text("select count(*) from pull_test_runs where g_p_id = ", ghp_id, " and deleted = false and rc = 0"));

    // if there aren't 10 completed tests (one for each platform), do nothing
    // TODO: num platforms really ought to come from the db
    if (to!int(r.front[0]) != 10)
        return true;

    r = mysql.query(text("select access_token, username from github_users where id = ", merge_authorizing_id));
    string access_token = r.front[0];
    string username = r.front[1];

    if (!github.userIsCollaborator(username, owner, reponame, access_token))
    {
        writelog("  WARNING: user no longer is authorized to merge pull, skipping");
        formattedWrite(outstr, "%s is not authorized to perform merges", username);
        mysql.query(text("update github_pulls set auto_pull = null where id = ", ghp_id));
        return false;
    }

    JSONValue jv;
    if (!github.getPull(owner, reponame, pullid, jv)) return true;

    r = mysql.query(text("select head_sha from github_pulls where id = ", ghp_id));
    if (r.front[0] != jv.object["head"].object["sha"].str)
    {
        writelog("  github has a newer sha than we do, skipping merge");
        return true;
    }

    string commit_message; // TODO: = text("auto-merge authorized by ", rows[0][1]);
    github.performPullMerge(owner, reponame, pullid, access_token, commit_message);
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

    string projectid;
    string owner, reponame, repoid;
    string sha, pullid, ghp_id;
    string merge_authorizing_id;
    if (!getRelatedData(runid, reponame, repoid, sha, pullid, ghp_id, projectid, owner, merge_authorizing_id, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);
    updateStore(runid, outstr);
    updateGithubPullStatus(runid, ghp_id, sha, pullid, projectid, repoid, owner, reponame, outstr);

    if (merge_authorizing_id != "")
        mergeGithubPull(owner, reponame, pullid, ghp_id, merge_authorizing_id, outstr);
}

