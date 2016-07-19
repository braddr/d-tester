// ==UserScript==
// @name                Auto-tester single pull result on github
// @namespace           https://auto-tester.puremagic.com/
// @description         show specific pull auto tester results in github
// @include             https://github.com/dlang/dmd/pull/*
// @include             https://github.com/dlang/druntime/pull/*
// @include             https://github.com/dlang/phobos/pull/*
// @include             https://github.com/D-Programming-Language/dmd/pull/*
// @include             https://github.com/D-Programming-Language/druntime/pull/*
// @include             https://github.com/D-Programming-Language/phobos/pull/*
// @include             https://github.com/organizations/D-Programming-Language/dmd/pull/*
// @include             https://github.com/organizations/D-Programming-Language/druntime/pull/*
// @include             https://github.com/organizations/D-Programming-Language/phobos/pull/*
// @version             1.5
// @grant               GM_xmlhttpRequest
// @downloadURL         https://auto-tester.puremagic.com/github-pull.user.js
// ==/UserScript==

function doLoad()
{
    var l = document.getElementById("apt_hdr");
    l.innerHTML = "loading...";

    GM_xmlhttpRequest({
        method:"GET",
        url:"https://auto-tester.puremagic.com/pull.json.ghtml?ref=" + document.location.href,
        onload:function(details) {
            var results = JSON.parse(details.responseText);

            var newhtml = "";
            if (results["auto-merge"])
                newhtml += "<span style=\"color:red\">Auto-merge on</span><br>";
            var platforms = results.results;
            for (i = 0; i < platforms.length; i++)
            {
                var r = platforms[i];
                var s = "background: #ffffff;";
                var t;
                if (r.rc == "0" || r.rc == "") { s += "color:green;"; t="success"; } else { s = "color:red;"; t="failed"; }
                if (r.deleted == "1") { s += "opacity:0.4;"; }
                newhtml += "<a href=\"" + r.url + "\"><span style=\"" + s + "\">" + r.platform + "</span></a><br>\n";
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
    var newhtml = "<div class=\"discussion-sidebar-item\"><h3><a id=\"apt_hdr\" href=\"https://auto-tester.puremagic.com/\">Test Results</a></h3>\n";

    newhtml += "<div id=\"apt_listing\">\n";
    newhtml += "</div>\n";

    var newdiv = document.createElement("div");
    newdiv.setAttribute("class", "discussion-sidebar-item");
    newdiv.setAttribute("id", "auto_tester_results");
    newdiv.innerHTML = newhtml;

    var loc = document.getElementById("discussion_bucket");
    loc = loc.children[0].children[0]; // descend to div class=discussion-sidebar
    loc.appendChild(newdiv);
}

addBox();
doLoad();

