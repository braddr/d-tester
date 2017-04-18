module model.project;

import mysql;
import utils;

import std.conv;

class Repository
{
    ulong id;
    string owner;
    string name;
    string refname;

    this(ulong _id, string _owner, string _name, string _refname)
    {
        id         = _id;
        owner      = _owner;
        name       = _name;
        refname    = _refname;
    }
}

Repository[] loadRepositoriesForProject(ulong pid)
{
    sql_exec(text("select r.id, r.owner, r.name, r.ref from repositories r, project_repositories pr where pr.project_id = ", pid, " and pr.repository_id = r.id order by r.id"));

    sqlrow[] rows = sql_rows();

    Repository[] repositories;
    foreach (row; rows)
    {
        auto r = new Repository(to!ulong(row[0]), row[1], row[2], row[3]);
        repositories ~= r;
    }

    return repositories;
}

class Project
{
    ulong  id;
    string menu_label;
    int    project_type;
    bool   test_pulls;
    Repository[] repositories;

    this(sqlrow row)
    {
        this(to!ulong(row[0]), row[1], to!int(row[2]), (row[3] == "1"));
    }

    this(ulong _id, string _label, int _type, bool _test_pulls)
    {
        id = _id;
        menu_label = _label;
        project_type = _type;
        test_pulls = _test_pulls;
        repositories = loadRepositoriesForProject(id);
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
    sql_exec(text("select id, menu_label, project_type, test_pulls from projects where enabled = true"));

    sqlrow[] rows = sql_rows();

    Project[ulong] projects;
    foreach (row; rows)
    {
        auto p = new Project(row);
        projects[to!ulong(row[0])] = p;
    }

    return projects;
}

Project loadProject(string owner, string repo, string branch)
{
    sql_exec(text("select p.id, p.menu_label, p.project_type, p.test_pulls from projects p where p.id in (select pr.project_id from repositories r, project_repositories pr where pr.repository_id = r.id and r.owner = \"", owner, "\" and r.name = \"", repo, "\" and r.ref = \"", branch, "\")"));

    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        writelog("  found more than one project matching %s/%s/%s, skipping", owner, repo, branch);
        return null;
    }

    auto p = new Project(rows[0]);
    return p;
}

Project loadProjectById(ulong projectid)
{
    sql_exec(text("select id, menu_label, project_type, test_pulls from projects where enabled = true and id = ", projectid));

    sqlrow[] rows = sql_rows();
    assert(rows.length == 1);

    auto p = new Project(rows[0]);

    return p;
}

Project[] loadProjectsByHostId(ulong hostid)
{
    sql_exec(text("select p.id, p.menu_label, p.project_type, p.test_pulls from projects p, build_hosts bh, build_host_projects bhp where p.id = bhp.project_id and bhp.host_id = bh.id and p.enabled = true and bh.id = ", hostid));
    sqlrow[] rows = sql_rows();

    Project[] projects;
    foreach (row; rows)
    {
        auto p = new Project(row);
        projects ~= p;
    }

    return projects;
}

Repository loadRepositoryById(ulong repoid)
{
    sql_exec(text("select r.id, r.owner, r.name, r.ref from repositories r where r.id = ", repoid));

    sqlrow[] rows = sql_rows();

    return new Repository(to!ulong(rows[0][0]), rows[0][1], rows[0][2], rows[0][3]);
}

