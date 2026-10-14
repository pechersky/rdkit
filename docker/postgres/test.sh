#!/bin/sh
# Usage: test.sh IMAGE [OLD_IMAGE]. Seeds data as a non-superuser on OLD_IMAGE, then
# checks it survives reopening on IMAGE, ALTER EXTENSION UPDATE and dump/restore.
# As on RDS, rdkit is not a trusted extension: the superuser (rds_superuser there)
# creates, updates and restores it; the app role `chem` owns and queries the data.
set -eux
new=$1 old=${2:-$1} pg=rdkit-test-$$
trap 'docker rm -fv "$pg"; docker volume rm "$pg"' EXIT

# (Re)start IMAGE on the shared data volume and wait until it accepts connections.
start() {
  docker rm -fv "$pg" 2>/dev/null || true
  docker run -d --name "$pg" -e POSTGRES_HOST_AUTH_METHOD=trust \
    -v "$pg:$(docker run --rm --entrypoint printenv "$1" PGDATA)" "$1"
  for _ in $(seq 60); do docker exec "$pg" pg_isready -qh 127.0.0.1 && return; sleep 1; done
  docker logs "$pg"
  exit 1
}
sql() { docker exec -i "$pg" psql -XAtq -v ON_ERROR_STOP=1 -U "$1" -d "$2"; }
# Everything a user would notice changing, read through the GiST indexes:
# stored molecules and fingerprints, substructure search and similarity search.
snapshot() {
  sql chem "$1" <<'SQL'
SET enable_seqscan = off;
SET rdkit.tanimoto_threshold = 0.5;
SELECT id, mol_to_smiles(m), bfp_to_binary_text(fp) FROM t ORDER BY id;
SELECT array_agg(id ORDER BY id) FROM t WHERE m @> 'CO'::qmol;
SELECT array_agg(id ORDER BY id) FROM t WHERE fp % morganbv_fp('CCO'::mol);
SQL
}

# Seed on the old image.
start "$old"
echo 'CREATE ROLE chem LOGIN; CREATE DATABASE chem OWNER chem;' | sql postgres postgres
echo 'CREATE EXTENSION rdkit;' | sql postgres chem
sql chem chem <<'SQL'
CREATE TABLE t (id int PRIMARY KEY, m mol, fp bfp);
INSERT INTO t SELECT i, s::mol, morganbv_fp(s::mol)
FROM (VALUES (1, 'CCO'), (2, 'CCN'), (3, 'COC'), (4, 'c1ccccc1'), (5, 'C[C@H](O)C(=O)O')) v(i, s);
CREATE INDEX ON t USING gist (m);
CREATE INDEX ON t USING gist (fp);
SQL
before=$(snapshot chem)
# Guard against a snapshot that is consistently wrong: C-O substructures are 1, 3, 5.
echo "$before" | grep -qx '{1,3,5}'
docker stop "$pg"

# Upgrade in place: the new rdkit.so must read old on-disk data and indexes, and
# the extension's update scripts must apply cleanly over them.
start "$new"
echo 'ALTER EXTENSION rdkit UPDATE;' | sql postgres chem
test "$(snapshot chem)" = "$before"

# Logical backup: the app role's dump must restore into a fresh database
# (type I/O round trip, index rebuild) with identical results.
echo 'CREATE DATABASE copy OWNER chem;' | sql postgres postgres
docker exec "$pg" sh -c 'pg_dump -U chem -Fc chem | pg_restore -U postgres -d copy --exit-on-error'
test "$(snapshot copy)" = "$before"
