module fixup;

// quick and dirty code to cleanup or backfill data, or whatever.

import config;
import mysql;
import utils;

import model.project;
import model.pull;
import model.user;

import etc.c.curl;
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

    return true;
}

bool parseAndReturn(string str, ref JSONValue jv)
{
    try
    {
        jv = parseJSON(str);
    }
    catch (JSONException e)
    {
        writelog("  error parsing github json: %s\n", e.toString);
        return false;
    }

    if (jv.type != JSON_TYPE.OBJECT)
    {
        writelog("  json parsed, but isn't an object: %s", str);
        return false;
    }

    return true;
}

void main(string[] args)
{
    if (!init()) return;
    scope(exit)
    {
        writelog("shutting down");
        sql_shutdown();
    }

    string responsePayload;
    string[] responseHeaders;
    if (!runCurlGET(curl, responsePayload, responseHeaders, "https://api.github.com/repos/dlang/phobos/pulls/5250", null, null))
    {
        writelog("error loading url");
        return;
    }

    JSONValue jv;
    if (!parseAndReturn(responsePayload, jv))
    {
        writelog("  failed to parse");
        return;
    }

}


