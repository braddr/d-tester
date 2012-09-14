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
}

