
create table if not exists audit_entries
(
    id                int          not null auto_increment,
    change_date       datetime     not null,
    user_id           int          not null,
    description       varchar(256) not null,

    primary key(id),
    key(change_date)
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

create table if not exists github_pulls
(
    id                int          not null auto_increment,
    repo_id           int          not null,
    pull_id           int          not null,
    user_id           int          not null,
    create_date       datetime     not null,
    close_date        datetime,
    updated_at        datetime     not null,
    open              bool         not null,
    base_git_url      varchar(256) not null,
    base_ref          varchar(256) not null,
    base_sha          varchar(256) not null,
    head_git_url      varchar(256) not null,
    head_ref          varchar(256) not null,
    head_sha          varchar(256) not null,
    head_date         datetime     not null,
    auto_pull         int,
    has_priority      bool,

    primary key(id),
    key(open, id),
    key(repo_id, open),
    key(updated_at),
    unique key(repo_id, pull_id)
);

create table if not exists github_users
(
    id                int          not null,
    username          varchar(32)  not null,
    access_token      varchar(1024),
    cookie            char(24),
    csrf              char(12),
    pull_approver     int,

    primary key(id),
    key(cookie)
);

create table if not exists github_posts
(
    id                int          not null auto_increment,
    post_time         datetime     not null,
    body              text,

    primary key(id),
    key(post_time)
);

create table if not exists project_capabilities
(
    id                int          not null auto_increment,
    project_id        int          not null,
    capability_id     int          not null,

    primary key(id),
    key(project_id)
);

create table if not exists project_repositories
(
    id                int          not null auto_increment,
    project_id        int          not null,
    repository_id     int          not null,

    primary key(id),
    key(project_id),
    key(repository_id)
);

create table if not exists projects
(
    id                int          not null auto_increment,
    menu_label        varchar(128) not null,
    project_url       varchar(128) not null,
    project_type      int          not null,
    test_pulls        bool         not null,
    beta_only         bool         not null,
    enabled           bool         not null,
    allow_auto_merge  bool         not null,

    primary key(id),
    unique key(menu_label)
);

create table if not exists repositories
(
    id                int          not null auto_increment,
    owner             varchar(128) not null,
    name              varchar(128) not null,
    ref               varchar(128) not null,

    primary key(id)
);

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
    key(name,enabled),
    key(ipaddr,name)
);

create table if not exists build_host_capabilities
(
    id                int          not null auto_increment,
    host_id           int          not null,
    capability_id     int          not null,

    primary key(id),
    key(host_id)
);

create table if not exists capability_types
(
    id                int          not null auto_increment,
    name              varchar(30)  not null,

    primary key (id),
    key(name)
);

-- find a better table name
create table if not exists capabilities
(
    id                 int          not null auto_increment,
    capability_type_id int          not null,
    name               varchar(128) not null,

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
insert into test_types values ( 8, "html");
insert into test_types values (15, "build");
insert into test_types values (16, "test");
insert into test_types values (17, "merge");

create table if not exists test_runs
(
    id                int          not null auto_increment,
    host_id           int          not null,
    project_id        int          not null,
    platform          varchar(32)  not null,
    start_time        datetime     not null,
    end_time          datetime,
    rc                int,
    deleted           bool         not null,

    primary key(id),
    key(start_time),
    key(platform, start_time),
    key(deleted),
    key(host_id, start_time)
);

create table if not exists test_data
(
    id                int       not null auto_increment,
    test_run_id       int       not null,
    test_type_id      int       not null,
    repository_id     int       not null,
    start_time        datetime  not null,
    end_time          datetime,
    rc                tinyint,

    primary key(id),
    key(test_run_id)
);

create table if not exists pull_test_runs
(
    id                int          not null auto_increment,
    g_p_id            int          not null,
    host_id           int          not null,
    project_id        int          not null,
    platform          varchar(32)  not null,
    sha               varchar(256) not null,
    start_time        datetime     not null,
    end_time          datetime,
    rc                tinyint,
    deleted           bool         not null,

    primary key(id),
    key(deleted, g_p_id, platform),
    key(deleted, start_time),
    key(g_p_id, platform, start_time),
    key(host_id, start_time)
);

create table if not exists pull_test_data
(
    id                int          not null auto_increment,
    test_run_id       int          not null,
    test_type_id      int          not null,
    repository_id     int          not null,
    start_time        datetime     not null,
    end_time          datetime,
    rc                tinyint,

    primary key(id),
    key(test_run_id, test_type_id)
);

create table if not exists pull_suppressions
(
    id                int          not null auto_increment,
    g_p_id            int          not null,
    platform          varchar(32)  not null,

    primary key(id),
    key(g_p_id, platform)
);

