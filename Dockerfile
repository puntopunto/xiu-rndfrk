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
## 1. Pre-flight setting

### Global args
# - Date and time
ARG tz="Europe/Moscow"

# - Default app user/group
# TODO: check and use (if exist) 'groupadd' and 'useradd' 
ARG user="appuser"
ARG appusers_group="appusers"

# - Packages cache
ARG apk_cache_dirs='`
    /var/cache/apk `
    /etc/apk/cache'

# ------------------------------------------------------------------------------
## 2. Setting up base

### Platform args
ARG base_platform="linux/amd64"
ARG base_platform_version="latest"

### Base image
FROM --platform=${base_platform} alpine:${base_platform_version} AS base

### Args
# - System-related
# TODO: check glob args
ARG tz='Africa/Algiers'

### Base setup
RUN apk --update-cache upgrade --no-cache;
RUN apk add "alpine-conf" `
    && setup-timezone -i ${tz} `
    && apk del "alpine-conf";
RUN apk cache clean && rm -rf ${apk_cache_dirs};

### App user
# TODO: check multiply 'ONBUILD' steps - image size, layers count, etc.
ONBUILD RUN addgroup ${appusers_group} `
    && adduser `
    -G ${appusers_group} `
    -g "Special no-login user for app." `
    -s "/sbin/nologin" `
    -h "/nonexistent" `
    -H `
    -D `
    -S `
    ${user};

# ------------------------------------------------------------------------------
## 3. Settings up build tools

### Toolset image
FROM base AS toolset

#### Args
# - Toolchain and deps
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

# - App builder user/group
ARG appbuilder="builder"
ARG appbuilders_group="builders"

#### Get tools
RUN apk cache sync && apk update && apk upgrade;
RUN apk add ${dev_packages};
RUN apk cache clean && rm -rf ${apk_cache_dirs};

#### On-build instruction set
# - Builders group
ONBUILD RUN addgroup ${appbuilders_group};

# - Default builder user
ONBUILD RUN adduser ${appbuilder} `
    -G ${appbuilders_group} `
    -g "Special user for build app";

# ------------------------------------------------------------------------------
## 4. Build app

### Builder image
FROM toolset as builder

#### Args
# - Dirs
ARG buildroot="/build"
ARG source_dir="${buildroot}/source"
ARG target_dir="${buildroot}/target"
# ARG artifacts="${target_dir}/artifacts"
ARG release_dir="${target_dir}/release"

# - Toolchain install tools
ARG rustup_init="${source_dir}/ci/scripts/common/rustup-init.sh"

# - Rustup install args
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

### Get rustup-init from internet and install toolchain
# TODO: switch to local (ar 'add by url' mode).
# RUN wget --quiet --secure-protocol=TLSv1_2 --output-document  `
#     ${rustup_init_url} `
#     | sh -s -- `
#         --quiet `
#         -y `
#         --default-host "x86_64-unknown-linux-musl" `
#         --default-toolchain "stable-x86_64-unknown-linux-musl" `
#         --profile "minimal" `
#         --component "cargo";

### Copy source
WORKDIR ${source_dir}
COPY . .

### Launch local rustup-init'
# TODO: auto-update 'rustup-init'
RUN ${rustup_init};

# - Build app
RUN rustup self update;
RUN rustup update;
RUN make local;
RUN make build;

# ------------------------------------------------------------------------------
## 5. Run app
# TODO: mount volume with workload configs and check size/layering.
# TODO: add 'CMD' instruction for config in mounted volume. 

### Runner image
FROM base AS runner

### Args
# - Install app
ARG release_dir="/build/target/release"
ARG app_dir="/app"
ARG app="xiu"
ARG web_server="http-server"
ARG pprtmp_server="pprtmp"
# TODO: check 'user' arg - may no need here.
# ARG user="appuser"

# - Port settings
ARG http_port=80
ARG httpudp_port="80/udp"
ARG https_port=443
ARG rtmp_port=1935
ARG rtmpudp_port="1935/udp"
ARG api_port=8000
ARG apiudp_port="8000/udp"

# - Healthcheck args
ARG statuscheck_addr="8.8.8.8"
ARG statuscheck_count=4
# TODO: var precedence and inheritance test.
ARG hc_exit_code=0
ARG hc_errcode_hook=${@}

### Main workload env
ENV PATH="${app_dir}:$PATH"
ENV APP=${app}

### Copy app
# TODO: chmod/chown to 'root' and RO-access for 'appusers' group.
WORKDIR "${app_dir}"
COPY --link --from=builder `
    "${release_dir}/${app}", `
    "${release_dir}/${web_server}", `
    "${release_dir}/${pprtmp_server}" `
        ./

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
HEALTHCHECK --interval=5m --timeout=10s --start-period=5s --retries=3 `
    # TODO: pipe status code and message output.
    CMD ping ${statuscheck_addr} -c ${statuscheck_count} `
    && exit(hc_exit_code) || exit (hc_errcode_hook);

### Switch user and start app
USER ${user}
ENTRYPOINT [ ${app} ]
