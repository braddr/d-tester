select bh.id,
           bh.name,
           bh.ipaddr,
           bh.last_heard_from,
           timediff(now(), last_heard_from) time_since,
           ip.run_id,
           ip.platform,
           concat(ip.r_name, '/', ip.ghp_pull_id) as pull,
           ip.p_name,
           bh.clientver
      from build_hosts bh left join
           (
               select ptr.id as run_id,
                      bh.ipaddr,
                      bh.name as bh_name,
                      platform,
                      r.name as r_name,
                      ghp.pull_id as ghp_pull_id,
                      p.menu_label as p_name,
                      p.id as p_id
                 from pull_test_runs ptr,
                      github_pulls ghp,
                      projects p,
                      repositories r,
                      repo_branches rb,
                      build_hosts bh
                where ghp.id = ptr.g_p_id and
                      p.id = r.project_id and
                      r.id = rb.repository_id and
                      rb.id = ghp.r_b_id and
                      bh.id = ptr.host_id and
                      end_time is null and
                      deleted = false
                union
               select tr.id,
                      b.ipaddr,
                      b.name,
                      tr.platform,
                      "branch",
                      -1,
                      p.menu_label,
                      p.id
                 from test_runs tr, build_hosts b, projects p
                where end_time is null and
                      deleted = false and
                      tr.host_id = b.id and
                      p.id = tr.project_id
           ) as ip on (ip.ipaddr = bh.ipaddr and ip.bh_name = bh.name)
     where bh.enabled = true and
           timediff(now(), last_heard_from) > "00:15:00"
     order by bh.name

