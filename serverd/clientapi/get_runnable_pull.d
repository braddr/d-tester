module clientapi.get_runnable_pull;

import config;
import mysql;
static import clientapi.finish_pull_run;
import serverd;
import utils;
import validate;

import model.project;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.random;
import std.range;

struct Pull
{
    string g_p_id;
    string project_id;
    ulong  repo_project_index; // index of this repo in the project.repositories array
    ulong  repo_id;
    string repo_name;
    string giturl;
    string gitref;
    string sha;
    bool merge;
}

void loadAllOpenRequests(ref sqlrow[string] openPulls, string hostid)
{
    // get set of pull requests that need to have runs
    //                 0      1     2       3           4            5                6            7              8             9      10    11                  12
    string q = text(
               "select gp.id, r.id, r.name, gp.pull_id, gp.head_sha, gp.head_git_url, gp.head_ref, gp.updated_at, gp.head_date, r.ref, p.id, p.allow_auto_merge, gp.auto_pull "
               "from github_pulls gp, projects p, repositories r, project_repositories pr, github_users u, build_host_projects bhp "
               "where gp.open = true and "
               "  gp.repo_id = r.id and "
               "  p.id = pr.project_id and "
               "  pr.repository_id = r.id and "
               "  gp.user_id = u.id and "
               "  u.pull_approver is not null and "
               "  p.enabled = true and "
               "  p.test_pulls = true and "
               "  bhp.project_id = p.id and "
               "  bhp.host_id = ", hostid);

    sql_exec(q);
    sqlrow[] rows = sql_rows();

    foreach(ref row; rows) { openPulls[row[0]] = row; }
}

void filterAlreadyCompleteRequests(string platform, ref sqlrow[string] openPulls)
{
    // get set of past tests for this platform and the above set of pull requests
    sql_exec(text("select ptr.id, ptr.g_p_id, ptr.sha "
                  "from pull_test_runs ptr, github_pulls ghp "
                  "where ptr.platform='", platform, "' and "
                  "ptr.g_p_id = ghp.id and "
                  "ghp.open = true and "
                  "ptr.deleted = false"));
    sqlrow[] rows = sql_rows();

    // for each past test, remove entries from openPulls where there exists a run that matches the pull id and it's head ref
    foreach (row; rows)
    {
        //writelog("previous run: g_p_id = %s", row[1]);

        sqlrow* pull = row[1] in openPulls;
        if (pull == null)
            continue; // happens when there's multiple runs for the same pull.  After the head matching run is processed, the rest will not find a match.

        //writelog("  repo_id: %s, repo_name: %s, pull_id: %s, head_sha: %s, last_sha: %s", (*pull)]1, (*pull)[2], (*pull)[3], (*pull)[4], row[2]);
        if ((*pull)[4] == row[2])
            openPulls.remove(row[1]);
    }
}

void filterSuppressedBuilds(string platform, ref sqlrow[string] openPulls)
{
    // get all suppressions for the given platform
    sql_exec(text("select s.id, s.g_p_id "
                  "from pull_suppressions s "
                  "where s.platform='", platform, "'"));
    sqlrow[] rows = sql_rows();

    // remove entries from openPulls
    foreach (row; rows)
    {
        //writelog("g_p_id = %s", row[1]);

        sqlrow* pull = row[1] in openPulls;
        if (pull == null)
            continue; // old suppression

        writelog("  suppressed build for pull id: %s/%s (%s)", (*pull)[2], (*pull)[3], row[1]);
        openPulls.remove(row[1]);
    }
}

