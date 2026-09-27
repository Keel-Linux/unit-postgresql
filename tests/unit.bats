#!/usr/bin/env bats
# The shape fab and bt-layer require of a unit, checked here so that a mistake
# in this repository fails on a hosted runner in seconds instead of on the
# build host in minutes.
#
# The rules are bin/layer-lib of buildtasks and share/product.mk of fab: a
# unit carries at least one of plan, overlay, conf and removelist; a conf that
# is not executable is skipped by fab without a word; conf-vars names one
# variable per line and fab refuses anything that is not a variable name; the
# version is a single token the layer manifest can carry.

setup() {
    unit="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "the conf script is executable, or fab would skip it in silence" {
    [ -x "$unit/conf" ]
}

@test "the plan names the server and its Webmin module" {
    run grep -c '^[a-z0-9]' "$unit/plan"
    [ "$output" = "2" ]
    grep -qx 'postgresql' "$unit/plan"
    grep -qx 'webmin-postgresql' "$unit/plan"
}

@test "conf-vars names PGSQL_PASS and nothing fab would refuse" {
    run bash -c "sed 's/#.*//' '$unit/conf-vars' | grep -v '^[[:space:]]*\$'"
    [ "$output" = "PGSQL_PASS" ]
    grep -qx 'PGSQL_PASS' <<< "$output"
    [[ "$output" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

@test "the conf script reads every variable conf-vars names" {
    grep -q 'PGSQL_PASS' "$unit/conf"
}

@test "the version is one line a layer manifest can carry" {
    [ "$(wc -l < "$unit/version")" -eq 1 ]
    run cat "$unit/version"
    [[ "$output" =~ ^[A-Za-z0-9][A-Za-z0-9._+~-]*$ ]]
    [ "${#output}" -le 64 ]
}

@test "the version is the version of the newest changelog entry" {
    run head -n 1 "$unit/changelog"
    [ "$output" = "unit-postgresql-$(cat "$unit/version") (1) keel; urgency=low" ]
}

@test "the overlay ships exactly the files the shared tree had" {
    run bash -c "cd '$unit/overlay' && find . -type f | sort"
    expected="./usr/lib/inithooks/bin/pgsqlconf.py
./usr/lib/inithooks/firstboot.d/35pgsqlpass"
    [ "$output" = "$expected" ]
}

@test "no removelist, which the shared tree did not have either" {
    [ ! -e "$unit/removelist" ]
}

@test "the conf script is POSIX shell, which is what its shebang says" {
    # tests/conf.bats runs it as bash, because that is what kcov can measure.
    # This is the check that bash and dash are running the same language.
    command -v shellcheck >/dev/null || skip "shellcheck is not installed"
    run shellcheck --shell=sh --severity=error "$unit/conf"
    [ "$status" -eq 0 ]
}
