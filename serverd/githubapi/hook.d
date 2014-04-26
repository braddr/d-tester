module githubapi.hook;

import mysql;
import utils;

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

bool processPush(const ref JSONValue jv)
{
    const(JSONValue)* refname = "ref" in jv.object;
    const(JSONValue)* repo    = "repository" in jv.object;

    // doesn't look like a Push request, bail out
    if (!refname || !repo) return false;

    const(JSONValue)* org      = "organization" in repo.object;
    const(JSONValue)* reponame = "name" in repo.object;

    if (!org || !reponame)
    {
        writelog("  missing repo.organization or repo.name, invalid push?");
        return false;
    }

    string branch = refname.str;
    if (!branch.startsWith("refs/heads/"))
    {
        writelog("  unexpected ref format, expecting refs/heads/<branchname>, got: %s", branch);
        return false;
    }
    branch = branch[11 .. $];

    sql_exec(text("select p.id "
                  "from projects p, repositories r, repo_branches rb "
                  "where p.id = r.project_id and r.id = rb.repository_id and "
                  "p.name = \"", sql_quote(org.str), "\" and r.name = \"", reponame.str, "\" and rb.name = \"", sql_quote(branch), "\""));
    sqlrow[] rows = sql_rows();

    if (rows.length == 0)
    {
        writelog ("  no project found for '%s/%s/%s'", org.str, reponame.str, branch);
        return false;
    }
    string projectid = rows[0][0];

    // invalidate obsoleted test_runs
    sql_exec(text("update test_runs set deleted = true where start_time < (select post_time from github_posts order by id desc limit 1) and deleted = false and project_id = ", projectid));

    // invalidate obsoleted pull_test_runs
    sql_exec(text("select rb.id "
                  "from projects p, repositories r, repo_branches rb "
                  "where p.id = r.project_id and r.id = rb.repository_id and "
                  "p.id = ", projectid));
    rows = sql_rows();

    string query = "update pull_test_runs set deleted = true where start_time < (select post_time from github_posts order by id desc limit 1) and deleted = false and g_p_id in (select id from github_pulls where r_b_id in (";
    bool first = true;
    foreach(row; rows)
    {
        if (first)
            first = false;
        else
            query ~= ", ";
        query ~= row[0];
    }
    query ~= "))";

    sql_exec(query);

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    outstr.put("Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string eventname = "push"; // lookup(hash, "X-GitHub-Event");  // TODO: add to schema and store
    string eventid = ""; // lookup(hash, "X-GitHub-Delivery"); // TODO: add to schema and store
    string bodytext = lookup(userhash, "REQUEST_BODY");

    // TODO: add auth check

    sql_exec(text("insert into github_posts (id, post_time, body) values (null, now(), \"", sql_quote(bodytext), "\")"));
    sql_exec("select last_insert_id()");
    sqlrow liid = sql_row();
    //formattedWrite(outstr, "%s\n", liid[0]);

    if (!eventname)
    {
        writelog("  missing X-GitHub-Event header, ignoring");
        return;
    }

    JSONValue jv;
    if (!parseAndReturn(bodytext, jv)) return;

    switch(eventname)
    {
        case "push": processPush(jv); break;
        default:     writelog("  unrecognize event, id: %s", liid[0]); break;
    }
}

//{
//    "ref":"refs/heads/master",
//    "after":"97cfb3daebf676c420816d98a0145d9727f78fe2",
//    "before":"e4da8bb7782e7196411e40cc431344f95ca3bdd3",
//    "created":false,
//    "deleted":false,
//    "forced":false,
//    "compare":"https://github.com/D-Programming-Language/phobos/compare/e4da8bb7782e...97cfb3daebf6",
//    "commits":
//        [
//            {
//                "id":"545a9450f8e3f2a1fd56f0d7fcfde3c3f7d1aeea",
//                "distinct":true,
//                "message":"fix property enforcement",
//                "timestamp":"2014-02-10T05:24:02-08:00",
//                "url":"https://github.com/D-Programming-Language/phobos/commit/545a9450f8e3f2a1fd56f0d7fcfde3c3f7d1aeea",
//                "author":
//                    {
//                        "name":"k-hara",
//                        "email":"k.hara.pg@gmail.com"
//                    },
//                "committer":
//                    {
//                        "name":"k-hara",
//                        "email":"k.hara.pg@gmail.com"
//                    },
//                "added":[],
//                "removed":[],
//                "modified":["std/variant.d"]
//            },
//            {
//                "id":"97cfb3daebf676c420816d98a0145d9727f78fe2",
//                "distinct":true,
//                "message":"Merge pull request #1922 from 9rnsr/enforceProp\n\nfix property enforcement",
//                "timestamp":"2014-02-10T06:01:37-08:00",
//                "url":"https://github.com/D-Programming-Language/phobos/commit/97cfb3daebf676c420816d98a0145d9727f78fe2",
//                "author":
//                    {
//                        "name":"Andrej Mitrovic",
//                        "email":"andrej.mitrovich@gmail.com",
//                        "username":"AndrejMitrovic"
//                    },
//                "committer":
//                    {
//                        "name":"Andrej Mitrovic",
//                        "email":"andrej.mitrovich@gmail.com",
//                        "username":"AndrejMitrovic"
//                    },
//                "added":[],
//                "removed":[],
//                "modified":["std/variant.d"]
//            }
//        ],
//    "head_commit":
//        {
//            "id":"97cfb3daebf676c420816d98a0145d9727f78fe2",
//            "distinct":true,
//            "message":"Merge pull request #1922 from 9rnsr/enforceProp\n\nfix property enforcement",
//            "timestamp":"2014-02-10T06:01:37-08:00",
//            "url":"https://github.com/D-Programming-Language/phobos/commit/97cfb3daebf676c420816d98a0145d9727f78fe2",
//            "author":
//                {
//                    "name":"Andrej Mitrovic",
//                    "email":"andrej.mitrovich@gmail.com",
//                    "username":"AndrejMitrovic"
//                },
//            "committer":
//                {
//                    "name":"Andrej Mitrovic",
//                    "email":"andrej.mitrovich@gmail.com",
//                    "username":"AndrejMitrovic"
//                },
//            "added":[],
//            "removed":[],
//            "modified":["std/variant.d"]
//        },
//    "repository":
//        {
//            "id":1257084,
//            "name":"phobos",
//            "url":"https://github.com/D-Programming-Language/phobos",
//            "description":"The standard library of the D programming language",
//            "homepage":"dlang.org/phobos",
//            "watchers":436,
//            "stargazers":436,
//            "forks":258,
//            "fork":false,
//            "size":36766,
//            "owner":
//                {
//                    "name":"D-Programming-Language",
//                    "email":null
//                },
//            "private":false,
//            "open_issues":8,
//            "has_issues":false,
//            "has_downloads":true,
//            "has_wiki":false,
//            "language":"D",
//            "created_at":1295074806,
//            "pushed_at":1392040898,
//            "master_branch":"master",
//            "organization":"D-Programming-Language"
//        },
//    "pusher":
//        {
//            "name":"AndrejMitrovic",
//            "email":"andrej.mitrovich@gmail.com"
//        }
//}