alias int[2] stat;
stat[string] loadCurrentRunStatistics()
{
    sql_exec("select g_p_id, ifnull(rc,0), count(*) from pull_test_runs where deleted = 0 group by g_p_id, ifnull(rc,0)");
    sqlrow[] rows = sql_rows();

    // create map of id -> [#rc0, #rc1]
    stat[string] stats;
    foreach(row; rows)
    {
        if (row[1] != "0" && row[1] != "1") continue;

        if (row[0] !in stats)
        {
            stat s;
            stats[row[0]] = s;
        }

        stats[row[0]][to!int(row[1])] = to!int(row[2]);
    }

    //writelog("stats begin:");
    //foreach(key, s; stats)
    //    writelog("%s: %s", key, s);
    //writelog("stats end:");

    return stats;
}

sqlrow selectOnePull_byNewest(ref sqlrow[string] openPulls)
{
    // create map of update -> id -- subject to time collisions resulting in loosing runs
    sqlrow[string] sorted;
    foreach(key, row; openPulls) { sorted[row[8]] = row; }

    // sort and get the most recent
    string key = (sorted.keys.sort.reverse)[0];
    sqlrow pull = sorted[key];

    return pull;
}

sqlrow selectOnePull(ref sqlrow[string] openPulls)
{
    stat[string] stats = loadCurrentRunStatistics();

    //writelog("stats begin:");
    //foreach(key, s; stats)
    //    writelog("%s: %s", key, s);
    //writelog("stats end:");

    // filter past runs into buckets
    sqlrow[string] automerge;
    sqlrow[string] noRuns;
    sqlrow[string] allPass;
    sqlrow[string] somePass;
    sqlrow[string] allFail;
    foreach(key, row; openPulls)
    {
        if (row[11] == "1" && row[12] != "")
            automerge[key] = row;
        else if (auto s = key in stats)
        {
            if ((*s)[1] == 0) // no failures
                allPass[key] = row;
            else if ((*s)[0] == 0) // no passes
                allFail[key] = row;
            else // some of both
                somePass[key] = row;
        }
        else
            noRuns[key] = row;
    }

    version (none)
    {
        if (noRuns.length > 0)
            return selectOnePull_byNewest(noRuns);
        else if (allPass.length > 0)
            return selectOnePull_byNewest(allPass);
        else if (somePass.length > 0)
            return selectOnePull_byNewest(somePass);
        else
            return selectOnePull_byNewest(allFail);
    }
    else
    {
        if (automerge.length > 0)
            return selectOnePull_byNewest(automerge);
        else if (allPass.length > 0)
            return selectOnePull_byNewest(allPass);
        else if (noRuns.length > 0)
            return selectOnePull_byNewest(noRuns);
        else if (somePass.length > 0)
            return selectOnePull_byNewest(somePass);
        else
            return selectOnePull_byNewest(allFail);
    }
}

string recordRunStart(string hostid, string platform, const ref Pull pull)
{
    sql_exec(text("insert into pull_test_runs (id, g_p_id, host_id, project_id, platform, sha, start_time, deleted) values (null, ",
                  pull.g_p_id, ", ", hostid, ", ", pull.project_id, ", \"", platform, "\", \"", pull.sha, "\", now(), false)"));
    sql_exec("select last_insert_id()");
    sqlrow lastidrow = sql_row();

    return lastidrow[0];
}

string recordMasterStart(string platform, string hostid, ulong projectid)
{
    sql_exec(text("insert into test_runs (start_time, project_id, host_id, platform, deleted) "
                  "values (now(), ", projectid, ", \"", hostid, "\", \"", platform, "\", false)"));
    sql_exec("select last_insert_id()");
    sqlrow row = sql_row();

    return row[0];
}

void tryToCleanup(string hostid)
{
    sql_exec(text("select ptr.id, r.name, ghp.pull_id "
                  "from pull_test_runs ptr, repositories r, github_pulls ghp "
                  "where ptr.g_p_id = ghp.id and "
                  "  ghp.repo_id = r.id and "
                  "  ptr.deleted = 0 and "
                  "  ptr.host_id = ", hostid, " and "
                  "  ptr.end_time is null"));
    sqlrow[] rows = sql_rows();
    foreach (row; rows)
    {
        writelog("  cleaning up in progress run: %s, %s/%s", row[0], row[1], row[2]);
        sql_exec(text("update pull_test_runs set rc = 2 where rc is null and id = ", row[0]));
        sql_exec(text("update pull_test_runs set deleted = 1 where id = ", row[0]));
    }
}

