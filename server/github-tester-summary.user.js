// ==UserScript==
// @name                Auto-tester results on github
// @namespace           http://auto-tester.puremagic.com/
// @description         add auto tester results to github
// @include             https://github.com/
// @include             https://github.com/D-Programming-Language
// @version             1.4
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
        url:"http://auto-tester.puremagic.com/summary.json.ghtml",
        onload:function(details) { var results = JSON.parse(details.responseText); showResults(results); }
    });
}

function addBox()
{
    var newhtml = "<h3 class=\"org-module-title\"><a id=\"at_hdr\" class=\"org-module-link\" href=\"http://auto-tester.puremagic.com/\">Auto-Tester Results</a></h3>\n";

    newhtml += "<ul id=\"at_listing\" class=\"org-teams-list\">\n";
    newhtml += "</ul>\n";

    var newdiv = document.createElement("div");
    newdiv.setAttribute("class", "org-module simple-box");
    newdiv.setAttribute("id", "auto_tester_results");
    newdiv.innerHTML = newhtml;

    var sb = document.getElementsByClassName("org-sidebar")[0];
    sb.insertBefore(newdiv, sb.firstChild);
}

addBox();
doLoad();

