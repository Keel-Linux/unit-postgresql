# Coverage

Standard: decisions 0003 (90 percent per repository, 95 for code the project
writes) and 0004 (bats plus kcov for shell). The acceptance test of a
component is the layer that consumes it: `keel-postgresql` builds it, boots it
in LXC and proves the database answers on `::1`, which is why this repository
carries no boot test of its own.

## Measured 2026-09-27

| File | Test | Lines | Note |
| --- | --- | --- | --- |
| conf | tests/conf.bats (14 tests) | 100 percent (17/17) under kcov | every line and every failure path: the cluster recreated as UTF-8, a cluster that was not there, one that cannot be created, password encryption, shared_buffers, the bind addresses in three shapes, a file with no listen_addresses line at all, the declared password and the upstream default, root's role and database, the start, restart and stop, and a cluster that refuses the password change |
| overlay/usr/lib/inithooks/firstboot.d/35pgsqlpass | none | 0 | see below |
| overlay/usr/lib/inithooks/bin/pgsqlconf.py | none | 0 | see below |

Total: **100 percent (17/17)**, 23 bats tests over two files (the conf script
and the shape of the unit). `tests/coverage.sh` fails below
`COVERAGE_THRESHOLD`, which the workflow sets to 100, the measured number. It
is only ever raised (decision 0006).

    $ COVERAGE_THRESHOLD=100 tests/coverage.sh
    kcov line coverage (threshold 100 percent):
     100.00  17/17  conf

The conf script is POSIX shell with the shebang `#!/bin/sh -ex`, and the tests
run it as `bash -e`: kcov measures bash and cannot see inside dash, and a
script run as an argument to an interpreter never gets the options of its own
shebang, so `-e` is passed explicitly. `tests/unit.bats` runs
`shellcheck --shell=sh` over the file, so the language the tests exercise is
the language the build runs.

## What is not measured, and what would change that

Both unmeasured files are shipped by the overlay, and **this repository may
not change a byte of what the image gets**: the extraction is proven by
rebuilding the `postgresql` layer and comparing it against a build from the
shared tree, and a file edited to make it testable would appear in that
comparison as a difference the extraction caused. The conf script is the one
file that can be adapted, because fab copies it into the chroot, runs it and
removes it, so it ships nowhere.

- `35pgsqlpass` sources `/etc/default/inithooks` by absolute path. One line of
  the kind `keel-mariadb`'s own hook already has
  (`INITHOOKS_DEFAULT="${INITHOOKS_DEFAULT:-/etc/default/inithooks}"`) would
  make it testable. That line belongs upstream (decision 0008), and this file
  can be measured here the day upstream takes it.
- `pgsqlconf.py` is Python, which decision 0003 measures with pytest rather
  than kcov, and it drives `libinithooks`' Dialog wrapper. It is the same
  blocker `keel-mariadb` records for `bin/dbpass.py`.

## Plan

- Offer upstream the parameterisation of `35pgsqlpass`, measure it here, and
  raise the gate.
- Add pytest coverage of `pgsqlconf.py` when the inithooks fork gains a Dialog
  stub.
- When decision 0013's replication work starts, the primary and replica
  settings belong in this component, and its tests are where the shape of
  `postgresql.conf` is held. The bind addresses are the first entry of that
  kind and are already here.
