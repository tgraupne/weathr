# syntax=docker/dockerfile:1

############################
# 1) Build static binary (musl)
############################
FROM rust:1-bookworm AS build
WORKDIR /src

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates musl-tools \
  && rm -rf /var/lib/apt/lists/*

RUN rustup target add x86_64-unknown-linux-musl

ARG WEATHR_REF=v1.3.0

RUN git clone https://github.com/Veirt/weathr.git . \
 && git checkout "${WEATHR_REF}"

ENV RUSTFLAGS="-C opt-level=z -C lto=fat -C codegen-units=1 -C panic=abort -C strip=symbols"

RUN cargo build --release --target x86_64-unknown-linux-musl

############################
# 2) Generate config at build time (with build args)
############################
FROM debian:bookworm-slim AS cfg

ARG GEO_AUTO=false
ARG GEO_LATITUDE=48.137154
ARG GEO_LONGITUDE=11.576124
ARG GEO_HIDE=false

ARG HIDE_HUD=false
ARG SILENT=false

ARG UNIT_TEMPERATURE=celsius
ARG UNIT_WIND_SPEED=kmh
ARG UNIT_PRECIPITATION=mm

RUN mkdir -p /out/weathr && \
    cat > /out/weathr/config.toml <<EOF
hide_hud = ${HIDE_HUD}
silent = ${SILENT}

[location]
auto = ${GEO_AUTO}
latitude = ${GEO_LATITUDE}
longitude = ${GEO_LONGITUDE}
hide = ${GEO_HIDE}

[units]
temperature = "${UNIT_TEMPERATURE}"
wind_speed = "${UNIT_WIND_SPEED}"
precipitation = "${UNIT_PRECIPITATION}"
EOF

############################
# 3) Grab CA certificates bundle
############################
FROM debian:bookworm-slim AS certs
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

############################
# 4) Runtime: scratch + CA bundle copied in
############################
FROM scratch

ENV XDG_CONFIG_HOME=/config

COPY --from=build /src/target/x86_64-unknown-linux-musl/release/weathr /weathr
COPY --from=cfg /out/weathr/config.toml /config/weathr/config.toml

# Critical for HTTPS / request
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["/weathr"]
