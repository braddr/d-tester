module model.project;

import log;
import mysql_client;
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
    Results r = mysql.query(text("select r.id, r.owner, r.name, r.ref from repositories r, project_repositories pr where pr.project_id = ", pid, " and pr.repository_id = r.id order by r.id"));

    Repository[] repositories;
    foreach (row; r)
    {
        auto repo = new Repository(to!ulong(row[0]), row[1], row[2], row[3]);
        repositories ~= repo;
    }

    return repositories;
}

Repository getOrCreateRepository(ulong project_id, string owner, string name, string refname)
{
    Results r = mysql.query(text("select id from repositories where owner = \"", owner, "\" and name = \"", name, "\" and ref = \"", refname, "\""));

    ulong id;

    if (r.empty)
    {
        mysql.query(text("insert into repositories (id, owner, name, ref) values (null, \"", owner, "\", \"", name, "\", \"", refname, "\")"));
        r = mysql.query("select last_insert_id()");
    }

    id = r.front[0].to!ulong;
    return new Repository(id, owner, name, refname);
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
    import std.array : array;

    Results r = mysql.query(text("select id, menu_label, project_type, test_pulls from projects where enabled = true"));
    sqlrow[] rows = r.array; // required since mysql doesn't support multiple in-flight queries

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
    Results r = mysql.query(text("select p.id, p.menu_label, p.project_type, p.test_pulls from projects p where p.id in (select pr.project_id from repositories r, project_repositories pr where pr.repository_id = r.id and r.owner = \"", owner, "\" and r.name = \"", repo, "\" and r.ref = \"", branch, "\")"));

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        writelog("  found more than one project matching %s/%s%s, skipping", owner, repo, branch);
        return null;
    }

    auto p = new Project(row);
    return p;
}

Project loadProjectById(ulong projectid)
{
    Results r = mysql.query(text("select id, menu_label, project_type, test_pulls from projects where enabled = true and id = ", projectid));

    sqlrow row = getExactlyOneRow(r);
    assert(row);

    auto p = new Project(row);

    return p;
}

Project[] loadProjectsByHostId(ulong hostid)
{
    Results r = mysql.query(text("select p.id, p.menu_label, p.project_type, p.test_pulls from projects p, build_hosts bh, build_host_projects bhp where p.id = bhp.project_id and bhp.host_id = bh.id and p.enabled = true and bh.id = ", hostid));

    Project[] projects;
    foreach (row; r)
    {
        auto p = new Project(row);
        projects ~= p;
    }

    return projects;
}

