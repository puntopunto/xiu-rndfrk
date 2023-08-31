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
## 1. Pre-build setting
### Global args
# - Date and time
ARG tz="Europe/Moscow"

# - Default app user/group
# TODO: check and use (if exist) 'groupadd' and 'useradd' 
ARG user="appuser"
ARG users="appusers"

# - Packages cache
ARG apk_cache1="/var/cache/apk"
ARG apk_cache2="/etc/apk/cache"

### Setup build stages
#### Base platform args
ARG bp_arch="linux/amd64"
ARG bp_platform="alpine"
ARG bp_version="latest"

#### Run platform args
ARG rp_arch="linux/amd64"
ARG rp_platform="alpine"
ARG rp_version="latest"

# ------------------------------------------------------------------------------

## 2. Base image
#
# TODO: select 'ONBUILD' invariants.
FROM --platform=${bp_arch} ${bp_platform}:${bp_version} AS base

### Args
#### System-related
# TODO: check 'tz' external args.
ARG tz_pack="alpine-conf"
ARG tz='Africa/Algiers'

#### Groups and users settings (only 1 for now)
ARG user_gecos='Special no-login user for app.'
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

### Base setup
# TODO: check for  smaller layers qty, if possible.
RUN apk --quiet --no-interactive --no-progress --update-cache upgrade --latest;
RUN apk --quiet --no-interactive --no-progress add --latest ${tz_pack}
RUN setup-timezone -i ${tz}
RUN apk cache clean && rm -rf ${apk_cache1} ${apk_cache2};

#### App user for next stages.
# TODO: check multiply 'ONBUILD' steps - image size, layers count, etc.
# ONBUILD RUN addgroup ${users} && adduser `
#     -G ${users} `
#     -g ${user_gecos} `
#     -s ${user_shell} `
#     -h ${user_home} `
#     -H `
#     -D `
#     -S `
#     ${user};

# # TODO: check 'addgroup' utility reasons for use.
ONBUILD RUN adduser `
    -G ${users} `
    -g ${user_gecos} `
    -s ${user_shell} `
    -h ${user_home} `
    -H `
    -D `
    -S `
    ${user};

# ------------------------------------------------------------------------------

## 3. Settings up build tools
#
# Additional env vars for 'rustup' and 'cargo build' can be added as 'ARGs'. 
# TODO: switch to net install? Git 'clone' or copy source / mount volume?
### Toolset image
FROM base AS builder

### Args
# - Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# ARG dev_packages='openssl-dev pkgconf musl-dev gcc make'
ARG dev_packages='pkgconf musl-dev gcc make'

# - Apk cache
# TODO: check if global ok.
# ARG apk_cache1="/var/cache/apk"
# ARG apk_cache2="/etc/apk/cache"

# - Dirs
# No roots.
ARG buildroot="build"
ARG source_dir="source"
ARG target_dir="target"
ARG release_dir="release"

# - Installer tools
# '/source' is root.
ARG rustup_init="ci/scripts/common/rustup-init.sh"

# - rust install params
ARG target_host="x86_64-unknown-linux-musl"
ARG target_profile="minimal"
ARG additional_component_1="cargo"

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
RUN apk --update-cache upgrade --no-cache;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache1} ${apk_cache2};

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
        --component ${additional_component_1};

# ------------------------------------------------------------------------------

## 4. Building

### Debugger image
FROM builder as building

#### Args
# - Source repo
ARG repo .

# - Dirs
# No roots.
ARG buildroot="build"
ARG source_dir="source"

# - Source files permissions
ARG builddir_perms=750

# - App builder user/group
ARG builder="root"
ARG builders="builders"

#### In debug mode we copying sources from local root.
# TODO: select 'COPY' or 'ADD'.
WORKDIR ${buildroot}/${source_dir}
ADD --chown=${builder}:{builders} --chmod=${builddir_perms} ${repo} .

#### Building
USER ${builder}
RUN make local && make build --quiet --release;

# ------------------------------------------------------------------------------

## 5 Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.

### Runner image
FROM --platform=${rp_arch} ${rp_platform}:${rp_version} AS runner

#### Args
# - Installer
ARG runner_sysconf="alpine-conf"
ARG release_mount="/mnt/distr"
ARG release_stage="builder"
ARG release_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

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
RUN --mount=type=bind,target=${release_mount},source=${release_dir},from=${release_stage},rw `
    # addgroup ${users} `
    # && adduser `
    adduser ${user} `
        -G ${users} `
        -g ${user_gecos} `
        -s ${user_shell} `
        -h ${user_home} `
        # TODO: check params (can be grouped).
        -HDS; `
    apk --quiet --no-interactive --no-progress --update-cache `
        upgrade --latest; `
    apk --no-interactive --no-progress add --latest ${runner_sysconf} `
    && setup-timezone -i ${tz} `
    && apk cache clean `
    && rm -rf ${apk_cache1} ${apk_cache2}; `
    mv ${release_mount} . ; `
    chown -R ${app_owner}:${users} . ; `
    chmod -R ${app_dir_perm} ${app_dir};

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
ENTRYPOINT [ ${app} ]

# - Args for default start
CMD  [ "-c", ${app_config} ]
