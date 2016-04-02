module test;

import mysql_client;

import std.stdio;

int main(string[] args)
{
    if (args.length != 2)
    {
        writefln("usage: %s \"sql query\"\n", args[0]);
        return 1;
    }

    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    if (!mysql) return 1;
    scope(exit) { delete mysql; mysql = null; }

    Results r = mysql.query(args[1]);

    if (!r)
    {
        writefln("error");
    }
    else
    {
        while (!r.empty)
        {
            sqlrow row = r.front;
            writefln("%s", row);

            r.popFront;
        }
    }

    return 0;
}
