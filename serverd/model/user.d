module model.user;

import mysql;
import utils;

import std.conv;

bool[string] loadUsers()
{
    sql_exec(text("select id, pull_approver from github_users"));

    sqlrow[] rows = sql_rows();

    bool[string] users;
    foreach(row; rows) { bool trusted = row[1] != ""; users[row[0]] = trusted; }

    return users;
}

bool checkUser(ulong uid, string uname)
{
    static bool[string] users;

    if (users.length == 0) users = loadUsers();

    string uidstr = sql_quote(to!string(uid));

    auto found = uidstr in users;
    if (!found)
    {
        writelog("  creating user %s(%s)", uname, uidstr);
        sql_exec(text("insert into github_users (id, username) values (", uidstr, ", '", sql_quote(uname), "')"));

        users[uidstr] = false;
        return false;
    }

    return *found;
}

