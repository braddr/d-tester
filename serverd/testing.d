module testing;

import mysql_client;
import std.conv : text, to;

void truncateTestTables()
{
    foreach(table; [
        "audit_entries",
        "authorized_addresses",
        "build_host_capabilities", //
        "build_host_projects",
        "build_hosts", //
        "capabilities",
        "capability_types",
        "github_posts",
        "github_pulls",
        "github_users",
        "platforms",
        "project_capabilities",
        "project_repositories", //
        "projects", //
        "pull_suppressions",
        "pull_test_data",
        "pull_test_runs",
        "repositories", //
        "test_data",
        "test_runs",
        "test_types",
        ])
    {
        mysql.query(text("truncate table ", table));
    }
}

ulong createProject(string project)
{
    import std.stdio;

    string q = text(`insert into projects (id, menu_label, project_url, project_type, test_pulls, beta_only, enabled, allow_auto_merge) values (null, "`, project, `", "url", 0, true, false, false, false)`);
    mysql.query(q);
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createRepository(string owner, string name, string refname)
{
    mysql.query(text(`insert into repositories (id, owner, name, ref) values (null, "`, owner, `", "`, name, `", "`, refname, `")`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createPRMapping(ulong pid, ulong rid)
{
    mysql.query(text(`insert into project_repositories (id, project_id, repository_id) values (null, `, pid, `, `, rid, `)`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createBuildHost(string name, string ipaddr, string owner_email)
{
    mysql.query(text(`insert into build_hosts (id, name, ipaddr, owner_email, enabled) values (null, "`, name, `", "`, ipaddr, `", "`, owner_email, `", false)`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createCapabilityType(string name)
{
    mysql.query(text(`insert into capability_types (id, name) values (null, "`, name, `")`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createCapability(string name, ulong cap_type_id)
{
    mysql.query(text(`insert into capabilities (id, capability_type_id, name) values (null, `, cap_type_id, `, "`, name, `")`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createBuildHostCapability(ulong host_id, ulong cap_id)
{
    mysql.query(text(`insert into build_host_capabilities (id, host_id, capability_id) values (null, `, host_id, `, `, cap_id, `)`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createBuildHostProject(ulong host_id, ulong project_id)
{
    mysql.query(text(`insert into build_host_projects (id, project_id, host_id) values (null, `, project_id, `, `, host_id, `)`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

ulong createProjectCapability(ulong project_id, ulong cap_id)
{
    mysql.query(text(`insert into project_capabilities (id, project_id, capability_id) values (null, `, project_id, `, `, cap_id, `)`));
    Results r = mysql.query("select last_insert_id()");
    return r.front[0].to!ulong;
}

void enableProject(ulong pid)
{
    mysql.query(text(`update projects set enabled = true where id = `, pid));
}

void createTestDB()
{
    ulong pid = createProject("proj1");
    ulong rid1 = createRepository("owner", "repo1", "master");
    ulong rid2 = createRepository("owner", "repo2", "master");
    createPRMapping(pid, rid1);
    createPRMapping(pid, rid2);

    ulong captype1 = createCapabilityType("cap_type_1");
    ulong cap1 = createCapability("cap1", 1);

    ulong bh1 = createBuildHost("host1", "ipaddr", "email");
    createBuildHostCapability(bh1, cap1);
    createBuildHostProject(bh1, pid);
    createProjectCapability(pid, cap1);

    enableProject(pid);
}

