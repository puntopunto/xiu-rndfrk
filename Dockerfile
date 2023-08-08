# syntax=docker/dockerfile:1
# escape=`

# XIU stream/restream server
# Test image

# Glob build args, config, and user management 
ARG PLATFORM
ARG VERSION


# ---

# 1. Base image
FROM --platform=${PLATFORM} alpine:${VERSION} AS base

# Build args
ARG TZ
ARG USER
ARG UID

# Base setup
RUN apk cache sync `
    && apk --update-cache upgrade --no-cache `
    && apk add "alpine-conf" `
    && setup-timezone -i ${TZ} `
    # or "Africa/Nairobi"
    && apk del "alpine-conf" `
    && rm -rf "/var/cache/apk" "/etc/apk/cache" `
    && adduser `
    --uid ${UID} `
    --gecos "Special no-login user for app." `
    --shell "/sbin/nologin" `
    --home "/nonexistent" `
    --no-create-home `
    --disabled-password `
    ${USER};

# ---

# 2. Build app
FROM base AS builder

# Builder args
ARG TZ
ARG BUILDERPATH
ARG APP_DIR

# Env
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV TZ=${TZ}

# Workdir
WORKDIR "/${BUILD_DIR}"

# Get toolchain
RUN "ls /"
RUN apk cache sync `
    && apk --update-cache upgrade --no-cache `
    && apk add --no-cache `
                "openssl-dev" "pkgconf" "git" "rustup" "musl-dev" `
                "gcc" "make" `
    && "apk cache clean" `
    && rm -rf "/var/cache/apk" "/etc/apk/cache";
RUN rustup-init -q -y `
                --component "cargo" `
                --component "x86_64-unknown-linux-musl" `
                --default-host "x86_64-unknown-linux-musl";

# Copying source and building
RUN git clone "https://github.com/puntopunto/xiu-rndfrk.git" --branch "ci" `
    && cd "xiu-rndfrk" `
    && git checkout -b "publish"

WORKDIR "/${BUILD_DIR}/xiu-rndfrk"
RUN "make online"
RUN "make build"

# ---

# 3. Run app
FROM base AS runner

# Args
ARG BUILD_DIR
ARG APP_DIR
ARG APPNAME
ARG USER

# Env
ENV TZ=${TZ}
ENV PATH=${RUNNERPATH}

# CWD
WORKDIR "/${APP_DIR}"

# Copy app
COPY --link --from=builder  "/${BUILD_DIR}/${TARGET_DIR}/${APPNAME}", `
                            "/${BUILD_DIR}/${TARGET_DIR}/${HTTPSERVERDIR}", `
                            "/${BUILD_DIR}/${TARGET_DIR}/${PPRTMPSERVER_DIR}" `
                            "/${APP_DIR}"

# Switch user
USER ${USER}

# Ports
EXPOSE "80"
EXPOSE "80/udp"
EXPOSE "443"
EXPOSE "1935"
EXPOSE "1935/udp"
EXPOSE "8000"
EXPOSE "8000/udp"

# Start app in exec mode
ENTRYPOINT [ "xiu" ]
