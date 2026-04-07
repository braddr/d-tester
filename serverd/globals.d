module globals;

import config;
import github_apis;

import etc.c.curl;

Github github;

void init_globals(Config c, CURL* curl)
{
    github = new Github(c.github_token, c.github_clientid, c.github_clientsecret, curl);
}
