module loggedin.deprecate_run;

import std.array;
import std.conv;

import mysql;
import utils;
import validate;

bool validateInput(ref string projectid, ref string runid, ref string runtype, ref string logid, Appender!string outstr)
{
    if (!validate_id(projectid, "projectit", outstr))
        return false;
    if (!validate_id(runid, "runid", outstr))
        return false;
    if (logid != "" && !validate_id(logid, "logid", outstr))
        return false;
    if (!validateNonEmpty(runtype, "runtype", outstr))
        return false;

    runtype = sql_quote(runtype);

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
    string runid = lookup(userhash, "runid");
    string logid = lookup(userhash, "logid");
    string runtype = lookup(userhash, "runtype");

    if (!validateInput(projectid, runid, runtype, logid, valout))
        goto Lerror;

    sql_exec(text("update ", (runtype == "pull" ? "pull_" : ""), "test_runs set deleted = true where id = ", runid));
    sql_exec(text("update ", (runtype == "pull" ? "pull_" : ""), "test_runs set end_time = now() where end_time is null and id = ", runid));
    sql_exec(text("update ", (runtype == "pull" ? "pull_" : ""), "test_data set end_time = now() where end_time is null and test_run_id = ", runid));

    outstr.put(text("Location: ", getURLProtocol(hash) , "://", lookup(hash, "SERVER_NAME"), "/",
               (runtype == "pull" ? "pull" : "test_data"),
               ".ghtml?",
               "projectid=", projectid, "&",
               "runid=", runid));
    if (logid != "")
        outstr.put(text("&logid=", logid));
    outstr.put("\n\n");
}

