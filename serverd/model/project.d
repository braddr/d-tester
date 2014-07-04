module model.project;

import mysql;
import utils;

import std.conv;

class Repository
{
    ulong id;
    ulong project_id;
    string owner;
    string name;
    string refname;

    this(ulong _id, ulong _pid, string _owner, string _name, string _refname)
    {
        id         = _id;
        project_id = _pid;
        owner      = _owner;
        name       = _name;
        refname    = _refname;
    }
}

Repository[] loadRepositories(ulong pid)
{
    sql_exec(text("select id, owner, name, ref from repositories where project_id = ", pid, " order by id"));

    sqlrow[] rows = sql_rows();

    Repository[] repositories;
    foreach (row; rows)
    {
        auto r = new Repository(to!ulong(row[0]), pid, row[1], row[2], row[3]);
        repositories ~= r;
    }

    return repositories;
}

class Project
{
    ulong  id;
    bool   test_pulls;
    Repository[] repositories;

    this(ulong _id, bool _test_pulls)
    {
        id = _id;
        test_pulls = _test_pulls;
        repositories = loadRepositories(id);
    }

    Repository getRepositoryByName(string reponame)
    {
        foreach (r; repositories)
        {
            if (r.name == reponame)
                return r;
        }

        return null;
    }
}

Project[ulong] loadProjects()
{
    sql_exec(text("select id, test_pulls from projects where enabled = true"));

    sqlrow[] rows = sql_rows();

    Project[ulong] projects;
    foreach (row; rows)
    {
        auto p = new Project(to!ulong(row[0]), (row[1] == "1"));
        projects[to!ulong(row[0])] = p;
    }

    return projects;
}

Project loadProject(string owner, string repo, string branch)
{
    sql_exec(text("select p.id, p.test_pulls from projects p where p.id in (select r.project_id from repositories r where r.owner = \"", owner, "\" and r.name = \"", repo, "\" and r.ref = \"", branch, "\")"));

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        writelog("  found more than one project matching %s/%s%s, skipping", owner, repo, branch);
        return null;
    }

    auto p = new Project(to!ulong(rows[0][0]), (rows[0][1] == "1"));
    return p;
}
