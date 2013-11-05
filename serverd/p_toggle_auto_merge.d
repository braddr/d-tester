module p_toggle_auto_merge;

static import p_finish_pull_run;
import std.conv;
import std.range;

import mysql;
import utils;
import validate;

bool validateInput(ref string raddr, ref string projectid, ref string repoid, ref string pullid, ref string ghp_id, Appender!string outstr)
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

    return true;
}

bool updateStore(string ghp_id)
{
    sql_exec(text("update github_pulls set auto_pull = not auto_pull where id=", sql_quote(ghp_id)));

    return true;
}

bool checkMergeNow(string projectid, string repoid, string pullid, string ghp_id, Appender!string outstr)
{
    sqlrow[] rows;

    sql_exec(text("select p.name, r.name, p.allow_auto_merge, ghp.auto_pull from projects p, repositories r, github_pulls ghp where p.id = ", projectid, " and r.id = ", repoid, " and ghp.id = ", ghp_id));
    rows = sql_rows();
    if (rows.length < 1)
    {
        outstr.put("checkMergeNow: should have gotten exactly one row back from db");
        return false;
    }

    // get out unless both project and pull are request auto-merging
    if (rows[0][2] != "1" || rows[0][3] != "1")
        return true;

    if (!p_finish_pull_run.mergeGithubPull(rows[0][0], rows[0][1], pullid, ghp_id, outstr))
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

    auto valout = appender!string;
    if (
            !validateInput(raddr, projectid, repoid, pullid, ghp_id, valout) ||
            !updateStore(ghp_id) ||
            !checkMergeNow(projectid, repoid, pullid, ghp_id, valout)
       )
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(valout.data);
        return;
    }

    outstr.put(text("Location: http://", lookup(hash, "SERVER_NAME"), "/test-results/pull-history.ghtml?",
               "projectid=", projectid, "&",
               "repoid=", repoid, "&",
               "pullid=", pullid,
               "\n\n"));
}
