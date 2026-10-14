# PostgreSQL with the RDKit cartridge. postgres-bump rewrites these NAME=version@hash
# pins and adds new majors. CI builds each POSTGRES_<major> as POSTGRES, also with
# RDKIT=AURORA_RDKIT_<major>, the release Aurora PostgreSQL ships for that major.
ARG RDKIT=2026_09_1@fece8caa860bdf6c9c82bdb9253f22a0cf87150c
ARG POSTGRES_17=17.11@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3
ARG AURORA_RDKIT_17=2024_09_6@b3076c77284b9a8b9d5ef78957ee067037f373a8
ARG POSTGRES_18=18.6@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336
ARG AURORA_RDKIT_18=2024_09_6@b3076c77284b9a8b9d5ef78957ee067037f373a8
ARG POSTGRES=$POSTGRES_18

FROM postgres:${POSTGRES} AS build
ENV CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache
# Server headers match the base image exactly. Debian's Eigen, since RDKit otherwise
# clones it from gitlab.com, which fails under load (3.4.0; 2024_09 would fetch 3.3.9).
RUN apt-get update && apt-get install -y --no-install-recommends \
      "postgresql-server-dev-$PG_MAJOR=$PG_VERSION" \
      ca-certificates ccache cmake g++ git libboost-all-dev libeigen3-dev libfreetype-dev make
# Args only after the shared layers: a changed ARG invalidates every later RUN.
ARG RDKIT
RUN git clone --depth 1 --branch "Release_${RDKIT%@*}" https://github.com/rdkit/rdkit /rdkit \
 && test "$(git -C /rdkit rev-parse HEAD)" = "${RDKIT#*@}"
WORKDIR /rdkit
RUN --mount=type=cache,target=/root/.cache/ccache \
    pg="/usr/lib/postgresql/$PG_MAJOR/bin/pg_config" \
 && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DRDK_BUILD_PGSQL=ON -DRDK_BUILD_INCHI_SUPPORT=ON \
      -DRDK_BUILD_CPP_TESTS=OFF -DRDK_BUILD_PYTHON_WRAPPERS=OFF -DRDK_INSTALL_COMIC_FONTS=OFF \
      -DRDK_BUILD_COORDGEN_SUPPORT=OFF -DRDK_BUILD_MAEPARSER_SUPPORT=OFF -DRDK_BUILD_CHEMDRAW_SUPPORT=OFF \
      -DPostgreSQL_CONFIG_DIR="$(dirname "$pg")" \
      -DPostgreSQL_INCLUDE_DIR="$("$pg" --includedir)" \
      -DPostgreSQL_TYPE_INCLUDE_DIR="$("$pg" --includedir-server)" \
      -DPostgreSQL_LIBRARY_DIR="$("$pg" --libdir)" \
 && ccache -z && cmake --build build -j"$(nproc)" --target rdkit && ccache -s
COPY costs.sql /
# See costs.sql. Empty for upstream's extension SQL as released (-unpatched images).
ARG PATCH_COSTS=1
RUN f=build/Code/PgSQL/rdkit/update_sql/rdkit--4.7.0--4.8.0.sql \
 && if [ -n "$PATCH_COSTS" ] && [ -f "$f" ]; then \
      sed -i '/^ALTER FUNCTION .* COST 100;$/d' "$f" && cat /costs.sql >> "$f"; fi \
 && DESTDIR=/cartridge sh -e build/Code/PgSQL/rdkit/pgsql_install.sh \
 && ldd "/cartridge/usr/lib/postgresql/$PG_MAJOR/lib/rdkit.so" | awk '/=> \//{print $3}' \
      | xargs readlink -f | xargs dpkg -S | cut -d: -f1 | sort -u > /cartridge/rdkit-runtime-packages

# Upstream SQL regression suite; prod bind-mounts this stage, so it must pass first.
FROM build AS regress
RUN cp -a /cartridge/. / && chown -R postgres build/Code/PgSQL/rdkit
USER postgres
RUN initdb -D /tmp/db >/dev/null && pg_ctl -D /tmp/db -l /tmp/db.log -w start \
 && cd build/Code/PgSQL/rdkit && { sh pgsql_regress.sh || { cat regression.diffs; exit 1; }; }

FROM postgres:${POSTGRES}
COPY --from=build /cartridge /
RUN --mount=from=regress,target=/regress \
    apt-get update && xargs -a /rdkit-runtime-packages apt-get install -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* /rdkit-runtime-packages \
 && ! ldd "/usr/lib/postgresql/$PG_MAJOR/lib/rdkit.so" | grep 'not found'
