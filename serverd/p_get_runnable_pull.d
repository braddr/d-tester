module p_get_runnable_pull;

import mysql;
import master = p_get_runnable_master;
static import p_finish_pull_run;
import serverd;
import utils;
import validate;

import std.conv;
import std.file;
import std.format;
import std.range;

void loadAllOpenRequests(ref sqlrow[string] openPulls, string hostid)
{
    // get set of pull requests that need to have runs
    //                 0      1     2       3           4            5                6            7              8             9        10
    string q = text(
               "select gp.id, r.id, r.name, gp.pull_id, gp.head_sha, gp.head_git_url, gp.head_ref, gp.updated_at, gp.head_date, rb.name, p.id "
               "from github_pulls gp, projects p, repositories r, repo_branches rb, github_users u, build_host_projects bhp "
               "where gp.open = true and "
               "  gp.r_b_id = rb.id and "
               "  rb.repository_id = r.id and "
               "  p.id = r.project_id and "
               "  gp.user_id = u.id and "
               "  u.trusted = true and "
               "  p.enabled = true and "
               "  p.test_pulls = true and "
               "  bhp.project_id = r.project_id and "
               "  bhp.host_id = ", hostid);

    sql_exec(q);
    sqlrow[] rows = sql_rows();

    foreach(ref row; rows) { openPulls[row[0]] = row; }
}

master.project loadProjectById(string projectid)
{
    sql_exec(text("select p.id, p.name, r.id, r.name, rb.name "
                  "  from projects p, repositories r, repo_branches rb "
                  " where r.id = rb.repository_id and "
                  "       p.id = r.project_id and "
                  "       p.id = ", projectid,
                  " order by p.id, r.id, rb.id"));

    sqlrow[] rows = sql_rows();

    master.project[] projects;
    master.project* proj = null;
    foreach (row; rows)
    {
        if (!proj || proj.project_id != row[0])
        {
            projects ~= master.project(row[0], row[1], []);
            proj = &(projects[$-1]);
        }
        proj.branches ~= master.repo_branch(row[2], row[3], row[4]);
    }

    return projects[0];
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

        //writelog("  repo: %s, pull_id: %s, head_sha: %s, last_sha: %s", (*pull)[2], (*pull)[3], (*pull)[4], row[2]);
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
    sqlrow[string] noRuns;
    sqlrow[string] allPass;
    sqlrow[string] somePass;
    sqlrow[string] allFail;
    foreach(key, row; openPulls)
    {
        if (auto s = key in stats)
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
        if (allPass.length > 0)
            return selectOnePull_byNewest(allPass);
        else if (noRuns.length > 0)
            return selectOnePull_byNewest(noRuns);
        else if (somePass.length > 0)
            return selectOnePull_byNewest(somePass);
        else
            return selectOnePull_byNewest(allFail);
    }
}

sqlrow recordRunStart(string hostid, string platform, sqlrow pull)
{
    sql_exec(text("insert into pull_test_runs (id, g_p_id, host_id, platform, sha, start_time, deleted) values (null, ",
                  pull[0], ", ", hostid, ", \"", platform, "\", \"", pull[4], "\", now(), false)"));
    sql_exec("select last_insert_id()");
    sqlrow lastidrow = sql_row();

    return lastidrow;
}

