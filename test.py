#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# THIS TEST MUST BE RUN AS ROOT
#
import unittest
import os
import tempfile
import shutil
import re
from subprocess import (
    Popen,
    PIPE,
    check_output,
    CalledProcessError,
    STDOUT)


J = os.path.join
D = os.path.dirname
CWD = os.path.abspath(D(__file__))

COMMON = u'''#!/usr/bin/env bash
chown -R postgres "{dir}"
cp $0 /fooo
export DB_SMART_BACKUP_AS_FUNCS=1
CWD={CWD}
TOP_BACKUPDIR={TOP_BACKUPDIR}
GLOBAL_SUBDIR={GLOBAL_SUBDIR}
BACKUP_TYPE={BACKUP_TYPE}
comp=bz2
SOURCE={SOURCE}
if [[ -n $SOURCE ]];then
    . "{cwd}/db_smart_backup.sh"
fi
dofic() {{
  COMP=${{COMP:-xz}}
  db="${{1:-${{DB:-"foomoobar"}}}}"
  create_db_directories "${{db}}"
  local fn="$(get_backupdir)/${{db}}/dumps/${{db}}_${{DATE}}.sql"
  touch "$fn" "$(get_compressed_name "$fn")"
  link_into_dirs "${{db}}" "$fn"
}}

'''
NO_COMPRESS = u'''
do_compression() {{
    echo "do_compression $@"
}}
'''
NO_DB = u'''
do_hook() {{
    echo "do_hook $@"
}}
do_db_backup() {{
    echo "do_db_backup $@"
}}
'''
NO_ROTATE = u'''
do_rotate() {{
    echo "do_rotate $@"
}}
'''
NO_ORPHAN = u'''
cleanup_orphans() {{
    echo "cleanup_orphans $@"
}}
'''
NO_MAIL = u'''
do_sendmail() {{
    echo "do_sendmail $@"
}}
'''


class TestCase(unittest.TestCase):

    def exec_script(self,
                    string,
                    common=True,
                    no_compress=True,
                    no_orphan=True,
                    no_rotate=True,
                    no_db=True,
                    no_mail=True,
                    source=True,
                    stderr=None):
        pt = os.path.join(self.dir, 'w.sh')
        if not isinstance(string, unicode):
            string = string.decode('utf-8')
        script = u''
        if common:
            script += COMMON
        if no_rotate:
            script += NO_ROTATE
        if no_orphan:
            script += NO_ORPHAN
        if no_compress:
            script += NO_COMPRESS
        if no_db:
            script += NO_DB
        if no_mail:
            script += NO_MAIL
        script += u'\ncd "{0}"\n'.format(self.dir)
        script += string
        script += u'\ncd "{0}"\n'.format(self.dir)
        with open(pt, 'w') as fic:
            opts = self.opts.copy()
            opts.update({
                'SOURCE': (source) and u'1' or u'',
            })
            sscript = script.format(**opts).encode('utf-8')
            fic.write(sscript)
        os.chmod(pt, 0755)
        try:
            if stderr:
                stderr = STDOUT
            ret = check_output([pt], shell=True, stderr=stderr)
        except CalledProcessError, ex:
            ret = ex.output
        return ret

    def setUp(self):
        self.env = os.environ.copy()
        self.dir = tempfile.mkdtemp()
        self.opts = {
            'cwd': unicode(CWD),
            'CWD': unicode(CWD),
            'dir': unicode(self.dir),
            'TOP_BACKUPDIR': unicode(os.path.join(self.dir, "pgbackups")),
            'BACKUP_TYPE': u"postgresql",
            'GLOBAL_SUBDIR': u"__GLOBAL__",
        }

    def tearDown(self):
        if os.path.exists(self.dir):
            shutil.rmtree(self.dir)
        os.environ.update(self.env)

    def test_Compressor(self):
        TEST = '''
COMP=""   COMPS="xz nocomp" XZ="/null";set_compressor;echo comp:$COMP;
COMP="xz" COMPS="xz"        XZ=""     ;set_compressor;echo comp:$COMP;
'''
        ret = self.exec_script(TEST, stderr=True)
        self.assertEqual(
            'comp:nocomp\n'
            'comp:xz\n', ret)
        TEST = '''
COMP=""      COMPS="bzip2 nocomp" BZIP2="/null";set_compressor;echo comp:$COMP;
COMP="bzip2" COMPS="bzip2"        BZIP2=""     ;set_compressor;echo comp:$COMP;
'''
        ret = self.exec_script(TEST, stderr=True)
        self.assertEqual(
            'comp:nocomp\n'
            'comp:bzip2\n', ret)
        TEST = '''
COMP=""     COMPS="gzip nocomp" GZIP="/null";set_compressor;echo comp:$COMP;
COMP="gzip" COMPS="gzip"        GZIP=""     ;set_compressor;echo comp:$COMP;
'''
        ret = self.exec_script(TEST, stderr=True)
        self.assertEqual(
            'comp:nocomp\n'
            'comp:gzip\n', ret)
        TEST = '''
COMP="xz"
COMPS="gzip bzip2 xz nocomp"
GZIP="/null"; XZ="/null"; BZIP2="/null"
set_compressor;echo comp:$COMP;
'''
        ret = self.exec_script(TEST, stderr=True)
        self.assertEqual(
            'comp:nocomp\n', ret)

    def test_Compression(self):
        TEST = '''
XZ=/nonexist
BZ2=/nonexist
COMP=gzip
echo "$(get_compressed_name a)"
COMP=bzip2
echo "$(get_compressed_name a)"
COMP=foo
echo "$(get_compressed_name a)"
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            'a.gz\n'
            'a.bz2\n'
            'a\n', ret)
        TEST = '''
