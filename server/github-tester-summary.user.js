// ==UserScript==
// @name                Auto-tester results on github
// @namespace           http://d.puremagic.com/test-results/
// @description         add auto tester results to github
// @include             https://github.com/
// @include             https://github.com/organizations/D-Programming-Language
// @version             1.2
// ==/UserScript==

function showResults(results)
{
    var newhtml = "";

    for (i = 0; i < results.length; i++)
    {
        var r = results[i];
        var c;
        if (r.state == "success") { c = "green"; } else if (r.state == "fail") { c = "red"; } else { c = "black"; }
        newhtml += "<li class=\"public source\" style=\"background: #ffffff;\"><a href=\"" + r.historyURL + "\">" +
            "<span style=\"color: " + c + ";\">" + r.state + "</span> - " + r.displayName +
            "</a></li>\n";
    }

    var toreplace = document.getElementById("at_listing");
    toreplace.innerHTML = newhtml;

    var l = document.getElementById("at_hdr");
    l.innerHTML = "Auto-Tester Results";

    window.setTimeout(doLoad, 1000 * 60);
}

function doLoad()
{
    var l = document.getElementById("at_hdr");
    l.innerHTML = "Auto-Tester Results - loading...";

    GM_xmlhttpRequest({
        method:"GET",
        url:"http://d.puremagic.com/test-results/summary.json.ghtml",
        onload:function(details) { var results = eval(details.responseText); showResults(results); }
    });
}

function addBox()
{
    var newhtml = "<div class=\"top-bar\"><h2><a id=\"at_hdr\" href=\"http://d.puremagic.com/test-results/\">Auto-Tester Results</a></h2></div>\n";

    newhtml += "<ul id=\"at_listing\" class=\"repo_list\">\n";
    newhtml += "</ul>\n";
    newhtml += "<div class=\"bottom-bar\"></div>\n";

    var newdiv = document.createElement("div");
    newdiv.setAttribute("class", "repos");
    newdiv.setAttribute("id", "auto_tester_results");
    newdiv.innerHTML = newhtml;

    var loc = document.getElementById("org_your_repos");
    if (loc)
        loc.parentNode.insertBefore(newdiv, null);
    else
    {
        loc = document.getElementById("watched_repos");
        if (loc)
            loc.parentNode.insertBefore(newdiv, null);
    }
}

addBox();
doLoad();

