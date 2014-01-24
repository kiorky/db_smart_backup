#!/usr/bin/env bash
cd $(dirname $0)
PWD=`pwd`
SHU="$PWD/shunit2-2.1.6"
testCompressision() {
  COMP=gzip
  assertEquals "a.gz" "$(get_compressed_name a)"
  COMP=bzip2
  assertEquals "a.bz2" "$(get_compressed_name a)"
  COMP=foo
  assertEquals "a" "$(get_compressed_name a)"
}

testCreateDirs() {
  cat > $outputdir/c << EOF
BACKUPDIR="$outputdir/pgback"
EOF
  . "$PWD/db_smart_backup.sh"
  create_directories
  create_db_directories foo
  for i in __GLOBAL__;do
    assertTrue "$i" "[ -d $outputDir/pgback ]"
  done

}
oneTimeSetUp() {
  export DB_SMART_BACKUP_AS_FUNCS=1
  . $PWD/db_smart_backup.sh
  outputDir="${SHUNIT_TMPDIR}/output"
  stdoutF="${outputDir}/stdout"
  stderrF="${outputDir}/stderr"
  mkdir "${outputDir}"
}
oneTimeTearDown() {
  rm -fr "$outputDir"
}
setUp() {
  COMP=gzip
  echo
}
tearDown() {
  echo
}
suite() {
  echo
}
. $SHU/src/shunit2
# vim:et:ft=sh:sts=2:sw=2
