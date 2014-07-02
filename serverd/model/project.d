module model.project;

import mysql;
import utils;

import std.conv;

class Repository
{
    ulong id;
    ulong project_id;
    string name;
    string refname;

    this(ulong _id, ulong _pid, string _name, string _refname)
    {
        id         = _id;
        project_id = _pid;
        name       = _name;
        refname    = _refname;
    }
}

Repository[string] loadRepositories(ulong pid)
{
    sql_exec(text("select id, name, ref from repositories where project_id = ", pid));

    sqlrow[] rows = sql_rows();

    Repository[string] repositories;
    foreach (row; rows)
    {
        auto r = new Repository(to!ulong(row[0]), pid, row[1], row[2]);
        repositories[row[1]] = r;
    }

    return repositories;
}

class Project
{
    ulong  id;
    string name;
    bool   test_pulls;
    Repository[string] repositories;

    this(ulong _id, string _name, bool _test_pulls)
    {
        id = _id;
        name = _name;
        test_pulls = _test_pulls;
        repositories = loadRepositories(id);
    }
}

Project[ulong] loadProjects()
{
    sql_exec(text("select id, name, test_pulls from projects where enabled = true"));

    sqlrow[] rows = sql_rows();

    Project[ulong] projects;
    foreach (row; rows)
    {
        auto p = new Project(to!ulong(row[0]), row[1], (row[2] == "1"));
        projects[to!ulong(row[0])] = p;
    }

    return projects;
}

Project loadProject(string owner, string repo, string branch)
{
    sql_exec(text("select p.id, p.name, p.test_pulls from projects p where p.id in (select r.project_id from repositories r where r.name = \"", repo, "\" and r.ref = \"", branch, "\") and p.name = \"", owner, "\""));

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        writelog("  found more than one project matching %s/%s%s, skipping", owner, repo, branch);
        return null;
    }

    auto p = new Project(to!ulong(rows[0][0]), rows[0][1], (rows[0][2] == "1"));
    return p;
}