COMP="xz";COMPS="$COMP";set_compressor
echo azerty>thiscompress
do_compression thiscompress
echo $COMPRESSED_NAME
'''
        ret = self.exec_script(TEST, stderr=True, no_compress=False)
        for i in [
            '^thiscompress.xz.*$',
        ]:
            self.assertTrue(re.search(i, ret, re.M | re.U), i)
        TEST = '''
COMP="gzip";COMPS="$COMP";set_compressor
echo azerty>thiscompress
do_compression thiscompress
echo $COMPRESSED_NAME
'''
        ret = self.exec_script(TEST, stderr=True, no_compress=False)
        for i in [
            '^thiscompress.gz.*$',
        ]:
            self.assertTrue(re.search(i, ret, re.M | re.U), i)
        TEST = '''
COMP="bzip2";COMPS="$COMP";set_compressor
echo azerty>thiscompress
do_compression thiscompress
echo $COMPRESSED_NAME
'''
        ret = self.exec_script(TEST, stderr=True, no_compress=False)
        for i in [
            '^thiscompress.bz2.*$',
        ]:
            self.assertTrue(re.search(i, ret, re.M | re.U), i)
        TEST = '''
COMP="nocomp";COMPS="$COMP";set_compressor
echo azerty>thiscompress
do_compression thiscompress
echo $COMPRESSED_NAME
'''
        ret = self.exec_script(TEST, stderr=True, no_compress=False)
        for i in [
            '\[db_smart_backup\] No compressor found, no compression done',
            'thiscompress',
        ]:
            self.assertTrue(re.search(i, ret, re.M | re.U), i)

    def test_runas(self):
        TEST = '''
export DB_SMART_BACKUP_AS_FUNCS="1" RUNAS="postgres" PSQL="psql"
mkdir -p  "$outputDir/WITH QUOTES/a b e"
mkdir -p  "$outputDir/WITH QUOTES/cc dd ff"
chown -Rf postgres  "$outputDir/WITH QUOTES"
export RUNAS="postgres"
ret=$(runas 'echo $(whoami):$(ls "'"$outputDir"'/WITH QUOTES")')
echo $ret
export RUNAS="root"
ret=$(runas 'echo $(whoami):$(ls "'"$outputDir"'/WITH QUOTES")')
echo $ret
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            'postgres:a b e cc dd ff\n'
            'root:a b e cc dd ff\n', ret)

    def test_monkeypatch(self):
        TEST = '''
export DB_SMART_BACKUP_AS_FUNCS="1" RUNAS="postgres" PSQL="psql"
. "$CWD/db_smart_backup.sh"
dummy_for_tests
dummy_callee_for_tests() {{
    echo "foo"
}}
dummy_for_tests
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            'here\nfoo\n'
        )

    def test_pgbins_run_as(self):
        TEST = '''
