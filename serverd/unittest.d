module ut;

unittest
{
    import mysql_client;
    import testing;
    import std.stdio;

    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    scope(exit) { delete mysql; mysql = null; }

    truncateTestTables();
    createTestDB();
}

