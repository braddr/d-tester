module clientapi.upload_master;

import mysql;
import serverd;
import utils;
import validate;

import std.conv;
import std.file;
import std.format;
import std.range;

bool validate_testidState(string testid, string clientver, ref string hostid, ref string testtypeid, ref string reponame, ref string runid, Appender!string outstr)
{
    string sqlstr;
    if (clientver == "5")
        sqlstr = text("select td.id, td.rc, td.test_run_id, td.test_type_id, tr.host_id, r.name from test_data td, test_runs tr, repositories r where r.id = td.repository_id and tr.id = td.test_run_id and td.id = ", testid);
    else
        sqlstr = text("select td.id, td.rc, td.test_run_id, td.test_type_id, tr.host_id from test_data td, test_runs tr where tr.id = td.test_run_id and td.id = ", testid);

    if (!sql_exec(sqlstr))
    {
        formattedWrite(outstr, "error executing sql, check error log\n");
        return false;
    }

    sqlrow row = sql_row();
    if (row == [])
    {
        formattedWrite(outstr, "error: no such testid: %s\n", testid);
        return false;
    }
    else
    {
        if (row[1] != "")
        {
            formattedWrite(outstr, "error: test already finished, may not upload log any more, testid: %s\n", testid);
            return false;
        }
        runid = row[2];
        testtypeid = row[3];
        hostid = row[4];
        if (clientver == "5")
            reponame = row[5];
    }

    return true;
}

bool validateInput(ref string raddr, ref string hostid, ref string testid, ref string runid, ref string testtypeid, ref string reponame, ref string clientver, Appender!string outstr)
{
    if (!validate_raddr(raddr, outstr))
        return false;
    if (!validate_id(testid, "testid", outstr))
        return false;
    if (!validate_clientver(clientver, outstr))
        return false;

    if (!validate_testidState(testid, clientver, hostid, testtypeid, reponame, runid, outstr))
        return false;

    return true;
}

string mapTTIDtoFilename(string testtypeid, string reponame)
{
    int num = to!int(testtypeid);

    switch (num)
    {
        case 1:  return "checkout.log";
        case 2:  return "dmd-build.log";
        case 3:  return "druntime-build.log";
        case 4:  return "phobos-build.log";
        case 5:  return "druntime-unittest.log";
        case 6:  return "phobos-unittest.log";
        case 7:  return "dmd-unittest.log";
        case 8:  return "phobos-html.log";
        case 9:  return "dmd-merge.log";
        case 10: return "druntime-merge.log";
        case 11: return "phobos-merge.log";
        case 12: return "GDC-build.log";
        case 13: return "GDC-unittest.log";
        case 14: return "GDC-merge.log";
        case 15: return reponame ~ "-build.log";
        case 16: return reponame ~ "-unittest.log";
        case 17: return reponame ~ "-merge.log";
        default: return "";
    }
}

bool storeResults(string runid, string testtypeid, string reponame, string contents, Appender!string outstr)
{
    string filename = mapTTIDtoFilename(testtypeid, reponame);
    if (filename == "")
    {
        formattedWrite(outstr, "error: unknown test_type_id: %s\n", testtypeid);
        return false;
    }

    string path = "/media/ephemeral0/auto-tester/test-results/" ~ runid ~ "/" ~ filename;
    try
    {
        write(path, contents);
    }
    catch(Exception e)
    {
        formattedWrite(outstr, "error: problem writing log to path: %s, error: %s\n", path, e.toString());
        return false;
    }

    return true;
}

void run(const ref string[string] hash, const ref string[string] userhash, Appender!string outstr)
{
    formattedWrite(outstr, "Content-type: text/plain\n\n");

    string raddr = lookup(hash, "REMOTE_ADDR");
    string testid = lookup(userhash, "testid");
    string clientver = lookup(userhash, "clientver");
    string logcontents = lookup(userhash, "REQUEST_BODY");
    string hostid;
    string runid;
    string testtypeid;
    string reponame;

    if (!validateInput(raddr, hostid, testid, runid, testtypeid, reponame, clientver, outstr))
        return;

    updateHostLastCheckin(hostid, clientver);

    if (!storeResults(runid, testtypeid, reponame, logcontents, outstr))
        return;
}
