# syntax=docker/dockerfile:1
# escape=`

# XIU stream/restream server
# Test image

# Base image args
ARG platform="linux/amd64"
ARG version="latest"

# ---

# 1. Base image
FROM --platform=${platform} alpine:${version} AS base

# Local args
ARG tz="Africa/Niamey"
ARG uid="10001"
ARG user="appuser"

# Base setup
RUN apk cache sync `
    && apk --update-cache upgrade --no-cache `
    && apk add "alpine-conf" `
    && setup-timezone -i ${tz} `
    && apk del "alpine-conf" `
    && apk cache clean `
    && rm -rf "/var/cache/apk" "/etc/apk/cache" `
    && `
    && adduser `
    --uid ${uid} `
    --gecos "Special no-login user for app." `
    --shell "/sbin/nologin" `
    --home "/nonexistent" `
    --no-create-home `
    --disabled-password `
    ${user};

# ---

# 2. Build app
FROM base AS builder

# App build args
ARG buildroot="/build"
ARG cargoroot="/root/.cargo/bin"
ARG user="appuser"

# App and deps sources
ARG rustup_init_url="https://sh.rustup.rs"
ARG source_url="https://github.com/puntopunto/xiu-rndfrk.git"
ARG source_branch="ci"
ARG source_dir="${buildroot}/xiu-rndfrk"

# Workdir
WORKDIR "${buildroot}"

# Get deps and toolchain
RUN apk cache sync && apk update && apk upgrade;
RUN apk add `
    "openssl-dev" "pkgconf" "git" "musl-dev" "gcc" "make";
RUN apk cache clean && rm -rf "/var/cache/apk" "/etc/apk/cache";
USER ${appuser}
RUN wget --quiet --output-document - ${rustup_init_url} | sh -s -- `
    --quiet `
    -y `
    --default-toolchain "stable-x86_64-unknown-linux-musl" `
    --default-host "x86_64-unknown-linux-musl" `
    --profile "minimal" `
    --component "cargo";

# Copying source
COPY . .

# Build app
RUN rustup self update
RUN rustup update
RUN make local
RUN make build

# ---

# 3. Run app
FROM base AS runner

# Image build settings
ARG target: "/build/xiu-rndfrk/_tgt/x86_64-unknown-linux-musl/release"
ARG appdir="/app"
ARG app="xiu"
ARG web="http-server"
ARG pprtmp="pprtmp"
ARG user="appuser"

# Network args
ARG p_http=80
ARG p_httpudp=80/udp
ARG p_https=443
ARG p_rtmp=1935
ARG p_rtmpudp=1935/udp
ARG p_api=8000
ARG p_apiudp=8000/udp

# Healthcheck args
ARG statuscheck_addr="8.8.8.8"
ARG statuscheck_count=5
ARG c_exit_code=101

# CWD
WORKDIR "${appdir}"

# Copy app
COPY --link --from=builder  "${target}/${app}", `
                            "${target}/${web}", `
                            "${target}/${pprtmp}" `
                                                    ./

# Switch user
USER ${user}

# Ports
EXPOSE ${p_http}
EXPOSE ${p_httpudp}
EXPOSE ${p_https}
EXPOSE ${p_rtmp}
EXPOSE ${p_rtmpudp}
EXPOSE ${p_api}
EXPOSE ${p_api}

# Set health-check
HEALTHCHECK --interval=5m --timeout=10s --start-period=5s --retries=3 `
    CMD ping ${statuscheck_addr} -c ${statuscheck_count} `
        || exit ${c_exit_code}

# Start app in exec mode
ENTRYPOINT [ ${app} ]
