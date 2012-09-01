create table if not exists test_runs
(
    id                int       not null auto_increment,
    reporter_ip       varchar(15) not null,
    platform          varchar(32) not null,
    start_time        datetime  not null,
    end_time          datetime,

    primary key(id),
    index (start_time),
    index (platform, start_time)
);

drop table test_types;

create table test_types
(
    id                int,
    name              varchar(128),

    primary key(id)
);

truncate table test_types;

insert into test_types values (1, "checkout");
insert into test_types values (2, "build dmd");
insert into test_types values (3, "build druntime");
insert into test_types values (4, "build phobos");
insert into test_types values (5, "test dmd");
insert into test_types values (6, "test druntime");
insert into test_types values (7, "test phobos");

create table if not exists test_data
(
    id                int       not null auto_increment,
    test_run_id       int       not null,
    test_type_id      int       not null,

    start_time        datetime  not null,
    end_time          datetime,

    rc                tinyint   not null,
    log               blob,

    primary key(id)
);

create table if not exists projects
(
    id                int       not null auto_increment,
    name              varchar(128),

    primary key(id)
);

truncate table projects;

insert into projects values (1, "dmd");
insert into projects values (2, "druntime");
insert into projects values (3, "phobos");

create table if not exists platforms
(
    id                int       not null auto_increment,
    name              varchar(128),

    primary key(id)
);

truncate table platforms;

insert into platforms values (1, "FreeBSD_32");
insert into platforms values (2, "FreeBSD_64");
insert into platforms values (3, "Linux_32");
insert into platforms values (4, "Linux_64_64");
insert into platforms values (5, "Linux_32_64");
insert into platforms values (6, "Linux_64_32");
insert into platforms values (7, "Darwin_32");
insert into platforms values (8, "Darwin_64_64");
insert into platforms values (9, "Darwin_32_64");
insert into platforms values (10, "Darwin_64_32");
insert into platforms values (11, "Win_32");

create table if not exists github_pulls_new
(
    id                int       not null auto_increment,
    project_id        int       not null,
    pull_id           int       not null,
    created_user_id   int       not null,
    created_at        datetime  not null,
    merged_user_id    int       not null,
    merged_at         datetime  not null,
    updated_user_id   int       not null,
    updated_at        datetime  not null,
    open              bool      not null,
    base_git_url      varchar(256) not null,
    base_ref          varchar(256) not null,
    base_sha          varchar(256) not null,
    head_git_url      varchar(256) not null,
    head_ref          varchar(256) not null,
    head_sha          varchar(256) not null,

    primary key(id),
    key(open, id)
);

create table if not exists github_users
(
    id                int       not null,
    username          varchar(32) not null,
    trusted           bool,

    primary key(id)
);

create table if not exists pull_test_runs
(
    id                int         not null auto_increment,
    g_p_id            int         not null,

    pull_id           int         not null,
    reporter_ip       varchar(15) not null,
    platform          varchar(32) not null,
    sha               varchar(256) not null,
    start_time        datetime    not null,
    end_time          datetime,
    rc                tinyint,
    deleted           bool        not null,

    primary key(id),
    key (deleted, g_p_id, platform),
    key (deleted, start_time),
    key (g_p_id, platform, start_time)
);

create table if not exists pull_test_data
(
    id                int       not null auto_increment,
    test_run_id       int       not null,
    test_type_id      int       not null,

    start_time        datetime  not null,
    end_time          datetime,

    rc                tinyint   not null,
    log               blob,

    primary key(id)
);

