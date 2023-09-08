# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------

# XIU stream/restream server

# ~ Test image

## TODO: improve header (add info, pic, etc.) and add more 'MD' formatting.

# ------------------------------------------------------------------------------
# ! README

# TODO: readme.
# ______________________________________________________________________________
# ------------------------------------------------------------------------------
## Global args
ARG builder_version="latest"
ARG runner_version="latest"

# ------------------------------------------------------------------------------

## 1. Base
FROM rust:${builder_version} AS base

### Args
#### User and group settings
ARG appuser="appuser"
ARG appgroup="appusers"
ARG user_gecos="Special no-login user for app"
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Builder env
ARG timezone="Europe/Moscow"

### Base setup
# TODO: check for smaller layers qty, if possible.
# Set alias for package manager
# Install sysconf
# Setup timezone
# Remove unnecessary packs and delete cache
RUN apkq="apk --quiet --no-interactive --no-progress --no-cache"; `
    $apkq upgrade --latest; `
    $apkq add --latest "alpine-conf"; `
    setup-timezone -i "${timezone}"; `
    $apkq del "alpine-conf"; `
    $apkq cache clean && rm -rf "/var/cache/apk" "/etc/apk/cache";

### Post-build steps
# Add app user and group
ONBUILD RUN addgroup -S "${appgroup}"; `
        adduser -G "${appgroup}" `
        -g "${user_gecos}" `
        -s "${user_shell}" `
        -h "${user_home}" `
        -H `
        -D `
        -S `
        "${appuser}";

# ------------------------------------------------------------------------------

## 2. Building
# Additional env vars for 'rustup' and 'cargo build' can be added as "ARG's".
# TODO: switch to net install? Git 'clone' or copy source / mount volume?
FROM base AS builder

### Args
#### Dirs
##### Builder
ARG buildroot="build"

##### Apps and configs (no roots)
ARG config_volume="/app_config"
ARG source_config_dir="./ci/config"

#### Source files permissions
# TODO: check if need.
# ARG buildroot_perms="750"

#### App build stage users/groups
ARG build_user="builder"
ARG build_group="builders"

#### Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
ARG RUSTUP_TOOLCHAIN="stable-x86_64-unknown-linux-musl"

#### Cargo build env
ARG CARGO_BUILD_TARGET="x86_64-unknown-linux-musl"
ARG CARGO_MANIFEST_DIR=.
ARG CARGO_TARGET_TMPDIR "temp"
ARG CARGO_BUILD_TARGET_DIR="target"
ARG OUT_DIR "release"

### Setup toolchain
# TODO: check dev packs.
# Set alias for package manager
# Install build packs
# Create build user
RUN apkq="apk --quiet --no-interactive --no-progress --no-cache"; `
    $apkq upgrade --latest; `
    $apkq add --latest "openssl-dev" "make" "gcc" "musl-dev"; `
    $apkq cache clean && rm -rf "/var/cache/apk" "/etc/apk/cache"; `
    rustup update "stable"; `
    addgroup -S ${build_group}; `
    adduser -G "${build_group}" -D -S "${build_user}";

#### Building
##### CWD and switch user
USER ${build_user}
WORKDIR ${buildroot}

##### Copying sources
# TODO: check if this need if run/build from git.
# COPY --chown=${build_user}:${build_group} --chmod=${buildroot_perms} . .

# Building
RUN make local && make build;
# Additional flags: "--quiet" "--release"

### After-build steps.
#### Copy default config files to shared volume
VOLUME ${config_volume}
COPY ${source_config_dir} ${config_volume}

# ------------------------------------------------------------------------------

## 3. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.
FROM alpine:${runner_version} AS runner
# FROM base as runner

### Args
#### Dirs
##### From previous stages
ARG distribution="/build/target/release"

##### Apps and configs
ARG app_dir="/app"
ARG app_config="/app/config/config.toml"

#### Apps
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

#### Users/groups
##### Apps user 
ARG appuser="appuser"
ARG appgroup="appusers"

##### Apps owner
ARG app_owner="root"

##### Apps permission
# TODO: check exec permissions
ARG app_dir_perms=750
ARG app_bin_perms="750+x"

#### Healthcheck
ARG prober="ping"
ARG probe_addr="8.8.8.8"
ARG probe_count=5
ARG probe_deadline=10
ARG probe_timeout=15

#### Main workload env
ENV TZ=${timezone}
# TODO: check other bins and full/short PATH with 'healthcheck'.
# ENV PATH="${app_dir}:$PATH"
ENV PATH=${app_dir}
ENV APP="xiu"
ENV APP_CONFIG=${app_config}

### CWD
WORKDIR ${app_dir}

### Install app
VOLUME "/app/config"
COPY    --from=builder `
        --chown="${app_owner}:${appgroup}" `
        --chmod=${app_dir_perms} `
                "${distribution}/${APP}", `
                "${distribution}/${web_server}", `
                "${distribution}/${pprtmp_server}" `
                        ./

### Ports
EXPOSE 80
EXPOSE 80/udp
EXPOSE 443
EXPOSE 1935
EXPOSE 1935/udp
EXPOSE 8000
EXPOSE 8000/udp

## Health-check
# TODO: check 'HEALTHCHECK' args is usable with vars.
HEALTHCHECK --interval=5m --timeout=30s --start-period=5s --retries=3 `
    # TODO: pipe status code and message output.
    CMD ${prober} `
            -q `
            -c ${probe_count} `
            -W ${probe_timeout} `
            -w ${probe_deadline} `
                ${probe_addr}; `
        exit "$?";

### Switch user and start app
USER ${appuser}

# hadolint ignore=DL3025
ENTRYPOINT [ ${APP} ]

# hadolint ignore=DL3025
CMD  [ "-c", ${APP_CONFIG} ]
