module p_update_pulls;

import config;
import github_apis;
import mysql;
import utils;

import model.project;
import model.user;

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
Github github;
alias string[] sqlrow;

class Pull
{
    ulong   id;
    ulong   r_b_id;
    ulong   pull_id;
    ulong   user_id;
    SysTime updated_at;
    bool    open;
    bool    base_usable;
    bool    head_usable;
    string  base_git_url;  // ex: https://github.com/D-Programming-Language/druntime.git
    string  base_ref;      // ex: master
    string  base_sha;      // ex: 98f410bd67e8a79630d05da7a37b0029bc45fa4b
    string  head_git_url;  // ex: git@github.com:fugalh/druntime.git
    string  head_ref;      // ex: master
    string  head_sha;      // ex: 9d63a68eb72c00b1303a047c4dfae71eae23dc81
    SysTime head_date;
    SysTime create_date;
    SysTime close_date;
    ulong   auto_pull;

    this(ulong _id, ulong _r_b_id, ulong _pull_id, ulong _user_id, SysTime _updated_at, bool _open, bool _base_usable, string _base_git_url, string _base_ref, string _base_sha, bool _head_usable, string _head_git_url, string _head_ref, string _head_sha, SysTime _head_date, SysTime _create_date, SysTime _close_date, ulong _auto_pull)
    {
        id           = _id;
        r_b_id       = _r_b_id;
        pull_id      = _pull_id;
        user_id      = _user_id;
        updated_at   = _updated_at;
        open         = _open;
        base_usable  = _base_usable;
        head_usable  = _head_usable;
        base_git_url = _base_git_url;
        base_ref     = _base_ref;
        base_sha     = _base_sha;
        head_git_url = _head_git_url;
        head_ref     = _head_ref;
        head_sha     = _head_sha;
        head_date    = _head_date;
        create_date  = _create_date;
        close_date   = _close_date;
        auto_pull    = _auto_pull;
    }
}

string getPullColumns()
{
    // field 1 is unused now (was repo_id)
    //      0   1  2        3        4                                               5             6         7         8             9         10        11                                             12                                               13                                              14    15      16
    return "id, 0, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, date_format(head_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(create_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(close_date, '%Y-%m-%dT%H:%i:%S%Z'), open, r_b_id, auto_pull";
}

Pull makePullFromRow(sqlrow row)
{
    if (row[11] == "") row[11] = row[4]; // use temporarily until loadCommitFromGitHub can get the right value
    if (row[4] == "0000-00-00T00:00:00Z") row[4] = "2000-01-01T00:00:00Z";
    if (row[11] == "" || row[11] == "0000-00-00T00:00:00Z") row[11] = "2000-01-01T00:00:00Z";
    if (row[12] == "" || row[12] == "0000-00-00T00:00:00Z") row[12] = "2000-01-01T00:00:00Z";
    if (row[13] == "" || row[13] == "0000-00-00T00:00:00Z") row[13] = "2000-01-01T00:00:00Z";

    // TODO: remove once r_b_id data is backfilled
    if (row[15] == "") row[15] = "0";
    // null -> 0 for auto_pull userid
    if (row[16] == "") row[16] = "0";

    //writelog("row[0] = %s, row[4] = %s, row[11] = %s, row[12] = %s, row[13] = %s, row[14] = %s", row[0], row[4], row[11], row[12], row[13], row[14]);
    return new Pull(to!ulong(row[0]), to!ulong(row[15]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), (row[14] == "1"), true, row[5], row[6], row[7], true, row[8], row[9], row[10], SysTime.fromISOExtString(row[11]), SysTime.fromISOExtString(row[12]), SysTime.fromISOExtString(row[13]), to!ulong(row[16]));
}

Pull loadPullFromGitHub(Project proj, Repository repo, ulong pullid)
{
    JSONValue jv;
    if (!github.getPull(proj.name, repo.name, to!string(pullid), jv))
        return null;

    return makePullFromJson(jv, proj, repo);
}

bool loadCommitFromGitHub(Project proj, Repository repo, Pull p)
{
    JSONValue jv;
    if (!github.getCommit(proj.name, repo.name, p.head_sha, jv))
        return false;

    string s = jv.object["commit"].object["committer"].object["date"].str;
    p.head_date = SysTime.fromISOExtString(s, UTC());
    //writelog("post fromISO: %s", p.head_date.toISOExtString());

    return true;
}

