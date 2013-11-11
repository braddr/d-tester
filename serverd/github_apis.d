module github_apis;

import config;
import serverd;
import utils;

import etc.c.curl;
import std.conv;
import std.json;

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
    string url = text("https://github.com/login/oauth/access_token?client_id=", c.github_clientid, "&client_secret=", c.github_clientsecret, "&code=", code);
    string responsepayload;
    string responseheaders[];
    if (!runCurlPOST(curl, responsepayload, responseheaders, url, null, headers, null, null))
    {
        writelog("  error retrieving access_token, not logging in");
        return false;
    }
    writelog("  access_token api returned: %s", responsepayload);

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

bool getAccessTokenDetails(string access_token, ref JSONValue jv)
{
    string url = text("https://api.github.com/applications/", c.github_clientid, "/tokens/", access_token);
    string responsepayload;
    string responseheaders[];
    if (!runCurlGET(curl, responsepayload, responseheaders, url, c.github_clientid, c.github_clientsecret))
    {
        writelog("  error retrieving authorization, not logging in");
        return false;
    }
    writelog("  applications api returned: %s", responsepayload);

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

bool setSHAStatus(string owner, string repo, string sha, string desc, string status, string targeturl)
{
    string url = text("https://api.github.com/repos/", owner, "/", repo, "/statuses/", sha);
    string payload;
    string[] headers;

    string requestpayload = text(
        `{`
            `"description" : "`, desc, `",`
            `"state" : "`, status, `",`
            `"target_url" : "`, targeturl, `"`
        `}`);

    writelog("  request body: %s", requestpayload);

    if (!runCurlPOST(curl, payload, headers, url, requestpayload, null, c.github_user, c.github_passwd))
    {
        writelog("  failed to update github");
        return false;
    }

    return true;
}

