module p_update_pulls;

import mysql;
import serverd;
import utils;

import core.thread;

import std.conv;
import std.datetime;
import std.json;
import std.format;
import std.range;
import std.string;

import etc.c.curl;

alias string[] sqlrow;

class Pull
{
    ulong   id;
    ulong   project_id;
    ulong   pull_id;
    ulong   user_id;
    SysTime updated_at;
    bool    open;
    string  base_git_url;  // ex: git@github.com:D-Programming-Language/druntime.git
    string  base_ref;      // ex: master
    string  base_sha;      // ex: 98f410bd67e8a79630d05da7a37b0029bc45fa4b
    string  head_git_url;  // ex: git@github.com:fugalh/druntime.git
    string  head_ref;      // ex: master
    string  head_sha;      // ex: 9d63a68eb72c00b1303a047c4dfae71eae23dc81

    this(ulong _id, ulong _project_id, ulong _pull_id, ulong _user_id, SysTime _updated_at, bool _open, string _base_git_url, string _base_ref, string _base_sha, string _head_git_url, string _head_ref, string _head_sha)
    {
        id           = _id;
        project_id   = _project_id;
        pull_id      = _pull_id;
        user_id      = _user_id;
        updated_at   = _updated_at;
        open         = _open;
        base_git_url = _base_git_url;
        base_ref     = _base_ref;
        base_sha     = _base_sha;
        head_git_url = _head_git_url;
        head_ref     = _head_ref;
        head_sha     = _head_sha;
    }
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

bool[string] loadUsers()
{
    sql_exec(text("select id, trusted from github_users"));

    sqlrow[] rows = sql_rows();

    bool[string] users;
    foreach(row; rows) { bool trusted = row[1] && row[1] == "1"; users[row[0]] = trusted; }

    return users;
}

bool checkUser(ulong uid, string uname)
{
    static bool[string] users;
   
    if (users.length == 0) users = loadUsers();

    string uidstr = sql_quote(to!string(uid));

    auto found = uidstr in users;
    if (!found)
    {
        writelog("creating user %s(%s)", uname, uidstr);
        sql_exec(text("insert into github_users values(", uidstr, ", '", sql_quote(uname), "', false)"));

        users[uname] = false;
        return false;
    }

    return *found;
}

bool loadPullDetails(string project, Pull p)
{
    string url = text("https://api.github.com/repos/D-Programming-Language/", project, "/pulls/", p.pull_id);
    string payload;
    string[] headers;

    if (!runCurl(payload, headers, url) || payload.length == 0)
    {
        writelog("failed to load pull details, skipping");
        return false;
    }

    JSONValue jv = parseJSON(payload);

    p.base_git_url = jv.object["base"].object["repo"].object["ssh_url"].str;
    p.base_ref     = jv.object["base"].object["ref"].str;
    p.base_sha     = jv.object["base"].object["sha"].str;
    p.head_git_url = jv.object["head"].object["repo"].object["ssh_url"].str;
    p.head_ref     = jv.object["head"].object["ref"].str;
    p.head_sha     = jv.object["head"].object["sha"].str;

    return true;
}

void updatePull(string[] project, Pull* k, Pull p)
{
    writelog("updating project %s pull %s: %s - %s", project[1], p.pull_id, k.updated_at, p.updated_at);
    sql_exec(text("update github_pulls set updated_at = '", p.updated_at.toISOExtString(), "' where id = ", k.id));
    if (k.open || p.base_sha != k.base_sha || p.head_sha != k.head_sha || p.base_git_url != k.base_git_url || p.head_git_url != k.head_git_url)
    {
        writelog("   sha changes:");
        writelog("      before: base: %s, head: %s", k.base_sha, k.head_sha);
        writelog("      after : base: %s, head: %s", p.base_sha, p.head_sha);
        sql_exec(text("update github_pulls set open=true, "
                    "base_git_url='", p.base_git_url, "', base_ref='", p.base_ref, "', base_sha='", p.base_sha, "', "
                    "head_git_url='", p.head_git_url, "', head_ref='", p.head_ref, "', head_sha='", p.head_sha, "' where id = ", k.id));
        writelog("   deprecating old test results");
        sql_exec(text("update pull_test_runs set deleted=1 where deleted=0 and g_p_id = ", k.id));
    }
}

void processPull(string[] project, Pull* k, Pull p)
{
    //writelog("processPull: %s/%s", p.project_id, p.pull_id);
    if (k is null)
    {
        if (!loadPullDetails(project[1], p)) return;

        // try to load specific pull to see if this is a re-opened request
        sql_exec(text("select id, project_id, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha from github_pulls where project_id = ", project[0], " and pull_id = ", p.pull_id));
        sqlrow[] rows = sql_rows();

        if (rows == [])
        {
            // new pull request
            writelog("opening project %s pull %s", project[1], p.pull_id);
            sql_exec(text("insert into github_pulls values (null, ", project[0], ", ", p.pull_id, ", ", p.user_id,
                ", '", p.updated_at.toISOExtString(), "', true, "
                "'", p.base_git_url, "', '", p.base_ref, "', '", p.base_sha, "', "
                "'", p.head_git_url, "', '", p.head_ref, "', '", p.head_sha, "')"));
        }
        else
        {
            // reopened pull request
            auto row = rows[0];
            auto newP = new Pull(to!ulong(row[0]), to!ulong(row[1]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), true, row[5], row[6], row[7], row[8], row[9], row[10]);
            updatePull(project, &newP, p);
        }

    }
    else if (k.updated_at < p.updated_at)
    {
        // newly updated pull request
        if (!loadPullDetails(project[1], p)) return;

        updatePull(project, k, p);
    }
    else
    {
        // unchanged
    }
}

// 0 == id, 1 == name
void processProject(Pull[ulong] knownpulls, string[] project, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        ulong uid    = obj.object["user"].object["id"].integer;
        string uname = obj.object["user"].object["login"].str;
        bool trusted = checkUser(uid, uname);

        auto p = new Pull(
            0, // our id not known from github data
            to!ulong(project[0]),
            obj.object["number"].integer,
            uid,
            SysTime.fromISOExtString(obj.object["updated_at"].str),
            obj.object["state"].str == "open",
            "",
            "",
            "",
            "",
            "",
            "");

        Pull* tmp = p.pull_id in knownpulls;
        processPull(project, tmp, p);

        knownpulls.remove(p.pull_id);
    }
}

