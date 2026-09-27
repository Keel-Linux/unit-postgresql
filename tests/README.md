# Tests

    bats tests/                                  every test
    COVERAGE_THRESHOLD=100 tests/coverage.sh     the gate, kcov over bats

Two files:

- `conf.bats` runs the build time conf script for real against scratch
  directories. `pg_dropcluster`, `pg_createcluster`, `systemctl`, `su`, `psql`,
  `createuser` and `createdb` are PATH stubs that record their calls and can be
  made to fail; the cluster the stubbed `pg_createcluster` leaves behind is a
  scratch `postgresql.conf` holding the lines Debian's default carries. Nothing
  needs root, a cluster or a network. The script is run as `bash -e`, for the
  reason COVERAGE.md gives.
- `unit.bats` checks the shape `fab` and `bt-layer` require of a unit, and that
  the conf script is POSIX shell.

COVERAGE.md says which file is measured and why the two the overlay ships are
not.
