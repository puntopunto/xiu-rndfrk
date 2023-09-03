# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------
#
# XIU stream/restream server
#
# ~ Test image
# ---
#
# TODO: improve header (add info, pic, etc.) and add more 'MD' formatting.
#
# ------------------------------------------------------------------------------
# ! README
#
# TODO: readme.
#
# ------------------------------------------------------------------------------
## Pre-build setting
# ### Global args
# TODO: check if it works.
# #### Date and time
# ARG timezone="Europe/Moscow"

### Setup build stages
#### Base platform args
ARG bp_arch="linux/amd64"
ARG bp_platform="rust"
ARG bp_version="alpine"

#### Run platform args
ARG rp_arch="linux/amd64"
ARG rp_platform="alpine"
ARG rp_version="latest"

# ------------------------------------------------------------------------------

## 1. Base
# hadolint ignore=DL3029
FROM --platform=${bp_arch} ${bp_platform}:${bp_version} AS base

### Args
#### System-related packs
ARG app_pack_1="alpine-conf"

#### Default app user/group
ARG appuser="appuser"
ARG appgroup="appgroup"

#### Dirs
##### Package manager cache
ARG pm_cache_1="/var/cache/apk"
ARG pm_cache_2="/etc/apk/cache"

#### Groups and users settings (only 1 for now)
ARG user_gecos="Special no-login user for app"
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Builder env
ARG timezone="Europe/Moscow"

### Base setup
# TODO: check for smaller layers qty, if possible.
# hadolint ignore=DL3018
RUN <<EOF
# Package manager settings
alias pkgman="apk --quiet --no-interactive --no-progress --no-cache";

# Install base packs
pkgman upgrade --latest;
pkgman add --latest "${app_pack_1}";

# Sys settings
setup-timezone -i "${timezone}";

# Remove unnecessary packs and delete cache
apk del "${app_pack_1}";
apk cache clean;
rm -rf "${pm_cache_1}" "${pm_cache_2}";

# Create app user
addgroup -S ${appgroup};
adduser -G "${appgroup}" \
        -g "${user_gecos}" \
        -s "${user_shell}" \
        -h "${user_home}" \
        -H \
        -D \
        -S \
        "${appuser}";
EOF

# ------------------------------------------------------------------------------

## 2. Building
# Additional env vars for 'rustup' and 'cargo build' scripts can be
# added as 'ARGs'. 
# TODO: switch to net install? Git 'clone' or copy source / mount volume?
FROM base AS builder

### Args
#### Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# TODO: check all dev deps packs invariants.
ARG dev_dep_01="openssl-dev"
# ARG dev_dep_02="pkgconf"
# ARG dev_dep_03="musl-dev"
ARG dev_dep_04="gcc"
ARG dev_dep_05="make"

#### Dirs
##### Package manager cache cache
ARG pm_cache_1="/var/cache/apk"
ARG pm_cache_2="/etc/apk/cache"

##### Builder (no roots)
ARG buildroot="build"

#### Apps and configs (no roots)
ARG app_dir="app"
ARG ci_dir="ci"
ARG config_dir="config"

#### Source files permissions
# ARG buildroot_perms=750

#### App build stage users/groups
ARG build_user="builder"
ARG build_group="builders"

#### Source repo
ARG repo="."

### Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
# ARG RUSTUP_TOOLCHAIN="stable-x86_64-unknown-linux-musl"

#### Cargo build env
# TODO: check can be safely remove from here.
# ARG CARGO_MANIFEST_DIR="."
# ARG CARGO_BUILD_TARGET="x86_64-unknown-linux-musl"
ARG CARGO_BUILD_TARGET_DIR="target"
ARG OUT_DIR "release"
ARG CARGO_TARGET_TMPDIR "temp"

### Get tools
# TODO: check dev packs.
RUN <<EOF
alias pkgman="apk --quiet --no-interactive --no-progress --no-cache";
pkgman upgrade --latest;
pkgman add "${dev_dep_01}" "${dev_dep_04}";
apk cache clean && rm -rf "${pm_cache_1}" "${pm_cache_2}";
rustup update "stable";
EOF

#### Build user creation
RUN <<EOF
addgroup -S ${build_group};
adduser -G "${build_group}" -D -S "${build_user}";
EOF

#### Building
##### CWD and switch user
USER ${build_user}
WORKDIR ${buildroot}

##### Copying sources from local root
COPY --chown=${build_user}:${build_group} --chmod=${buildroot_perms} ${repo} .
# COPY ${repo} .
RUN make local && make build;
# Additional flags: "--quiet" "--release"

### After-build steps.
#### Copy default config folder to shared volume
VOLUME "/${app_dir}/${config_dir}"
COPY "${ci_dir}/${config_dir}" "/${app_dir}"

# ------------------------------------------------------------------------------

## 3. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.
# hadolint ignore=DL3029
# FROM --platform=${rp_arch} ${rp_platform}:${rp_version} AS runner
FROM base as runner

### Args
#### Dirs
##### From previous stages
ARG distribution="/build/target/release"

##### Apps and configs (local, no roots)
ARG app_dir="app"
ARG config_dir="config"
ARG config="config.toml"

#### Apps
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

#### Users/groups
##### Apps user 
ARG user="appuser"
ARG appgroup="appusers"

##### Apps owner
ARG app_owner="root"

##### Apps permission
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
ENV APP_CONFIG="${app_dir}/${config_dir}/${config}"

### CWD
WORKDIR ${app_dir}

### Install app
VOLUME [ "/${app_dir}/${config_dir}" ]
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

### Health-check
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

### Switch user and start app
USER ${user}

# hadolint ignore=DL3025
ENTRYPOINT [ ${APP} ]

# hadolint ignore=DL3025
CMD  [ "-c", ${APP_CONFIG} ]
