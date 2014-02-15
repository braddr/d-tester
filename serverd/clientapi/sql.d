module clientapi.sql;

import mysql;
import utils;

import std.conv;

bool isPullRunAborted(string runid)
{
    sql_exec(text("select deleted from pull_test_runs where id = ", runid));
    sqlrow[] rows = sql_rows();

    if (rows.length != 1)
    {
        writelog("  isPullRunAborted: rows.length = %s", rows.length);
        return true;
    }

    return rows[0][0] == "1";
}

