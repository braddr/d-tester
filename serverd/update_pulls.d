module p_update_pulls;

import config;
import mysql;
import utils;

import etc.c.curl;
import std.conv;
import std.datetime;
import std.json;
import std.format;
import std.process;
import std.range;
import std.string;

CURL* curl;
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
    SysTime head_date;

    this(ulong _id, ulong _project_id, ulong _pull_id, ulong _user_id, SysTime _updated_at, bool _open, string _base_git_url, string _base_ref, string _base_sha, string _head_git_url, string _head_ref, string _head_sha, SysTime _head_date)
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
        head_date    = _head_date;
    }
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
        writelog("  creating user %s(%s)", uname, uidstr);
        sql_exec(text("insert into github_users values(", uidstr, ", '", sql_quote(uname), "', false)"));

        users[uname] = false;
        return false;
    }

    return *found;
}

bool loadCommitDate(string repo, Pull p)
{
    string url = text("https://api.github.com/repos/D-Programming-Language/", repo, "/commits/", p.head_sha);
    string payload;
    string[] headers;

    if (!runCurlGET(curl, payload, headers, url) || payload.length == 0)
    {
        writelog("  failed to load pull details, skipping");
        return false;
    }

    JSONValue jv = parseJSON(payload);

    string s = jv.object["commit"].object["committer"].object["date"].str;
    p.head_date = SysTime.fromISOExtString(s, UTC());
    //writelog("post fromISO: %s", p.head_date.toISOExtString());

    return true;
}

void updatePull(string repo, Pull* k, Pull p)
{
    if (k.updated_at != p.updated_at)
    {
        writelog("  updating repo %s pull %s:", repo, p.pull_id);
        writelog("    updated_at: before: %s - after: %s", k.updated_at.toISOExtString(), p.updated_at.toISOExtString());
        sql_exec(text("update github_pulls set updated_at = '", p.updated_at.toISOExtString(), "' where id = ", k.id));
        writelog(text("    sql: update github_pulls set updated_at = '", p.updated_at.toISOExtString(), "' where id = ", k.id));

        if ((!p.open && k.open) || p.base_sha != k.base_sha || p.head_sha != k.head_sha || p.base_git_url != k.base_git_url || p.head_git_url != k.head_git_url)
        {
            if (!loadCommitDate(repo, p)) return;

            writelog("    head_date:  before: %s - after: %s", k.head_date.toISOExtString(), p.head_date.toISOExtString());
            sql_exec(text("update github_pulls set head_date = '", p.head_date.toISOExtString(), "' where id = ", k.id));
            writelog(text("    sql: update github_pulls set head_date = '", p.head_date.toISOExtString(), "' where id = ", k.id));

            writelog("    sha changes:");
            writelog("      before: base: %s, head: %s", k.base_sha, k.head_sha);
            writelog("      after : base: %s, head: %s", p.base_sha, p.head_sha);
            sql_exec(text("update github_pulls set open=true, "
                        "base_git_url='", p.base_git_url, "', base_ref='", p.base_ref, "', base_sha='", p.base_sha, "', "
                        "head_git_url='", p.head_git_url, "', head_ref='", p.head_ref, "', head_sha='", p.head_sha, "' where id = ", k.id));

            writelog("    deprecating old test results");
            sql_exec(text("update pull_test_runs set deleted=1 where deleted=0 and g_p_id = ", k.id));
        }
    }
}

void processPull(string repoid, string reponame, Pull* k, Pull p)
{
    //writelog("  processPull: %s/%s", p.project_id, p.pull_id);
    if (k is null)
    {
        // try to load specific pull to see if this is a re-opened request
        sql_exec(text("select id, project_id, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, date_format(head_date, '%Y-%m-%dT%H:%i:%S%Z') from github_pulls where project_id = ", repoid, " and pull_id = ", p.pull_id));
        sqlrow[] rows = sql_rows();

        if (rows == [])
        {
            if (!loadCommitDate(reponame, p)) return;

            // new pull request
            writelog("  opening repo %s pull %s", reponame, p.pull_id);
            sql_exec(text("insert into github_pulls values (null, ", repoid, ", ", p.pull_id, ", ", p.user_id,
                ", '", p.updated_at.toISOExtString(), "', true, "
                "'", p.base_git_url, "', '", p.base_ref, "', '", p.base_sha, "', "
                "'", p.head_git_url, "', '", p.head_ref, "', '", p.head_sha, "', "
                "'", p.head_date.toISOExtString(), "')"));
        }
        else
        {
            // reopened pull request
            auto row = rows[0];
            if (row[11] == "") row[11] = row[4]; // use temporarily until loadCommitDate can get the right value
            writelog("reopen: row[0] = %s, row[4] = %s, row[11] = %s", row[0], row[4], row[11]);
            auto newP = new Pull(to!ulong(row[0]), to!ulong(row[1]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), true, row[5], row[6], row[7], row[8], row[9], row[10], SysTime.fromISOExtString(row[11]));
            updatePull(reponame, &newP, p);
        }

    }
    else
    {
        updatePull(reponame, k, p);
    }
}

