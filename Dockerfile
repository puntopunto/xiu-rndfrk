# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------
#
# # XIU stream/restream server
#
# ###### Test image
#
# ------------------------------------------------------------------------------
## 1. Pre-flight setting

# Global args
ARG tz="Europe/Moscow"
ARG base_tz="Africa/Niamey"
ARG uid="10001"
ARG user="appuser"

# Base image args
ARG base_platform="linux/amd64"
ARG base_platform_version="latest"

# ------------------------------------------------------------------------------
## 2. Setting up base seetings

### Base
FROM --platform=${base_platform} alpine:${base_platform_version} AS base

### Args
# TODO: check glob args
# ARG tz # Or 'base_tz'?
# ARG uid
# ARG user

### Base setup
RUN apk --update-cache upgrade --no-cache `
    && apk cache sync `
    && apk add "alpine-conf" `
    && setup-timezone -i ${base_tz} `
    && apk del "alpine-conf" `
    && apk cache clean `
    && rm -rf "/var/cache/apk" "/etc/apk/cache"
RUN addgroup -g "101" "appusers"
RUN adduser `
        -u ${uid} `
        -g "Special no-login user for app." `
        -s "/sbin/nologin" `
        -h "/nonexistent" `
        -H `
        -D `
        -S `
        ${user};

ONBUILD WORKDIR ${app_dir}

# ------------------------------------------------------------------------------
## 3. Settings up build tools

### Toolset
FROM base AS toolset

### Args
# Toolchain and deps
ARG rustup_init_url="https://sh.rustup.rs"
ARG dev_packages='`
    openssl-dev `
    pkgconf `
    musl-dev `
    gcc `
    make'
ARG apk_cache_dirs='`
    /var/cache/apk `
    /etc/apk/cache'

### Get tools
RUN apk cache sync && apk update && apk upgrade;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache_dirs};

# ------------------------------------------------------------------------------
## 4. Build app

### Builder
FROM toolset as builder

### Args
# Dirs
ARG buildroot="/build"
ARG source_dir="${buildroot}/source"
ARG rustup_init="${buildroot}/source/ci/scripts/common/rustup-init.sh"
ARG target_dir="${buildroot}/target/release"

# Build env rustup arg
ARG RUSTUP_HOME
ARG RUSTUP_TOOLCHAIN 
ARG RUSTUP_DIST_SERVER
ARG RUSTUP_DIST_ROOT
ARG RUSTUP_UPDATE_ROOT
ARG RUSTUP_IO_THREADS 
ARG RUSTUP_TRACE_DIR
ARG RUSTUP_UNPACK_RAM
ARG RUSTUP_NO_BACKTRACE
ARG RUSTUP_PERMIT_COPY_RENAME

### Switch user for sec reasons
USER ${appuser}

### Get rustup-init from internet and install toolchain
# TODO: switch to local
RUN wget --quiet --output-document --secure-protocol=TLSv1_2 - `
    ${rustup_init_url} `
    | sh -s -- `
        --quiet `
        -y `
        --default-host "x86_64-unknown-linux-musl" `
        --default-toolchain "stable-x86_64-unknown-linux-musl" `
        --profile "minimal" `
        --component "cargo";

### Copy source
WORKDIR ${source_dir}
COPY . .

### Launch local rustup-init'
# TODO: auto-update 'rustup-init'
RUN ${rustup_init}

# Build app
RUN rustup self update;
RUN rustup update;
RUN make local;
RUN make build;

# ------------------------------------------------------------------------------
#### 3. Run app

FROM base AS runner

# Install app
ARG target_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"
ARG user="appuser"

# Port settings
ARG http_port=80
ARG httpudp_port="80/udp"
ARG https_port=443
ARG rtmp_port=1935
ARG rtmpudp_port="1935/udp"
ARG api_port=8000
ARG apiudp_port="8000/udp"


# Healthcheck args
ARG statuscheck_addr="8.8.8.8"
ARG statuscheck_count=4
# TODO: var precedence and inheritance test.
ARG hc_success_code=0
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
EXPOSE ${http_port}
EXPOSE ${httpudp_port}
EXPOSE ${https_port}
EXPOSE ${rtmp_port}
EXPOSE ${rtmpudp_port}
EXPOSE ${api_port}
EXPOSE ${apiudp_port}

# Set health-check
# TODO: check 'HEALTHCHECK' args is usable with vars.
HEALTHCHECK --interval=5m --timeout=10s --start-period=5s --retries=3 `
    # TODO: pipe status code and message output.
    CMD ping ${statuscheck_addr} -c ${statuscheck_count} `
        && exit(hc_success_code) `
        || exit ${hc_err_code};

# Start app in exec mode
ENTRYPOINT [ ${app} ]
