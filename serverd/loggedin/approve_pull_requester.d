module loggedin.approve_pull_requester;

import std.array;
import std.conv;
import std.format;

import mysql;
import utils;
import validate;

bool validateInput(ref string projectid, ref string pull_userid, Appender!string outstr)
{
    if (!validate_id(projectid, "projectit", outstr))
        return false;
    if (!validate_id(pull_userid, "userid", outstr))
        return false;

    return true;
}

bool validateCanApprove(string userid, Appender!string outstr)
{
    sql_exec(text("select pull_approver from github_users where id = ", userid));
    sqlrow[] rows = sql_rows();
    if (rows.length != 1 || rows[0][0] == "")
    {
        formattedWrite(outstr, "error, user not approved to approve new pullers");
        return false;
    }

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
Lerror:
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(valout.data);
        return;
    }

    string projectid = lookup(userhash, "projectid");
    string pull_userid = lookup(userhash, "userid");

    if (!validateInput(projectid, pull_userid, valout))
        goto Lerror;

    if (!validateCanApprove(userid, valout))
        goto Lerror;

    sql_exec(text("update github_users set pull_approver = ", userid, " where id = ", pull_userid));

    outstr.put(text("Location: ", getURLProtocol(hash) , "://", lookup(hash, "SERVER_NAME"), "/test-results/pulls.ghtml?projectid=", projectid));
    outstr.put("\n\n");
}

