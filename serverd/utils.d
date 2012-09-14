module utils;

import core.thread;
import core.vararg;

import std.algorithm;
import std.array;
import std.datetime;
import std.format;
import std.process;
import std.range;
import std.stdio;
import std.string;

import etc.c.curl;

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

bool runCurlGET(CURL* curl, ref string payload, ref string[] headers, string url)
{
    int tries;
    while (tries < 3)
    {
        writelog("  get url: %s, try #%s", url, tries);

        payload = "";
        headers = [];

        curl_easy_setopt(curl, CurlOption.httpget, 1);

        curl_easy_setopt(curl, CurlOption.writefunction, &handleBodyData);
        curl_easy_setopt(curl, CurlOption.file, &payload);

        curl_easy_setopt(curl, CurlOption.headerfunction, &handleHeaderData);
        curl_easy_setopt(curl, CurlOption.writeheader, &headers);

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

bool runCurlPOST(CURL* curl, ref string responsepayload, ref string[] responseheaders, string url, string requestpayload)
{
    int tries;
    while (tries < 1)
    {
        writelog("  post url: %s, try #%s", url, tries);

        responsepayload = "";
        responseheaders = [];

        curl_easy_setopt(curl, CurlOption.post, 1L);

        curl_easy_setopt(curl, CurlOption.username, toStringz("braddr"));
        curl_easy_setopt(curl, CurlOption.password, toStringz("adg1Qet"));
        curl_easy_setopt(curl, CurlOption.httpauth, CurlAuth.basic);

        string rpay = requestpayload; // copy original string since rpay is altered during the send
        curl_easy_setopt(curl, CurlOption.infile, cast(void*)&rpay);
        curl_easy_setopt(curl, CurlOption.readfunction, &handleRequestBodyData);
        curl_easy_setopt(curl, CurlOption.postfieldsize, requestpayload.length);

        curl_easy_setopt(curl, CurlOption.writefunction, &handleBodyData);
        curl_easy_setopt(curl, CurlOption.file, &responsepayload);

        curl_easy_setopt(curl, CurlOption.headerfunction, &handleHeaderData);
        curl_easy_setopt(curl, CurlOption.writeheader, &responseheaders);

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
        Thread.sleep(dur!("seconds")( tries ));
    }
    return false;
}
