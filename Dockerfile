# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------

# XIU stream/restream server

# ~ Test image

## TODO: improve header (add info, pic, etc.) and add more 'MD' formatting.

# ------------------------------------------------------------------------------
# ! README

# TODO: readme.

# ------------------------------------------------------------------------------
## Pre-build setting
# ### Global args
# TODO: check if it works.
# #### Date and time
# ARG timezone="Africa/Nairobi"

# ------------------------------------------------------------------------------

## 1. Base
FROM rust:alpine AS base

### Args
#### Groups and users settings (only 1 for now)
ARG user_gecos="Special no-login user for app"
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Builder env
ARG timezone="Europe/Moscow"

### Base setup
# TODO: check for smaller layers qty, if possible.
RUN <<EOF
# Package manager settings
export alias apkq="apk --quiet --no-interactive --no-progress --no-cache";

# Install base packs
apkq upgrade --latest;
apkq add --latest "alpine-conf";

# Sys settings
setup-timezone -i "${timezone}";

# Remove unnecessary packs and delete cache
apk del "alpine-conf";
apk cache clean;
rm -rf "/var/cache/apk" "/etc/apk/cache";
EOF

# ------------------------------------------------------------------------------

## 2. Building
# ```text
# Additional env vars for 'rustup' and 'cargo build' can be added as "ARG's".
# ```
# TODO: switch to net install? Git 'clone' or copy source / mount volume?
FROM base AS builder

### Args
#### Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# TODO: check if arg is need by something external.
# ARG dependencies='"openssl-dev" "pkgconf" "musl-dev" "gcc" "make"'

#### Dirs
##### Builder
ARG buildroot="build"

#### Apps and configs (no roots)
ARG config_volume="/app_config"
ARG source_config_dir="./ci/config"

#### Source files permissions
ARG buildroot_perms="750+x"

#### App build stage users/groups
ARG build_user="builder"
ARG build_group="builders"

### Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
# ARG RUSTUP_TOOLCHAIN="stable-x86_64-unknown-linux-musl"

#### Cargo build env
ARG CARGO_BUILD_TARGET="x86_64-unknown-linux-musl"
ARG CARGO_MANIFEST_DIR=.
ARG CARGO_TARGET_TMPDIR "temp"
ARG CARGO_BUILD_TARGET_DIR="target"
ARG OUT_DIR "release"

### Setup toolchain
# TODO: check dev packs.
RUN <<EOF
# Package manager settings
export alias apkq="apk --quiet --no-interactive --no-progress --no-cache";

# Install build packs
apkq upgrade --latest;
apkq add --latest "openssl-dev" "make" "gcc" "musl-dev";
apk cache clean && rm -rf "/var/cache/apk" "/etc/apk/cache";
rustup update "stable";

# Build user creation
addgroup -S ${build_group};
adduser -G "${build_group}" -D -S "${build_user}";

# end
EOF

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
# Tis is test file, ignoring image version linter warning.
# hadolint ignore=DL3007
FROM alpine:latest AS runner
# FROM base as runner

### Args
#### Dirs
##### From previous stages
ARG distribution="/build/target/release"

##### Apps and configs
ARG app_dir="/app"
ARG config_volume="/app/config"

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
ARG app_exec_perms="750+x"

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
ENV APP=${app}
ENV APP_CONFIG="${config_volume}/config.toml"

### CWD
WORKDIR ${app_dir}

### Install app
VOLUME [ ${config_volume} ]
COPY    --from=builder `
        --chown="${app_owner}:${appgroup}" `
        --chmod=${app_dir_perms} `
             "${distribution}/${app}", `
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
