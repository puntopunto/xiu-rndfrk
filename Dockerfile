# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------
#
# # XIU stream/restream server
#
# Test image
# ---
# # TODO: improve header (add info, pic, etc.) and add more 'MD' formatting.
#
# ------------------------------------------------------------------------------
# ## README
#
# TODO: readme.
#
# ------------------------------------------------------------------------------
## Pre-build setting
# ### Global args
# TODO: check if it works.
# # - Date and time
# ARG tz="Europe/Moscow"

### Setup build stages
# - Base platform args
ARG bp_arch="linux/amd64"
ARG bp_platform="rust"
ARG bp_version="alpine"

# - Run platform args
ARG rp_arch="linux/amd64"
ARG rp_platform="alpine"
ARG rp_version="latest"

# ------------------------------------------------------------------------------

## 1. Base image
# hadolint ignore=DL3029
FROM --platform=${bp_arch} ${bp_platform}:${bp_version} AS base

### Args
#### System-related
# - 'pack_1' - sysconf pack with 'tzdata'
ARG app_pack_1="alpine-conf"

# - Default app user/group
ARG user="appuser"
ARG users="appusers"

# - Dirs
# Package manager cache
ARG pm_cache_1="/var/cache/apk"
ARG pm_cache_2="/etc/apk/cache"

#### Groups and users settings (only 1 for now)
ARG user_gecos="Special no-login user for app"
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Builder env
ARG tz="Europe/Moscow"

### Base setup
# TODO: check for smaller layers qty, if possible.
# hadolint ignore=DL3018
RUN apk --quiet --no-interactive --no-progress --no-cache `
        upgrade --latest; `
    apk --quiet --no-interactive --no-progress --no-cache `
        add --latest "${app_pack_1}";
RUN setup-timezone -i "${tz}";
RUN apk cache clean && rm -rf "${pm_cache_1}" "${pm_cache_2}";

#### Necessary after-build steps
# TODO: check 'addgroup' utility reasons for use.
# hadolint ignore=SC2154
ONBUILD RUN adduser `
    -G "${users}" `
    -g "${user_gecos}" `
    -s "${user_shell}" `
    -h "${user_home}" `
    -H `
    -D `
    -S `
    "${user}";

# ------------------------------------------------------------------------------

## 2. Building
# - Additional env vars for 'rustup' and 'cargo build' can be added as 'ARGs'. 
# TODO: switch to net install? Git 'clone' or copy source / mount volume?
### Toolset image
FROM base AS builder

### Args
# - Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# TODO: check all dev deps packs invariants.
# ARG dev_packages='openssl-dev pkgconf musl-dev gcc make'
# ARG dev_packages='pkgconf musl-dev gcc make'

# - Dirs
# Package manager cache cache
ARG pm_cache_1="/var/cache/apk"
ARG pm_cache_2="/etc/apk/cache"

# Builder
ARG buildroot="build"

# Apps and configs (no roots)
ARG app_dir="app"
ARG ci_dir="ci"
ARG config_path="config"

# - Source files permissions
ARG buildroot_perms=750

# - App build stage users/groups
ARG build_user="builder"
ARG build_group="builders"

# - Source repo
ARG repo="."

# - Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
ARG RUSTUP_TOOLCHAIN="x86_64-unknown-linux-musl"

# - Cargo build env
# No roots in dirs.
ARG CARGO_MANIFEST_DIR="."
ARG CARGO_BUILD_TARGET="x86_64-unknown-linux-musl"
ARG CARGO_BUILD_TARGET_DIR="target"
ARG OUT_DIR "release"
ARG CARGO_TARGET_TMPDIR "temp"

#### Get tools
# TODO: check dev packs.
# hadolint ignore=DL3018,SC2154
RUN apk --quiet --no-interactive --no-progress --no-cache `
        upgrade --latest; `
    # apk --quiet --no-interactive --no-progress --no-cache `
    #     add "${dev_packages}"; `
    apk cache clean && rm -rf "${pm_cache_1}" "${pm_cache_2}";

#### Building
# CWD and switch user
WORKDIR ${buildroot}
USER ${build_user}

# - Copying sources from local root
COPY --chown=${build_user}:${build_group} --chmod=${buildroot_perms} ${repo} .
RUN make local && make build;
# Additional flags: "--quiet" "--release"

#### After-build steps.
# Copy default config to volume
ONBUILD COPY "${ci_dir}/${config_path}" "/${app_dir}/"

# ------------------------------------------------------------------------------

## 3. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.

### Runner image
# hadolint ignore=DL3029
FROM --platform=${rp_arch} ${rp_platform}:${rp_version} AS runner

#### Args
# - Dirs
# From stages
ARG distribution="/build/target/release"

# Apps path (local, no roots)
ARG app_dir="app"
ARG config_path="config"
ARG config="config.toml"

# Apps
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

# - Users/groups
# Apps user 
ARG user="appuser"
ARG users="appusers"

# Apps owner
ARG app_owner="root"

# - App files permission
ARG app_perms=750

# - Healthcheck
ARG prober="ping"
ARG probe_addr="8.8.8.8"
ARG probe_count=5
ARG probe_deadline=10
ARG probe_timeout=15

#### Main workload env
ENV TZ=${tz}
# TODO: check other bins and full/short PATH with 'healthcheck'.
# ENV PATH="${app_dir}:$PATH"
ENV PATH=${app_dir}
ENV APP=${app}
ENV APP_CONFIG="${app_dir}/${config_path}/${config}"

#### CWD
WORKDIR ${app_dir}

### Install app
VOLUME [ "/${app_dir}/${config_path}" ]
COPY    --from=builder `
        --chown="${app_owner}:${users}" `
        --chmod=${app_perms} `
             "${distribution}/${app}", `
             "${distribution}/${web_server}", `
             "${distribution}/${pprtmp_server}" `
                ./

#### Ports
EXPOSE 80
EXPOSE 80/udp
EXPOSE 443
EXPOSE 1935
EXPOSE 1935/udp
EXPOSE 8000
EXPOSE 8000/udp

#### Health-check
# TODO: check 'HEALTHCHECK' args is usable with vars.
# HEALTHCHECK --interval=5m --timeout=30s --start-period=5s --retries=3 `
#     # TODO: pipe status code and message output.
#     CMD ${prober} `
#             -q `
#             -c ${probe_count} `
#             -W ${probe_timeout} `
#             -w ${probe_deadline} `
#                 ${probe_addr}; `
#         exit "$?";

#### Switch user and start app
USER ${user}

# hadolint ignore=DL3025
ENTRYPOINT [ ${APP} ]

# - Args for default start
# hadolint ignore=DL3025
CMD  [ "-c", ${APP_CONFIG} ]
