module model.pull;

import mysql;
import utils;

import model.project;
import model.user;

import std.conv;
import std.datetime;
import std.json;

class Pull
{
    ulong   id;
    ulong   repo_id;
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

    this(ulong _id, ulong _repo_id, ulong _pull_id, ulong _user_id, SysTime _updated_at, bool _open, bool _base_usable, string _base_git_url, string _base_ref, string _base_sha, bool _head_usable, string _head_git_url, string _head_ref, string _head_sha, SysTime _head_date, SysTime _create_date, SysTime _close_date, ulong _auto_pull)
    {
        id           = _id;
        repo_id      = _repo_id;
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
    return "id, 0, pull_id, user_id, date_format(updated_at, '%Y-%m-%dT%H:%i:%S%Z'), base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, date_format(head_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(create_date, '%Y-%m-%dT%H:%i:%S%Z'), date_format(close_date, '%Y-%m-%dT%H:%i:%S%Z'), open, repo_id, auto_pull";
}

Pull makePullFromRow(sqlrow row)
{
    if (row[11] == "") row[11] = row[4]; // use temporarily until loadCommitDateFromGithub can get the right value
    if (row[4] == "0000-00-00T00:00:00Z") row[4] = "2000-01-01T00:00:00Z";
    if (row[11] == "" || row[11] == "0000-00-00T00:00:00Z") row[11] = "2000-01-01T00:00:00Z";
    if (row[12] == "" || row[12] == "0000-00-00T00:00:00Z") row[12] = "2000-01-01T00:00:00Z";
    if (row[13] == "" || row[13] == "0000-00-00T00:00:00Z") row[13] = "2000-01-01T00:00:00Z";

    // null -> 0 for auto_pull userid
    if (row[16] == "") row[16] = "0";

    //writelog("row[0] = %s, row[4] = %s, row[11] = %s, row[12] = %s, row[13] = %s, row[14] = %s", row[0], row[4], row[11], row[12], row[13], row[14]);
    return new Pull(to!ulong(row[0]), to!ulong(row[15]), to!ulong(row[2]), to!ulong(row[3]), SysTime.fromISOExtString(row[4]), (row[14] == "1"), true, row[5], row[6], row[7], true, row[8], row[9], row[10], SysTime.fromISOExtString(row[11]), SysTime.fromISOExtString(row[12]), SysTime.fromISOExtString(row[13]), to!ulong(row[16]));
}

Pull makePullFromJson(const JSONValue obj, Repository repo)
{
    ulong  uid     = obj.object["user"].object["id"].integer;
    string uname   = obj.object["user"].object["login"].str;
    long   pullid  = obj.object["number"].integer;
    bool   trusted = checkUser(uid, uname);

    const JSONValue base = obj.object["base"];

    if (base.type != JSON_TYPE.OBJECT || base.object.length() == 0)
    {
        writelog("%s/%s/%s: base is null, skipping", repo.owner, repo.name, pullid);
        return null;
    }

    const JSONValue b_repo = base.object["repo"];

    if (b_repo.type != JSON_TYPE.OBJECT || b_repo.object.length() == 0)
    {
        writelog("%s/%s/%s: base.repo is null, skipping", repo.owner, repo.name, pullid);
        return null;
    }
    string base_ref = base.object["ref"].str;
    if (base_ref != repo.refname)
    {
        //writelog("%s/%s/%s: pull is for %s, not %s", repo.owner, repo.name, pullid, base_ref, repo.refname);
        return null;
    }

    bool   h_isusable = true;
    string h_url;
    string h_ref;
    string h_sha;
    const JSONValue head = obj.object["head"];
    if (head.type != JSON_TYPE.OBJECT || head.object.length() == 0)
    {
        writelog("WARNING: %s/%s/%s: head is null", repo.owner, repo.name, pullid);
        h_isusable = false;
    }
    else
    {
        const JSONValue h_repo = head.object["repo"];
        if (h_repo.type != JSON_TYPE.OBJECT || h_repo.object.length() == 0)
        {
            writelog("WARNING: %s/%s/%s: head.repo is null", repo.owner, repo.name, pullid);
            h_isusable = false;
        }
        else
        {
            h_url = h_repo.object["clone_url"].str;
            h_ref = head.object["ref"].str;
            h_sha = head.object["sha"].str;
        }
    }

    const(JSONValue)* jvU = "updated_at" in obj.object;
    string updated_at   = (jvU && jvU.type == JSON_TYPE.STRING) ? jvU.str : "";
    if (updated_at == "") { updated_at = "2000-01-01T00:00:00Z"; }

    const(JSONValue)* jvC = "created_at" in obj.object;
    string created_at   = (jvC && jvC.type == JSON_TYPE.STRING) ? jvC.str : "";
    if (created_at == "") { created_at = "2000-01-01T00:00:00Z"; }

    const(JSONValue)* jvD = "closed_at" in obj.object;
    string closed_at    = (jvD && jvD.type == JSON_TYPE.STRING) ? jvD.str : "";
    if (closed_at  == "") { closed_at  = "2000-01-01T00:00:00Z"; }
    // writelog("%s %s %s", updated_at, created_at, closed_at);

    const(JSONValue)* merged_by = "merged_by" in obj.object;
    ulong auto_pull = 0;
    if (merged_by && merged_by.type == JSON_TYPE.OBJECT)
    {
        const JSONValue id = merged_by.object["id"];
        if (id.type == JSON_TYPE.INTEGER) auto_pull = id.integer;
    }

    auto p = new Pull(
            0, // our id not known from github data
            repo.id,
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
            SysTime.fromISOExtString(updated_at), // wrong time, but need a value. Will be fixed during loadCommitDateFromGithub
            SysTime.fromISOExtString(created_at),
            SysTime.fromISOExtString(closed_at),
            auto_pull);

    return p;
}

bool updatePull(Repository repo, Pull current, Pull updated)
{
    bool headerPrinted = false;
    void printHeader()
    {
        if (headerPrinted) return;
        headerPrinted = true;

        string oper = (current.open != updated.open) ? (updated.open ? "reopening" : "closing") : "updating";
        writelog("  %s %s/%s/%s:", oper, repo.owner, repo.name, updated.pull_id);
    }

    bool clearOldResults = false;
    bool clearAutoPull = false;

    //writelog("  c.o = %s, u.o = %s, c.ap = %s, u.ap = %s", current.open, updated.open, current.auto_pull, updated.auto_pull);
    if (current.open != updated.open)
    {
        printHeader();
        clearOldResults = true;
        sql_exec(text("update github_pulls set open = ", updated.open, " where id = ", current.id));

        if (updated.open)
            sql_exec(text("update github_pulls set close_date = null where id = ", current.id));
        else if (current.auto_pull != updated.auto_pull)
        {
            writelog("    auto_pull: %s -> %s", current.auto_pull, updated.auto_pull);
            sql_exec(text("update github_pulls set auto_pull = ", updated.auto_pull, " where id = ", current.id));
        }
    }

    if (current.updated_at != updated.updated_at)
    {
        printHeader();
        writelog("    updated_at: %s -> %s", current.updated_at.toISOExtString(), updated.updated_at.toISOExtString());
        sql_exec(text("update github_pulls set updated_at = '", updated.updated_at.toISOExtString(), "' where id = ", current.id));
    }

    if (updated.head_usable && current.head_date != updated.head_date)
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

    return clearAutoPull;
}

void newPull(Repository repo, Pull pull)
{
    writelog("  opening %s/%s/%s", repo.owner, repo.name, pull.pull_id);

    string sqlcmd = text("insert into github_pulls (id, repo_id, pull_id, user_id, create_date, close_date, updated_at, open, base_git_url, base_ref, base_sha, head_git_url, head_ref, head_sha, head_date, auto_pull) values (null, ", repo.id, ", ", pull.pull_id, ", ", pull.user_id, ", '", pull.create_date.toISOExtString(), "', ");

    if (pull.close_date.toISOExtString() == "2000-01-01T00:00:00Z")
        sqlcmd ~= "null";
    else
        sqlcmd ~= "'" ~ pull.close_date.toISOExtString() ~ "'";

    sqlcmd ~= text(", '", pull.updated_at.toISOExtString(), "', true, "
                   "'", pull.base_git_url, "', '", pull.base_ref, "', '", pull.base_sha, "', "
                   "'", pull.head_git_url, "', '", pull.head_ref, "', '", pull.head_sha, "', "
                   "'", pull.head_date.toISOExtString(), "', null)");

    sql_exec(sqlcmd);
}

Pull loadPull(ulong repo_id, ulong pull_id)
{
    sql_exec(text("select ", getPullColumns(), " from github_pulls where repo_id = ", repo_id, " and pull_id = ", pull_id));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
        return null;
    else
        return makePullFromRow(rows[0]);
}

