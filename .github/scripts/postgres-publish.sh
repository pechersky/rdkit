#!/bin/bash
# Usage: postgres-publish.sh MAJOR, with each platform's tested tars in images/*/.
# Pushes those exact images untagged by digest, then points the tags at an index of them.
set -euo pipefail
r=ghcr.io/$GITHUB_REPOSITORY
pin() { grep -oP "^ARG $1=\K[^@]+" docker/postgres/Dockerfile; }
publish() { # image tag tag
  refs=()
  for t in images/*/"$1.tar"; do
    d=$(tar -xOf "$t" index.json | jq -r '.manifests[0].digest')
    skopeo copy -q --preserve-digests "oci-archive:$t" "docker://$r@$d"
    refs+=("$r@$d")
  done
  docker buildx imagetools create -t "$r:$2" -t "$r:$3" "${refs[@]}"
}

pg=postgres-$(pin "POSTGRES_$1")
rdkit=$(pin RDKIT)
publish latest "$pg-$rdkit" "postgres-$1"
publish unpatched "$pg-$rdkit-unpatched" "postgres-$1-unpatched"
if aurora=$(pin "AURORA_RDKIT_$1"); then
  publish aurora "$pg-$aurora" "postgres-$1-aurora"
fi
