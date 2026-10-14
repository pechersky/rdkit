#!/bin/bash
# Pins docker/postgres/Dockerfile to the newest releases, then, unless branch
# bump/postgres-<id> already exists for the result, writes id and title to $GITHUB_OUTPUT.
# Locally: GITHUB_OUTPUT=/dev/stdout GH_TOKEN=$(gh auth token) .github/scripts/postgres-bump.sh
set -euo pipefail
f=docker/postgres/Dockerfile
hub=https://hub.docker.com/v2/repositories/library/postgres/tags
aws=https://docs.aws.amazon.com/AmazonRDS/latest/AuroraPostgreSQLReleaseNotes/AuroraPostgreSQL.Extensions.html
pin() { sed -i "s|^ARG $1=.*|ARG $1=$2|" "$f"; }
sha() { gh api "repos/rdkit/rdkit/commits/$1" --jq .sha; }
# Newest X.Y@digest of a major, not betas or RCs; fails if there is none.
newest() {
  curl -fsS "$hub?page_size=100&name=$1." | jq -r '.results[] | "\(.name)@\(.digest)"' \
    | grep -E "^$1\.[0-9]+@" | sort -V | tail -1
}

tag=$(gh api repos/rdkit/rdkit/releases/latest --jq .tag_name)
commit=$(sha "$tag")
pin RDKIT "${tag#Release_}@$commit"

# The next major becomes the default once its X.0 is out. Majors are never removed.
next=$(( $(grep -oP '^ARG POSTGRES_\K\d+' "$f" | sort -n | tail -1) + 1 ))
if newest "$next" >/dev/null; then
  sed -i "/^ARG POSTGRES=/i ARG POSTGRES_$next=\n# No Aurora PostgreSQL $next yet: no AURORA_RDKIT_$next pin or -aurora images." "$f"
  pin POSTGRES "\$POSTGRES_$next"
fi

page=$(curl -fsS "$aws")
majors=$(grep -oP '^ARG POSTGRES_\K\d+' "$f")
for major in $majors; do
  pg=$(newest "$major")
  pin "POSTGRES_$major" "$pg"
  # Aurora's pin once AWS lists the major; a pinned major must stay listed.
  grep -q "^ARG AURORA_RDKIT_$major=" "$f" \
    || [[ $page == *"id=\"AuroraPostgreSQL.Extensions.$major\""* ]] || continue
  # The release after "rdkit" in that major's table, e.g. "4.6.1 (2024_09_6)".
  aurora=$(sed -n "/id=\"AuroraPostgreSQL.Extensions.$major\"/,/<h2/p" <<<"$page" \
    | grep -A1 '<span>rdkit</span>' | grep -oP '\((Release_)?\K\d{4}_\d{2}_\d+(?=\))') \
    || { echo "::error::No rdkit version for Aurora PostgreSQL $major at $aws"; exit 1; }
  commit=$(sha "Release_$aurora")
  sed -i "s|^# No Aurora PostgreSQL $major .*|ARG AURORA_RDKIT_$major=|" "$f"
  pin "AURORA_RDKIT_$major" "$aurora@$commit"
done

# One branch per pin set, digests included, so base-image refreshes land too.
id=$(grep '^ARG \w*=\S*@' "$f" | sha256sum | cut -c1-12)
# Never overwrite a bump branch: someone may have pushed a fix to it.
ref=$(git ls-remote origin "refs/heads/bump/postgres-$id")
[ -z "$ref" ] || { echo "bump/postgres-$id exists"; exit; }
echo "id=$id" >> "$GITHUB_OUTPUT"
# Also the commit message.
echo "title=Bump postgres-image pins: $(grep -oP '^ARG \K\w+=[^@]+(?=@)' "$f" | paste -sd' ')" >> "$GITHUB_OUTPUT"
