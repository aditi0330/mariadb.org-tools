#!/bin/sh

set -xeuvo pipefail

die()
{
	echo $@ >2
	exit 1
}

runandwait()
{
	n=$1
	shift
	podman run --name "$1" --rm "$@"
	podman exec "$1" sh -c 'c=5; while [ $c -gt 0 ] && [ ! -S /run/mysqld/mysqld.sock ]; do echo waiting $c; c=$(( $c - 1 )); done; [ -S /run/mysqld/mysqld.sock ] || exit 1'
}

# Failure - none of MYSQL_ALLOW_EMPTY_PASSWORD, MYSQL_RANDOM_ROOT_PASSWORD, MYSQL_ROOT_PASSWORD
podman run --rm --name m_noargs mariadb && die "should fail with 'Database is uninitialized and password option is not specified'"

# MYSQL_ROOT_PASSWORD

runandwait m_rootpass -d  -e MYSQL_ROOT_PASSWORD=examplepass  mariadb
podman exec -t m_rootpass  mysql -u root -pexamplepass -e 'select current_user()'
podman exec -t m_rootpass  mysql -u root -pwrongpass -e 'select current_user()' || echo 'expected failure' 
podman kill m_rootpass

# MYSQL_ALLOW_EMPTY_PASSWORD

runandwait m_emptyrootpass -d  -e MYSQL_ALLOW_EMPTY_PASSWORD=1  mariadb
podman exec -t m_emptyrootpass  mysql -u root -e 'select current_user()'
podman kill m_emptyrootpass
podman exec -t m_emptyrootpass  mysql -u root -pexamplepass -e 'select current_user()' || echo 'expected failure'

# MYSQL_ALLOW_EMPTY_PASSWORD Implementation is non-empty value so this should fail
podman run  --rm  --name m_emptyrootpass -d  -e MYSQL_ALLOW_EMPTY_PASSWORD  mariadb || echo 'expected failure'


# MYSQL_ROOT_PASSWORD
runandwait m_rndrootpass -d  -e MYSQL_RANDOM_ROOT_PASSWORD=1  mariadb
pass=$(podman logs m_rndrootpass | grep 'GENERATED ROOT PASSWORD' 2>&1)
# trim up until passwod
pass=${pass##* } 
podman exec -t m_rndrootpass  mysql -u root -p"${pass}" -e 'select current_user()'
podman kill m_rndrootpass

runandwait m_rndrootpass -d  -e MYSQL_RANDOM_ROOT_PASSWORD=1  mariadb
newpass=$(podman logs m_rndrootpass | grep 'GENERATED ROOT PASSWORD' 2>&1)
# trim up until passwod
newpass=${newpass##* } 
podman kill m_rndrootpass

[ "$pass" = "$newpass" ] && die "highly improbable - two consequitive passwords are the same" 

# Clean environment
runandwait m_envtest -d  -e MYSQL_ALLOW_EMPTY_PASSWORD=1  mariadb
podman exec -t m_envtest  mysql -u root -e 'show databases'

othertables=$(podman exec -t m_envtest  mysql -u root --skip-column-names -Be "select group_concat(SCHEMA_NAME) from information_schema.SCHEMATA where SCHEMA_NAME not in ('mysql', 'information_schema', 'performance_schema')")
[ "$othertables" != "NULL" ] && die "unexpected table $othertables"
otherusers=$(podman exec -t m_envtest  mysql -u root --skip-column-names -Be "select user,host from mysql.user where (user,host) not in (('root', 'localhost'), ('root', '%'), ('mariadb.sys', 'localhost'))")
[ "$otherusers" != "NULL" ] && die "unexpected users $otherusers"
podman kill m_envtest


exit 0
# MariaDB naming (after https://github.com/docker-library/mariadb/pull/333 )
runandwait m_rootpass -d  -e MARIADB_ROOT_PASSWORD=examplepass  mariadb
podman exec -t m_rootpass  mysql -u root -pexamplepass -e 'select current_user()'
podman exec -t m_rootpass  mysql -u root -pwrongpass -e 'select current_user()' || echo 'expected failure' 
podman kill m_rootpass

# Prefer MariaDB names
runandwait m_rootpass -d  -e MARIADB_ROOT_PASSWORD=examplepass -e MYSQL_ROOT_PASSWORD=mysqlexamplepass  mariadb
podman exec -t m_rootpass  mysql -u root -pexamplepass -e 'select current_user()'
podman exec -t m_rootpass  mysql -u root -pwrongpass -e 'select current_user()' || echo 'expected failure' 
podman kill m_rootpass

