create table if not exists test_runs
(
    id                int       not null auto_increment,
    start_time        datetime  not null,
    end_time          datetime,

    primary key(id),
    index (start_time)
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