export DB_SMART_BACKUP_AS_FUNCS="1" RUNAS="postgres" PSQL="psql"
. "$CWD/db_smart_backup.sh"
export RUNAS="postgres"
psql_ -c "select * from pg_roles"
echo $ret
'''
        ret = self.exec_script(TEST)
        self.assertTrue('rolnam' in ret)

    def test_createdirs(self):
        TEST = '''
create_db_directories "WITH QUOTES ET utf8 éà"
create_db_directories $GLOBAL_SUBDIR
create_db_directories foo
'''
        self.exec_script(TEST)
        for i in[
            'postgresql/localhost/WITH QUOTES ET utf8 éà/daily',
            'postgresql/localhost/WITH QUOTES ET utf8 éà/dumps',
            'postgresql/localhost/WITH QUOTES ET utf8 éà/monthly',
            'postgresql/localhost/WITH QUOTES ET utf8 éà/weekly',
            'postgresql/localhost/foo/daily',
            'postgresql/localhost/foo/dumps',
            'postgresql/localhost/foo/monthly',
            'postgresql/localhost/foo/weekly',
            'postgresql/localhost/__GLOBAL__/daily',
            'postgresql/localhost/__GLOBAL__/dumps',
            'postgresql/localhost/__GLOBAL__/monthly',
            'postgresql/localhost/__GLOBAL__/weekly',
            'postgresql/localhost/__GLOBAL__',
        ]:
            self.assertTrue(
                os.path.isdir(J(self.dir, "pgbackups", i)), i)

    def test_backdir(self):
        TEST = '''
