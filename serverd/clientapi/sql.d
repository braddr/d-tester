module clientapi.sql;

import mysql;
import std.conv;

bool isPullRunAborted(string runid)
{
    sql_exec(text("select deleted from pull_test_runs where id = ", runid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1) return true;

    if (rows[0][0] != "") return true;

    return false;
}

