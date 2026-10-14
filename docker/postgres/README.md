# PostgreSQL + RDKit cartridge images

`Dockerfile` builds the cartridge on a digest-pinned official `postgres` image and
runs the upstream SQL regression suite. `test.sh` checks that data survives an
image upgrade, `ALTER EXTENSION UPDATE` and dump/restore. As on Amazon RDS, rdkit
is not a trusted extension, so the superuser creates and updates it.

```sh
docker build -t rdkit-postgres docker/postgres   # newest major; another: --build-arg POSTGRES=<its POSTGRES_* pin>
docker/postgres/test.sh rdkit-postgres [OLD_IMAGE]
```

Each PostgreSQL major with a `POSTGRES_<major>` pin in the Dockerfile (17 and 18) gets
its own images. A major Aurora PostgreSQL doesn't ship yet has a `# No Aurora` comment
instead of an `AURORA_RDKIT_<major>` pin, and no `-aurora` images.

Images, all `ghcr.io/pechersky/rdkit:postgres-…`:

| Tags | RDKit |
|---|---|
| `<pg>-<rdkit>`, `<major>` | newest release, plus the `costs.sql` workaround so `ALTER EXTENSION rdkit UPDATE` works |
| `<pg>-<rdkit>-unpatched`, `<major>-unpatched` | the same release exactly as shipped (`--build-arg PATCH_COSTS=`) |
| `<pg>-<aurora_rdkit>`, `<major>-aurora` | the release Aurora PostgreSQL ships for this major (`--build-arg RDKIT=<its AURORA_RDKIT_* pin>`) |

This `postgres-cartridge-image` branch holds only the image sources; the build clones
RDKit at its pin. Workflows in `.github/workflows/`:

- `postgres-bump` (weekly; on `master`, since schedules only run on the default branch,
  running `.github/scripts/postgres-bump.sh` from this branch): pins the newest RDKit
  release and, per major, the newest PostgreSQL minor and the RDKit release in AWS's
  Aurora extension table, and opens a `bump/...` PR against this branch. Adds the next
  major (as the default) once its X.0 is on Docker Hub; its Aurora pin follows when AWS
  lists it.
- `postgres-image`: per major, native amd64 + arm64 build of all three images (the
  Dockerfile's ccache mount persists in the Actions cache), `test.sh` on each and an
  upgrade from the Aurora image. On `postgres-cartridge-image`, after `postgres-publish`
  approval, `.github/scripts/postgres-publish.sh` pushes those exact tested images by
  digest and tags a two-platform index.

Setup: App secrets `POSTGRES_IMAGE_APP_CLIENT_ID` and `POSTGRES_IMAGE_APP_PRIVATE_KEY`
(Contents and Pull requests write) and a protected `postgres-publish` environment.
