module p_update_pulls;

import config;
import github_apis;
import mysql;
import utils;

import model.project;
import model.pull;
import model.user;

import etc.c.curl;
import std.conv;
import std.datetime;
import std.json;
import std.format;
import std.process;
import std.range;
import std.string;
import std.stdio;

CURL* curl;
Github github;
alias string[] sqlrow;

Pull loadPullFromGitHub(Project proj, Repository repo, Pull current_pull, ulong pullid)
{
    JSONValue jv;
    if (!github.getPull(proj.name, repo.name, to!string(pullid), jv))
        return null;

    Pull pull = makePullFromJson(jv, proj, repo);

    if (current_pull.head_sha == pull.head_sha)
        pull.head_date = current_pull.head_date;
    else
    {
        string date = loadCommitDateFromGithub(proj, repo, pull.head_sha);
        if (!date) return null;
        pull.head_date = SysTime.fromISOExtString(date, UTC());;
    }

    return pull;
}

string loadCommitDateFromGithub(Project proj, Repository repo, string sha)
{
    JSONValue jv;
    if (!github.getCommit(proj.name, repo.name, sha, jv))
        return null;

    string s = jv.object["commit"].object["committer"].object["date"].str;

    return s;
}

void updatePullAndGithub(Project proj, Repository repo, Pull current_pull, Pull github_pull)
{
    bool rc = updatePull(proj, repo, current_pull, github_pull);

    if (rc && current_pull.auto_pull != 0)
    {
        writelog("    clearing auto-pull state");
        JSONValue jv;
        github.addPullComment(proj.name, repo.name, to!string(current_pull.pull_id), "Pull updated, auto_merge toggled off", jv);
        sql_exec(text("update github_pulls set auto_pull = null where id = ", current_pull.id));
    }
}

bool processProject(Pull[ulong] knownpulls, Project proj, Repository repo, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        Pull p = makePullFromJson(obj, proj, repo);
        if (!p) continue;

        Pull* tmp = p.pull_id in knownpulls;
        knownpulls.remove(p.pull_id);
        Pull current_pull = tmp ? *tmp : null;

        bool isNew = false;
        if (!current_pull)
        {
            current_pull = loadPull(repo.id, p.pull_id);

            if (!current_pull)
            {
                if (!p.head_usable)
                {
                    writelog("ERROR: %s/%s/%s, new pull request with null head.repo, skipping", proj.name, repo.name, p.pull_id);
                    continue;
                }

                isNew = true;
            }
        }

        if (!isNew && current_pull.head_sha == p.head_sha)
            p.head_date = current_pull.head_date;
        else if (!p.head_usable)
            continue;
        else
        {
            string date = loadCommitDateFromGithub(proj, repo, p.head_sha);
            if (!date) continue;
            p.head_date = SysTime.fromISOExtString(date, UTC());;
        }

        if (isNew)
            newPull(proj, repo, p);
        else
            updatePullAndGithub(proj, repo, current_pull, p);
    }

    return true;
}

void update_pulls(Project[ulong] projects)
{
projloop:
    foreach(pk, pv; projects)
    {
        foreach (rk, rv; pv.repositories)
        {
            writelog("processing pulls for %s/%s/%s", pv.name, rv.name, rv.refname);

            sql_exec(text("select ", getPullColumns()," from github_pulls where repo_id = ", rv.id, " and open = true"));
            sqlrow[] rows = sql_rows();
            Pull[ulong] knownpulls;
            foreach(row; rows)
            {
                Pull p = makePullFromRow(row);
                knownpulls[to!ulong(row[2])] = p;
            }

            string nextlink;
            do
            {
                JSONValue jv;
                if (!github.getPulls(pv.name, rv.name, jv, nextlink))
                    continue projloop;

                if (jv.type != JSON_TYPE.ARRAY)
                {
                    writelog("  github pulls data malformed, expected an array");
                    break;
                }

                if (!processProject(knownpulls, pv, rv, jv))
                {
                    writelog("  failed to process project, skipping repo");
                    continue projloop;
                }
            }
            while (nextlink != "");

            //writelog("closing pulls");
            // any elements left in knownpulls means they're no longer open, so mark closed
            foreach(k; knownpulls.keys)
            {
                Pull* tmp = k in knownpulls;
                Pull p = loadPullFromGitHub(pv, rv, *tmp, k);
                if (p)
                    updatePullAndGithub(pv, rv, *tmp, p);
            }
        }
    }
}

void backfill_pulls()
{
    string ids_with_no_repo =
        "8, "
        "105, 137, "
        "203, 204, 206, 241, 257, 268, "
        "301, 314, 316, 323, 328, "
        "401, 425, 430, 495, "
        "505, 519, 540, "
        "679, "
        "720, 726, 758, 777, "
        "810, 856, "
        "1009, 1027, 1042, 1060, 1072, 1074, "
        "1137, 1144, 1153, "
        "1230, 1294, "
        "1306, 1316, 1321, 1322, 1331, 1340, 1342, 1349, 1350, 1351, 1352, 1360, "
        "1478, 1479, 1480, 1491, "
        "2382";



    // resetting to open where we don't het have a create_date to force a re-populate from github
    // TODO: build a better mechanism than having to open the request
    sql_exec(text("update github_pulls set open=1 where open=0 and create_date is null and base_ref = \"master\" and id not in (", ids_with_no_repo, ") limit 10"));
}

int main(string[] args)
{
    LOGNAME = "/tmp/update-pulls.log";

    writelog("start app");

    load_config(getenv("SERVERD_CONFIG"));

    if (!sql_init())
    {
        writelog("failed to initialize sql connection, exiting");
        return 1;
    }

    curl = curl_easy_init();
    if (!curl)
    {
        writelog("failed to initialize curl library, exiting");
        return 1;
    }

    github = new Github(c.github_user, c.github_passwd, c.github_clientid, c.github_clientsecret, curl);

    // loads the tree of Project -> Repository -> RepoBranch
    Project[ulong] projects = loadProjects();

    //backfill_pulls();
    update_pulls(projects);

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
