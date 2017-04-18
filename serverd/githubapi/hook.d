module githubapi.hook;

import mysql;
import utils;

import model.project;
import model.pull;

import std.algorithm;
import std.conv;
import std.json;
import std.range;

bool parseAndReturn(string str, ref JSONValue jv)
{
    try
    {
        jv = parseJSON(str);
    }
    catch (JSONException e)
    {
        writelog("  error parsing github json: %s\n", e.toString);
        return false;
    }

    if (jv.type != JSON_TYPE.OBJECT)
    {
        writelog("  json parsed, but isn't an object: %s", str);
        return false;
    }

    return true;
}

bool parsePush(const ref JSONValue jv, ref string ownerstr, ref string repostr, ref string branchstr)
{
    const(JSONValue)* refname = "ref" in jv.object;
    const(JSONValue)* repo    = "repository" in jv.object;

    if (!refname || !repo)
    {
        writelog("  missing ref or repository, invalid push?");
        return false;
    }

    const(JSONValue)* owner    = "owner" in repo.object;
    const(JSONValue)* reponame = "name" in repo.object;

    if (!owner || !reponame)
    {
        writelog("  missing repo.owner or repo.name, invalid push?");
        return false;
    }

    owner = "name" in owner.object;

    if (!owner)
    {
        writelog("  missing repo.owner.name, invalid push?");
        return false;
    }

    string branch = refname.str;
    if (!branch.startsWith("refs/heads/"))
    {
        writelog("  unexpected ref format, expecting refs/heads/<branchname>, got: %s", branch);
        return false;
    }
    branch = branch[11 .. $];

    ownerstr  = owner.str;
    repostr   = reponame.str;
    branchstr = branch;

    return true;
}

bool processPush(const ref JSONValue jv)
{
    string owner, reponame, branch;

    if (!parsePush(jv, owner, reponame, branch))
        return false;

    writelog("  processPush: %s/%s/%s", owner, reponame, branch);

    // build list of affected projects
    sql_exec(text("select p.id " ~
                  "from projects p, repositories r, project_repositories pr " ~
                  "where p.enabled = true and p.id = pr.project_id and pr.repository_id = r.id and " ~
                  "r.owner = \"", sql_quote(owner), "\" and r.name = \"", reponame, "\" and r.ref = \"", sql_quote(branch), "\""));

    sqlrow[] rows = sql_rows();
    if (rows.length == 0)
    {
        writelog("  ignoring post, %s/%s/%s not part of any project", owner, reponame, branch);
        return true;
    }

    string pid_in_list = "(";
    foreach(index, row; rows)
    {
        if (index != 0)
            pid_in_list ~= ", ";
        pid_in_list ~= row[0];
    }
    pid_in_list ~= ")";

    writelog("  invalidate obsoleted test_runs");
    sql_exec("update test_runs set deleted = true where start_time < (select post_time from github_posts order by id desc limit 1) and deleted = false and project_id in " ~ pid_in_list);

    writelog("  invalidate obsoleted pull_test_runs");
    sql_exec("update pull_test_runs " ~
             "set deleted = true " ~
             "where deleted = false and " ~
             "start_time < (select post_time from github_posts order by id desc limit 1) and " ~
             "g_p_id in ( " ~
                 "select id " ~
                 "from github_pulls " ~
                 "where repo_id in (" ~
                     "select r.id " ~
                     "from projects p, repositories r, project_repositories pr " ~
                     "where p.id = pr.project_id and " ~
                     "pr.repository_id = r.id and " ~
                     "p.id in " ~ pid_in_list ~
                 ")" ~
             ")");

    return true;
}

Repository findRepo(const ref JSONValue jv, const ref JSONValue pull_request)
{
    const(JSONValue)* base           = "base"  in pull_request.object;
    const(JSONValue)* base_repo      = "repo"  in base.object;
    const(JSONValue)* base_repo_name = "name"  in base_repo.object;

    const(JSONValue)* base_user      = "user"  in base.object;
    const(JSONValue)* base_ref       = "ref"   in base.object;
    const(JSONValue)* owner          = "login" in base_user.object;

    // TODO: a single pull may affect multiple projects
    Project proj = loadProject(owner.str, base_repo_name.str, base_ref.str);
    Repository repo = proj.getRepositoryByName(base_repo_name.str);

    return repo;
}