void updatePull(Project proj, Repository repo, Pull current, Pull updated)
{
    bool headerPrinted = false;
    void printHeader()
    {
        if (headerPrinted) return;
        headerPrinted = true;

        string oper = (current.open != updated.open) ? (updated.open ? "reopening" : "closing") : "updating";
        writelog("  %s %s/%s/%s:", oper, proj.name, repo.name, updated.pull_id);
    }

    bool clearOldResults = false;
    bool clearAutoPull = false;

    bool headDateAccurate = false;
    if (!current.open || (updated.head_usable && current.head_sha != updated.head_sha))
    {
        printHeader();
        if (!loadCommitFromGitHub(proj, repo, updated))
        {
            // don't update anything in the db if we can't get the current commit date
            return;
        }
        headDateAccurate = true;
    }

    if (current.open != updated.open)
    {
        printHeader();
        clearOldResults = true;
        sql_exec(text("update github_pulls set open = ", updated.open, " where id = ", current.id));

        if (updated.open)
            sql_exec(text("update github_pulls set close_date = null where id = ", current.id));
    }

    if (current.updated_at != updated.updated_at)
    {
        printHeader();
        writelog("    updated_at: %s -> %s", current.updated_at.toISOExtString(), updated.updated_at.toISOExtString());
        sql_exec(text("update github_pulls set updated_at = '", updated.updated_at.toISOExtString(), "' where id = ", current.id));
    }

    if (headDateAccurate && updated.head_usable && current.head_date != updated.head_date)
    {
        printHeader();
        clearOldResults = true;
        writelog("    head_date: %s -> %s", current.head_date.toISOExtString(), updated.head_date.toISOExtString());
        sql_exec(text("update github_pulls set head_date = '", updated.head_date.toISOExtString(), "' where id = ", current.id));
    }

    if (current.base_git_url != updated.base_git_url)
    {
        printHeader();
        clearOldResults = true;
        clearAutoPull = true;
        writelog("    base_git_url: %s -> %s", current.base_git_url, updated.base_git_url);
        sql_exec(text("update github_pulls set base_git_url = '", updated.base_git_url, "' where id = ", current.id));
    }

    if (current.base_sha != updated.base_sha)
    {
        printHeader();
        clearOldResults = true;
        clearAutoPull = true;
        writelog("    base_sha: %s -> %s", current.base_sha, updated.base_sha);
        sql_exec(text("update github_pulls set base_sha = '", updated.base_sha, "' where id = ", current.id));
    }

    if (updated.head_usable && current.head_git_url != updated.head_git_url)
    {
        printHeader();
        clearOldResults = true;
        clearAutoPull = true;
        writelog("    head_git_url: %s -> %s", current.head_git_url, updated.head_git_url);
        sql_exec(text("update github_pulls set head_git_url = '", updated.head_git_url, "' where id = ", current.id));
    }

    if (updated.head_usable && current.head_sha != updated.head_sha)
    {
        printHeader();
        clearOldResults = true;
        clearAutoPull = true;
        writelog("    head_sha: %s -> %s", current.head_sha, updated.head_sha);
        sql_exec(text("update github_pulls set head_sha = '", updated.head_sha, "' where id = ", current.id));
    }

    if (current.create_date != updated.create_date)
    {
        printHeader();
        writelog("    create_date: %s -> %s", current.create_date.toISOExtString(), updated.create_date.toISOExtString());
        sql_exec(text("update github_pulls set create_date = '", updated.create_date.toISOExtString(), "' where id = ", current.id));
    }

    if (current.close_date != updated.close_date)
    {
        printHeader();
        writelog("    close_date: %s -> %s", current.close_date.toISOExtString(), updated.close_date.toISOExtString());
        sql_exec(text("update github_pulls set close_date = '", updated.close_date.toISOExtString(), "' where id = ", current.id));
    }

    if (clearOldResults)
    {
        writelog("    deprecating old test results");
        sql_exec(text("update pull_test_runs set rc = 2, end_time = now() where rc is null and deleted = 0 and g_p_id = ", current.id));
        sql_exec(text("update pull_test_runs set deleted = 1 where deleted = 0 and g_p_id = ", current.id));
        sql_exec(text("delete from pull_suppressions where g_p_id = ", current.id));
    }

    if (clearAutoPull && current.auto_pull != 0)
    {
        writelog("    clearing auto-pull state");
        JSONValue jv;
        github.addPullComment(proj.name, repo.name, to!string(current.pull_id), "Pull updated, auto_merge toggled off", jv);
        sql_exec(text("update github_pulls set auto_pull = null where id = ", current.id));
    }
}

