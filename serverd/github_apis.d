module github_apis;

import log;
import utils;

import etc.c.curl;
import std.conv;
import std.json;
import std.string;

class Github
{
private:
    string userid;
    string passwd;
    string clientid;
    string clientsecret;
    CURL*  curl;

private:

bool parseAndReturn(string responsepayload, ref JSONValue jv)
{
    try
    {
        jv = parseJSON(responsepayload);
    }
    catch (JSONException e)
    {
        writelog("  error parsing github json response: %s\n", e.toString);
        return false;
    }

    return true;
}

public:

this(string userid_, string passwd_, string clientid_, string clientsecret_, CURL* curl_)
{
    userid = userid_;
    passwd = passwd_;
    clientid = clientid_;
    clientsecret = clientsecret_;
    curl = curl_;
}

bool userIsCollaborator(string login, string owner, string repo, string access_token)
{
    string responsepayload;
    string[] responseheaders;

    string url = text("https://api.github.com/repos/", owner, "/", repo, "/collaborators/", login, "?access_token=", access_token);
    runCurlMethod(curl, CurlOption.httpget, responsepayload, responseheaders, url, null, null, null, null);

    long statusCode;
    curl_easy_getinfo(curl, CurlInfo.response_code, &statusCode);

    return statusCode == 204;
}

bool getAccessToken(string code, ref JSONValue jv)
{
    string[] headers;
    headers ~= "Accept: application/json";
    string url = text("https://github.com/login/oauth/access_token?client_id=", clientid, "&client_secret=", clientsecret, "&code=", code);
    string responsepayload;
    string responseheaders[];
    if (!runCurlPOST(curl, responsepayload, responseheaders, url, null, headers, null, null))
    {
        writelog("  error retrieving access_token, not logging in");
        return false;
    }
    writelog("  access_token api returned: %s", responsepayload);

    return parseAndReturn(responsepayload, jv);
}

bool getAccessTokenDetails(string access_token, ref JSONValue jv)
{
    string url = text("https://api.github.com/applications/", clientid, "/tokens/", access_token);
    string responsepayload;
    string responseheaders[];
    if (!runCurlGET(curl, responsepayload, responseheaders, url, clientid, clientsecret))
    {
        writelog("  error retrieving authorization, not logging in");
        return false;
    }
    writelog("  applications api returned: %s", responsepayload);

    return parseAndReturn(responsepayload, jv);
}

bool setSHAStatus(string owner, string repo, string sha, string desc, string status, string targeturl)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/statuses/", sha);
    string responsepayload;
    string[] responseheaders;

    string requestpayload = text(
        `{`
            `"description" : "`, desc, `",`
            `"state" : "`, status, `",`
            `"target_url" : "`, targeturl, `",`
            `"context" : "auto-tester"`
        `}`);

    writelog("  request body: %s", requestpayload);

    if (!runCurlPOST(curl, responsepayload, responseheaders, url, requestpayload, null, userid, passwd))
    {
        writelog("  failed to update github: %s", responsepayload);
        return false;
    }

    return true;
}

// TODO: add sha to catch the race condition of post-build commit changes
bool performPullMerge(string owner, string repo, string pullid, string access_token, string commit_message)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/pulls/", pullid, "/merge?access_token=", access_token);
    string responsepayload;
    string[] responseheaders;

    string requestbody = commit_message != "" ? text("{ \"commit_message\" : \"", commit_message, "\"}") : "{}";
    writelog("  calling github to merge %s/%s/%s", owner, repo, pullid);
    if (!runCurlPUT(curl, responsepayload, responseheaders, url, requestbody, null, null, null))
    {
        writelog("  github failed to merge pull request");
        return false;
    }

    return true;
}

bool getPull(string owner, string repo, string pullid, ref JSONValue jv)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/pulls/", pullid);
    string responsepayload;
    string[] responseheaders;

    if (!runCurlGET(curl, responsepayload, responseheaders, url, userid, passwd) || responsepayload.length == 0)
    {
        writelog("  failed to load pull from github");
        return false;
    }

    return parseAndReturn(responsepayload, jv);
}

string loadCommitDateFromGithub(string owner, string repo, string sha)
{
    JSONValue jv;
    if (!getCommit(owner, repo, sha, jv))
        return null;

    string s = jv.object["commit"].object["committer"].object["date"].str;

    return s;
}

bool getCommit(string owner, string repo, string sha, ref JSONValue jv)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/commits/", sha);
    string responsepayload;
    string[] responseheaders;

    if (!runCurlGET(curl, responsepayload, responseheaders, url, userid, passwd) || responsepayload.length == 0)
    {
        writelog("  failed to load commit from github");
        return false;
    }

    return parseAndReturn(responsepayload, jv);
}

string findNextLink(string[] headers)
{
    // Link: <https://api.github.com/repos/D-Programming-Language/dmd/pulls?page=2&per_page=100&state=open>; rel="next",
    //       <https://api.github.com/repos/D-Programming-Language/dmd/pulls?page=2&per_page=100&state=open>; rel="last"
    foreach (h; headers)
    {
        if (h.length >= 5 && toLower(h[0 .. 5]) == "link:")
        {
            string rest = h[5 .. $];
            strip(rest);

            string[] links = std.string.split(rest, ",");
            foreach (l; links)
            {
                string[] parts = std.string.split(l, ";");
                if (toLower(strip(parts[1])) == `rel="next"`)
                {
                    string toReturn = strip(parts[0])[1 .. $-1].idup;
                    //writelog("continuation link: %s", toReturn);
                    return toReturn;
                }
            }
        }
    }
    return null;
}

bool getPulls(string owner, string repo, ref JSONValue jv, ref string nextlink)
{
    string url = nextlink != "" ? nextlink : text("https://api.github.com/repos/", owner, "/", repo, "/pulls?state=open&per_page=100");
    string responsepayload;
    string[] responseheaders;

    if (!runCurlGET(curl, responsepayload, responseheaders, url, userid, passwd) || responsepayload.length == 0)
    {
        writelog("  failed to load pulls from github");
        return false;
    }

    nextlink = findNextLink(responseheaders);

    return parseAndReturn(responsepayload, jv);
}

bool getPullComments(string owner, string repo, string issuenum, ref JSONValue jv)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/issues/", issuenum, "/comments");
    string responsepayload;
    string[] responseheaders;

    if (!runCurlGET(curl, responsepayload, responseheaders, url, userid, passwd) || responsepayload.length == 0)
    {
        writelog("  failed to load comments from github");
        return false;
    }

    return parseAndReturn(responsepayload, jv);
}

bool addPullComment(string access_token, string owner, string repo, string issuenum, string comment, ref JSONValue jv)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/issues/", issuenum, "/comments?access_token=", access_token);
    string responsepayload;
    string[] responseheaders;

    string payload = text(`{ "body" : "`, comment, `" }`);
    if (!runCurlPOST(curl, responsepayload, responseheaders, url, payload, null, null, null))
    {
        writelog("  failed to add a comment to github(access_token)");
        return false;
    }

    return parseAndReturn(responsepayload, jv);
}

bool addPullComment(string owner, string repo, string issuenum, string comment, ref JSONValue jv)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/issues/", issuenum, "/comments");
    string responsepayload;
    string[] responseheaders;

    string payload = text(`{ "body" : "`, comment, `" }`);
    if (!runCurlPOST(curl, responsepayload, responseheaders, url, payload, null, userid, passwd))
    {
        writelog("  failed to add a comment to github(userid, passwd)");
        return false;
    }

    return parseAndReturn(responsepayload, jv);
}

}

