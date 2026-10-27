#!/usr/bin/env bash
# Rejoue toutes les migrations + seed sur une base vide, puis les tests.
# Usage : PGHOST=... ./supabase/tests/run.sh   (base locale jetable)
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
DB=${DB:-findar_test}
dropdb --if-exists "$DB" && createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/00_supabase_stub.sql
for f in migrations/*.sql; do
  echo "→ $f"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done
echo "→ seed.sql"; psql -q -o /dev/null -v ON_ERROR_STOP=1 -d "$DB" -f seed.sql
echo "→ seed.sql (2e passage : doit être idempotent)"; psql -q -o /dev/null -v ON_ERROR_STOP=1 -d "$DB" -f seed.sql
for t in tests/[1-9]*.sql; do
  echo "→ $t"; psql -q -X -o /dev/null -v ON_ERROR_STOP=1 -d "$DB" -f "$t"
done
echo "OK"