echo $(TOP_BACKUPDIR="foo" BACKUP_TYPE=bar HOST="" PGHOST="" get_backupdir)
echo $(TOP_BACKUPDIR="foo" BACKUP_TYPE=postgresql PGHOST="" get_backupdir)
echo $(TOP_BACKUPDIR="foo" BACKUP_TYPE=postgresql HOST="bar" PGHOST="foo" get_backupdir)
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            'foo/bar\n'
            'foo/postgresql/localhost\n'
            'foo/postgresql/bar\n')

    def test_link_into_dirs(self):
        TEST = '''
DB=foo;YEAR="2002";MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";DOY="0$DOM";W="2" dofic
'''
        self.exec_script(TEST)
        for i in [
            "postgresql/localhost/foo/weekly/foo_2002_2.sql.xz",
            "postgresql/localhost/foo/monthly/foo_2002_01.sql.xz",
            "postgresql/localhost/foo/daily/foo_2002_008_2002-01-08.sql.xz",
        ]:
            self.assertTrue(os.path.exists(J(self.dir, 'pgbackups', i)), i)

    def test_cleanup_orphans_1(self):
        common = u'''
BACKUPDIR="$outputDir/pgbackups"
KEEP_MONTHES=1
KEEP_WEEKS=3
KEEP_DAYS=9
DB=foo
YEAR=2002
'''
        RTEST1 = common + u'''
DB="WITH QUOTES é utf8"
find "$(get_backupdir)/$DB/"{{daily,monthly,lastsnapshots,weekly}}/ -type f|\
while read fic;do rm -f "${{fic}}";done
do_cleanup_orphans 2>&1
'''
        TEST = common + u'''
DB="WITH QUOTES é utf8"
MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";DOY="0$DOM";
DOY="0$DOM";W="2"
FDATE="${{DATE}}_01-02-03";dofic
'''
        # removing file from all subdirs except dump place
        self.exec_script(TEST)
        ret = self.exec_script(RTEST1)
        self.assertTrue(
            re.search(
                'Pruning .*/pgbackups/postgresql/localhost/'
                'WITH QUOTES é utf8/dumps/'
                'WITH QUOTES é utf8_2002-01-08.sql',
                ret
            )
        )

    def test_cleanup_orphans_2(self):
        common = u'''
BACKUPDIR="$outputDir/pgbackups"
KEEP_LOGS=1
KEEP_LASTS=24
KEEP_MONTHES=1
KEEP_WEEKS=3
KEEP_DAYS=9
DB=foo
YEAR=2002
'''
        RTEST2 = common + u'''
DB="WITH QUOTES é utf8"
find "$(get_backupdir)/$DB/"{{dumps,daily,monthly,weekly}} -type f|\
while read fic;do rm -f "${{fic}}";done
do_cleanup_orphans 2>&1
'''
        TEST = common + u'''
DB="WITH QUOTES é utf8"
MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";DOY="0$DOM";
DOY="0$DOM";W="2"
FDATE="${{DATE}}_01-02-03";dofic
'''
        # removing file from dumps + all-one dir
        # and test than orphan cleanup the last bits
        self.exec_script(TEST)
        ret = self.exec_script(RTEST2)
        self.assertTrue(
            re.search(
                'Pruning .*/pgbackups/postgresql/localhost/'
                'WITH QUOTES é utf8/lastsnapshots/'
                'WITH QUOTES é utf8_2002_008_2002-01-08_01-02-03.sql.xz',
                ret
            )
        )

    def test_rotate(self):
        rotatec = u'''
BACKUPDIR="$outputDir/pgbackups"
KEEP_MONTHES=1
KEEP_WEEKS=3
KEEP_DAYS=9
DB=foo
YEAR=2002
'''
        RTEST = rotatec + u'''
do_rotate 2>&1
'''
        TEST = rotatec + u'''
DB="WITH QUOTES é utf8"
MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="09";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="10";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="11";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="12";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="13";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="14";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="15";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="16";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="03";DOM="01";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="60"   ;W="8" dofic
DB=__GLOBAL__
MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="09";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="10";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="11";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="12";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="13";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="14";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="15";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="16";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="03";DOM="01";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="60"   ;W="8" dofic
DB=bar
MNUM="01";DOM="08";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="09";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="10";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="11";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="12";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="13";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="14";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="2" dofic
MNUM="01";DOM="15";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="16";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="3" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="01";DOM="17";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="0$DOM";W="5" dofic
MNUM="03";DOM="01";DATE="$YEAR-$MNUM-$DOM";FDATE="${{DATE}}_01-01-01";DOY="60"   ;W="8" dofic
'''
        self.exec_script(TEST)
        counters = {
            '': 50,
            'daily': 11,
            'monthly': 2,
            'weekly': 4,
            'dumps': 22,
            'lastsnapshots': 11,

        }
        for i in ['__GLOBAL__', 'bar', u"WITH QUOTES é utf8"]:
            for j in ['', 'daily', 'weekly', 'monthly',
                      'dumps', 'lastsnapshots']:
                cmd = (
                    u"find '{0}/pgbackups/postgresql/localhost/{1}/{2}' "
                    u"-type f 2>/dev/null"
                    u"|wc -l".format(self.dir, i, j))
                ret = self.exec_script(cmd)
                counter = counters.get(j)
                self.assertTrue(int(ret.strip()) == counter,
                                u"{3} {0}: {2} != {1}".format(
                                    j, ret, counter, i))
        ret = self.exec_script(RTEST, no_rotate=False)
        counters = {
            '': 37,
            'daily': 9,
            'monthly': 1,
            'weekly': 3,
            'dumps': 22,
            'lastsnapshots': 2,
        }
        for i in ['__GLOBAL__', 'bar', u"WITH QUOTES é utf8"]:
            for j in ['', 'daily', 'weekly', 'monthly',
                      'dumps', 'lastsnapshots']:
                cmd = (
                    u"find '{0}/pgbackups/postgresql/localhost/{1}/{2}' "
                    u"-type f 2>/dev/null"
                    u"|wc -l".format(self.dir, i, j))
                ret = self.exec_script(cmd)
                counter = counters.get(j)
                self.assertTrue(int(ret.strip()) == counter,
                                u"{3} {0}: {2} != {1}".format(
                                    j, ret, counter, i))



    def test_sort1(self):
        TEST = u'''
# weekly
cd "{dir}"
rm -rf testtest;mkdir testtest
touch testtest/foo_2001_55.sql
touch testtest/foo_2001_02.sql
touch testtest/foo_2001_3.sql
touch testtest/foo_2001_1.sql
touch testtest/foo_2001_44.sql
get_sorted_files testtest
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            (
                'foo_2001_55.sql\n'
                'foo_2001_44.sql\n'
                'foo_2001_3.sql\n'
                'foo_2001_02.sql\n'
                'foo_2001_1.sql\n'
            )
        )

    def test_sort2(self):
        TEST = u'''
