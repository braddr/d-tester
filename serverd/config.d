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

bool as_bool(JSONValue jv, string f)
{
    JSONValue* v = f in jv.object;
    if (!v) return false;

    return v.type == JSON_TYPE.TRUE;
}

string as_string(JSONValue jv, string f, string d = "")
{
    JSONValue* v = f in jv.object;
    if (!v) return d;
    if (v.type != JSON_TYPE.STRING) return d;

    return v.str;
}

void load_config(string filename)
{
    string contents = cast(string)read(filename);

    JSONValue jv = parseJSON(contents);

    JSONValue db = jv.object["db"];
    c.db_host   = db.as_string("host");
    c.db_db     = db.as_string("db");
    c.db_user   = db.as_string("user");
    c.db_passwd = db.as_string("passwd");

    c.builds_enabled  = jv.as_bool("builds_enabled");
    c.log_env         = jv.as_bool("log_env");
    c.log_sql_queries = jv.as_bool("log_sql_queries");

    JSONValue gh = jv.object["github"];
    c.github_user         = gh.as_string("user");
    c.github_passwd       = gh.as_string("passwd");
    c.github_clientid     = gh.as_string("client_id");
    c.github_clientsecret = gh.as_string("client_secret");
}

