module clientapi.sql;

import log;
import mysql_client;
import utils;

import std.conv;

bool isPullRunAborted(string runid)
{
    Results r = mysql.query(text("select deleted from pull_test_runs where id = ", runid));

    sqlrow row = getExactlyOneRow(r);
    if (!row)
    {
        writelog("  isPullRunAborted: should be exactly one row, run id = ", runid);
        return true;
    }

    return row[0] == "1";
}

