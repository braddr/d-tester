module config;

import utils;

import std.json;
import std.file;

struct Config
{
    string db_host;
    string db_db;
    string db_user;
    string db_passwd;

    string github_user;
    string github_passwd;
    string github_clientid;
    string github_clientsecret;

    bool builds_enabled;
    bool log_env;
    bool log_sql_queries;
}

Config c;

void load_config(string filename)
{
    string contents = cast(string)read(filename);

    JSONValue jv = parseJSON(contents);

    JSONValue db = jv.object["db"];
    c.db_host   = db.object["host"].str;
    c.db_db     = db.object["db"].str;
    c.db_user   = db.object["user"].str;
    c.db_passwd = db.object["passwd"].str;

    c.builds_enabled = jv.object["builds_enabled"].type == JSON_TYPE.TRUE;
    c.log_env = jv.object["log_env"].type == JSON_TYPE.TRUE;
    c.log_sql_queries = jv.object["log_sql_queries"].type == JSON_TYPE.TRUE;

    JSONValue gh = jv.object["github"];
    c.github_user   = gh.object["user"].str;
    c.github_passwd = gh.object["passwd"].str;
    c.github_clientid = gh.object["client_id"].str;
    c.github_clientsecret = gh.object["client_secret"].str;
}

