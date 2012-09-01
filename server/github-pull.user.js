// ==UserScript==
// @name                Auto-tester single pull result on github
// @namespace           http://d.puremagic.com/test-results/
// @description         show specific pull auto tester results in github
// @include             https://github.com/D-Programming-Language/dmd/pull/*
// @include             https://github.com/D-Programming-Language/druntime/pull/*
// @include             https://github.com/D-Programming-Language/phobos/pull/*
// @include             https://github.com/organizations/D-Programming-Language/dmd/pull/*
// @include             https://github.com/organizations/D-Programming-Language/druntime/pull/*
// @include             https://github.com/organizations/D-Programming-Language/phobos/pull/*
// @version             1.1
// ==/UserScript==

function doLoad()
{
    var l = document.getElementById("apt_hdr");
    l.innerHTML = "loading...";

    GM_xmlhttpRequest({
        method:"GET",
        url:"http://d.puremagic.com/test-results/pull.json.ghtml?ref=" + document.location.href,
        onload:function(details) {
            var results = JSON.parse(details.responseText);

            var newhtml = "";
            var platforms = results.results;
            for (i = 0; i < platforms.length; i++)
            {
                var r = platforms[i];
                var s = "background: #ffffff;";
                var t;
                if (r.rc == "0" || r.rc == "") { s += "color:green;"; t="success"; } else { s = "color:red;"; t="failed"; }
                if (r.deleted == "1") { s += "opacity:0.4;"; }
                newhtml += "<a href=\"" + r.url + "\"><span style=\"" + s + "\">" + r.platform + "</span></a>\n";
            }

            var toreplace = document.getElementById("apt_listing");
            toreplace.innerHTML = newhtml;

            var l = document.getElementById("apt_hdr");
            l.href = results.historyURL;
            l.innerHTML = "Test Results";

            window.setTimeout(doLoad, 1000 * 60);
        }
    });
}

function addBox()
{
    var newhtml = "<div class=\"top-bar\"><h3><a id=\"apt_hdr\" href=\"http://d.puremagic.com/test-results/\">Test Results</a></h3></div>\n";

    newhtml += "<div id=\"apt_listing\">\n";
    newhtml += "</div>\n";
    newhtml += "<div class=\"bottom-bar\"></div>\n";

    var newdiv = document.createElement("div");
    newdiv.setAttribute("class", "repos");
    newdiv.setAttribute("id", "auto_tester_results");
    newdiv.innerHTML = newhtml;

    var loc = document.getElementById("discussion_bucket");
    loc = loc.children[0]; // descend to div class=discussion-sidebar
    loc.appendChild(newdiv);
}

addBox();
doLoad();

