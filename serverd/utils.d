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

static const char* USERAGENT = "Auto-Tester. https://d.puremagic.com/test-results/  contact: braddr@puremagic.com";

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

string getURLProtocol(const ref string[string] hash)
{
    return lookup(hash, "HTTPS") == "on" ? "https" : "http";
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

bool getAccessTokenFromCookie(string cookie, string csrf, ref string access_token, ref string userid, ref string username)
{
    sql_exec(text("select id, username, access_token, csrf from github_users where cookie=\"", cookie, "\" and csrf=\"", csrf, "\""));
    sqlrow[] rows = sql_rows();
    if (rows.length != 1)
    {
        writelog("  found %s rows, expected 1, for cookie '%s'", rows.length, cookie);
        return false;
    }

    userid = rows[0][0];
    username = rows[0][1];
    access_token = rows[0][2];

    return true;
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

bool runCurlGET(CURL* curl, ref string responsepayload, ref string[] responseheaders, string url, string user, string passwd)
{
    return runCurlMethodRetry(curl, CurlOption.httpget, responsepayload, responseheaders, url, null, null, user, passwd);
}

bool runCurlPUT(CURL* curl, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload, string[] requestheaders, string user, string passwd)
{
    return runCurlMethodRetry(curl, CurlOption.put, responsepayload, responseheaders, url, requestpayload, requestheaders, user, passwd);
}

bool runCurlPOST(CURL* curl, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload, string[] requestheaders, string user, string passwd)
{
    return runCurlMethodRetry(curl, CurlOption.post, responsepayload, responseheaders, url, requestpayload, requestheaders, user, passwd);
}

bool runCurlMethodRetry(CURL* curl, CurlOption co, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload, string[] requestheaders, string user, string passwd)
{
    int tries;
    while (tries < 3)
    {
        writelog("  url: %s, try: #%s", url, tries);
        CURLcode res = runCurlMethod(curl, co, responsepayload, responseheaders, url, requestpayload, requestheaders, user, passwd);

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

CURLcode runCurlMethod(CURL* curl, CurlOption co, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload, string[] requestheaders, string user, string passwd)
{
    auto fp = File("/tmp/serverd.log", "a");

    responsepayload = "";
    responseheaders = [];

    curl_easy_reset(curl);

    curl_easy_setopt(curl, co, 1L);
    if (co != CurlOption.httpget)
        curl_easy_setopt(curl, CurlOption.forbid_reuse, 1L);

    curl_easy_setopt(curl, CurlOption.useragent, toStringz(USERAGENT));

    if (user && passwd)
    {
        curl_easy_setopt(curl, CurlOption.httpauth, CurlAuth.basic);
        curl_easy_setopt(curl, CurlOption.username, toStringz(user));
        curl_easy_setopt(curl, CurlOption.password, toStringz(passwd));
    }

    curl_slist* curl_request_headers;
    foreach (h; requestheaders)
        curl_request_headers = curl_slist_append(curl_request_headers, cast(char*) toStringz(h));
    curl_easy_setopt(curl, CurlOption.httpheader, curl_request_headers);

    if (co != CurlOption.httpget)
    {
        string rpay = requestpayload; // copy original string since rpay is altered during the send
        curl_easy_setopt(curl, CurlOption.infile, cast(void*)&rpay);
        curl_easy_setopt(curl, CurlOption.readfunction, &handleRequestBodyData);
        curl_easy_setopt(curl, CurlOption.postfieldsize, requestpayload.length);
    }

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

    curl_slist_free_all(curl_request_headers);
    curl_request_headers = null;
    curl_easy_setopt(curl, CurlOption.httpheader, curl_request_headers);

    curl_easy_setopt(curl, CurlOption.stderr, 0);

    return res;
}
