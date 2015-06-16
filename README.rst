=====================================================
Backup Script for various databases:
=====================================================
Simple dump based backup with intelligent rotation and hooks.
Supports with battery included for mysql, mongodb, slapd & postgresql

.. contents::


Badges
------

.. image:: https://travis-ci.org/kiorky/db_smart_backup.png
    :target: http://travis-ci.org/kiorky/db_smart_backup

Supported databases
-------------------
    - Mongodb
    - PostGRESQL
    - Redis
    - Elasticsearch
    - MySQL
    - slapd (OpenLDAP)

Why another tool ?
--------------------
- There are great tools out there, but they are not fitting our needs and
  knowledge, and some of them did not have much tests, sorry.
- We just wanted a simple bash script, and using **dumps** (even in custom format
  for postgres) but just snapshots. So for example, postgreSQL PITR wal were not an
  option eliminating btw *barman* & *pg_rman*. All the other shell scripts including
  *automysqlbackup*/*autopostgresql* were not fitting exactly all the features we
  wanted and some were just too bash complicated for our little own brains.
- We wanted hooks to react on each backup stage, those hooks can be in another
  language, this is up to the user (very usefull for monitoring stuff).
- We want a generic script for any database, providing you add support on
  it, this consists just on writing a 'global' and a 'dump' function. For more
  information, read the sources luke.

- **WARNING**
  DO NOT PUT DATA UNDER THE DATADIR ELSE THAN WHAT DBSMARTBACKUP

So main features/requirements are:

    - Posix shell compliant (goal, but not that tested, the really tested one
      is bash in posix mode)
    - **PostgreSQL / MySQL support** for simple database and privileges
      dumps
    - Enougthly unit **tested**
    - XZ **compression** if available
    - Easily **extensible** to add another backup type / Generic backups methods
    - **Optional hooks** at each stage of the process addable via configuration
      (bash functions to uncomment)
    - **Keep a fixed number of dumps**, recent ones, old ones, and in a smart way.
      More on that later on this document. But for example the default is to keep
      the last 24 dumps, then 14 days (1 per day), 8 weeks (1 per week) and 12
      months (1 per month).


Installation
------------
::

    curl -OJLs https://raw.githubusercontent.com/kiorky/db_smart_backup/master/db_smart_backup.sh
    curl -OJLs https://raw.githubusercontent.com/kiorky/db_smart_backup/master/run_dbsmartbackups.sh
    chmod +x db_smart_backup.sh run_dbsmartbackups.sh

Generate a config file::

    ./db_smart_backup.sh --gen-config /path/to/config
    vim /path/to/config

Backup::

    ./db_smart_backup.sh /path/to/config



Backup all found databases in cron
-----------------------------------
We also bundle a script named **run_dbsmartbackups.sh** which search in /etc/dbsmartbackup for any database configuration:

    -  pg: /etc/dbsmartbackup/postgresql.conf
    -  mysql: /etc/dbsmartbackup/mysql.conf
    -  mongodb: /etc/dbsmartbackup/mongod.conf
    -  slapd /etc/dbsmartbackup/slapd.conf
    -  redis /etc/dbsmartbackup/redis.conf
    -  elasticsearch /etc/dbsmartbackup/elasticsearch.conf

be sure to have the scripts in your path::

    curl -OJLs https://raw.githubusercontent.com/kiorky/db_smart_backup/master/db_smart_backup.sh
    curl -OJLs https://raw.githubusercontent.com/kiorky/db_smart_backup/master/run_dbsmartbackups.sh
    chmod +x db_smart_backup.sh run_dbsmartbackups.sh
    mkdir /etc/dbsmartbackup

In /etc/dbsmartbackup, generate a config file (either: mysql.conf, mongod.conf, slapd.conf, postgresql.conf)::

    ./db_smart_backup.sh --gen-config /etc/dbsmartbackup/<db_type>.conf
    vim /path/to/configa

Testing the backup::

    ./db_smart_backup.sh /etc/dbsmartbackup/<db_type>.conf

Only execute the pruning policy::

    ./db_smart_backup.sh -p /etc/dbsmartbackup/<db_type>.conf

Test the cron that search for all possible things to backups::

    run_dbsmartbackups.sh

Add it to cron::

    0 0 * * * root /usr/bin/run_dbsmartbackups.sh --no-colors --quiet

Changelog
----------

Credits
-------------
  - by Mathieu Le Marec - Pasquet / kiorky@cryptelium.net
  - inspired by automysqlbackup/autopostgresqlbackup

The great things
-----------------
- Hooks support for each stage, those are bash functions acting as entry point
  for you to customize the backup upon what will happen during execution
- Smart idiot and simple retention policies
  Idea is to have a directory with all the sql for all days of the year
  and then hard links in subdirs to those files for easy access
  but also to triage what to rotate and what to prune::

    POSTGRESQL/
     DBNAME/
      dumps/
        DBNAME_20xx0101_01-01-01.sql.compressed  <- 01/01/20xx
        DBNAME_20xx0102_01-01-01.sql.compressed
        DBNAME_20xx0103_01-01-01.sql.compressed
        DBNAME_20xx0107_01-01-01.sql.compressed
        DBNAME_20xx0108_01-01-01.sql.compressed
        DBNAME_20xx3101_01-01-01.sql.compressed
        DBNAME_20xx0202_01-01-01.sql.compressed
      lastsnapshots/
        DBNAME_20xx0101_01-01-01.sql.compressed
        DBNAME_20xx0102_01-01-01.sql.compressed
        DBNAME_20xx0202_01-01-01.sql.compressed
      monthly/
        20xx_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0101.sql.compressed
        20xx_02_DBNAME_20xx0201.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0202.sql.compressed
        20xx_03_DBNAME_20xx0301.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0202.sql.compressed
      weekly/
        20xx_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0101.sql.compressed
        20xx_02_DBNAME_20xx0108.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0108.sql.compressed
      daily/
        20xx_01_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0101.sql.compressed
        20xx_02_01_DBNAME_20xx0108.sql.compressed -> /fullpath/DBNAME/dumps/DBNAME_20xx0108.sql.compressed

- Indeed:

    - First thing to do after after a backup is to look if a folder has more than the
      configured backups per each type of rotation (month, week, days, snapshots)
      and clean the oldest first.
    - Then we will just have to prune hardlinks where linked count is stricly inferior to 2,
      meaning that no one of the retention policies link this backup anymore. It
      is what we can call an orphan and is willing to be pruned.
    - Indeed, this means that **our backups are only in the dumps folder**.

- How do I see that other directories contains only hard links from dump directory?

    - You can see the hard links with ls in two ways. Using `ls -i` to get the
      real inode number in first col or `ls -l` to get the hard link counters.
::

    # ls -il /var/backup/postgresql/localhost/foobar/dumps/
    total 13332
    14044 -rw-r----- 5 root root 1237208 22 mars  16:19 foobar_2014-03-22_16-19-34.sql
    14049 -rw-r----- 2 root root 1237208 22 mars  16:25 foobar_2014-02-22_11-25-53.sql
    14054 -rw-r----- 2 root root 1237208 22 mars  16:27 foobar_2014-01-22_15-27-22.sql
    (...)
    # ls -il /var/backup/postgresql/localhost/foobar/weekly/
    total 1212
    14044 -rw-r----- 5 root root 1237208 22 mars  16:19 foobar_2014_12.sql
    ___^ inode       ^
    _________________^ here we see the hard link counter on this file



Backup types
-------------
PostgreSQL & MySQL specificities
++++++++++++++++++++++++++++++++++++++++
- We use traditionnal postgreSQL environment variables to set the host, port, password and user to set at backup
  time

- For PostgreSQL, you will certainly have to set only the BACKUP_TYPE to
  postgresql
- For MySQL you may have only to input the password

Add another backup type
++++++++++++++++++++++++
You need to first read the implementations for **mysql** and **postgresql**, those are
really simple, then follow the next guide (you do not need to make the script
call your functions, they are introspected):

    - Add a function **yourtype_set_connection_vars** to set any necessary extra global variable needed
      at the connect phase to your service
    - Add a function **yourtype_check_connectivity** that exit in error if the
      connexion is not possible and die in error else (use the **die_in_error**
      function)
    - Add a function **yourtype_set_vars** to set any necessary extra global variable needed
      to handle your service
    - Add a function **yourtype_get_all_databases** that return a space separated
      list of your database dbs.
    - Add a function **yourtype_dump** that will dump a database to a file, or a
      stub returning 0 as $? (call **/bin/true**) if it is not relevant for your
      backup type.
    - Add a function **yourtype_dumpall** even if one of them
      is just an empty stub, the script will then introspect itself to find
      them. Those functions must set the **LAST_BACKUP_STATUS** either to **""**
      on sucess or **"failure"** if the backup failed.
    - Add what is needed to load the configuration in the default configuration
      file in the **generate_configuration_file** method
    - Hack the defaults and variables in **set_vars**, the same way, if
      necessary.

