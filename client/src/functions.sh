
function getdate
{
    date +%Y-%m-%d-%H:%M:%S
}

# start_run.ghtml  --> new run id
# start_test.ghtml?runid=##&type=##" --> new test id
# finish_test.ghtml?testid=7&rc=100  --> nothing

function callcurl
{
    curl "http://d.puremagic.com/test-results/add/$1.ghtml?$2"
}

