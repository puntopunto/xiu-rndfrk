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
### Global args
# - Date and time
ARG tz="Europe/Moscow"

### Setup build stages
# - Base platform args
ARG bp_arch="linux/amd64"
ARG bp_platform="alpine"
ARG bp_version="latest"

# - Run platform args
ARG rp_arch="linux/amd64"
ARG rp_platform="alpine"
ARG rp_version="latest"

# ------------------------------------------------------------------------------

## 1. Base image
# TODO: select 'ONBUILD' invariants.
# hadolint ignore=DL3029
FROM --platform=${bp_arch} ${bp_platform}:${bp_version} AS base

### Args
#### System-related
# - 'pack_1' - sysconf pack with 'tzdata'
ARG pack_1="alpine-conf"

# - Default app user/group
ARG user="appuser"
ARG users="appusers"

# - Packages cache
ARG apk_cache_1="/var/cache/apk"
ARG apk_cache_2="/etc/apk/cache"

#### Groups and users settings (only 1 for now)
ARG user_gecos="Special no-login user for app"
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Builder env
ARG tz="Europe/Moscow"

### Base setup
# TODO: check for  smaller layers qty, if possible.
# hadolint ignore=DL3018
RUN apk --quiet --no-interactive --no-progress --no-cache `
        upgrade --latest; `
    apk --quiet --no-interactive --no-progress --no-cache `
        add --latest "${pack_1}";
RUN setup-timezone -i "${tz}";
RUN apk cache clean && rm -rf "${apk_cache_1}" "${apk_cache_2}";

#### App user for next stages.
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
FROM base AS build

### Args
# - Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# ARG dev_packages='openssl-dev pkgconf musl-dev gcc make'
ARG dev_packages='pkgconf musl-dev gcc make'

# - Apk cache
# TODO: check if global ok.
# ARG apk_cache_1="/var/cache/apk"
# ARG apk_cache_2="/etc/apk/cache"

# - App build stage users/groups
ARG builder="autobuilder"
ARG builders="builders"

# - Dirs
# No roots.
ARG buildroot="build"
ARG source_dir="source"
ARG target_dir="target"
ARG release_dir="release"
ARG buildroot="build"
ARG source_dir="source"

# - Source files permissions
ARG builddir_perms=750

# - Source repo
ARG repo .

# - Installer tools
# '/source' is root.
ARG rustup_init="ci/scripts/common/rustup-init.sh"

# - rust install params
ARG target_host="x86_64-unknown-linux-musl"
ARG target_profile="minimal"
ARG rust_component_1="cargo"

# - Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
ARG RUSTUP_TOOLCHAIN="x86_64-unknown-linux-musl"

# - Cargo build env
ARG CARGO_MANIFEST_DIR .
ARG CARGO_BUILD_TARGET "x86_64-unknown-linux-musl"
ARG CARGO_BUILD_TARGET_DIR "target"
ARG OUT_DIR "release"
ARG CARGO_TARGET_TMPDIR "temp"

#### Get tools
# hadolint ignore=DL3018,SC2154
RUN apk --quiet --no-interactive --no-progress --no-cache `
        upgrade --latest; `
    apk --quiet --no-interactive --no-progress --no-cache `
        add "${dev_packages}"; `
    apk cache clean && rm -rf "${apk_cache_1}" "${apk_cache_2}";

#### Switch user for sec reasons
USER ${builder}

#### Launch local rustup-init
# TODO: auto-update 'rustup-init'.
# TODO: switch to script?
RUN "${buildroot}/${source_dir}/${rustup_init}" `
        --quiet `
        -y `
        --default-host ${target_host} `
        --default-toolchain ${RUSTUP_TOOLCHAIN} `
        --profile ${target_profile} `
        --component ${rust_component_1};

#### In debug mode we copying sources from local root.
WORKDIR ${buildroot}/${source_dir}
COPY --chown=${builder}:{builders} --chmod=${builddir_perms} ${repo} .
RUN make local && make build --quiet --release;

# ------------------------------------------------------------------------------

## 3. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.

### Runner image
# hadolint ignore=DL3029
FROM --platform=${rp_arch} ${rp_platform}:${rp_version} AS runner

#### Args
# - Installer
ARG runner_sysconf="alpine-conf"
ARG release_mount="/mnt/distr"
ARG release_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

# - Default app user/group
ARG user="appuser"
ARG users="appusers"

# - Users/groups
ARG app_owner="root"
ARG builder_gecos="Special user for building app."

# - App files permission
ARG app_dir_perm=750

# -App config
ARG app_config="ci/config/config.toml"

# - Healthcheck
ARG prober="ping"
ARG probe_addr="8.8.8.8"
ARG probe_count=5
ARG probe_deadline=10
ARG probe_timeout=15

#### Main workload env
ENV TZ=${tz}
ENV PATH="${app_dir}:$PATH"
ENV APP=${app}
ENV app_config=${app_config}

#### CWD
WORKDIR ${app_dir}

#### Sys settings
# hadolint ignore=DL3018,SC2154
RUN --mount=type=bind,target=${release_mount},source=${release_dir},from=build,rw `
    adduser "${user}" `
        -G "${users}" `
        -g "${user_gecos}" `
        -s "${user_shell}" `
        -h "${user_home}" `
        -HDS; `
    apk --quiet --no-interactive --no-progress --no-cache `
        upgrade --latest; `
    apk --quiet --no-interactive --no-progress --no-cache `
        add --latest "${runner_sysconf}" `
    && setup-timezone -i "${tz}" `
    && apk --quiet --no-interactive --no-progress cache clean `
    && rm -rf "${apk_cache_1}" "${apk_cache_2}"; `
    mv "${release_mount}" . ; `
    chown -R "${app_owner}:${users}" . ; `
    chmod -R "${app_dir_perm}" "${app_dir}";

#### Copy app
# COPY --link --from=${target_stage} `
#     --chown=${app_owner}:${users} `
#     --chmod=${app_perm} `
#     "${release_dir}/${app}", `
#     "${release_dir}/${web_server}", `
#     "${release_dir}/${pprtmp_server}" `
#         ./

# VOLUME ["./ci/config"]

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
HEALTHCHECK --interval=5m --timeout=30s --start-period=5s --retries=3 `
    # TODO: pipe status code and message output.
    CMD ${prober} `
        -q `
        -c ${probe_count} `
        -W ${probe_timeout} `
        -w ${probe_deadline} `
            ${probe_addr}; `
        exit "$?";

#### Switch user and start app
USER ${user}

# hadolint ignore=DL3025
ENTRYPOINT [ ${app} ]

# - Args for default start
# hadolint ignore=DL3025
CMD  [ "-c", ${app_config} ]