void tryToCleanupMaster(string hostid)
{
    sql_exec(text("select id from test_runs where deleted = 0 and host_id = \"", hostid, "\" and end_time is null"));
    sqlrow[] rows = sql_rows();
    foreach (row; rows)
    {
        writelog("  cleaning up in progress master run: %s", row[0]);
        sql_exec(text("update test_runs set deleted = 1 where id = ", row[0]));
    }
}

bool validateInput(ref string raddr, ref string rname, ref string hostid, ref string platform, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_platform(platform, outstr))
        return false;
    if (!validate_knownhost(raddr, rname, hostid, outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    return true;
}

void output(string clientver, string runid, string platform, Project proj, Pull[] pulls, Appender!string outstr)
{
    if (clientver != "4" && clientver != "5")
    {
        writelog("  illegal clientver: %s", clientver);
        outstr.put("skip\n");
        return;
    }

    if (proj.project_type != 1 && proj.project_type != 2)
    {
        writelog ("  unknown project type: %s", proj.project_type);
        outstr.put("skip\n");
        return;
    }

    switch (clientver)
    {
        case "4":
            formattedWrite(outstr, "%s\n", runid);
            formattedWrite(outstr, "%s\n", (pulls.length == 0) ? "master" : "pull");
            formattedWrite(outstr, "%s\n", proj.repositories[0].owner);

            formattedWrite(outstr, "%s\n", platform);

            // list of repositories
            formattedWrite(outstr, "%s\n", proj.repositories.length);
            foreach (r; proj.repositories)
                formattedWrite(outstr, "%s\n%s\n%s\n", r.id, r.name, r.refname);

            switch (proj.project_type)
            {
                case 1:
                    formattedWrite(outstr, "1 0\n"); // checkout dummy

                    //  merge(9|10|11) repoindex(0|1|2) url ref
                    foreach (p; pulls)
                    {
                        int step, repoindex;
                        switch (p.repo_name)
                        {
                            case "dmd":      step =  9; repoindex = 0; break;
                            case "druntime": step = 10; repoindex = 1; break;
                            case "phobos":   step = 11; repoindex = 2; break;
                            default: assert(false, "unknown repository");
                        }
                        formattedWrite(outstr, "%s %s %s %s\n", step, repoindex, p.giturl, p.gitref);
                    }

                    formattedWrite(outstr, "2 0\n"); // build dmd
                    formattedWrite(outstr, "3 1\n"); // build druntime
                    formattedWrite(outstr, "4 2\n"); // build phobos
                    formattedWrite(outstr, "5 1\n"); // test druntime
                    formattedWrite(outstr, "6 2\n"); // test phobos
                    formattedWrite(outstr, "7 0\n"); // test dmd
                    break;
                case 2:
                    formattedWrite(outstr, "1 0\n"); // checkout dummy

                    // merge(14) repoindex(0) url ref
                    foreach (p; pulls)
                    {
                        int step, repoindex;
                        switch (p.repo_name)
                        {
                            case "GDC": step = 14; repoindex = 0; break;
                            default: assert(false, "unknown repository");
                        }
                        formattedWrite(outstr, "%s %s %s %s\n", step, repoindex, p.giturl, p.gitref);
                    }
                    formattedWrite(outstr, "12 0\n"); // build gdc
                    formattedWrite(outstr, "13 0\n"); // test gdc
                    break;
                default: assert(false);
            }
            break;

        case "5":
            formattedWrite(outstr, "%s\n", runid);
            formattedWrite(outstr, "%s\n", (pulls.length == 0) ? "master" : "pull");
            formattedWrite(outstr, "%s\n", proj.project_type);

            formattedWrite(outstr, "%s\n", platform);

            // list of repositories
            formattedWrite(outstr, "%s\n", proj.repositories.length);
            foreach (r; proj.repositories)
                formattedWrite(outstr, "%s\n%s\n%s\n%s\n", r.id, r.owner, r.name, r.refname);

            formattedWrite(outstr, "1 0\n"); // checkout dummy

            // merge
            foreach (p; pulls)
                formattedWrite(outstr, "17 %s %s %s\n", p.repo_project_index, p.giturl, p.gitref);

            // build
            foreach (i; 0 .. proj.repositories.length)
                formattedWrite(outstr, "15 %s\n", i);

            // test
            foreach (i; 0 .. proj.repositories.length)
                formattedWrite(outstr, "16 %s\n", i);

            break;
        default: assert(false);
    }
}

Pull[] selectPullsToBuild(string hostid, string platform)
{
    sqlrow[string] openPulls;
    loadAllOpenRequests(openPulls, hostid);

    filterAlreadyCompleteRequests(platform, openPulls);
    filterSuppressedBuilds(platform, openPulls);

    if (openPulls.length == 0)
        return null;

    sqlrow pull = selectOnePull(openPulls);
    Pull[] pulls = [Pull(pull[0], pull[10], 0, to!ulong(pull[1]), pull[2], pull[5], pull[6], pull[4], (pull[11] == "1" && pull[12] != ""))];
    return pulls;
}

bool shouldDoBuild(bool force, string platform, ulong projectid)
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

Project[] selectMasterToBuild(bool force, string hostid, string platform)
{
    Project[] projects = loadProjectsByHostId(to!ulong(hostid));

    projects = projects.filter!(a => shouldDoBuild(force, platform, a.id)).array;
    return projects;
}

void mapPullsToProj(Project proj, Pull[] pulls)
{
PullLoop:
    foreach(ref p; pulls)
    {
        foreach(i, r; proj.repositories)
        {
            if (r.id == p.repo_id)
            {
                p.repo_project_index = i;
                continue PullLoop;
            }
        }
    }
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

    if (!validateInput(raddr, rname, hostid, platform, clientver, outstr))
        return;

    string skip = "skip\n";

    if (!c.builds_enabled)
    {
        outstr.put(skip);
        return;
    }

    updateHostLastCheckin(hostid, clientver);

    if (exists("/tmp/serverd.suspend"))
    {
        outstr.put(skip);
        return;
    }

    tryToCleanup(hostid);
    tryToCleanupMaster(hostid);

    Pull[] pulls = selectPullsToBuild(hostid, platform);
    Project[] projects = selectMasterToBuild(force.length != 0, hostid, platform);

    bool doPull = false;
    bool doMaster = false;
    if (pulls.length > 0 && pulls[0].merge)
        doPull = true;
    else if (projects.length > 0)
        doMaster = true;
    else if (pulls.length > 0)
        doPull = true;

    if (!doPull && !doMaster)
    {
        outstr.put(skip);
        return;
    }

    string runid;
    Project proj;

    if (doPull)
    {
        proj = loadProjectById(to!ulong(pulls[0].project_id));
        mapPullsToProj(proj, pulls);
        runid = recordRunStart(hostid, platform, pulls[0]);
    }
    else
    {
        pulls = null;
        proj = projects[uniform(0, projects.length)];
        runid = recordMasterStart(platform, hostid, proj.id);
    }

    try
    {
        string path = "/media/ephemeral0/auto-tester/" ~ (doMaster ? "test-results/" : "pull-results/pull-") ~ runid;
        mkdir(path);
    }
    catch(Exception e) { writelog("  caught exception: %s", e); }

    writelog("  building: %s", pulls);

    output(clientver, runid, platform, proj, pulls, outstr);

//    if (doPull) // TODO: this an be made to work with master runs as well
//        clientapi.finish_pull_run.updateGithubPullStatus(runid, outstr);
}

