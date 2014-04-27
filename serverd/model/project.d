module model.project;

import mysql;

import std.conv;

class RepoBranch
{
    ulong   id;
    ulong   repo_id;
    string  name;

    this(ulong _id, ulong _rid, string _name)
    {
        id      = _id;
        repo_id = _rid;
        name    = _name;
    }
}

RepoBranch[string] loadRepoBranches(ulong repo_id)
{
    sql_exec(text("select id, name from repo_branches where repository_id = ", repo_id));

    sqlrow[] rows = sql_rows();

    RepoBranch[string] repo_branches;
    foreach (row; rows)
    {
        auto rb = new RepoBranch(to!ulong(row[0]), repo_id, row[1]);
        repo_branches[row[1]] = rb;
    }

    return repo_branches;
}

class Repository
{
    ulong id;
    ulong project_id;
    string name;
    RepoBranch branch;

    this(ulong _id, ulong _pid, string _name)
    {
        id         = _id;
        project_id = _pid;
        name       = _name;

        RepoBranch[string] branches = loadRepoBranches(id);
        assert(branches.length == 1);

        branch = branches[branches.keys[0]];
    }
}

Repository[string] loadRepositories(ulong pid)
{
    sql_exec(text("select id, name from repositories where project_id = ", pid));

    sqlrow[] rows = sql_rows();

    Repository[string] repositories;
    foreach (row; rows)
    {
        auto r = new Repository(to!ulong(row[0]), pid, row[1]);
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

