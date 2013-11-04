module p_toggle_auto_merge;

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

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    string raddr = lookup(hash, "REMOTE_ADDR");
    string projectid = lookup(userhash, "projectid");
    string repoid = lookup(userhash, "repoid");
    string pullid = lookup(userhash, "pullid");
    string ghp_id = lookup(userhash, "ghp_id");

    auto valout = appender!string;
    if (!validateInput(raddr, projectid, repoid, pullid, ghp_id, valout))
    {
        outstr.put("Content-type: text/plain\n\n");
        outstr.put(valout.data);
        return;
    }

    if (!updateStore(ghp_id))
        return;

    outstr.put(text("Location: http://", lookup(hash, "SERVER_NAME"), "/test-results/pull-history.ghtml?",
               "projectid=", projectid, "&",
               "repoid=", repoid, "&",
               "pullid=", pullid,
               "\n\n"));
}
