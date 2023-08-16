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
ARG group_appusers="appusers"

# - Packages cache
ARG apk_cache1="/var/cache/apk"
ARG apk_cache2="/etc/apk/cache"

# ------------------------------------------------------------------------------
## 2. Setting up base
### Platform args
ARG base_platform="linux/amd64"
ARG base_platform_version="latest"

### Base image
FROM --platform=${base_platform} alpine:${base_platform_version} AS base

### Args
# - System-related
# TODO: check 'tz' glob args.
ARG tz_pack="alpine-conf"
ARG tz='Africa/Algiers'

# Groups and users settings (only 1 for now)
ARG user_gecos='Special no-login user for app.'
ARG user_shell="/sbin/nologin"
ARG user_home="/nonexistent"

### Base setup
# TODO: check for  smaller layers qty, if possible.
RUN apk --quiet --no-interactive --no-progress --update-cache upgrade --latest;
RUN apk --quiet --no-interactive --no-progress add --latest ${tz_pack}
RUN setup-timezone -i ${tz}
RUN apk cache clean && rm -rf ${apk_cache1} ${apk_cache2};

### App user for next stages.
# TODO: check multiply 'ONBUILD' steps - image size, layers count, etc.
ONBUILD RUN addgroup ${group_appusers} && adduser `
    -G ${group_appusers} `
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
ARG rustup_init_url="https://sh.rustup.rs"
ARG dev_packages='openssl-dev pkgconf musl-dev gcc make'

#  Apk cache
# TODO: check if global ok.
# ARG apk_cache1="/var/cache/apk"
# ARG apk_cache2="/etc/apk/cache"

# - App builder user/group
ARG appbuilder="builder"
ARG group_build="builders"
ARG appbuilder_gecos="Special user for building app."

#### Get tools
RUN apk --update-cache upgrade --no-cache;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache_dirs};

#### On-build instruction set
# - Builders group
ONBUILD RUN addgroup ${group_build};

# - Default builder user
ONBUILD RUN adduser ${appbuilder} `
    -G ${group_build} `
    -g ${appbuilder_gecos};

# ------------------------------------------------------------------------------
## 4. Build app
# TODO: switch to net install? Git 'clone' or copy source / mount volume?

### Builder image
FROM toolset as builder

#### Args
# - Source repo
ARG repo="."

# - Dirs
ARG buildroot="/build"
ARG source_dir="${buildroot}/source"
ARG target_dir="${buildroot}/target"
ARG release_dir="${buildroot}/release"

# - Installer tools
ARG rustup_init="${source_dir}/ci/scripts/common/rustup-init.sh"

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

### Switch user for sec reasons
USER ${appbuilder}

### Launch local rustup-init
# TODO: auto-update 'rustup-init'.
# TODO: switch to script?
RUN ${rustup_init} `
    --quiet `
    -y `
    --default-host "x86_64-unknown-linux-musl" `
    --default-toolchain "stable-x86_64-unknown-linux-musl" `
    --profile "minimal" `
    --component "cargo";

### Copy source
WORKDIR ${source_dir}
# TODO: select 'COPY' or 'ADD'.
ADD --chown=${appbuilder}:{group_build} `
    --chmod=${builddir_perms} `
    ${repo} .

### Build app
RUN rustup self update;
RUN rustup update;
RUN make local;
RUN make build;

# ------------------------------------------------------------------------------
## 5. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume. 

### Runner image
FROM --platform=${base_platform} alpine:${base_platform_version} AS runner

### Args
# - Installer
ARG mount_target="/mnt/distr"
ARG target_stage="builder"
ARG release_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"

# - Protocols/Ports
ARG http_port=80
ARG httpudp_port=80/udp
ARG https_port=443
ARG rtmp_port=1935
ARG rtmpudp_port=1935/udp
ARG api_port=8000
ARG apiudp_port=8000/udp

# - Users/groups
ARG app_owner="root"

# - App files permission
ARG app_perm=750

# - Healthcheck
ARG prober="ping"
ARG probe_addr="8.8.8.8"
ARG probe_count=5
ARG probe_deadline=10
ARG probe_timeout=15

### Main workload env
ENV PATH="${app_dir}:$PATH"
ENV APP=${app}

# CWD
WORKDIR ${app_dir}

### Sys settings
RUN --mount=type=bind,target=${mount_target},source=${release_dir},from=${target_stage},rw `
    addgroup ${group_appusers} `
    && adduser `
        -G ${group_appusers} `
        -g ${user_gecos} `
        -s ${user_shell} `
        -h ${user_home} `
        -H `
        -D `
        -S `
        ${user}; `
    apk --quiet --no-interactive --no-progress --update-cache `
        upgrade --latest; `
    apk --no-interactive --no-progress add --latest "alpine-conf" `
    && setup-timezone -i ${tz} `
    && apk cache clean `
    && rm -rf ${apk_cache1} ${apk_cache2}; `
    mv ${mount_target} . ; `
    chown -R ${app_owner}:${group_appusers} ${app_dir}; `
    chmod -R ${app_perm} ${app_dir};

### Copy app
# COPY --link --from=${target_stage} `
#     --chown=${app_owner}:${group_appusers} `
#     --chmod=${app_perm} `
#     "${release_dir}/${app}", `
#     "${release_dir}/${web_server}", `
#     "${release_dir}/${pprtmp_server}" `
#         ./

# VOLUME ["./ci/config"]

### Ports
EXPOSE ${http_port}
EXPOSE ${httpudp_port}
EXPOSE ${https_port}
EXPOSE ${rtmp_port}
EXPOSE ${rtmpudp_port}
EXPOSE ${api_port}
EXPOSE ${apiudp_port}

### Health-check
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
USER ${user}
ENTRYPOINT [ ${app} ]

# - Args for default start
CMD [ "-c" "ci/config/config.toml" ]
