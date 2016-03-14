module log;

import std.datetime;
import std.process;
import std.stdio;

static string LOGNAME = "/tmp/serverd.log";

void writelog(S...)(S s)
{
    static int mypid = -1;
    
    if (mypid == -1)
        mypid = thisProcessID();

    try
    { 
        auto fp = File(LOGNAME, "a");

        auto t = Clock.currTime();
        t.fracSecs = msecs(0);
        fp.writef("%05d - %s - ", mypid, t.toISOExtString());

        fp.writefln(s);
    }
    catch (Exception e)
    {
        printf("uh: %.*s", e.toString.length, e.toString.ptr);
        // maybe get fcgi_err visible here and write to it?
    }
}
