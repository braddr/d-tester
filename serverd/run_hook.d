module fixup;

// quick and dirty code to cleanup or backfill data, or whatever.

import config;
import globals;
import mysql;
import utils;

import githubapi.hook;

import model.project;
import model.pull;
import model.user;

import etc.c.curl;
import std.array;
import std.conv;
import std.datetime;
import std.json;
import std.process;
import std.stdio;

CURL* curl;
alias string[] sqlrow;

bool init()
{
    LOGNAME = "/tmp/fixup.log";

    writelog("start app");

    load_config(environment["SERVERD_CONFIG"]);

    if (!sql_init(c.db_host, 3306, c.db_user, c.db_passwd, c.db_db))
    {
        writelog("failed to initialize sql connection, exiting");
        return false;
    }

    curl = curl_easy_init();
    if (!curl)
    {
        writelog("failed to initialize curl library, exiting");
        return false;
    }

    init_globals(c, curl);

    return true;
}

int main(string[] args)
{
    if (!init()) return 1;
    scope(exit)
    {
        writelog("shutting down");
        sql_shutdown();
    }

    sql_exec(text("select body from github_posts where id = ", args[1]));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        writelog("  should be just one row for each hook id, not %d", rows.length);
        return 2;
    }

    string[string] hash;
    string[string] userhash;
    Appender!string outstr;

    hash["run_hook_id"] = args[1];
    hash["HTTP_X_GITHUB_EVENT"] = "pull_request";
    userhash["REQUEST_BODY"] = rows[0][0];

    githubapi.hook.run(hash, userhash, outstr);

    writefln("run output: %s", outstr.data);

    return 0;
}