void processProject(Pull[ulong] knownpulls, string repoid, string reponame, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        ulong uid    = obj.object["user"].object["id"].integer;
        string uname = obj.object["user"].object["login"].str;
        bool trusted = checkUser(uid, uname);

        auto p = new Pull(
            0, // our id not known from github data
            to!ulong(repoid),
            obj.object["number"].integer,
            uid,
            SysTime.fromISOExtString(obj.object["updated_at"].str),
            obj.object["state"].str == "open",
            obj.object["base"].object["repo"].object["ssh_url"].str,
            obj.object["base"].object["ref"].str,
            obj.object["base"].object["sha"].str,
            obj.object["head"].object["repo"].object["ssh_url"].str,
            obj.object["head"].object["ref"].str,
            obj.object["head"].object["sha"].str,
            SysTime.fromISOExtString(obj.object["updated_at"].str)); // wrong time, but need a value. Will be fixed during loadCommitDate

        Pull* tmp = p.pull_id in knownpulls;
        processPull(repoid, reponame, tmp, p);

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

void update_pulls()
{
    if (!sql_exec("select id, name from repositories"))
    {
        writelog("Error loading list of repos");
        return;
    }

    // 0 == id, 1 == name
    sqlrow[] repos = sql_rows();

projloop:
    foreach(repo; repos)
    {
        writelog("processing pulls for repo %s", repo);

        //                    0   1           2        3        4                                               5             6         7         8             9         10        11
        sql_exec(text("select id, project_id, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, date_format(head_date, '%Y-%m-%dT%H:%i:%S%Z') from github_pulls where project_id = ", repo[0], " and open"));
        sqlrow[] rows = sql_rows();
        Pull[ulong] knownpulls;
        foreach(row; rows)
        {
            if (row[11] == "") row[11] = row[4]; // use temporarily until loadCommitDate can get the right value
            //writelog("row[0] = %s, row[4] = %s, row[11] = %s", row[0], row[4], row[11]);
            knownpulls[to!ulong(row[2])] = new Pull(to!ulong(row[0]), to!ulong(row[1]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), true, row[5], row[6], row[7], row[8], row[9], row[10], SysTime.fromISOExtString(row[11]));
        }

        string url = text("https://api.github.com/repos/D-Programming-Language/", repo[1], "/pulls?state=open&per_page=100");
        while (url)
        {
            string payload;
            string[] headers;

            if (!runCurlGET(curl, payload, headers, url) || payload.length == 0)
            {
                writelog("  failed to load pulls, skipping repo");
                continue projloop;
            }

            JSONValue jv;
            try
            {
                jv = parseJSON(payload);
            }
            catch (JSONException e)
            {
                writelog("  error parsing github json response: %s\n", e.toString);
                break;
            }

            if (jv.type != JSON_TYPE.ARRAY)
            {
                writelog("  github pulls data malformed: %s\n", payload);
                break;
            }

            processProject(knownpulls, repo[0], repo[1], jv);

            url = findNextLink(headers);
        }

        //writelog("closing pulls");
        // any elements left in knownpulls means they're no longer open, so mark closed
        foreach(k; knownpulls.keys)
        {
            sql_exec(text("update github_pulls set open=false where project_id = ", repo[0], " and pull_id = ", k));
            writelog("  closing repo %s pull %s", repo[1], k);
        }
    }
}

int main(string[] args)
{
    writelog("start app");

    load_config(getenv("SERVERD_CONFIG"));

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

    update_pulls();

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
