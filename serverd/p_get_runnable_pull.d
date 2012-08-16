module p_get_runnable_pull;

import mysql;
import serverd;
import utils;

import std.conv;
import std.format;
import std.range;

alias string[] sqlrow;

void loadAllRequests(ref sqlrow[string] openPulls)
{
    // get set of pull requests that need to have runs
    //               0      1              2       3           4            5                6            7
    sql_exec("select gp.id, gp.project_id, p.name, gp.pull_id, gp.head_sha, gp.head_git_url, gp.head_ref, gp.updated_at from github_pulls gp, projects p, github_users u where gp.open and gp.project_id = p.id and gp.user_id = u.id and u.trusted and gp.id != 48");
    sqlrow[] rows = sql_rows();

    foreach(ref row; rows) { openPulls[row[0]] = row; }
}

void filterAlreadyCompleteRequests(string platform, ref sqlrow[string] openPulls)
{
    // get set of past tests for this platform and the above set of pull requests
    sql_exec(text("select ptr.id, ptr.g_p_id, ptr.sha from pull_test_runs ptr, github_pulls ghp where ptr.platform='", sql_quote(platform), "' and ptr.g_p_id = ghp.id and ghp.open=true and ptr.deleted=false"));
    sqlrow[] rows = sql_rows();

    // for each past test, remove entries from openPulls where there exists a run that matches the pull id and it's head ref
    foreach (row; rows)
    {
        //writelog("previous run: g_p_id = %s", row[1]);

        sqlrow* pull = row[1] in openPulls;
        if (pull == null)
            continue; // happens when there's multiple runs for the same pull.  After the head matching run is processed, the rest will not find a match.

        //writelog("  project: %s, pull_id: %s, head_sha: %s, last_sha: %s", (*pull)[2], (*pull)[3], (*pull)[4], row[2]);
        if ((*pull)[4] == row[2])
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
    foreach(key, row; openPulls) { sorted[row[7]] = row; }

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

sqlrow recordRunStart(string raddr, string platform, sqlrow pull)
{
    sql_exec(text("insert into pull_test_runs (id, g_p_id, pull_id, reporter_ip, platform, sha, start_time, deleted) values (null, ", pull[0], ", ", pull[3], ", \"", sql_quote(raddr), "\", \"", sql_quote(platform), "\", \"", pull[4], "\", now(), false)"));
    sql_exec("select last_insert_id()");
    sqlrow lastidrow = sql_row();

    return lastidrow;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    auto tmpout = appender!string();
    if (!auth_check(raddr, tmpout))
    {
        outstr.put(tmpout.data);
        return;
    }

    string platform = lookup(userhash, "os");
    if (platform.empty)
    {
        outstr.put("bad input: missing os\n");
        return;
    }

    string hostname = lookup(userhash, "hostname");
    //if (!hostname.empty && hostname == "diamond")
    //{
    //    outstr.put("skip\n");
    //    return;
    //}

    sqlrow[string] openPulls;
    loadAllRequests(openPulls);

    filterAlreadyCompleteRequests(platform, openPulls);

    if (openPulls.length > 0)
    {
        sqlrow pull = selectOnePull(openPulls);

        sqlrow runid = recordRunStart(raddr, platform, pull);

        writelog("building: %s\n", pull);
        formattedWrite(outstr, "%s\n%s\n%s\n%s\n", runid[0], pull[2], pull[5], pull[6], pull[4]);  // runid, project, url, ref, sha
    }
    else
        outstr.put("skip\n");
}

