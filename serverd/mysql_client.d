module mysql_client;

import core.stdc.config : c_ulong;

// TODO: query with bind parameters
// TODO: consider alternatives to disconnect via delete

alias string[] sqlrow;

private
{

struct MYSQL;
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
    extern int mysql_real_query(MYSQL *mysql, const char *q, c_ulong len);
    extern MYSQL_ROW mysql_fetch_row(MYSQL_RES *result);
    extern c_ulong* mysql_fetch_lengths(MYSQL_RES *result);
    extern MYSQL_RES* mysql_store_result(MYSQL *mysql);
    extern MYSQL_RES* mysql_use_result(MYSQL *mysql);
    extern void	mysql_free_result(MYSQL_RES *result);

    extern c_ulong mysql_escape_string(char *to, const char *from, c_ulong from_length);
    extern uint mysql_field_count(MYSQL *mysql);
    extern uint mysql_num_fields(MYSQL_RES *res);
}

}

Mysql mysql;

alias PreQueryCallbackFunc = void delegate(string query);

class Mysql
{
public:
    PreQueryCallbackFunc callback;

private:
    MYSQL* m;

    string sql_cmd;
    Results r;

    this(MYSQL* _m)
    {
        m = _m;
    }

    ~this()
    {
        close_result_sets(this);
        mysql_close(m);
        m = null;
        mysql_server_end();
    }

}

private string wrap_mysql_error(MYSQL* m)
{
    import core.stdc.string : strlen;
    const(char)* msg = mysql_error(m);
    return msg[0 .. strlen(msg)].idup;
}

private void exiterr(MYSQL* m)
{
    throw new Exception("error: " ~ wrap_mysql_error(m));
}

private void exiterr(MYSQL* m, string sql_cmd)
{
    throw new Exception("cmd: " ~ sql_cmd ~ ", error: " ~ wrap_mysql_error(m));
}

Mysql connect(string host, int port, string user, string passwd, string db)
{
    import core.exception : OutOfMemoryError;
    import std.string : toStringz;

    MYSQL* mysql = mysql_init(null);
    if (!mysql)
        throw new OutOfMemoryError;

    scope(failure)
    {
        mysql_close(mysql);
        mysql = null;
    }

    ubyte opt = 1;
    if (mysql_options(mysql, mysql_option.MYSQL_OPT_RECONNECT, &opt) != 0)
        exiterr(mysql);

    if (!mysql_real_connect(mysql, toStringz(host), toStringz(user), toStringz(passwd), toStringz(db), port, null, CLIENT_REMEMBER_OPTIONS))
        exiterr(mysql);

    return new Mysql(mysql);
}

unittest
{
    import std.exception: collectException;

    Exception e = collectException(connect("127.0.0.1", 3000, "userid", "password", "database"));
    assert(e);
    assert(e.msg == "error: Can't connect to MySQL server on '127.0.0.1' (111)", e.msg);
    assert(!mysql);
}

unittest
{
    import std.exception: collectException;

    Exception e = collectException(connect("127.0.0.1", 3306, "userid", "password", "database"));
    assert(e);
    assert(e.msg == "error: Access denied for user 'userid'@'localhost' (using password: YES)", e.msg);
    assert(!mysql);
}

unittest
{
    bool called = false;
    void check(string query) { called = true; }

    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    scope(exit) { delete mysql; mysql = null; }

    mysql.callback = &check;

    assert(!called);
    mysql.query("select 1");
    assert(called);
}

void close_result_sets(Mysql m)
{
    assert(m);

    if (m.r)
    {
        delete m.r;
        m.r = null;
    }

    m.sql_cmd = null;
}

unittest
{
    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    scope(exit) { delete mysql; mysql = null; }

    Results r = mysql.query("select 1");

    assert(r);
    assert(r is mysql.r);
    assert(mysql.r); // left set from previous query
    assert(mysql.sql_cmd == "select 1");
    mysql.close_result_sets();
    assert(r); // though invalid as it's been deleted
    assert(!mysql.r);
    assert(!mysql.sql_cmd);
}

class Results
{
private:
    MYSQL_RES* res;
    MYSQL_ROW  row;
    sqlrow     row_values;
    uint       num_fields;