void processPull(Project proj, Repository repo, Pull* k, Pull p)
{
    //writelog("  processPull: %s/%s/%s", proj.name, repo.name, p.pull_id);
    if (k is null)
    {
        // try to load specific pull to see if this is a re-opened request
        sql_exec(text("select ", getPullColumns(), " from github_pulls where r_b_id = ", repo.branch.id, " and pull_id = ", p.pull_id));
        sqlrow[] rows = sql_rows();

        if (rows == [])
        {
            if (!loadCommitFromGitHub(proj, repo, p)) return;
            if (!p.head_usable)
            {
                writelog("ERROR: %s/%s/%s, new pull request with null head.repo, skipping", proj.name, repo.name, p.pull_id);
                return;
            }

            // new pull request
            writelog("  opening %s/%s/%s", proj.name, repo.name, p.pull_id);
            // TODO: replace second null with p.r_b_id after r_b_id has a meaningful value
            string sqlcmd = text("insert into github_pulls (id, r_b_id, pull_id, user_id, create_date, close_date, updated_at, open, base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, head_date, auto_pull) values (null, ", repo.branch.id, ", ", p.pull_id, ", ", p.user_id, ", '", p.create_date.toISOExtString(), "', ");

            if (p.close_date.toISOExtString() == "2000-01-01T00:00:00Z")
                sqlcmd ~= "null";
            else
                sqlcmd ~= "'" ~ p.close_date.toISOExtString() ~ "'";

            sqlcmd ~= text(", '", p.updated_at.toISOExtString(), "', true, "
                           "'", p.base_git_url, "', '", p.base_ref, "', '", p.base_sha, "', "
                           "'", p.head_git_url, "', '", p.head_ref, "', '", p.head_sha, "', "
                           "'", p.head_date.toISOExtString(), "', null)");

            sql_exec(sqlcmd);
        }
        else
        {
            // reopened pull request
            Pull newP = makePullFromRow(rows[0]);
            updatePull(proj, repo, newP, p);
        }
    }
    else
    {
        updatePull(proj, repo, *k, p);
    }
}

Pull makePullFromJson(const JSONValue obj, Project proj, Repository repo)
{
    ulong  uid     = obj.object["user"].object["id"].integer;
    string uname   = obj.object["user"].object["login"].str;
    long   pullid  = obj.object["number"].integer;
    bool   trusted = checkUser(uid, uname);

    const JSONValue base = obj.object["base"];

    if (base.type != JSON_TYPE.OBJECT || base.object.length() == 0)
    {
        writelog("%s/%s/%s: base is null, skipping", proj.name, repo.name, pullid);
        return null;
    }

    const JSONValue b_repo = base.object["repo"];

    if (b_repo.type != JSON_TYPE.OBJECT || b_repo.object.length() == 0)
    {
        writelog("%s/%s/%s: base.repo is null, skipping", proj.name, repo.name, pullid);
        return null;
    }
    string base_ref = base.object["ref"].str;
    if (base_ref != repo.branch.name)
    {
        //writelog("%s/%s/%s: pull is for %s, not %s", proj.name, repo.name, pullid, base_ref, repo.branch.name);
        return null;
    }

    bool   h_isusable = true;
    string h_url;
    string h_ref;
    string h_sha;
    const JSONValue head = obj.object["head"];
    if (head.type != JSON_TYPE.OBJECT || head.object.length() == 0)
    {
        writelog("WARNING: %s/%s/%s: head is null", proj.name, repo.name, pullid);
        h_isusable = false;
    }
    else
    {
        const JSONValue h_repo = head.object["repo"];
        if (h_repo.type != JSON_TYPE.OBJECT || h_repo.object.length() == 0)
        {
            writelog("WARNING: %s/%s/%s: head.repo is null", proj.name, repo.name, pullid);
            h_isusable = false;
        }
        else
        {
            h_url = h_repo.object["clone_url"].str;
            h_ref = head.object["ref"].str;
            h_sha = head.object["sha"].str;
        }
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
            repo.branch.id,
            obj.object["number"].integer,
            uid,
            SysTime.fromISOExtString(updated_at),
            obj.object["state"].str == "open",
            true,
            base.object["repo"].object["clone_url"].str,
            base.object["ref"].str,
            base.object["sha"].str,
            h_isusable,
            h_url,
            h_ref,
            h_sha,
            SysTime.fromISOExtString(updated_at), // wrong time, but need a value. Will be fixed during loadCommitFromGitHub
            SysTime.fromISOExtString(created_at),
            SysTime.fromISOExtString(closed_at),
            0);

    return p;
}

