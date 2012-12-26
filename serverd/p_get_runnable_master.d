module p_get_runnable_master;

import mysql;
//static import p_finish_pull_run;
import serverd;
import utils;
import validate;

import std.conv;
import std.file;
import std.format;
import std.range;

bool shouldDoBuild(bool force, string platform)
{
    bool dobuild = force;

    if (dobuild)
    {
        writelog("  forced build, deprecating old build(s)");
        sql_exec(text("update test_runs set deleted=1 where platform = \"", platform, "\" and deleted=0"));
    }

    if (!dobuild)
    {
        sql_exec(text("select id from test_runs where platform = \"", platform, "\" and deleted = 0"));
        sqlrow[] rows = sql_rows();

        if (rows.length == 0)
            dobuild = true;
    }
   
    return dobuild; 
}

string getNewID(string platform, string hostid)
{
    sql_exec(text("insert into test_runs (start_time, project_id, host_id, platform, deleted) "
                  "values (now(), 1, \"", hostid, "\", \"", platform, "\", false)"));
    sql_exec("select last_insert_id()");
    sqlrow row = sql_row();

    return row[0];
}

void tryToCleanup(string hostid)
{
    sql_exec(text("select id from test_runs where deleted = 0 and host_id = \"", hostid, "\" and end_time is null"));
    sqlrow[] rows = sql_rows();
    foreach (row; rows)
    {
        writelog("  cleaning up in progress master run");
        sql_exec(text("update test_runs set deleted = 1 where id = ", row[0]));
    }
}

bool validateInput(ref string rname, ref string raddr, ref string hostid, ref string platform, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_knownhost(raddr, rname, hostid, outstr))
        return false;

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rname = lookup(userhash, "hostname");
    string hostid;
    string platform = lookup(userhash, "os");
    string force = lookup(userhash, "force");

    if (!validateInput(rname, raddr, hostid, platform, outstr))
        return;

    updateHostLastCheckin(hostid);
    tryToCleanup(hostid);

    if (shouldDoBuild(force.length != 0, platform))
    {
        string rid = getNewID(platform, hostid);
        try
        {
            string path = "/home/dwebsite/test-results/" ~ rid;
            mkdir(path);
        }
        catch(Exception e)
        {
            writelog("  caught exception: %s", e);
            outstr.put("skip\n");
            return;
        }

        writelog("  starting new master build: %s", rid);
        formattedWrite(outstr, "%s\n", rid);
        //p_finish_pull_run.updateGithub(runid[0], outstr);
    }
    else
        outstr.put("skip\n");
}

