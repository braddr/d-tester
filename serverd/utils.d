module utils;

import core.thread;
import core.vararg;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.format;
import std.process;
import std.range;
import std.stdio;
import std.string;

import etc.c.curl;

import mysql;

static const char* USERAGENT = "Auto-Tester. http://d.puremagic.com/test-results/  contact: braddr@puremagic.com";

void writelog(S...)(S s)
{
    static int mypid = -1;
    
    if (mypid == -1)
        mypid = getpid();

    try
    { 
        auto fp = File("/tmp/serverd.log", "a");

        auto t = Clock.currTime();
        t.fracSec = FracSec.from!"hnsecs"(0);
        fp.writef("%05d - %s - ", mypid, t.toISOExtString());

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
    static bool check_set(sqlrow[] rows, string addr)
    {
        foreach(row; rows)
        {
            size_t l = row[0].length;
            if (addr.length < l)
                l = addr.length;
            if (addr[0 .. l] == row[0])
                return true;
        }

        return false;
    }

    sql_exec("select ipaddr from authorized_addresses where enabled = 1");
    sqlrow[] rows = sql_rows();

    if (check_set(rows, addr))
        return true;

    sql_exec(text("select ipaddr from build_hosts where enabled = 1 and ipaddr = \"", addr, "\""));
    rows = sql_rows();

    if (check_set(rows, addr))
        return true;

    return false;
}

void updateHostLastCheckin(string hostid, string clientver)
{
    sql_exec(text("update build_hosts set last_heard_from = now(), clientver = ", clientver, " where id = ", hostid));
}

extern(C) size_t handleBodyData(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    auto payload = cast(string*)userdata;

    *payload ~= cast(string)(ptr[0 .. size*nmemb].idup);

    return size*nmemb;
}

extern(C) size_t handleHeaderData(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    auto payload = cast(string[]*)userdata;

    *payload ~= chomp(cast(string)(ptr[0 .. size*nmemb].idup));

    return size*nmemb;
}

extern(C) size_t handleRequestBodyData(void *ptr, size_t size, size_t nmemb, void *userdata)
{
    auto payload = cast(string*)userdata;

    size_t bytesAllowed = size * nmemb;
    size_t bytesToSend = min(payload.length, bytesAllowed);

    if (bytesToSend > 0)
    {
        (cast(char*)ptr)[0 .. bytesToSend] = (*payload)[0 .. bytesToSend];
        *payload = (*payload)[bytesToSend .. $];
        return bytesToSend;
    }

    return 0;
}

bool runCurlGET(CURL* curl, ref string payload, ref string[] headers, string url, string userid = null, string passwd = null)
{
    int tries;
    while (tries < 3)
    {
        writelog("  get url: %s, try #%s", url, tries);

        payload = "";
        headers = [];

        curl_easy_reset(curl);

        curl_easy_setopt(curl, CurlOption.httpget, 1);

        curl_easy_setopt(curl, CurlOption.useragent, toStringz(USERAGENT));

        curl_easy_setopt(curl, CurlOption.writefunction, &handleBodyData);
        curl_easy_setopt(curl, CurlOption.file, &payload);

        curl_easy_setopt(curl, CurlOption.headerfunction, &handleHeaderData);
        curl_easy_setopt(curl, CurlOption.writeheader, &headers);

        if (userid && passwd)
        {
            curl_easy_setopt(curl, CurlOption.httpauth, CurlAuth.basic);
            curl_easy_setopt(curl, CurlOption.username, toStringz(userid));
            curl_easy_setopt(curl, CurlOption.password, toStringz(passwd));
        }

        curl_easy_setopt(curl, CurlOption.verbose, 0);

        curl_easy_setopt(curl, CurlOption.url, toStringz(url));
        CURLcode res = curl_easy_perform(curl);

        if (res != 0) writelog("  result: %s", res);

        //foreach(h; headers)
        //    writelog("header: '%s'", h);
        //writelog("body: '%s'", payload);

        long statusCode;
        curl_easy_getinfo(curl, CurlInfo.response_code, &statusCode);
        if (statusCode >= 200 && statusCode <= 299)
            return true;

        ++tries;
        writelog("  http status code %s, retrying in %s seconds", statusCode, tries);
        Thread.sleep(dur!("seconds")( tries ));
    }
    return false;
}

bool runCurlPOST(CURL* curl, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload, string user = null, string passwd = null)
{
    int tries;
    auto fp = File("/tmp/serverd.log", "a");
    while (tries < 3)
    {
        writelog("  post url: %s, try #%s", url, tries);

        responsepayload = "";
        responseheaders = [];

        curl_easy_reset(curl);

        curl_easy_setopt(curl, CurlOption.post, 1L);
        curl_easy_setopt(curl, CurlOption.forbid_reuse, 1L);

        curl_easy_setopt(curl, CurlOption.useragent, toStringz(USERAGENT));

        if (user && passwd)
        {
            curl_easy_setopt(curl, CurlOption.httpauth, CurlAuth.basic);
            curl_easy_setopt(curl, CurlOption.username, toStringz(user));
            curl_easy_setopt(curl, CurlOption.password, toStringz(passwd));
        }

        string rpay = requestpayload; // copy original string since rpay is altered during the send
        curl_easy_setopt(curl, CurlOption.infile, cast(void*)&rpay);
        curl_easy_setopt(curl, CurlOption.readfunction, &handleRequestBodyData);
        curl_easy_setopt(curl, CurlOption.postfieldsize, requestpayload.length);

        curl_easy_setopt(curl, CurlOption.writefunction, &handleBodyData);
        curl_easy_setopt(curl, CurlOption.file, &responsepayload);

        curl_easy_setopt(curl, CurlOption.headerfunction, &handleHeaderData);
        curl_easy_setopt(curl, CurlOption.writeheader, &responseheaders);

        curl_easy_setopt(curl, CurlOption.stderr, fp.getFP());
        curl_easy_setopt(curl, CurlOption.verbose, 0);

        curl_easy_setopt(curl, CurlOption.url, toStringz(url));
        CURLcode res = curl_easy_perform(curl);

        if (res != 0) writelog("  result: %s", res);

        //foreach(h; responseheaders)
        //    writelog("header: '%s'", h);
        //writelog("body: '%s'", responsepayload);

        long statusCode;
        curl_easy_getinfo(curl, CurlInfo.response_code, &statusCode);
        if (statusCode >= 200 && statusCode <= 299)
            return true;

        ++tries;
        writelog("  http status code %s, retrying in %s seconds", statusCode, tries);
        //foreach(h; responseheaders)
        //    writelog("header: '%s'", h);
        //writelog("body: '%s'", responsepayload);

        Thread.sleep(dur!("seconds")( tries ));
    }
    curl_easy_setopt(curl, CurlOption.stderr, 0);
    return false;
}