# daily
cd "{dir}"
rm -rf testtest;mkdir testtest
touch testtest/foo_2001_034_2001_02_01.sql
touch testtest/foo_2002_035_2002_02_02.sql
touch testtest/foo_2001_001_2001_01_01.sql
touch testtest/foo_2001_002_2001_01_02.sql
touch testtest/foo_2001_003_2001_1_3.sql
touch testtest/foo_2001_001_2001_01_01.sql
touch testtest/foo_2001_067_2001_04_02.sql
touch testtest/foo_2001_066_2001_04_01.sql
touch testtest/foo_2002_001_2002_1_1.sql
get_sorted_files testtest
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            (
                'foo_2002_035_2002_02_02.sql\n'
                'foo_2002_001_2002_1_1.sql\n'
                'foo_2001_067_2001_04_02.sql\n'
                'foo_2001_066_2001_04_01.sql\n'
                'foo_2001_034_2001_02_01.sql\n'
                'foo_2001_003_2001_1_3.sql\n'
                'foo_2001_002_2001_01_02.sql\n'
                'foo_2001_001_2001_01_01.sql\n'
            )
        )

    def test_sort3(self):
        TEST = u'''
# dumps
cd "{dir}"
rm -rf testtest;mkdir testtest
touch testtest/foo_2001_9_16.sql
touch testtest/foo_2001_02_01.sql
touch testtest/foo_2002_02_02.sql
touch testtest/foo_2001_01_1.sql
touch testtest/foo_2001_01_03.sql
touch testtest/foo_2001_1_2.sql
touch testtest/foo_2001_01_1.sql
touch testtest/foo_2001_04_02.sql
touch testtest/foo_2001_04_01.sql
touch testtest/foo_2003_4_1.sql
get_sorted_files testtest
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            (
                'foo_2003_4_1.sql\n'
                'foo_2002_02_02.sql\n'
                'foo_2001_9_16.sql\n'
                'foo_2001_04_02.sql\n'
                'foo_2001_04_01.sql\n'
                'foo_2001_02_01.sql\n'
                'foo_2001_01_03.sql\n'
                'foo_2001_1_2.sql\n'
                'foo_2001_01_1.sql\n'

            )
        )

    def test_asanitize(self):
        TEST = u'''
# monthly
cd "{dir}"
set_vars
activate_IO_redirection
cyan_log "foo"
yellow_log "foo"
log "foo"
deactivate_IO_redirection
sanitize_log
cat -e "$DSB_LOGFILE"
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret.splitlines()[-3:],
            ['foo$',
             '[db_smart_backup] foo$',
             '[db_smart_backup] foo$']
        )

    def test_sort4(self):
        TEST = u'''
# monthly
cd "{dir}"
rm -rf testtest;mkdir testtest
touch testtest/foo_2002_02.sql
touch testtest/foo_2001_02.sql
touch testtest/foo_2003_2.sql
touch testtest/foo_2001_01.sql
touch testtest/foo_2001_04.sql
touch testtest/foo_2002_2.sql
get_sorted_files testtest
'''
        ret = self.exec_script(TEST)
        self.assertEqual(
            ret,
            (
                'foo_2003_2.sql\n'
                'foo_2002_2.sql\n'
                'foo_2002_02.sql\n'
                'foo_2001_04.sql\n'
                'foo_2001_02.sql\n'
                'foo_2001_01.sql\n'
            )
        )


if __name__ == '__main__':
    unittest.main()

# vim:et:ft=python:sts=4:sw=4
