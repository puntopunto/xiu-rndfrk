# syntax=docker/dockerfile:1
# escape=`

# XIU stream/restream server
# Test image

# Base image args
ARG platform="linux/amd64"
ARG platform_version="latest"

# ------------------------------------------------------------------------------

# 1. Base image
FROM --platform=${platform} alpine:${platform_version} AS base

# Local args
ARG tz="Africa/Niamey"
ARG uid="10001"
ARG user="appuser"

# Base setup
RUN apk --update-cache upgrade --no-cache `
    && apk cache sync `
    && apk add "alpine-conf" `
    && setup-timezone -i ${tz} `
    && apk del "alpine-conf" `
    && apk cache clean `
    && rm -rf "/var/cache/apk" "/etc/apk/cache" `
    && addgroup -g "101" "appusers" `
    && adduser `
        -u "101" `
        -g "Special user for app debug and test" `
        -G "appusers" `
        "appuser" `
    && adduser `
        -u ${uid} `
        -g "Special no-login user for app." `
        -s "/sbin/nologin" `
        -h "/nonexistent" `
        -H `
        -D `
        -S `
        ${user}

# ------------------------------------------------------------------------------

# 2. Build app
FROM base AS builder

# App and deps sources
ARG rustup_init_url="https://sh.rustup.rs"
ARG dev_packages=[ "openssl-dev", "pkgconf", "musl-dev", "gcc", "make" ]
ARG apk_cache_dirs=[ "/var/cache/apk", "/etc/apk/cache" ]

# Dirs
ARG source_dir="/build/source"
ARG release_dir="/build/target/release"
ARG user="appuser"

# Get deps and toolchain
RUN apk cache sync && apk update && apk upgrade;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache_dirs};

# Switch user for sec reasons
USER ${appuser}

RUN wget --quiet --output-document - ${rustup_init_url} | sh -s -- `
    --quiet `
    -y `
    --default-host "x86_64-unknown-linux-musl" `
    --default-toolchain "stable-x86_64-unknown-linux-musl" `
    --profile "minimal" `
    --component "cargo";

# Copying source
WORKDIR ${source_dir}
COPY . ${source_dir}

# Build app
RUN rustup self update
RUN rustup update
RUN make local
RUN make build

# ------------------------------------------------------------------------------

# 3. Run app
FROM base AS runner

# Image build settings
ARG release_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"
ARG user="appuser"

# Healthcheck args
ARG statuscheck_addr="8.8.8.8"
ARG statuscheck_count=4

# TODO: var precedence and inheritance test 
ARG hc_success_code = 0
ARG hc_err_code=101


# CWD
WORKDIR "${app_dir}"

# Copy app
COPY --link --from=builder `
    "${target}/${app}", `
    "${target}/${web_server}", `
    "${target}/${pprtmp_server}" `
        ./

# Switch user
USER ${user}

# Ports
EXPOSE 80
EXPOSE 80/udp
EXPOSE 443
EXPOSE 1935
EXPOSE 1935/udp
EXPOSE 8000
EXPOSE 8000/udp

# Set health-check
# TODO: check 'HEALTHCHECK' args is usable with vars.
HEALTHCHECK --interval=5m --timeout=10s --start-period=5s --retries=3 `
    # TODO: pipe status code and message output.
    CMD ping ${statuscheck_addr} -c ${statuscheck_count} `
        && exit(hc_success_code) `
        || exit ${hc_err_code}

# Start app in exec mode
ENTRYPOINT [ ${app} ]
