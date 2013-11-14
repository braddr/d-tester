module serverd;

import config;
import mysql;
import utils;
import setup;
import www;

import p_finish_run;

import p_github_hook;
import p_github_process_login;
import p_logout;

import p_get_runnable_master;
import p_finish_master_run;
import p_start_master_test;
import p_finish_master_test;
import p_upload_master;

import p_get_runnable_pull;
import p_finish_pull_run;
import p_start_pull_test;
import p_finish_pull_test;
import p_upload_pull;

import p_toggle_auto_merge;

import std.array;
import std.datetime;
import std.file;
import std.format;
import std.process;
import std.range;
import std.stdio;
import std.string;

import etc.c.curl;

import core.sys.posix.signal;

extern(C)
{
    struct FCGX_Stream;
    alias char** FCGX_ParamArray;

    extern int FCGX_Accept(FCGX_Stream **instr, FCGX_Stream **outstr, FCGX_Stream **err, FCGX_ParamArray *envp);
    extern void FCGX_Finish();
    extern int FCGX_GetStr(char *str, int n, FCGX_Stream *stream);
    extern int FCGX_PutS(const char *str, FCGX_Stream *stream);
    extern char *FCGX_GetParam(const char *name, FCGX_ParamArray envp);
}

CURL* curl;
FCGX_Stream* fcgi_in, fcgi_out, fcgi_err;
FCGX_ParamArray fcgi_envp;
bool shutdown = false;

void FPUTS(string s)
{
    version (FASTCGI)
        FCGX_PutS(toStringz(s), fcgi_out);
    else
        write(s);
}

void dispatch(string uri, const ref string[string] hash, const ref string[string] userhash, ref Appender!string outdata)
{
    alias void function(const ref string[string] hash, const ref string[string] userhash, Appender!string outdata) page_func;
    page_func[string] commands =
    [
        "/dump"                 : &p_dump,

        // github_post hook
        "/github_hook"          : &p_github_hook.run,
        "/github_process_login" : &p_github_process_login.run,
        "/logout"               : &p_logout.run,
        "/toggle_auto_merge"    : &p_toggle_auto_merge.run,

        // master checkins
        "/get_runnable_master"  : &p_get_runnable_master.run, // for a given platform, see if it's time to run
        "/finish_master_run"    : &p_finish_master_run.run,   // mark a master build as complete
        "/start_master_test"    : &p_start_master_test.run,   // start a test phase for a master request build
        "/finish_master_test"   : &p_finish_master_test.run,  // start a test phase for a master request build
        "/upload_master"        : &p_upload_master.run,       // for a specific test, receive the resulting log

        // pull request apis
        "/get_runnable_pull"    : &p_get_runnable_pull.run, // for a given platform, select a pull to build
        "/finish_pull_run"      : &p_finish_pull_run.run,   // mark a pull build as complete
        "/start_pull_test"      : &p_start_pull_test.run,   // start a test phase for a pull request build
        "/finish_pull_test"     : &p_finish_pull_test.run,  // finish a test phase
        "/upload_pull"          : &p_upload_pull.run,      // for a specific test, receive the resulting log
    ];

    if (uri.startsWith("/test-results/addv2"))
        uri = uri["/test-results/addv2".length .. $];

    page_func* func = uri in commands;
    if (!func)
    {
        writelog("could not find page func for %s", uri);
        formattedWrite(outdata, "Content-type: text/plain\n\nUnable to dispatch uri %s\n", uri);
        return;
    }

    (*func)(hash, userhash, outdata);
}

void p_dump(const ref string[string] hash, const ref string[string] userhash, Appender!string outdata)
{
    formattedWrite(outdata, "Content-type: text/plain\n\n");

    formattedWrite(outdata, "Hash:\n");
    foreach(k, v; hash)
        formattedWrite(outdata, "  key: %s, value: %s\n", k, v);

    formattedWrite(outdata, "\nUser Hash:\n");
    foreach(k, v; userhash)
        formattedWrite(outdata, "  key: %s, value: %s\n", k, v);
}

void processRequest()
{
    string[string] hash;
    string[string] userhash;
    processEnv(hash);
    processInput(hash, userhash);
    processCookies(userhash, lookup(hash, "HTTP_COOKIE"));

    string path = lookup(hash, "PATH_INFO");
    if (path.empty)
        path = lookup(hash, "SCRIPT_NAME");
    if (path.empty)
        path = lookup(hash, "REQUEST_URI");
    if (path.empty)
        return;

    writelog("processing request: %s %s", path, lookup(hash, "QUERY_STRING"));

    auto outdata = appender!string();

    dispatch(path, hash, userhash, outdata);

    FPUTS(outdata.data);

    sql_cleanup_after_request();
}

extern(C) void handle_sigterm(int sig) @system nothrow
{
    //writelog("caught sigterm");
    shutdown = true;
}

int main(string[] args)
{
    writelog("start app");

    signal(SIGTERM, &handle_sigterm);

    string filename = std.process.getenv("SERVERD_CONFIG");
    if (filename == "")
    {
        writelog("using default config path");
        filename = "/home/www-data/d.puremagic.com/d-tester/config.json";
    }

    load_config(filename);

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

    version (FASTCGI)
    {
        SysTime exeDate = timeLastModified(args[0]);

        writelog("start fcgi loop");

        size_t numHits = 100;
        while (!shutdown && FCGX_Accept(&fcgi_in, &fcgi_out, &fcgi_err, &fcgi_envp) >= 0)
        {
            processRequest();
            FCGX_Finish();

            if (timeLastModified(args[0]) != exeDate)
            {
                writelog("new binary detected");
                shutdown = true;
            }

            if (--numHits == 0)
                shutdown = true;
        }
    }
    else
    {
        processRequest();
    }

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