    this(MYSQL_RES* r)
    {
        res = r;

        if (!res) return;

        num_fields = mysql_num_fields(res);
        row_values.length = num_fields;
        popFront();
    }

    ~this()
    {
        while (row)
        {
           row = mysql_fetch_row(res);
        }
        mysql_free_result(res);
        res = null;
        row_values = null;
    }

public:
    bool empty()
    {
        return row == null;
    }

    sqlrow front()
    {
        return row_values;
    }

    void popFront()
    {
        row = mysql_fetch_row(res);
        if (!row)
        {
            mysql_free_result(res);
            res = null;
            row_values = null;
            return;
        }

        c_ulong[] lengths = mysql_fetch_lengths(res)[0 .. num_fields];

        foreach(i; 0 .. num_fields)
            row_values[i] = row[i] ? row[i][0 .. lengths[i]].idup : "";
    }
}

Results query(Mysql m, string sqlstr)
{
    if (m.callback) m.callback(sqlstr);

    m.close_result_sets();

    m.sql_cmd = sqlstr;

    if (mysql_real_query(m.m, sqlstr.ptr, sqlstr.length))
        exiterr(m.m, sqlstr);

    MYSQL_RES* res = mysql_use_result(m.m);
    if (!res && mysql_field_count(m.m))
        exiterr(m.m, sqlstr);

    m.r = new Results(res);
    return m.r;
}

unittest
{
    import std.exception: collectException;

    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    assert(mysql);
    scope(exit) { delete mysql; mysql = null; }

    Results r;
    assert(r is null);

    // checking before other tests to make sure connection is still usable afterwards
    Exception e = collectException(mysql.query("invalid sql"));
    assert(e.msg == "cmd: invalid sql, error: You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'invalid sql' at line 1");

    r = mysql.query("create temporary table foo ( id int not null )");
    assert(r !is null);
    assert(r.empty);

    r = mysql.query("select count(*) from foo");
    assert(r !is null);
    assert(!r.empty);
    assert(r.front);
    assert(r.front[0] == "0");

    r = mysql.query("insert into foo values (1)");
    assert(r !is null);
    assert(r.empty);

    r = mysql.query("select count(*) from foo");
    assert(r !is null);
    assert(!r.empty);
    assert(r.front);
    assert(r.front[0] == "1");

    r = mysql.query("insert into foo values (2)");
    r = mysql.query("insert into foo values (3)");
    r = mysql.query("insert into foo values (4)");

    r = mysql.query("select id from foo order by id");
    assert(r.row_values.length == 1);
    assert(r.front == ["1"]); r.popFront;
    assert(r.front == ["2"]); r.popFront;
    assert(r.front == ["3"]); r.popFront;
    assert(r.front == ["4"]); r.popFront;
    assert(r.empty);
    assert(r.front == null);
    assert(r.row_values.length == 0);
    assert(!r.res);
}

// quote a string; that is, replace double quotes with backslashed double-quotes
string sql_quote(string sqlstr)
{
    import core.memory;

    char* outstr = cast(char*)GC.malloc(sqlstr.length * 2 + 1);

    size_t len = mysql_escape_string(outstr, sqlstr.ptr, sqlstr.length);

    return cast(string)outstr[0 .. len];
}

unittest
{
    string quoted;

    quoted = sql_quote("unchanged");
    assert(quoted == "unchanged");

    quoted = sql_quote("\"changed\"");
    assert(quoted == "\\\"changed\\\"");
}

sqlrow getExactlyOneRow(Results r)
{
    sqlrow row;

    if (!r.empty)
    {
        row = r.front;
        r.popFront();
    }

    if (!row || !r.empty)
        return null;
    else
        return row;
}

unittest
{
    mysql = connect("localhost", 3306, "root", "password", "at-dev");
    scope(exit) { delete mysql; mysql = null; }

    mysql.query("create temporary table foo ( id int not null )");

    Results r;
    sqlrow row;

    r = mysql.query("select id from foo");
    row = getExactlyOneRow(r);
    assert(!row);

    mysql.query("insert into foo values (1)");

    r = mysql.query("select id from foo");
    row = getExactlyOneRow(r);
    assert(row);
    assert(row[0] == "1");

    mysql.query("insert into foo values (2)");

    r = mysql.query("select id from foo");
    row = getExactlyOneRow(r);
    assert(!row);
}