bool processProject(Pull[ulong] knownpulls, Project proj, Repository repo, const ref JSONValue jv)
{
    foreach(ref const JSONValue obj; jv.array)
    {
        Pull p = makePullFromJson(obj, proj, repo);
        if (!p) continue;

        Pull* tmp = p.pull_id in knownpulls;
        processPull(proj, repo, tmp, p);

        knownpulls.remove(p.pull_id);
    }

    return true;
}

void update_pulls(Project[ulong] projects)
{
projloop:
    foreach(pk, pv; projects)
    {
        foreach (rk, rv; pv.repositories)
        {
            writelog("processing pulls for %s/%s branch %s", pv.name, rv.name, rv.branch.name);

            sql_exec(text("select ", getPullColumns()," from github_pulls where r_b_id = ", rv.branch.id, " and open = true"));
            sqlrow[] rows = sql_rows();
            Pull[ulong] knownpulls;
            foreach(row; rows)
            {
                Pull p = makePullFromRow(row);
                knownpulls[to!ulong(row[2])] = p;
            }

            string nextlink;
            do
            {
                JSONValue jv;
                if (!github.getPulls(pv.name, rv.name, jv, nextlink))
                    continue projloop;

                if (jv.type != JSON_TYPE.ARRAY)
                {
                    writelog("  github pulls data malformed, expected an array");
                    break;
                }

                if (!processProject(knownpulls, pv, rv, jv))
                {
                    writelog("  failed to process project, skipping repo");
                    continue projloop;
                }
            }
            while (nextlink != "");

            //writelog("closing pulls");
            // any elements left in knownpulls means they're no longer open, so mark closed
            foreach(k; knownpulls.keys)
            {
                Pull p = loadPullFromGitHub(pv, rv, k);
                if (p)
                {
                    Pull* tmp = k in knownpulls;
                    processPull(pv, rv, tmp, p);
                }
            }
        }
    }
}

void backfill_pulls()
{
    string ids_with_no_repo =
        "8, "
        "105, 137, "
        "203, 204, 206, 241, 257, 268, "
        "301, 314, 316, 323, 328, "
        "401, 425, 430, 495, "
        "505, 519, 540, "
        "679, "
        "720, 726, 758, 777, "
        "810, 856, "
        "1009, 1027, 1042, 1060, 1072, 1074, "
        "1137, 1144, 1153, "
        "1230, 1294, "
        "1306, 1316, 1321, 1322, 1331, 1340, 1342, 1349, 1350, 1351, 1352, 1360, "
        "1478, 1479, 1480, 1491, "
        "2382";



    // resetting to open where we don't het have a create_date to force a re-populate from github
    // TODO: build a better mechanism than having to open the request
    sql_exec(text("update github_pulls set open=1 where open=0 and create_date is null and base_ref = \"master\" and id not in (", ids_with_no_repo, ") limit 10"));
}

int main(string[] args)
{
    LOGNAME = "/tmp/update-pulls.log";

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

    github = new Github(c.github_user, c.github_passwd, c.github_clientid, c.github_clientsecret, curl);

    // loads the tree of Project -> Repository -> RepoBranch
    Project[ulong] projects = loadProjects();

    //backfill_pulls();
    update_pulls(projects);

    writelog("shutting down");

    sql_shutdown();

    return 0;
}
