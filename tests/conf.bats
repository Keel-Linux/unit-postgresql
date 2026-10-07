#!/usr/bin/env bats
# The build time conf script of the component, run for real against scratch
# directories. pg_dropcluster, pg_createcluster, systemctl, su, psql,
# createuser and createdb are PATH stubs that record what they were called
# with; the created cluster is a scratch postgresql.conf with the lines
# Debian's default carries. Nothing here needs root, a cluster or a network.
#
# The case these tests exist for is the bind addresses. Debian's default
# listen_addresses = 'localhost' binds the IPv4 loopback only, because
# /etc/hosts maps ::1 to ip6-localhost and never to localhost, so an appliance
# reaching its own database over IPv6 finds nothing listening. The component
# writes both loopbacks as literal addresses and checks the file afterwards,
# and these tests hold that in place.
#
# The script is POSIX shell, as the shared tree wrote it, and its shebang is
# "#!/bin/sh -ex". The tests run it as "bash -e" instead: kcov measures bash
# and cannot see inside dash, and -e has to be passed explicitly because a
# script run as an argument to an interpreter never gets the options of its
# own shebang. tests/unit.bats keeps the file POSIX with shellcheck, so the
# two interpreters are running the same language.

setup() {
    unit="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    scratch="$BATS_TEST_TMPDIR"
    export PG_LIB_DIR="$scratch/usr/lib/postgresql"
    export PG_CONF_ROOT="$scratch/etc/postgresql"
    export CALLS="$scratch/calls"
    export SQL="$scratch/sql"
    mkdir -p "$PG_LIB_DIR/17" "$scratch/stubs"
    : > "$CALLS"
    : > "$SQL"

    # What pg_createcluster leaves behind, reduced to the four lines this
    # script reads or writes. DEFAULT_CONF overrides it per test.
    cat > "$scratch/default.conf" <<'EOF'
#listen_addresses = 'localhost'		# what IP address(es) to listen on;
port = 5432
#password_encryption = on
shared_buffers = 32MB
EOF

    stub() {
        printf '#!/bin/sh\n%s\n' "$2" > "$scratch/stubs/$1"
        chmod 755 "$scratch/stubs/$1"
    }
    stub pg_dropcluster 'echo "pg_dropcluster $*" >> "$CALLS"; [ -z "$DROP_FAIL" ] || exit 1'
    stub pg_createcluster 'echo "pg_createcluster $*" >> "$CALLS"
[ -z "$CREATE_FAIL" ] || exit 1
mkdir -p "$PG_CONF_ROOT/17/main"
cp "${DEFAULT_CONF:-$PG_CONF_ROOT/../../default.conf}" "$PG_CONF_ROOT/17/main/postgresql.conf"'
    stub systemctl 'echo "systemctl $*" >> "$CALLS"'
    # su runs the command it is given, so the stubs below see the heredoc
    stub su 'echo "su $*" >> "$CALLS"
while [ $# -gt 0 ]; do case $1 in -c) shift; exec sh -c "$1" ;; esac; shift; done'
    stub psql 'echo "psql $*" >> "$CALLS"; cat >> "$SQL"; [ -z "$PSQL_FAIL" ] || exit 1'
    stub createuser 'echo "createuser $*" >> "$CALLS"'
    stub createdb 'echo "createdb $*" >> "$CALLS"'
    export PATH="$scratch/stubs:$PATH"
    conf="$PG_CONF_ROOT/17/main/postgresql.conf"
}

@test "the cluster listens on both loopbacks, written as literal addresses" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -qE "^listen_addresses = '::1,127\.0\.0\.1'" "$conf"
    ! grep -qE "^#?listen_addresses = 'localhost'" "$conf"
}

@test "the line it writes says where it came from" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -q "set by the postgresql component" "$conf"
}

@test "an address family is never dropped: ::1 comes first and 127.0.0.1 is there" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    line="$(grep '^listen_addresses' "$conf")"
    [[ "$line" == *"'::1,127.0.0.1'"* ]]
}

@test "a cluster whose listen_addresses line is already set is rewritten, not doubled" {
    printf "listen_addresses = '*'\nport = 5432\n" > "$scratch/other.conf"
    DEFAULT_CONF="$scratch/other.conf" run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^listen_addresses' "$conf")" -eq 1 ]
    grep -qE "^listen_addresses = '::1,127\.0\.0\.1'" "$conf"
}

@test "a cluster with no listen_addresses line at all fails the build" {
    printf 'port = 5432\n' > "$scratch/bare.conf"
    DEFAULT_CONF="$scratch/bare.conf" run bash -e "$unit/conf"
    [ "$status" -ne 0 ]
    ! grep -q 'systemctl stop postgresql' "$CALLS"
}

@test "the cluster is recreated as UTF-8 for the version that is installed" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -qx 'pg_dropcluster --stop 17 main' "$CALLS"
    grep -qx 'pg_createcluster -e UTF-8 17 main' "$CALLS"
}

@test "a cluster that was not there yet is not a failure" {
    DROP_FAIL=1 run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -qx 'pg_createcluster -e UTF-8 17 main' "$CALLS"
}

@test "a cluster that cannot be created stops the script" {
    CREATE_FAIL=1 run bash -e "$unit/conf"
    [ "$status" -ne 0 ]
    [ ! -s "$SQL" ]
}

@test "password encryption is turned on and shared_buffers reduced" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -qx 'password_encryption = on' "$conf"
    grep -qx 'shared_buffers = 24MB' "$conf"
}

@test "the postgres role gets no password at build time" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    run grep -i 'password' "$SQL"
    [ "$status" -eq 1 ]
    run grep -x 'psql.*' "$CALLS"
    [ "$status" -eq 1 ]
}

@test "a PGSQL_PASS in the build environment is not given to any role" {
    PGSQL_PASS=declared-at-build run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    run grep -i 'password' "$SQL"
    [ "$status" -eq 1 ]
    run grep -r 'declared-at-build' "$scratch/sql" "$CALLS" "$PG_CONF_ROOT"
    [ "$status" -eq 1 ]
}

@test "root gets a superuser role and a database of its own" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    grep -qx 'createuser --superuser root' "$CALLS"
    grep -qx 'createdb root' "$CALLS"
}

@test "the cluster is started, restarted after the file changes and stopped at the end" {
    run bash -e "$unit/conf"
    [ "$status" -eq 0 ]
    run grep -n 'systemctl' "$CALLS"
    [ "${lines[0]#*:}" = "systemctl start postgresql" ]
    [ "${lines[1]#*:}" = "systemctl restart postgresql" ]
    [ "${lines[2]#*:}" = "systemctl stop postgresql" ]
    [ "${#lines[@]}" -eq 3 ]
}
