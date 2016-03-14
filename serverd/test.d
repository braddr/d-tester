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

    Mysql m = connect("localhost", 3306, "root", "password", "at-dev");
    if (!m) return 1;

    Results r = m.query(args[1]);

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