Hooks
---------
- We provide a hook mechanism to let you configure custom code at each stage of
  the backup program. For this, you just need to uncomment the relevant part in
  your configuration file and implement whatever code you want, and even call
  another script in another language.

  - after the backup program starts: **pre_backup_hook**
  - after the global backup(failure): **postglobalbackup_hook**
  - after the global backup: **post_global_backup_failure_hook**
  - after specific db backup: **post_dbbackup_hook**
  - after specific db backup(failure): **post_db_backup_failure_hook**
  - after the backups rotation: **post_rotate_hook**
  - after the backups orphans cleanups: **post_cleanup_hook**
  - at backup end: **post_backup_hook**

- Think that you will have access in the environment of
  the hook to all the variables defined and exported by the script.
  You just have to check by reading the source what to test and how.

Options
-----------
- Read the script header to know what each option can do
- You'll need to tweak at least:

    - The database identifiers
    - The backup root location (/var/backup/<type> by default)
    - Which type of backup to do (maybe only postgresql)
    - The retention policy (there's a default one)


Backup Rotation..
------------------
We use hardlinks to achieve that but be aware that it may have filesystem limits:
    - number of databases backed up (a lot if every possible anyway on modern filesystems (2^32 hardlinks)
      and count something for the max like **366x2+57+12** for a year and a db.
    - and all subdirs should be on the same mounted point than the **dumps** directory.

Default policy
++++++++++++++
- We keep the **24** last done dumps
- We keep **14** days left
- We keep 1 backup per week for the last **8** weeks
- We keep 1 backup per month for the last **12** months

Please Note!!
--------------
I take no responsability for any data loss or corruption when using this script..
This script will not help in the event of a hard drive crash. If a
copy of the backup has not be stored offline or on another PC..
You should copy your backups offline regularly for best protection.
Happy backing up...
