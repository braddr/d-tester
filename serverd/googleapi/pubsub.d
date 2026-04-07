module googleapi.pubsub;

import mysql;
import globals;
import utils;

import std.algorithm;
import std.conv;
import std.json;
import std.range;
    import std.stdio;

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

//    string raddr = lookup(hash, "REMOTE_ADDR");
    string bodytext = lookup(userhash, "REQUEST_BODY");

    // TODO: add auth check

    string hook_id = lookup(hash, "run_hook_id");
    if (hook_id.empty)
    {
        sql_exec(text("insert into youtube.google_posts (id, post_time, body, processed, deleted) values (null, now(), \"", sql_quote(bodytext), "\", false, false)"));
        sql_exec("select last_insert_id()");
        hook_id = sql_row()[0];
    }
    writelog("  processing event: %s", hook_id);

    // TODO: add secret / hmac handling
    //
    // hub.topic=https://www.youtube.com/feeds/videos.xml%3Fchannel_id%3DUC6ZUvKkpzxy10Vz89nEE6FQ&
    // hub.challenge=16832595826105906514&
    // hub.mode=subscribe&
    // hub.lease_seconds=432000
    string challenge_id = lookup(userhash, "hub.challenge");
    if (!challenge_id.empty)
    {
        outstr.put(challenge_id);
        sql_exec(text("update youtube.google_posts set processed = true, deleted = true where id = ", hook_id));
        return;
    }
}

