module utils;

import core.sys.posix.sys.time;
import core.vararg;

import std.array;
import std.format;
import std.process;
import std.range;
import std.stdio;

void writelog(S...)(S s)
{
    static int mypid = -1;
    
    if (mypid == -1)
        mypid = getpid();

    try
    { 
        auto fp = File("/tmp/serverd.log", "a");

        timeval tp;
        gettimeofday(&tp, null);
        fp.writef("%05d - %d.%06d - ", mypid, tp.tv_sec, tp.tv_usec);

        fp.writefln(s);
    }
    catch (Exception e)
    {
        printf("uh: %.*s", e.toString.length, e.toString.ptr);
        // maybe get fcgi_err visible here and write to it?
    }
}

string lookup(const ref string[string] hash, string key)
{
    const(string*) ptr = key in hash;
    return ptr ? *ptr : "";
}

bool auth_check(string raddr, Appender!string outstr)
{
    if (raddr.empty)
    {
        formattedWrite(outstr, "no remote addr: %s\n", raddr);
        return false;
    }
    if (!check_addr(raddr))
    {
        formattedWrite(outstr, "unauthorized: %s\n", raddr);
        return false;
    }

    return true;
}

bool check_addr(string addr)
{
    static string[] prefixes = [
        //"24.16.98.20",    // comcast home connection, 9/22/2011
        //"24.16.96.64",    // comcast home connection, 1/25/2012
        "24.16.98.44",    // comcast home connection, 4/4/2012
        //"71.231.121.195", // comcast home connection
        "173.45.241.208", // slice-1
        "76.244.44.56",   // sean's mac mini
        "207.97.227.",    // github
        "173.203.140.",   // github
        "173.45.241.",    // github
        "192.168.10.",    // home network
        "107.21.106.218", // ec2 pull tester, windows
        "107.21.116.243", // ec2 pull tester, linux
        "107.21.200.190", // ec2 pull tester, freebsd
        "107.21.155.214", // ec2 pull tester, linux -- bradrob@amzn account
        "23.23.186.223",  // ec2 pull tester, freebsd32 -- bradrob@amzn account
    ];

    foreach(c; prefixes)
    {
        size_t l = c.length;
        if (addr.length < l)
            l = addr.length;
        if (addr[0 .. l] == c)
            return true;
    }

    return false;
}
