=====================================================
Backup Script for various databases
=====================================================

.. contents::



.. image:: https://secure.travis-ci.org/kiorky/db_smart_backup.png
    :target: http://travis-ci.org/kiorky/db_smart_backup

Supported databases
-------------------
    - PostGRESQL
    - MySQL (Work in progress)

Why another tool ?
--------------------
- There are great tools out there, but they are not fitting to our needs and
  knwoledge, and some of them did not have much tests, sorry.
- We just wanted a simple bash script, and using dumps (even in custom format
  for postgres) but just snapshots. So for example, postres PITR wal were not an
  option eliminating btw barman & pg_rman. All the other shell scripts including
  automysqlbackup/autopostgresql were not fitting exactly all the feature we
  wanted and some were just too bash complicated for our little own brains.
- We wanted hooks to react on each backup stage, those hooks can be in another
  language, this is up to the user.
- We want a generic script for any database, providing that you add support on
  it, this consists just on writing a 'global' and a 'dump' function. For more
  information, read the sources luke.


So main features are:

    - Posix shell compliant (goal, but not that tested, the really tested one
      is bash in posix mode)
    - Postgresql / Mysql support for simple database and privileges
      dumps
    - Extensible
    - Generic backups methods
    - Optional hooks at each stage of the process

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
        DBNAME_20xx0101.sql.compressed  <- 01/01/20xx
        DBNAME_20xx0102.sql.compressed
        DBNAME_20xx0103.sql.compressed
        DBNAME_20xx0107.sql.compressed
        DBNAME_20xx0108.sql.compressed
        DBNAME_20xx3101.sql.compressed
        DBNAME_20xx0202.sql.compressed
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

    - First thing to do after after a backup is to look if a folder has more than the configured backups and clean the oldest first.
    - Then we will just have to prune hardlinks where linked count is stricly inferior to 2
    - Indeed, this means that our backups are only in the dumps folder.

PostGRESQL specificities
-------------------------
- We use environment variables to set the host, port, password and user to set at backup
  time

Hooks
---------
- We provide ways to run a script

  - after the backup program starts: **pre_backup_hook**
  - after the global backup: **post_global_backup_failure_hook**
  - after the global backup(failure): **postglobalbackup_hook**
  - after specific db backup: **post_dbbackup_hook**
  - after specific db backup(failure): **post_db_backup_failure_hook**
  - after the backups rotation: **post_rotate_hook**
  - after the backups orphans cleanups: **post_cleanup_hook**
  - at backup end: **post_backup_hook**
  - when the mail is sent: **post_mail_hook**

- Think that you will have in the environment one of
  all the variables defined and exported by the script.

Options
-----------
- Read the script header to know what can do each option
- You ll need to tweak at least:

    - the database identifiers
    - the backup root location
    - what to backup
    - which types to do (maybe only postgresl)


Backup Rotation..
------------------
We use hardlinks, be aware that it may have filesystem limits:
    - number of databases backed up (a lot if every possible anymay on modern filesystems (2^32 hardlinks)
      and count something for the max like **366x2+57+12** for a year and a db.
    - and all subdirs should be on the same mounted point where the backup dir

Please Note!!
--------------
I take no responsability for any data loss or corruption when using this script..
This script will not help in the event of a hard drive crash. If a
copy of the backup has not be stored offline or on another PC..
You should copy your backups offline regularly for best protection.
Happy backing up...
