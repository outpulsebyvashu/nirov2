#!/usr/bin/env bash
# Applies the migrations and seed to a throwaway local Postgres and runs the
# RLS tests. Needs Postgres 15+ binaries on PATH (or PG_BIN set).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
bin="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
export PATH="$bin:$PATH"

dir="$(mktemp -d)"
port="${PGPORT_TEST:-54329}"
# initdb and pg_ctl refuse to run as root
if [ "$(id -u)" = 0 ]; then
  chown -R postgres "$dir"
  run() { su postgres -s /bin/bash -c "PATH='$PATH' $*"; }
else
  run() { bash -c "$*"; }
fi
cleanup() { run "pg_ctl -D '$dir' -m immediate stop" >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT

run "initdb -D '$dir' -U postgres --auth=trust >/dev/null"
run "pg_ctl -D '$dir' -o '-p $port -k /tmp -c listen_addresses=' -w start >/dev/null"

psql_() { psql -h /tmp -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

psql_ -f "$here/stubs.sql"
for f in "$root"/migrations/*.sql; do
  echo "migrate $(basename "$f")"
  psql_ -f "$f"
done
psql_ -f "$root/seed.sql"
psql_ -At -f "$here/rls_test.sql" 2>&1 | sed -n "s/^psql:[^ ]* NOTICE:  //p; /PASSED/p"
