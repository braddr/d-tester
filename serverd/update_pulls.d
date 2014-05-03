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

Pull loadPullFromGitHub(Repository repo, Pull current_pull, ulong pullid)
{
    JSONValue jv;
    if (!github.getPull(repo.owner, repo.name, to!string(pullid), jv))
        return null;

    Pull pull = makePullFromJson(jv, repo);

    if (current_pull.head_sha == pull.head_sha)
        pull.head_date = current_pull.head_date;
    else
    {
        string date = loadCommitDateFromGithub(repo, pull.head_sha);
        if (!date) return null;
        pull.head_date = SysTime.fromISOExtString(date, UTC());;
    }

    return pull;
}

string loadCommitDateFromGithub(Repository repo, string sha)
{
    JSONValue jv;
    if (!github.getCommit(repo.owner, repo.name, sha, jv))
        return null;

    string s = jv.object["commit"].object["committer"].object["date"].str;

    return s;
}

void updatePullAndGithub(Repository repo, Pull current_pull, Pull github_pull)
{
    bool rc = updatePull(repo, current_pull, github_pull);

    if (rc && current_pull.auto_pull != 0)
    {
        writelog("    clearing auto-pull state");
        JSONValue jv;
        github.addPullComment(repo.owner, repo.name, to!string(current_pull.pull_id), "Pull updated, auto_merge toggled off", jv);
        sql_exec(text("update github_pulls set auto_pull = null where id = ", current_pull.id));
    }
}

bool processProject(Pull[ulong] knownpulls, Repository repo, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        Pull p = makePullFromJson(obj, repo);
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
                    writelog("ERROR: %s/%s/%s, new pull request with null head.repo, skipping", repo.owner, repo.name, p.pull_id);
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
            string date = loadCommitDateFromGithub(repo, p.head_sha);
            if (!date) continue;
            p.head_date = SysTime.fromISOExtString(date, UTC());;
        }

        if (isNew)
            newPull(repo, p);
        else
            updatePullAndGithub(repo, current_pull, p);
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
            writelog("processing pulls for %s/%s/%s", rv.owner, rv.name, rv.refname);

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
                if (!github.getPulls(rv.owner, rv.name, jv, nextlink))
                    continue projloop;

                if (jv.type != JSON_TYPE.ARRAY)
                {
                    writelog("  github pulls data malformed, expected an array");
                    break;
                }

                if (!processProject(knownpulls, rv, jv))
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
                Pull p = loadPullFromGitHub(rv, *tmp, k);
                if (p)
                    updatePullAndGithub(rv, *tmp, p);
            }
        }
    }
}

int main(string[] args)
{
    LOGNAME = "/var/log/update-pulls.log";

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

    // loads the tree of Project -> Repositories
    Project[ulong] projects = loadProjects();

    update_pulls(projects);

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
