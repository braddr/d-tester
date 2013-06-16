
create table if not exists audit_entries
(
    id                int          not null auto_increment,
    change_date       datetime     not null,
    user_id           int          not null,
    description       varchar(256) not null,

    primary key(id),
    key (change_date)
);

create table if not exists authorized_addresses
(
    id                int          not null auto_increment,
    ipaddr            varchar(128) not null,
    enabled           bool         not null,
    description       varchar(128) not null,

    primary key(id),
    key(ipaddr)
);

-- note: only need addresses that are NOT tester clients
insert into authorized_addresses values (null, "173.45.241.208",  true, "slice-1.puremagic.com");
insert into authorized_addresses values (null, "108.171.174.178", true, "github");
insert into authorized_addresses values (null, "173.203.140.",    true, "github");
insert into authorized_addresses values (null, "173.45.241.",     true, "github");
insert into authorized_addresses values (null, "207.97.227.",     true, "github");
insert into authorized_addresses values (null, "50.57.128.",      true, "github");
insert into authorized_addresses values (null, "192.168.10.",     true, "home network");
insert into authorized_addresses values (null, "207.171.191.60",  true, "amazon sea firewall");
insert into authorized_addresses values (null, "54.240.196.185",  true, "amazon sea firewall");

create table if not exists github_pulls
(
    id                int          not null auto_increment,
    r_b_id            int          not null,
    pull_id           int          not null,
    user_id           int          not null,
    updated_at        datetime     not null,
    open              bool         not null,
    base_git_url      varchar(256) not null,
    base_ref          varchar(256) not null,
    base_sha          varchar(256) not null,
    head_git_url      varchar(256) not null,
    head_ref          varchar(256) not null,
    head_sha          varchar(256) not null,
    head_date         datetime,

    primary key(id),
    key(open, id),
    key(project_id, open),
    key(updated_at),
    unique key (repo_id, pull_id)
);

create table if not exists github_users
(
    id                int          not null,
    username          varchar(32)  not null,
    trusted           bool,

    primary key(id)
);

create table if not exists github_posts
(
    id                int          not null auto_increment,
    post_time         datetime     not null,
    body              text,

    primary key(id),
    key (post_time)
);

create table if not exists projects
(
    id                int          not null auto_increment,
    menu_label        varchar(128) not null,
    name              varchar(128) not null,
    project_url       varchar(128) not null,
    test_pulls        bool         not null,
    beta_only         bool         not null,
    enabled           bool         not null,

    primary key(id),
    index (name)
);

truncate table projects;

insert into projects values (1, "D2 master",   "D-Programming-Language", "http://dlang.org",       1, 0);
insert into projects values (2, "GDC",         "D-Programming-GDC",      "http://gdcproject.org/", 1, 1);
insert into projects values (3, "LDC",         "ldc-developers",         "",                       1, 1);
insert into projects values (4, "D2 staging",  "D-Programming-Language", "http://dlang.org",       1, 0);
insert into projects values (5, "D2 2.061",    "D-Programming-Language", "http://dlang.org",       1, 0);


create table if not exists repositories
(
    id                int          not null auto_increment,
    project_id        int          not null,
    name              varchar(128) not null,

    primary key (id),
    index (project_id)
);

truncate table repositories;

insert into repositories values (1, 1, "dmd");
insert into repositories values (2, 1, "druntime");
insert into repositories values (3, 1, "phobos");

create table if not exists repo_branches
(
    id                int          not null auto_increment,
    repository_id     int          not null,
    name              varchar(128) not null,

    primary key(id),
    index (repository_id)
);

insert into repo_branches values (1, 1, "master");
insert into repo_branches values (2, 2, "master");
insert into repo_branches values (3, 3, "master");

create table if not exists platforms
(
    id                int          not null auto_increment,
    name              varchar(128) not null,
    cbits             int          not null,
    obits             int          not null,
    arch              varchar(128) not null,
    os                varchar(128) not null,

    primary key(id)
);

truncate table platforms;

