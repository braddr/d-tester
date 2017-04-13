module clientapi.get_runnable_pull;

import config;
import mysql;
static import clientapi.finish_pull_run;
import serverd;
import utils;
import validate;

import model.project;
import model.pull;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.random;
import std.range;

// ptr1 == already built or not for specific platforms
// ptr2 == already failed
sqlrow[] getPullToBuild(string hostid)
{
    sql_exec(text(
        //      0          1     2         3           4          5        6        7       8
        "select ghp_id,    p_id, cap_name, auto_merge, head_date, repo_id, pull_id, cap_id, is_passing
           from (
                  select ghp.head_date, ghp.id as ghp_id, p.id as p_id, ghp.repo_id, ghp.pull_id, c.id as cap_id, c.name as cap_name, ifnull(ptr2.max_rc = 0,true) as is_passing, if(p.allow_auto_merge, ifnull(ghp.auto_pull, 0),0) as auto_merge
                    from (github_pulls ghp, github_users ghu, project_repositories pr, projects p, project_capabilities pc, capabilities c)
                         left join pull_test_runs ptr1 use index (g_p_id) on (ptr1.deleted = false and ptr1.g_p_id = ghp.id and ptr1.project_id = p.id and c.name = ptr1.platform)
                         left join (
                             select g_p_id, project_id, max(rc) as max_rc
                               from pull_test_runs
                              where deleted = false
                              group by g_p_id, project_id
                         ) ptr2 on (ptr2.g_p_id = ghp.id and ptr2.project_id = p.id)
                         left join pull_suppressions ps on (ps.g_p_id = ghp.id and ps.platform = c.name)
                   where ghu.pull_approver is not null and
                         ghu.id = ghp.user_id and
                         ghp.open = true and
                         ghp.repo_id = pr.repository_id and
                         pr.project_id = p.id and
                         pc.project_id = p.id and
                         pc.capability_id = c.id and
                         c.capability_type_id = 1 and
                         ptr1.platform is null and
                         ps.id is null
               ) todo, build_host_capabilities bhc, build_host_projects bhp
          where todo.cap_id = bhc.capability_id and
                bhc.host_id = ", hostid, " and bhp.host_id = ", hostid, " and bhp.project_id = p_id",
        " order by auto_merge desc, is_passing desc, head_date desc
          limit 1;"));
    sqlrow[] rows = sql_rows();
    return rows;
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

string recordRunStart(string hostid, string platform, ulong project_id, ulong ghp_id, string pull_sha)
{
    sql_exec(text("insert into pull_test_runs (id, g_p_id, host_id, project_id, platform, sha, start_time, deleted) values (null, ",
                  ghp_id, ", ", hostid, ", ", project_id, ", \"", platform, "\", \"", pull_sha, "\", now(), false)"));
    sql_exec("select last_insert_id()");
    sqlrow lastidrow = sql_row();

    return lastidrow[0];
}

string recordMasterStart(string hostid, string platform, ulong projectid)
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

bool validateInput(ref string raddr, ref string rname, ref string hostid, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_knownhost(raddr, rname, hostid, outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    return true;
}

void output(string clientver, string runid, string platform, Project proj, Pull[] pulls, Appender!string outstr)
{
    if (clientver != "5")
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
                formattedWrite(outstr, "17 %s %s %s\n", getRepoIndex(proj, p.repo_id), p.head_git_url, p.head_ref);

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

Pull[] selectPullsToBuild(string hostid, ref string project_id, ref string platform)
{
    sqlrow[] rows = getPullToBuild(hostid); // ghp_id, project_id, cap_name, auto_merge, head_date, repo_id, pull_id, cap_id, is_passing
    if (rows.length == 0)
        return [];

    sqlrow row = rows[0];
    Pull p = loadPullById(to!ulong(row[0]));
    p.auto_pull = to!ulong(row[3]);

    project_id = row[1];
    platform   = row[2];

    // TODO: add support for related pulls
    return [p];
}

Project selectMasterToBuild(string hostid, ref string platform)
{
    sql_exec(text(
        //      0     1        2        3             4       5
        "select p_id, p_label, p_ptype, p_test_pulls, cap_id, cap_name
           from (
                  select p.id as p_id, p.menu_label as p_label, p.project_type as p_ptype, p.test_pulls as p_test_pulls, c.id as cap_id, c.name as cap_name
                    from (projects p, project_capabilities pc, capabilities c)
                         left join test_runs tr1 on (tr1.deleted = false and tr1.project_id = p.id and c.name = tr1.platform)
                   where p.enabled = true and
                         pc.project_id = p.id and
                         pc.capability_id = c.id and
                         c.capability_type_id = 1 and
                         tr1.platform is null
               ) todo, build_host_capabilities bhc, build_hosts bh, build_host_projects bhp
          where todo.cap_id = bhc.capability_id and
                bh.enabled = true and
                bh.id = bhc.host_id and
                bhp.host_id = bh.id and
                bhp.project_id = p_id and
                bhc.host_id = ", hostid,
        " limit 1;"));
    sqlrow[] rows = sql_rows();

    if (rows.length == 0)
        return null;

    platform = rows[0][5];
    return new Project(rows[0]);
}

size_t getRepoIndex(Project proj, ulong repo_id)
{
    foreach(i, r; proj.repositories)
    {
        if (r.id == repo_id)
        {
            return i;
        }
    }
    assert(false, "um.. repo not found?");
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string rname = lookup(userhash, "hostname");
    string hostid;
    string clientver = lookup(userhash, "clientver");

    if (!validateInput(raddr, rname, hostid, clientver, outstr))
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

    string pull_project_id; // temporary until decided to do a pull
    string pull_platform;   // temporary until decided to do a pull
    Pull[] pulls = selectPullsToBuild(hostid, pull_project_id, pull_platform);

    string master_platform; // temporary until decided to do a master
    Project master_proj = selectMasterToBuild(hostid, master_platform);

    bool doPull = false;
    bool doMaster = false;
    if (pulls.length > 0 && pulls[0].auto_pull != 0)
        doPull = true;
    else if (master_proj)
        doMaster = true;
    else if (pulls.length > 0)
        doPull = true;

    if (!doPull && !doMaster)
    {
        outstr.put(skip);
        return;
    }

    string runid;

    string platform;
    Project proj;

    if (doPull)
    {
        platform = pull_platform;
        proj = loadProjectById(to!ulong(pull_project_id));
        runid = recordRunStart(hostid, platform, proj.id, pulls[0].id, pulls[0].head_sha);
        writelog("  building: project %s, platform %s, %s", proj.id, platform, pulls[0]);
    }
    else
    {
        platform = master_platform;
        proj = master_proj;
        pulls = null;
        runid = recordMasterStart(hostid, platform, proj.id);
        writelog("  building: project %s, platform %s, master", proj.id, platform);
    }

    try
    {
        string path = "/media/ephemeral0/auto-tester/" ~ (doMaster ? "test-results/" : "pull-results/pull-") ~ runid;
        mkdir(path);
    }
    catch(Exception e) { writelog("  caught exception: %s", e); }

    output(clientver, runid, platform, proj, pulls, outstr);

//    if (doPull) // TODO: this an be made to work with master runs as well
//        clientapi.finish_pull_run.updateGithubPullStatus(runid, outstr);
}

