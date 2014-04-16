module clientapi.get_runnable_master;

import config;
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
        writelog("  cleaning up in progress master run: %s", row[0]);
        sql_exec(text("update test_runs set deleted = 1 where id = ", row[0]));
    }
}

bool validateInput(ref string rname, ref string raddr, ref string hostid, ref string platform, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_knownhost(raddr, rname, hostid, outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    // TODO: validate that the host and platform match

    return true;
}

struct repo_branch
{
    string repo_id;
    string repo_name;
    string branch_name;
}

struct project
{
    string project_id;
    string project_name;
    repo_branch[] branches;
}

project[] loadProjects(string hostid)
{
    sql_exec(text("select p.id, p.name, r.id, r.name, rb.name "
                  "  from projects p, repositories r, repo_branches rb, build_host_projects bhp "
                  " where r.id = rb.repository_id and "
                  "       p.id = r.project_id and "
                  "       p.enabled = true and "
                  "       bhp.project_id = p.id and "
                  "       bhp.host_id = ", hostid,
                  " order by p.id, r.id, rb.id"));

    sqlrow[] rows = sql_rows();

    project[] projects;
    project* proj = null;
    foreach (row; rows)
    {
        if (!proj || proj.project_id != row[0])
        {
            projects ~= project(row[0], row[1], []);
            proj = &(projects[$-1]);
        }
        proj.branches ~= repo_branch(row[2], row[3], row[4]);
    }

    return projects;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rname = lookup(userhash, "hostname");
    string hostid;
    string platform = lookup(userhash, "os");
    string force = lookup(userhash, "force");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(rname, raddr, hostid, platform, clientver, outstr))
        return;

    if (!c.builds_enabled)
    {
        outstr.put("skip\n");
        return;
    }

    updateHostLastCheckin(hostid, clientver);
    tryToCleanup(hostid);

    project[] projects = loadProjects(hostid);

    projects = projects.filter!(a => shouldDoBuild(force.length != 0, platform, a.project_id)).array;
    if (projects.length > 0)
    {
        size_t idx = uniform(0, projects.length);
        project proj = projects[idx];

        string runid = getNewID(platform, hostid, proj.project_id);
        try
        {
            string path = "/home/dwebsite/test-results/" ~ runid;
            mkdir(path);
        }
        catch (Exception e)
        {
            writelog("  caught exception: %s", e);
            outstr.put("skip\n");
            return;
        }

        writelog("  starting new master build: %s", runid);
        formattedWrite(outstr, "%s\n", runid);
        switch (clientver)
        {
            case "3":
                formattedWrite(outstr, "%s\n", proj.project_name);
                formattedWrite(outstr, "%s\n", platform);

                formattedWrite(outstr, "%s\n", proj.branches.length);
                foreach (p; proj.branches)
                    formattedWrite(outstr, "%s\n%s\n%s\n", p.repo_id, p.repo_name, p.branch_name);

                switch (proj.project_name)
                {
                    case "D-Programming-Language":
                        // num steps
                        // checkout(1) dummy
                        // build(2) dmd(0), build(3) druntime(1), build(4) phobos(2)
                        // test(5) druntime(1), test(6) phobos(2), test(7) dmd(0)
                        formattedWrite(outstr, "14\n");
                        formattedWrite(outstr, "1 0 2 0 3 1 4 2 5 1 6 2 7 0\n");
                        break;
                    case "D-Programming-GDC":
                        // num steps
                        // checkout(1) dummy
                        // build(12) gdc(0)
                        // test(13) gdc(0)
                        formattedWrite(outstr, "6\n");
                        formattedWrite(outstr, "1 0 12 0 13 0\n");
                        break;
                    default:
                        writelog ("  unknown project: %s", proj.project_name);
                        outstr.put("skip\n");
                        break;
                }
                break;
            default:
                writelog("  illegal clientver: %s", clientver);
                outstr.put("skip\n");
        }
        //p_finish_pull_run.updateGithubPullStatus(runid[0], outstr);
    }
    else
        outstr.put("skip\n");
}

