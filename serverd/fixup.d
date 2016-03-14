module fixup;

// quick and dirty code to cleanup or backfill data, or whatever.

import config;
import github_apis;
import log;
import mysql_client;
import utils;

import model.project;
import model.pull;
import model.user;

import etc.c.curl;
import std.array;
import std.conv;
import std.datetime;
import std.json;
import std.process;

CURL* curl;
Github github;
alias string[] sqlrow;

bool init()
{
    LOGNAME = "/tmp/fixup.log";

    writelog("start app");

    load_config(environment["SERVERD_CONFIG"]);

    mysql = mysql_client.connect(c.db_host, 3306, c.db_user, c.db_passwd, c.db_db);

    curl = curl_easy_init();
    if (!curl)
    {
        writelog("failed to initialize curl library, exiting");
        return false;
    }

    github = new Github(c.github_user, c.github_passwd, c.github_clientid, c.github_clientsecret, curl);

    return true;
}

void main(string[] args)
{
    if (!init()) return;
    scope(exit)
    {
        writelog("shutting down");
        delete mysql;
    }

    Results r = mysql.query(text("select ghp.id, r.owner, r.name, ghp.pull_id from github_pulls ghp, repositories r where ghp.auto_pull is null and ghp.open = false and ghp.repo_id = r.id and ghp.id > ", args[1], " order by ghp.id limit ", args[2]));
    sqlrow[] rows = r.array();

    foreach (row; rows)
    {
        JSONValue jv;
        writelog("loading %s %s/%s/%s", row[0], row[1], row[2], row[3]);
        if (!github.getPull(row[1], row[2], row[3], jv))
        {
            writelog("  error loading pull, skipping");
            continue;
        }

        JSONValue * merged_by = "merged_by" in jv.object;
        if (!merged_by)
        {
            writelog("  missing merged_by field in response, skipping");
            continue;
        }

        if (merged_by.type != JSON_TYPE.OBJECT)
        {
            writelog("  missing merged_by field is not an object, skipping");
            continue;
        }

        JSONValue * id = "id" in merged_by.object;
        if (!id)
        {
            writelog("  missing merged_by.id field in response, skipping");
            continue;
        }
        if (id.type != JSON_TYPE.INTEGER)
        {
            writelog("  merged_by.id field is not an integer, skipping");
            continue;
        }

        writelog(" setting auto_pull to %s", id.integer);
        mysql.query(text("update github_pulls set auto_pull = '", id.integer, "' where id = ", row[0]));
    }
}
