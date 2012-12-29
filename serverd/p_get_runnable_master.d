module p_get_runnable_master;

import mysql;
//static import p_finish_pull_run;
import serverd;
import utils;
import validate;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.random;
import std.range;

bool shouldDoBuild(bool force, string platform, string projectid)
{
    bool dobuild = force;

    if (dobuild)
    {
        writelog("  forced build, deprecating old build(s)");
        sql_exec(text("update test_runs set deleted=1 where platform = \"", platform, "\" and deleted=0"));
    }

    if (!dobuild)
    {
        sql_exec(text("select id "
                      "from test_runs "
                      "where platform = \"", platform, "\" and "
                      "  project_id = ", projectid, " and "
                      "  deleted = 0"));
        sqlrow[] rows = sql_rows();

        if (rows.length == 0)
            dobuild = true;
    }

    return dobuild;
}

string getNewID(string platform, string hostid, string projectid)
{
    sql_exec(text("insert into test_runs (start_time, project_id, host_id, platform, deleted) "
                  "values (now(), ", projectid, ", \"", hostid, "\", \"", platform, "\", false)"));
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

struct proj_branch
{
    string projectid;
    string branch;
}

proj_branch[] loadProjects()
{
    sql_exec("select distinct project_id, rb.name from projects p, repositories r, repo_branches rb where r.id = rb.repository_id and p.id = r.project_id");

    sqlrow[] rows = sql_rows();

    proj_branch[] results;
    foreach (row; rows)
        results ~= proj_branch(row[0], row[1]);

    return results;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rname = lookup(userhash, "hostname");
    string hostid;
    string platform = lookup(userhash, "os");
    string force = lookup(userhash, "force");
    bool supportprojects = lookup(userhash, "supportprojects") == "true";

    if (!validateInput(rname, raddr, hostid, platform, outstr))
        return;

    updateHostLastCheckin(hostid);
    tryToCleanup(hostid);

    proj_branch[] projects = [ proj_branch("1", "master") ];
    if (supportprojects)
        projects = loadProjects();

    projects = projects.filter!(a => shouldDoBuild(force.length != 0, platform, a.projectid)).array;
    if (projects.length > 0)
    {
        size_t idx = uniform(0, projects.length);
        proj_branch project = projects[idx];

        string runid = getNewID(platform, hostid, project.projectid);
        try
        {
            string path = "/home/dwebsite/test-results/" ~ runid;
            mkdir(path);
        }
        catch(Exception e)
        {
            writelog("  caught exception: %s", e);
            outstr.put("skip\n");
            return;
        }

        writelog("  starting new master build: %s", runid);
        formattedWrite(outstr, "%s\n", runid);
        if (supportprojects)
            formattedWrite(outstr, "%s\n", project.branch);
        //p_finish_pull_run.updateGithub(runid[0], outstr);
    }
    else
        outstr.put("skip\n");
}

