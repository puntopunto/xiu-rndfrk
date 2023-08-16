# syntax=docker/dockerfile:1
# escape=`

# ------------------------------------------------------------------------------
#
# # XIU stream/restream server
#
# Test image
# ---
# # TODO: improve header (add info, pic, etc.) and add more 'MD' formatting.  
# ------------------------------------------------------------------------------
# ## README
#
# TODO: readme.
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

# ------------------------------------------------------------------------------
## 2. Setting up base
### Base platform args
ARG base_arch="linux/amd64"
ARG base_platform="alpine"
ARG base_platform_version="latest"

### Base image
FROM --platform=${base_arch} `
    ${base_platform}:${base_platform_version} AS base

#### Args
# - System-related
# TODO: check 'tz' external args.
ARG tz_pack="alpine-conf"
ARG tz='Africa/Algiers'

# - Groups and users settings (only 1 for now)
ARG user_gecos='Special no-login user for app.'
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

#### Base setup
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

# TODO: check 'addgroup' utility reasons for use.
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
### Toolset image
FROM base AS toolset

### Args
# - Toolchain and deps
# TODO: check 'openssl-dev' reasons.
# ARG dev_packages='openssl-dev pkgconf musl-dev gcc make'
ARG dev_packages='pkgconf musl-dev gcc make'

# - Apk cache
# TODO: check if global ok.
# ARG apk_cache1="/var/cache/apk"
# ARG apk_cache2="/etc/apk/cache"

# - App builder user/group
ARG builder="builder"
ARG builders="builders"
ARG builder_gecos="Special user for building app."

#### Get tools
RUN apk --update-cache upgrade --no-cache;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache_dirs};

#### On-build instruction set
# - Builders group
# ONBUILD RUN addgroup ${builders};

# - Default builder user
ONBUILD RUN adduser ${builder} `
    -G ${builders} `
    -g ${builder_gecos};

# ------------------------------------------------------------------------------
## 4. Build app
# TODO: switch to net install? Git 'clone' or copy source / mount volume?

### Builder image
FROM toolset as builder

#### Args
# - Source repo
ARG repo=.

# - Dirs
ARG buildroot="/build"
ARG source_dir="${buildroot}/source"
ARG target_dir="${buildroot}/target"
ARG release_dir="${buildroot}/release"

# - Installer tools
ARG rustup_init="ci/scripts/common/rustup-init.sh"
ARG selected_rust_installer="${source_dir}/${rustup_init}"

# - rust install params
ARG target_host="x86_64-unknown-linux-musl"
ARG target_toolchain="x86_64-unknown-linux-musl"
ARG target_profile="minimal"
ARG additional_component="cargo"

# - Source files permissions
ARG builddir_perms=750

# - Rustup-init env args
# TODO: check args is accessible for installer during installong 'Rust'.
# ARG RUSTUP_HOME
# ARG RUSTUP_TOOLCHAIN 
# ARG RUSTUP_DIST_SERVER
# ARG RUSTUP_DIST_ROOT
# ARG RUSTUP_UPDATE_ROOT
# ARG RUSTUP_IO_THREADS 
# ARG RUSTUP_TRACE_DIR
# ARG RUSTUP_UNPACK_RAM
# ARG RUSTUP_NO_BACKTRACE
# ARG RUSTUP_PERMIT_COPY_RENAME

#### Switch user for sec reasons
USER ${builder}

#### Launch local rustup-init
# TODO: auto-update 'rustup-init'.
# TODO: switch to script?
RUN ${selected_rust_installer} `
        --quiet `
        -y `
        --default-host ${target_host} `
        --default-toolchain ${target_toolchain} `
        --profile ${target_profile} `
        --component ${additional_component};

#### Copy source
# TODO: select 'COPY' or 'ADD'.
WORKDIR ${source_dir}
COPY --chown=${builder}:{builders} `
    --chmod=${builddir_perms} `
    ${repo} .

#### Build app
RUN rustup self update;
RUN rustup update;
RUN make local;
RUN make build;

# ------------------------------------------------------------------------------
## 5. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume.

### Run platform args
ARG runner_arch="linux/amd64"
ARG runner_platform="alpine"
ARG runner_platform_version="latest"

### Runner image
FROM --platform="linux/amd64" alpine:${runner_platform_version} AS runner

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

# - App files permission
ARG app_dir_perm=750

# -App config
ARG default_app_config="ci/config/config.toml"

# - Healthcheck
ARG prober="ping"
ARG probe_addr="8.8.8.8"
ARG probe_count=5
ARG probe_deadline=10
ARG probe_timeout=15

# - Protocols/Ports
ARG http_port=80
ARG httpudp_port="80/udp"
ARG https_port=443
ARG rtmp_port=1935
ARG rtmpudp_port="1935/udp"
ARG api_port=8000
ARG apiudp_port="8000/udp"

#### Main workload env
ENV TZ=${tz}
ENV PATH="${app_dir}:$PATH"
ENV APP=${app}
ENV app_config=${default_app_config}

#### CWD
WORKDIR ${app_dir}

#### Sys settings
RUN --mount=type=bind,target=${release_mount},source=${release_dir},from="builder",rw `
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
EXPOSE ${http_port}
EXPOSE ${httpudp_port}
EXPOSE ${https_port}
EXPOSE ${rtmp_port}
EXPOSE ${rtmpudp_port}
EXPOSE ${api_port}
EXPOSE ${apiudp_port}

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
CMD  [ "-c", ${default_app_config} ]
