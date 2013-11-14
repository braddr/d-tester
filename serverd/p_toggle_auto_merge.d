module p_toggle_auto_merge;

static import p_finish_pull_run;
import std.conv;
import std.range;

import github_apis;
import mysql;
import utils;
import validate;

bool validateInput(ref string raddr, ref string projectid, ref string repoid, ref string pullid, ref string ghp_id, ref string testerlogin, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(projectid, "projectid", outstr))
        return false;
    if (!validate_id(repoid, "repoid", outstr))
        return false;
    if (!validate_id(pullid, "pullid", outstr))
        return false;
    if (!validate_id(ghp_id, "ghp_id", outstr))
        return false;

    if (!validate_id(testerlogin, "testerlogin", outstr))
        return false;

    return true;
}

bool getAccessTokenFromCookie(string testerlogin, ref string access_token, ref string userid, ref string username)
{
    sql_exec(text("select username, access_token from github_users where id = ", testerlogin));
    sqlrow[] rows = sql_rows();
    if (rows.length != 1)
    {
        writelog("  found %s rows, expected 1, for id %s", rows.length, testerlogin);
        return false;
    }

    userid = testerlogin;
    username = rows[0][0];
    access_token = rows[0][1];

    return true;
}

bool updateStore(string ghp_id, string loginid)
{
    sql_exec(text("select auto_pull from github_pulls where id = ", ghp_id));
    sqlrow[] rows = sql_rows();

    if (rows[0][0] == "")
        sql_exec(text("update github_pulls set auto_pull = \"", loginid, "\" where id=", ghp_id));
    else
        sql_exec(text("update github_pulls set auto_pull = null where id=", ghp_id));

    return true;
}

bool checkMergeNow(string projectid, string repoid, string pullid, string ghp_id, Appender!string outstr)
{
    sql_exec(text("select p.name, r.name, p.allow_auto_merge, ghp.auto_pull from projects p, repositories r, github_pulls ghp where p.id = ", projectid, " and r.id = ", repoid, " and ghp.id = ", ghp_id));
    sqlrow[] rows = sql_rows();
    if (rows.length < 1)
    {
        outstr.put("checkMergeNow: should have gotten exactly one row back from db");
        return false;
    }

    // get out unless both project and pull are request auto-merging
    if (rows[0][2] != "1" || rows[0][3] == "")
        return true;

    if (!p_finish_pull_run.mergeGithubPull(rows[0][0], rows[0][1], pullid, ghp_id, rows[0][3], outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string raddr = lookup(hash, "REMOTE_ADDR");
    string projectid = lookup(userhash, "projectid");
    string repoid = lookup(userhash, "repoid");
    string pullid = lookup(userhash, "pullid");
    string ghp_id = lookup(userhash, "ghp_id");
    string testerlogin = lookup(userhash, "testerlogin");

    auto valout = appender!string;
    if (!validateInput(raddr, projectid, repoid, pullid, ghp_id, testerlogin, valout)) goto Lerror;

    string access_token;
    string userid;
    string username;
    if (!getAccessTokenFromCookie(testerlogin, access_token, userid, username))
    {
        valout.put("error toggling auto-merge state\n");
        goto Lerror;
    }

    if (!updateStore(ghp_id, userid)) goto Lerror;
    if (!checkMergeNow(projectid, repoid, pullid, ghp_id, valout)) goto Lerror;

    outstr.put(text("Location: ", getURLProtocol(hash) , "://", lookup(hash, "SERVER_NAME"), "/test-results/pull-history.ghtml?",
               "projectid=", projectid, "&",
               "repoid=", repoid, "&",
               "pullid=", pullid,
               "\n\n"));

    return;

Lerror:
    outstr.put("Content-type: text/plain\n\n");
    outstr.put(valout.data);
}