string findNextLink(string[] headers)
{
    // Link: <https://api.github.com/repos/D-Programming-Language/dmd/pulls?page=2&per_page=100&state=open>; rel="next", <https://api.github.com/repos/D-Programming-Language/dmd/pulls?page=2&per_page=100&state=open>; rel="last"
    foreach (h; headers)
    {
        if (h.length >= 5 && toLower(h[0 .. 5]) == "link:")
        {
            string rest = h[5 .. $];
            strip(rest);

            string[] links = std.string.split(rest, ",");
            foreach (l; links)
            {
                string[] parts = std.string.split(l, ";");
                if (toLower(strip(parts[1])) == `rel="next"`)
                {
                    string toReturn = strip(parts[0])[1 .. $-1].idup;
                    //writelog("continuation link: %s", toReturn);
                    return toReturn;
                }
            }
        }
    }
    return null;
}

bool runCurl(ref string payload, ref string[] headers, string url)
{
    static string uastr = "curl/7.21.6 (x86_64-pc-linux-gnu) libcurl/7.21.6 OpenSSL/1.0.0e zlib/1.2.3.4 libidn/1.22 librtmp/2.3";

    int tries;
    while (tries < 3)
    {
        writelog("url: %s, try #%s", url, tries);

        payload = "";
        headers = [];

        curl_easy_setopt(curl, CurlOption.writefunction, &handleBodyData);
        curl_easy_setopt(curl, CurlOption.file, &payload);

        curl_easy_setopt(curl, CurlOption.writeheader, &headers);
        curl_easy_setopt(curl, CurlOption.headerfunction, &handleHeaderData);

        curl_easy_setopt(curl, CurlOption.verbose, 0);

        curl_easy_setopt(curl, CurlOption.url, toStringz(url));
        CURLcode res = curl_easy_perform(curl);

        if (res != 0) writelog("result: %s", res);

        foreach(h; headers)
            writelog("header: '%s'", h);
        //writelog("body: '%s'", payload);

        long statusCode;
        curl_easy_getinfo(curl, CurlInfo.response_code, &statusCode);
        if (statusCode == 200)
            return true;

        ++tries;
        writelog("http status code %s, retrying in %s seconds", statusCode, tries);
        Thread.sleep(dur!("seconds")( tries ));
    }
    return false;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    auto tmpout = appender!string();
    string raddr = lookup(hash, "REMOTE_ADDR");
    if (!auth_check(raddr, tmpout))
    {
        outstr.put(tmpout.data);
        return;
    }

    string pid = lookup(userhash, "id");
    if (!pid)
    {
        outstr.put("Content-type: text/plain\n\nError, missing project id\n");
        return;
    }

    //if (!sql_exec(text("select id, name from projects where id = ", sql_quote(pid))))
    //if (!sql_exec("select id, name from projects where name=\"druntime\""))
    if (!sql_exec("select id, name from projects"))
    {
        outstr.put("Content-type: text/plain\n\nError loading list of projects\n");
        return;
    }

    // 0 == id, 1 == name
    sqlrow[] projects = sql_rows();

projloop:
    foreach(project; projects)
    {
        writelog("processing pulls for project %s", project);

        //                    0   1           2        3        4                                               5             6         7         8             9         10
        sql_exec(text("select id, project_id, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha from github_pulls where project_id = ", project[0], " and open"));
        sqlrow[] rows = sql_rows();
        Pull[ulong] knownpulls;
        foreach(row; rows) { knownpulls[to!ulong(row[2])] = new Pull(to!ulong(row[0]), to!ulong(row[1]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), true, row[5], row[6], row[7], row[8], row[9], row[10]); }

        string url = text("https://api.github.com/repos/D-Programming-Language/", project[1], "/pulls?state=open&per_page=100");
        while (url)
        {
            string payload;
            string[] headers;

            if (!runCurl(payload, headers, url) || payload.length == 0)
            {
                writelog("failed to load pulls, skipping project");
                continue projloop;
            }

            JSONValue jv;
            try
            {
                jv = parseJSON(payload);
            }
            catch (JSONException e)
            {
                writelog("    error parsing github json response: %s\n", e.toString);
                break;
            }

            if (jv.type != JSON_TYPE.ARRAY)
            {
                writelog("    github pulls data malformed: %s\n", payload);
                break;
            }

            processProject(knownpulls, project, jv);

            url = findNextLink(headers);
        }

        //writelog("closing projects");
        // any elements left in knownpulls means they're no longer open, so mark closed
        foreach(k; knownpulls.keys)
        {
            sql_exec(text("update github_pulls set open=false where project_id = ", project[0], " and pull_id = ", k));
            writelog("closing project %s pull %s", project[1], k);
        }

        Thread.sleep(dur!("seconds")( 1 ));
    }
}