void tryToCleanup(string hostid)
{
    sql_exec(text("select ptr.id, r.name, ghp.pull_id "
                  "from pull_test_runs ptr, repositories r, repo_branches rb, github_pulls ghp "
                  "where ptr.g_p_id = ghp.id and "
                  "  ghp.r_b_id = rb.id and "
                  "  rb.repository_id = r.id and "
                  "  ptr.deleted = 0 and "
                  "  ptr.host_id = ", hostid, " and "
                  "  ptr.end_time is null"));
    sqlrow[] rows = sql_rows();
    foreach (row; rows)
    {
        writelog("  cleaning up in progress run: %s/%s", row[1], row[2]);
        sql_exec(text("update pull_test_runs set deleted = 1 where id = ", row[0]));
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

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rname = lookup(userhash, "hostname");
    string hostid;
    string platform = lookup(userhash, "os");
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, rname, hostid, platform, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);

    if (exists("/tmp/serverd.suspend"))
    {
        outstr.put("skip\n");
        return;
    }

    tryToCleanup(hostid);

    sqlrow[string] openPulls;
    loadAllOpenRequests(openPulls, hostid);

    filterAlreadyCompleteRequests(platform, openPulls);
    filterSuppressedBuilds(platform, openPulls);

    if (openPulls.length > 0)
    {
        sqlrow pull = selectOnePull(openPulls);

        sqlrow runid = recordRunStart(hostid, platform, pull);

        master.project proj = loadProjectById(pull[10]);

        try
        {
            string path = "/home/dwebsite/pull-results/pull-" ~ runid[0];
            mkdir(path);
        }
        catch(Exception e) { writelog("  caught exception: %s", e); }

        writelog("  building: %s", pull);
        // runid
        formattedWrite(outstr, "%s\n", runid[0]);
        switch (clientver)
        {
            case "1":
                // repo, url, ref, sha, branch
                formattedWrite(outstr, "%s\n%s\n%s\n%s\n%s\n", pull[2], pull[5], pull[6], pull[4], pull[9]);
                break;
            case "2":
                // branch, repo, url, ref, sha
                formattedWrite(outstr, "%s\n%s\n%s\n%s\n%s\n", pull[9], pull[2], pull[5], pull[6], pull[4]);
                break;
            case "3":
                formattedWrite(outstr, "%s\n", proj.project_name);
                formattedWrite(outstr, "%s\n", platform);

                // repo, url, ref, sha
                formattedWrite(outstr, "%s\n%s\n%s\n%s\n", pull[2], pull[5], pull[6], pull[4]);

                // list of repositories
                formattedWrite(outstr, "%s\n", proj.branches.length);
                foreach (p; proj.branches)
                    formattedWrite(outstr, "%s\n%s\n%s\n", p.repo_id, p.repo_name, p.branch_name);

                switch (proj.project_name)
                {
                    case "D-Programming-Language":
                        // steps to execute
                        //     num steps
                        //     checkout(1) dummy
                        //     merge(9|10|11) repo(0|1|2)
                        //     build(2) dmd(0), build(3) druntime(1), build(4) phobos(2)
                        //     test(5) druntime(1), test(6) phobos(2), test(7) dmd(0)
                        formattedWrite(outstr, "16\n");
                        formattedWrite(outstr, "1 0\n");
                        switch (pull[2])
                        {
                            case "dmd":      formattedWrite(outstr, "%s %s\n",  9, 0); break;
                            case "druntime": formattedWrite(outstr, "%s %s\n", 10, 1); break;
                            case "phobos":   formattedWrite(outstr, "%s %s\n", 11, 2); break;
                            default: assert(false, "unknown repository");
                        }
                        formattedWrite(outstr, "2 0 3 1 4 2\n");
                        formattedWrite(outstr, "5 1 6 2 7 0\n");
                        break;
                    case "D-Programming-GDC":
                        // steps to execute
                        //     num steps
                        //     checkout(1) dummy
                        //     merge(14) repo(0)
                        //     build(12) gdc(0)
                        //     test(13) gdc(0)
                        formattedWrite(outstr, "8\n");
                        formattedWrite(outstr, "1 0\n");
                        switch (pull[2])
                        {
                            case "GDC":      formattedWrite(outstr, "%s %s\n", 14, 0); break;
                            default: assert(false, "unknown repository");
                        }
                        formattedWrite(outstr, "12 0 13 0\n");
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

        p_finish_pull_run.updateGithub(runid[0], outstr);
    }
    else
        outstr.put("skip\n");
}

