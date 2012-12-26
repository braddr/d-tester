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
import std.stdio;

CURL* curl;
alias string[] sqlrow;

class Pull
{
    ulong   id;
    ulong   repo_id;
    ulong   pull_id;
    ulong   user_id;
    SysTime updated_at;
    bool    open;
    string  base_git_url;  // ex: https://github.com/D-Programming-Language/druntime.git
    string  base_ref;      // ex: master
    string  base_sha;      // ex: 98f410bd67e8a79630d05da7a37b0029bc45fa4b
    string  head_git_url;  // ex: git@github.com:fugalh/druntime.git
    string  head_ref;      // ex: master
    string  head_sha;      // ex: 9d63a68eb72c00b1303a047c4dfae71eae23dc81
    SysTime head_date;
    SysTime create_date;
    SysTime close_date;

    this(ulong _id, ulong _repo_id, ulong _pull_id, ulong _user_id, SysTime _updated_at, bool _open, string _base_git_url, string _base_ref, string _base_sha, string _head_git_url, string _head_ref, string _head_sha, SysTime _head_date, SysTime _create_date, SysTime _close_date)
    {
        id           = _id;
        repo_id      = _repo_id;
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
        create_date  = _create_date;
        close_date   = _close_date;
    }
}

string getPullColumns()
{
    //      0   1        2        3        4                                               5             6         7         8             9         10        11                                             12                                               13                                              14
    return "id, repo_id, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, date_format(head_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(create_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(close_date, '%Y-%m-%dT%H:%i:%S%Z'), open";
}