insert into platforms values (1,  "FreeBSD_32",   32, 32, "x86", "FreeBSD");
insert into platforms values (2,  "FreeBSD_64",   64, 64, "x86", "FreeBSD");
insert into platforms values (3,  "Linux_32",     32, 32, "x86", "Linux");
insert into platforms values (4,  "Linux_64_64",  64, 64, "x86", "Linux");
insert into platforms values (5,  "Linux_32_64",  32, 64, "x86", "Linux");
insert into platforms values (6,  "Linux_64_32",  64, 32, "x86", "Linux");
insert into platforms values (7,  "Darwin_32",    32, 32, "x86", "Darwin");
insert into platforms values (8,  "Darwin_64_64", 64, 64, "x86", "Darwin");
insert into platforms values (9,  "Darwin_32_64", 32, 64, "x86", "Darwin");
insert into platforms values (10, "Darwin_64_32", 64, 32, "x86", "Darwin");
insert into platforms values (11, "Win_32",       32, 32, "x86", "Win");
insert into platforms values (12, "Win_64_64",    64, 64, "x86", "Win");
insert into platforms values (13, "Win_32_64",    32, 64, "x86", "Win");
insert into platforms values (14, "Win_64_32",    64, 32, "x86", "Win");

create table if not exists build_hosts
(
    id                int          not null auto_increment,
    name              varchar(128) not null,
    ipaddr            varchar(128) not null,
    owner_email       varchar(128) not null,
    enabled           bool         not null,
    last_heard_from   datetime,
    clientver         int,

    primary key(id),
    key(ipaddr)
);

create table if not exists build_host_capabilities
(
    id                int          not null auto_increment,
    build_host_id     int          not null,
    capability_id     int          not null,

    primary key(id)
);

-- find a better table name
create table if not exists capabilities
(
    id                int          not null auto_increment,
    name              varchar(128) not null,

    primary key(id)
);

create table if not exists build_host_projects
(
    id                int          not null auto_increment,
    project_id        int          not null,
    host_id           int          not null,

    primary key(host_id, project_id),
    key(id)
);

create table if not exists test_types
(
    id                int          not null auto_increment,
    name              varchar(128) not null,

    primary key(id)
);

truncate table test_types;

insert into test_types values ( 1, "checkout");
insert into test_types values ( 2, "build dmd");
insert into test_types values ( 3, "build druntime");
insert into test_types values ( 4, "build phobos");
insert into test_types values ( 5, "test dmd");
insert into test_types values ( 6, "test druntime");
insert into test_types values ( 7, "test phobos");
insert into test_types values ( 8, "html phobos");
insert into test_types values ( 9, "merge dmd");
insert into test_types values (10, "merge druntime");
insert into test_types values (11, "merge phobos");


create table if not exists test_runs
(
    id                int          not null auto_increment,
    host_id           int          not null,
    platform          varchar(32)  not null,
    project_id        int          not null,
    start_time        datetime     not null,
    end_time          datetime,
    rc                int,
    deleted           bool         not null,

    primary key(id),
    index (start_time),
    index (platform, start_time)
);


create table if not exists test_data
(
    id                int       not null auto_increment,
    test_run_id       int       not null,
    test_type_id      int       not null,
    start_time        datetime  not null,
    end_time          datetime,
    rc                tinyint   not null,

    primary key(id),
    index (test_run_id)
);


create table if not exists pull_test_runs
(
    id                int          not null auto_increment,
    g_p_id            int          not null,

    host_id           int          not null,
    platform          varchar(32)  not null,
    sha               varchar(256) not null,
    start_time        datetime     not null,
    end_time          datetime,
    rc                tinyint,
    deleted           bool         not null,

    primary key(id),
    key (deleted, g_p_id, platform),
    key (deleted, start_time),
    key (g_p_id, platform, start_time),
);

create table if not exists pull_test_data
(
    id                int       not null auto_increment,
    test_run_id       int       not null,
    test_type_id      int       not null,
    start_time        datetime  not null,
    end_time          datetime,
    rc                tinyint   not null,

    primary key(id),
    key (test_run_id, test_type_id)
);


