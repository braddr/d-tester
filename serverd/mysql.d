module mysql;

import config;
import utils;

import core.memory;
import core.stdc.config;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.time;

import std.string;

struct MYSQL { ubyte[1272] junk; } // sizeof on 64 bit linux from the c header
struct MYSQL_RES;
alias char** MYSQL_ROW;

enum mysql_option
{
    MYSQL_OPT_CONNECT_TIMEOUT, MYSQL_OPT_COMPRESS, MYSQL_OPT_NAMED_PIPE,
    MYSQL_INIT_COMMAND, MYSQL_READ_DEFAULT_FILE, MYSQL_READ_DEFAULT_GROUP,
    MYSQL_SET_CHARSET_DIR, MYSQL_SET_CHARSET_NAME, MYSQL_OPT_LOCAL_INFILE,
    MYSQL_OPT_PROTOCOL, MYSQL_SHARED_MEMORY_BASE_NAME, MYSQL_OPT_READ_TIMEOUT,
    MYSQL_OPT_WRITE_TIMEOUT, MYSQL_OPT_USE_RESULT,
    MYSQL_OPT_USE_REMOTE_CONNECTION, MYSQL_OPT_USE_EMBEDDED_CONNECTION,
    MYSQL_OPT_GUESS_CONNECTION, MYSQL_SET_CLIENT_IP, MYSQL_SECURE_AUTH,
    MYSQL_REPORT_DATA_TRUNCATION, MYSQL_OPT_RECONNECT,
    MYSQL_OPT_SSL_VERIFY_SERVER_CERT
};

enum CLIENT_REMEMBER_OPTIONS = 1UL << 31;

extern(C)
{
    extern MYSQL* mysql_init(MYSQL *mysql);
    extern int mysql_options(MYSQL *mysql, mysql_option option, const void *arg);
    extern MYSQL* mysql_real_connect(MYSQL *mysql, const char *host, const char *user, const char *passwd, const char *db, uint port, const char *unix_socket, c_ulong clientflag);
    extern void mysql_close(MYSQL *sock);
    extern void mysql_server_end();

    extern const(char)* mysql_error(MYSQL *mysql);

    extern int mysql_query(MYSQL *mysql, const char *q);
    extern MYSQL_ROW mysql_fetch_row(MYSQL_RES *result);
    extern c_ulong* mysql_fetch_lengths(MYSQL_RES *result);
    extern MYSQL_RES* mysql_store_result(MYSQL *mysql);
    extern void	mysql_free_result(MYSQL_RES *result);

    extern c_ulong mysql_escape_string(char *to, const char *from, c_ulong from_length);
    extern uint mysql_field_count(MYSQL *mysql);
    extern uint mysql_num_fields(MYSQL_RES *res);
}

MYSQL mysql;

string sql_cmd = "";
MYSQL_RES *res = null;

private void exiterr()
{
    writelog("cmd:\t%s", sql_cmd);
    const(char)* m = mysql_error(&mysql);
    writelog("error:\t%s\n", m[0 .. strlen(m)]);
}

bool sql_init()
{
    version (FASTCGI)
        string servername = "localhost";
    else
        string servername = "slice-1.puremagic.com";

    writelog("connecting to mysql server: ", servername);
    mysql_init(&mysql);

    ubyte opt = 1;
    if (mysql_options(&mysql, mysql_option.MYSQL_OPT_RECONNECT, &opt) != 0)
    {
        exiterr();
        return false;
    }

    MYSQL* m = mysql_real_connect(&mysql, toStringz(c.db_host), toStringz(c.db_user), toStringz(c.db_passwd), toStringz(c.db_db), 3306, null, CLIENT_REMEMBER_OPTIONS);
    if (!m)
    {
        exiterr();
        return false;
    }

    return true;
}

char *sql_cleanup_after_request()
{
    if (res)
    {
        mysql_free_result(res);
        res = null;
    }

    sql_cmd = "";

    return null;
}

void sql_shutdown()
{
    mysql_close(&mysql);
    mysql_server_end();
}

bool sql_exec(string sqlstr)
{
    if (res)
    {
        mysql_free_result (res);
        res = null;
    }

    sql_cmd = sqlstr;

    if (mysql_query (&mysql, toStringz(sql_cmd)))
    {
        exiterr();
        return false;
    }

    res = mysql_store_result(&mysql);
    if (!res && mysql_field_count(&mysql))
    {
        exiterr();
        return false;
    }

    return true;
}

string[] sql_row()
{
    // if no query in progress
    if (!res) return null;

    MYSQL_ROW row = mysql_fetch_row(res);
    if (!row) return null;

    size_t nf = mysql_num_fields(res);

    c_ulong[] lengths = mysql_fetch_lengths(res)[0 .. nf];

    string[] fields;
    foreach(i; 0 .. nf)
    {
        c_ulong l = lengths[i];
        string  r = row[i] ? row[i][0 .. l].idup : "";

        fields ~= r;
    }

    return fields;
}

string[][] sql_rows()
{
    string[][] rows;
    string[] row;

    while ((row = sql_row()) != [])
    {
        rows ~= row;
    }

    return rows;
}

// quote a string; that is, replace double quotes with backslashed double-quotes
string sql_quote(string sqlstr)
{
    char* outstr = cast(char*)GC.malloc(sqlstr.length * 2 + 1);

    size_t len = mysql_escape_string(outstr, sqlstr.ptr, sqlstr.length);

    return cast(string)outstr[0 .. len];
}

