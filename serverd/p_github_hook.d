module p_github_hook;

import mysql;
import utils;

import std.conv;
import std.range;

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string bodytext = lookup(userhash, "REQUEST_BODY");

    sql_exec(text("insert into github_posts values (null, now(), \"", sql_quote(bodytext), "\")"));
}

