module loggedin.toggle_auto_merge;

static import clientapi.finish_pull_run;
import std.conv;
import std.json;
import std.range;

import github_apis;
import mysql;
import serverd;
import utils;
import validate;

bool validateInput(ref string projectid, ref string repoid, ref string pullid, ref string ghp_id, Appender!string outstr)
{
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

bool updateStore(string ghp_id, string loginid, ref bool newstate)
{
    sql_exec(text("select auto_pull from github_pulls where id = ", ghp_id));
    sqlrow[] rows = sql_rows();

    if (rows[0][0] == "")
    {
        newstate = true;
        sql_exec(text("update github_pulls set auto_pull = \"", loginid, "\" where id=", ghp_id));
    }
    else
    {
        newstate = false;
        sql_exec(text("update github_pulls set auto_pull = null where id=", ghp_id));
    }

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

    if (!clientapi.finish_pull_run.mergeGithubPull(rows[0][0], rows[0][1], pullid, ghp_id, rows[0][3], outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    auto valout = appender!string;

    string access_token;
    string userid;
    string username;
    if (!validateAuthenticated(userhash, access_token, userid, username, valout))
    {
        valout.put("error toggling auto-merge state\n");
Lerror:
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(valout.data);
        return;
    }

    string projectid = lookup(userhash, "projectid");
    string repoid = lookup(userhash, "repoid");
    string pullid = lookup(userhash, "pullid");
    string ghp_id = lookup(userhash, "ghp_id");
    string from = lookup(userhash, "from");

    if (!validateInput(projectid, repoid, pullid, ghp_id, valout))
        goto Lerror;

    sql_exec(text("select p.name, r.name from projects p, repositories r where p.id = ", projectid, " and r.id = ", repoid));
    sqlrow[] rows = sql_rows();

    string extra_param;
    // TODO: this should be cached data to avoid github load
    if (!github.userIsCollaborator(username, rows[0][0], rows[0][1], access_token))
        extra_param = "&notcollab=1";
    else
    {
        bool newstate;
        if (!updateStore(ghp_id, userid, newstate)) goto Lerror;

        string commenttext = text("Auto-merge toggled ", newstate ? "on" : "off");

        JSONValue jv;
        if (!github.addPullComment(access_token, rows[0][0], rows[0][1], pullid, commenttext, jv))
            writelog("  failed to submit a comment to github, continuing anwyay");

        // TODO: change so that a github related error in merging is presented as normal in the ui, not an internal error
        if (!checkMergeNow(projectid, repoid, pullid, ghp_id, valout)) goto Lerror;
    }

    outstr.put(text("Location: ", getURLProtocol(hash) , "://", lookup(hash, "SERVER_NAME"), "/", from, ".ghtml?",
               "projectid=", projectid, "&",
               "repoid=", repoid, "&",
               "pullid=", pullid,
               extra_param,
               "\n\n"));
}
