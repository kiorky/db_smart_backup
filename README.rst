=====================================================
Backup Script for various databases
=====================================================

.. contents::

Supported databases
-------------------
    - PostGRESQL
    - MySQL (Work in progress)

Changelog
----------

Credits
-------------
  - by Mathieu Le Marec - Pasquet / kiorky@cryptelium.net
  - inspired by automysqlbackup/autopostgresqlbackup

The whole thing
-----------------
Idea is to have a directory with all the sql for all days of the year
and then hard links in subdirs to those files for easy access
but also to triage what to rotate and what to prune::

    POSTGRESQL/
     DBNAME/
      dumps/
        20xx_001_DBNAME_20xx0101.sql.compressed  <- 01/01/20xx
        20xx_002_DBNAME_20xx0102.sql.compressed
        20xx_003_DBNAME_20xx0103.sql.compressed
        20xx_007_DBNAME_20xx0107.sql.compressed
        20xx_031_DBNAME_20xx3101.sql.compressed
        20xx_032_DBNAME_20xx0202.sql.compressed
      monthly/
        20xx_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/20xx_001_DBNAME_20xx0101.sql.compressed
        20xx_02_DBNAME_20xx0201.sql.compressed -> /fullpath/DBNAME/dumps/20xx_032_DBNAME_20xx0202.sql.compressed
        20xx_03_DBNAME_20xx0301.sql.compressed -> /fullpath/DBNAME/dumps/20xx_063_DBNAME_20xx0202.sql.compressed
      weekly/
        20xx_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/20xx_001_DBNAME_20xx0101.sql.compressed
        20xx_02_DBNAME_20xx0108.sql.compressed -> /fullpath/DBNAME/dumps/20xx_008_DBNAME_20xx0108.sql.compressed
      daily/
        20xx_01_01_DBNAME_20xx0101.sql.compressed -> /fullpath/DBNAME/dumps/20xx001_DBNAME_20xx0101.sql.compressed
        20xx_02_01_DBNAME_20xx0108.sql.compressed -> /fullpath/DBNAME/dumps/20xx008_DBNAME_20xx0108.sql.compressed


First thing to do after after a backup is to look if a folder has more that
configured backups and clean the oldest first.

Then we will just have to prune hardlinks where linked count is stricly inferior to 2
Indeed, this means that our backups are only in the dumps folder.

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
    - and no subdirs across mounted points  where the backup dir is

Please Note!!
--------------
I take no resposibility for any data loss or corruption when using this script..
This script will not help in the event of a hard drive crash. If a
copy of the backup has not be stored offline or on another PC..
You should copy your backups offline regularly for best protection.
Happy backing up...