bool processPull_updated(const Repository repo, ulong pull_id, const ref JSONValue pull_request)
{
    Pull github_pull = makePullFromJson(pull_request, repo);
    if (!github_pull) return false;
    if (github_pull.base_ref != repo.refname) return false;

    Pull db_pull = loadPull(repo.id, pull_id);

// TODO: figureout how to make this work cleanly here.. currently using github's updated_at field which
//       updates more frequently than when commits are made.  Luckily, this hook is only supposed to
//       be called when a commit has been made, so it's roughly the same.
//
//    if (db_pull.head_sha == github_pull.head_sha)
//        github_pull.head_date = db_pull.head_date;
//    else
//    {
//        string date = github.loadCommitDateFromGithub(repo.owner, repo.name, github_pull.head_sha);
//        if (!date) return false;
//        github_pull.head_date = SysTime.fromISOExtString(date, UTC());;
//    }

    if (db_pull)
        updatePull(repo, db_pull, github_pull);
    else
        newPull(repo, github_pull);

    return true;
}

bool processPull_labels(string action, const Repository repo, ulong pull_id, const ref JSONValue jv)
{
    //"label" : {
    //  "color" : "d3d3d3",
    //  "name" : "auto-merge-squash",
    //  "url" : "https://api.github.com/repos/dlang/phobos/labels/auto-merge-squash",
    //  "default" : false,
    //  "id" : 502726977
    //}

    Pull db_pull = loadPull(repo.id, pull_id);

    const(JSONValue)* label = "label" in jv.object;
    if (!label || label.type != JSON_TYPE.OBJECT)
    {
        writelog("    invalid label");
        return false;
    }

    const(JSONValue)* name = "name" in label.object;
    if (!name || name.type != JSON_TYPE.STRING)
    {
        writelog("    invalid name");
        return false;
    }

    if (name.str == "auto-merge" || name.str == "auto-merge-squash")
    {
        bool has_priority = action == "labeled";

        sql_exec(text("update github_pulls set has_priority = ", (has_priority ? "true" : "false"), " where id = ", db_pull.id));
    }

    return true;
}

bool processPull(const ref JSONValue jv)
{
    const(JSONValue)* action       = "action" in jv.object;
    const(JSONValue)* number       = "number" in jv.object;
    const(JSONValue)* pull_request = "pull_request" in jv.object;

    // doesn't look like a Push request, bail out
    if (!action       || action.type       != JSON_TYPE.STRING)  return false;
    if (!number       || number.type       != JSON_TYPE.INTEGER) return false;
    if (!pull_request || pull_request.type != JSON_TYPE.OBJECT)  return false;

    Repository repo = findRepo(jv, *pull_request);

    writelog("  processPull: %s", action.str);

    switch (action.str)
    {
        case "labeled":
        case "unlabeled":
            return processPull_labels(action.str, repo, number.integer, jv);

        default:
            return processPull_updated(repo, number.integer, *pull_request);
    }
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string eventname = lookup(hash, "HTTP_X_GITHUB_EVENT");  // TODO: add to schema and store
    string eventid = lookup(hash, "HTTP_X_GITHUB_DELIVERY"); // TODO: add to schema and store
    string bodytext = lookup(userhash, "REQUEST_BODY");

    // TODO: add auth check

    sql_exec(text("insert into github_posts (id, post_time, body) values (null, now(), \"", sql_quote(bodytext), "\")"));
    sql_exec("select last_insert_id()");
    sqlrow liid = sql_row();
    writelog("  processing event: %s", liid[0]);

    if (!eventname)
    {
        writelog("  missing X-GitHub-Event header, ignoring");
        return;
    }

    JSONValue jv;
    if (!parseAndReturn(bodytext, jv)) return;

    bool rc = true;
    switch(eventname)
    {
        case "push":         rc = processPush(jv); break;
        case "pull_request": rc = processPull(jv); break;
        default:             writelog("  unrecognized event, id: %s", liid[0]); break;
    }

    if (!rc)
        writelog("  processing of event id %s failed", liid[0]);
}

