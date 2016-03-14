module model.user;

import log;
import mysql_client;
import utils;

import std.conv;

bool[string] loadUsers()
{
    Results r = mysql.query(text("select id, pull_approver from github_users"));

    bool[string] users;
    foreach(row; r) { bool trusted = row[1] != ""; users[row[0]] = trusted; }

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
        mysql.query(text("insert into github_users (id, username) values (", uidstr, ", '", sql_quote(uname), "')"));

        users[uidstr] = false;
        return false;
    }

    return *found;
}