Pull makePullFromRow(sqlrow row)
{
    if (row[11] == "") row[11] = row[4]; // use temporarily until loadCommitFromGitHub can get the right value
    if (row[4] == "0000-00-00T00:00:00Z") row[4] = "2000-01-01T00:00:00Z";
    if (row[11] == "" || row[11] == "0000-00-00T00:00:00Z") row[11] = "2000-01-01T00:00:00Z";
    if (row[12] == "" || row[12] == "0000-00-00T00:00:00Z") row[12] = "2000-01-01T00:00:00Z";
    if (row[13] == "" || row[13] == "0000-00-00T00:00:00Z") row[13] = "2000-01-01T00:00:00Z";

    //writelog("row[0] = %s, row[4] = %s, row[11] = %s, row[12] = %s, row[13] = %s, row[14] = %s", row[0], row[4], row[11], row[12], row[13], row[14]);
    return new Pull(to!ulong(row[0]), to!ulong(row[1]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), (row[14] == "1"), row[5], row[6], row[7], row[8], row[9], row[10], SysTime.fromISOExtString(row[11]), SysTime.fromISOExtString(row[12]), SysTime.fromISOExtString(row[13]));
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

Pull loadPullFromGitHub(string repoid, string reponame, ulong pullid)
{
    string url = text("https://api.github.com/repos/D-Programming-Language/", reponame, "/pulls/", pullid);
    string payload;
    string[] headers;

    if (!runCurlGET(curl, payload, headers, url, c.github_user, c.github_passwd) || payload.length == 0)
    {
        writelog("  failed to load pull from github");
        return null;
    }

    JSONValue jv;
    try
    {
        jv = parseJSON(payload);
    }
    catch (JSONException e)
    {
        writelog("  error parsing github json response: %s\n", e.toString);
        return null;
    }

    return makePullFromJson(jv, repoid, reponame);
}

bool loadCommitFromGitHub(string reponame, Pull p)
{
    string url = text("https://api.github.com/repos/D-Programming-Language/", reponame, "/commits/", p.head_sha);
    string payload;
    string[] headers;

    if (!runCurlGET(curl, payload, headers, url, c.github_user, c.github_passwd) || payload.length == 0)
    {
        writelog("  failed to load commit from github");
        return false;
    }

    JSONValue jv;
    try
    {
        jv = parseJSON(payload);
    }
    catch (JSONException e)
    {
        writelog("  error parsing github json response: %s\n", e.toString);
        return false;
    }

    string s = jv.object["commit"].object["committer"].object["date"].str;
    p.head_date = SysTime.fromISOExtString(s, UTC());
    //writelog("post fromISO: %s", p.head_date.toISOExtString());

    return true;
}

void updatePull(string reponame, Pull* k, Pull p)
{
    bool headerPrinted = false;
    void printHeader()
    {
        if (headerPrinted) return;
        headerPrinted = true;

        string oper = (k.open != p.open) ? (p.open ? "reopening" : "closing") : "updating";
        writelog("  %s %s/%s:", oper, reponame, p.pull_id);
    }

    bool clearOldResults = false;

    bool headDateAccurate = false;
    if (!k.open || k.head_sha != p.head_sha)
    {
        printHeader();
        if (!loadCommitFromGitHub(reponame, p)) return; // don't update anything in the db if we can't get the current commit date
        headDateAccurate = true;
    }

    if (k.open != p.open)
    {
        printHeader();
        clearOldResults = true;
        sql_exec(text("update github_pulls set open = ", p.open, " where id = ", k.id));

        if (p.open)
            sql_exec(text("update github_pulls set close_date = null where id = ", k.id));
    }

    if (k.updated_at != p.updated_at)
    {
        printHeader();
        writelog("    updated_at: %s -> %s", k.updated_at.toISOExtString(), p.updated_at.toISOExtString());
        sql_exec(text("update github_pulls set updated_at = '", p.updated_at.toISOExtString(), "' where id = ", k.id));
    }

    if (headDateAccurate && k.head_date != p.head_date)
    {
        printHeader();
        clearOldResults = true;
        writelog("    head_date: %s -> %s", k.head_date.toISOExtString(), p.head_date.toISOExtString());
        sql_exec(text("update github_pulls set head_date = '", p.head_date.toISOExtString(), "' where id = ", k.id));
    }

    if (k.base_git_url != p.base_git_url)
    {
        printHeader();
        clearOldResults = true;
        writelog("    base_git_url: %s -> %s", k.base_git_url, p.base_git_url);
        sql_exec(text("update github_pulls set base_git_url = '", p.base_git_url, "' where id = ", k.id));
    }

    if (k.base_sha != p.base_sha)
    {
        printHeader();
        clearOldResults = true;
        writelog("    base_sha: %s -> %s", k.base_sha, p.base_sha);
        sql_exec(text("update github_pulls set base_sha = '", p.base_sha, "' where id = ", k.id));
    }

    if (k.head_git_url != p.head_git_url)
    {
        printHeader();
        clearOldResults = true;
        writelog("    head_git_url: %s -> %s", k.head_git_url, p.head_git_url);
        sql_exec(text("update github_pulls set head_git_url = '", p.head_git_url, "' where id = ", k.id));
    }

    if (k.head_sha != p.head_sha)
    {
        printHeader();
        clearOldResults = true;
        writelog("    head_sha: %s -> %s", k.head_sha, p.head_sha);
        sql_exec(text("update github_pulls set head_sha = '", p.head_sha, "' where id = ", k.id));
    }

    if (k.create_date != p.create_date)
    {
        printHeader();
        writelog("    create_date: %s -> %s", k.create_date.toISOExtString(), p.create_date.toISOExtString());
        sql_exec(text("update github_pulls set create_date = '", p.create_date.toISOExtString(), "' where id = ", k.id));
    }

    if (k.close_date != p.close_date)
    {
        printHeader();
        writelog("    close_date: %s -> %s", k.close_date.toISOExtString(), p.close_date.toISOExtString());
        sql_exec(text("update github_pulls set close_date = '", p.close_date.toISOExtString(), "' where id = ", k.id));
    }

    if (clearOldResults)
    {
        writelog("    deprecating old test results");
        sql_exec(text("update pull_test_runs set deleted=1 where deleted=0 and g_p_id = ", k.id));
    }
}

void processPull(string repoid, string reponame, Pull* k, Pull p)
{
    //writelog("  processPull: %s/%s", p.repo_id, p.pull_id);
    if (k is null)
    {
        // try to load specific pull to see if this is a re-opened request
        sql_exec(text("select ", getPullColumns(), " from github_pulls where repo_id = ", repoid, " and pull_id = ", p.pull_id));
        sqlrow[] rows = sql_rows();

        if (rows == [])
        {
            if (!loadCommitFromGitHub(reponame, p)) return;

            // new pull request
            writelog("  opening %s/%s", reponame, p.pull_id);
            string sqlcmd = text("insert into github_pulls values (null, ", repoid, ", ", p.pull_id, ", ", p.user_id, ", '", p.create_date.toISOExtString(), "', ");

            if (p.close_date.toISOExtString() == "2000-01-01T00:00:00Z")
                sqlcmd ~= "null";
            else
                sqlcmd ~= "'" ~ p.close_date.toISOExtString() ~ "'";

            sqlcmd ~= text(", '", p.updated_at.toISOExtString(), "', true, "
                           "'", p.base_git_url, "', '", p.base_ref, "', '", p.base_sha, "', "
                           "'", p.head_git_url, "', '", p.head_ref, "', '", p.head_sha, "', "
                           "'", p.head_date.toISOExtString(), "')");

            sql_exec(sqlcmd);
        }
        else
        {
            // reopened pull request
            Pull newP = makePullFromRow(rows[0]);
            updatePull(reponame, &newP, p);
        }
    }
    else
    {
        updatePull(reponame, k, p);
    }
}

Pull makePullFromJson(const JSONValue obj, string repoid, string reponame)
{
    ulong  uid     = obj.object["user"].object["id"].integer;
    string uname   = obj.object["user"].object["login"].str;
    long   pullid  = obj.object["number"].integer;
    bool   trusted = checkUser(uid, uname);

    const JSONValue base = obj.object["base"];
    const JSONValue head = obj.object["head"];

    if (base.type != JSON_TYPE.OBJECT || base.object.length() == 0)
    {
        writelog("%s/%s: base is null, skipping", reponame, pullid);
        return null;
    }
    if (head.type != JSON_TYPE.OBJECT || head.object.length() == 0)
    {
        writelog("%s/%s: head is null, skipping", reponame, pullid);
        return null;
    }

    const JSONValue b_repo = base.object["repo"];
    const JSONValue h_repo = head.object["repo"];

    if (b_repo.type != JSON_TYPE.OBJECT || b_repo.object.length() == 0)
    {
        writelog("%s/%s: base.repo is null, skipping", reponame, pullid);
        return null;
    }
    if (h_repo.type != JSON_TYPE.OBJECT || h_repo.object.length() == 0)
    {
        writelog("%s/%s: head.repo is null, skipping", reponame, pullid);
        return null;
    }

    string base_ref = base.object["ref"].str;
    if (base_ref != "master")
    {
        writelog("%s/%s: pull is for %s, not master", reponame, pullid, base_ref);
        return null;
    }

    const JSONValue jvU = obj.object["updated_at"];
    string updated_at   = jvU.type == JSON_TYPE.STRING ? jvU.str : "";
    if (updated_at == "") { updated_at = "2000-01-01T00:00:00Z"; }

    const JSONValue jvC = obj.object["created_at"];
    string created_at   = jvC.type == JSON_TYPE.STRING ? jvC.str : "";
    if (created_at == "") { created_at = "2000-01-01T00:00:00Z"; }

    const JSONValue jvD = obj.object["closed_at"];
    string closed_at    = jvD.type == JSON_TYPE.STRING ? jvD.str : "";
    if (closed_at  == "") { closed_at  = "2000-01-01T00:00:00Z"; }
    // writelog("%s %s %s", updated_at, created_at, closed_at);

    auto p = new Pull(
            0, // our id not known from github data
            to!ulong(repoid),
            obj.object["number"].integer,
            uid,
            SysTime.fromISOExtString(updated_at),
            obj.object["state"].str == "open",
            base.object["repo"].object["clone_url"].str,
            base.object["ref"].str,
            base.object["sha"].str,
            head.object["repo"].object["clone_url"].str,
            head.object["ref"].str,
            head.object["sha"].str,
            SysTime.fromISOExtString(updated_at), // wrong time, but need a value. Will be fixed during loadCommitFromGitHub
            SysTime.fromISOExtString(created_at),
            SysTime.fromISOExtString(closed_at));

    return p;
}

bool processProject(Pull[ulong] knownpulls, string repoid, string reponame, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        Pull p = makePullFromJson(obj, repoid, reponame);
        if (!p) continue;

        Pull* tmp = p.pull_id in knownpulls;
        processPull(repoid, reponame, tmp, p);

        knownpulls.remove(p.pull_id);
    }

    return true;
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

        sql_exec(text("select ", getPullColumns()," from github_pulls where repo_id = ", repo[0], " and open = true"));
        sqlrow[] rows = sql_rows();
        Pull[ulong] knownpulls;
        foreach(row; rows)
        {
            Pull p = makePullFromRow(row);
            knownpulls[to!ulong(row[2])] = p;
        }

        string url = text("https://api.github.com/repos/D-Programming-Language/", repo[1], "/pulls?state=open&per_page=100");
        while (url)
        {
            string payload;
            string[] headers;

            if (!runCurlGET(curl, payload, headers, url, c.github_user, c.github_passwd) || payload.length == 0)
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

            if (!processProject(knownpulls, repo[0], repo[1], jv))
            {
                writelog("  failed to process project, skipping repo");
                continue projloop;
            }

            url = findNextLink(headers);
        }

        //writelog("closing pulls");
        // any elements left in knownpulls means they're no longer open, so mark closed
        foreach(k; knownpulls.keys)
        {
            Pull p = loadPullFromGitHub(repo[0], repo[1], k);
            if (p)
            {
                Pull* tmp = k in knownpulls;
                processPull(repo[0], repo[1], tmp, p);
            }
        }
    }
}

void backfill_pulls()
{
    version (none)
    {
    string repoid = "1";
    string reponame = "dmd";
    ulong pullid = 1;

    sql_exec(text("select ", getPullColumns(), " from github_pulls where repo_id = ", repoid, " and pull_id = ", pullid));
    sqlrow[] rows = sql_rows();

    Pull k = makePullFromRow(rows[0]);

    Pull p = loadPullFromGitHub(repoid, reponame, pullid);

    processPull(repoid, reponame, &k, p);
    }

    sql_exec("update github_pulls set open=1 where open=0 and create_date is null limit 10");
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

    backfill_pulls();
    update_pulls();

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
