module setup;

import serverd;
import utils;
import www;

import core.stdc.string;

import std.algorithm;
import std.conv;
import std.range;
import std.stdio;

extern(C)
{
    extern __gshared const(char)** environ;
}

bool split_keyvalue(string str, ref string key, ref string value, bool doDecode)
{
    auto r = findSplit(str, "=");
    if (r[0].empty)
        return false;

    if (doDecode)
    {
        char[] k = r[0].dup;
        http_decode(k);
        key = k.idup;

        char[] v = r[2].dup;
        http_decode(v);
        value = v.idup;
    }
    else
    {
        key = r[0];
        value = r[2];
    }

    return true;
}

void processEnv(ref string[string] hash)
{
    //writelog("begin processEnv");

    version (FASTCGI)
        const(char)** envp = cast(const(char)**)fcgi_envp;
    else
        const(char)** envp = environ;

    size_t i = 0;
    while (envp[i] != null)
    {
        string str = envp[i][0 .. strlen(envp[i])].idup;

        string key, value;
        if (split_keyvalue(str, key, value, false))
            hash[key] = value;
        else
            writelog("unable to parse env var: %s", str);

        ++i;
    }
    //writelog("end processEnv");
}

void processInput(const ref string[string] hash, ref string[string] userhash)
{
    string env_ptr = lookup(hash, "QUERY_STRING");
    //writelog("query_string = %s", env_ptr);
    parseFormArgs(userhash, env_ptr);

    string clstr = lookup(hash, "CONTENT_LENGTH");
    size_t cl = clstr.empty() ? 0 : to!size_t(clstr);
    if (cl)
    {
        char[] bodystr = new char[cl];
        version (FASTCGI)
            FCGX_GetStr(bodystr.ptr, cast(int)cl, fcgi_in);
        else
            stdin.rawRead(bodystr);

        string str = bodystr.idup;
        userhash["REQUEST_BODY"] = str;

        if (lookup(hash, "CONTENT_TYPE") == "application/x-www-form-urlencoded")
            parseFormArgs(userhash, str);
    }
}

void parseFormArgs(ref string[string] hash, string str)
{
    while (!str.empty)
    {
        auto r = findSplit(str, "&");
        if (r[0].empty)
        {
            writelog("hrm, empty token?");
            return;
        }

        string key, value;
        if (split_keyvalue(r[0], key, value, true))
            hash[key] = value;

        str = r[2];
    }
}

