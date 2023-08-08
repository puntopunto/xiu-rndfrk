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
    && apk del "alpine-conf" `
    && apk cache clean`
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
ARG BUILDERPATH
ARG BUILDDIR

# Workdir
WORKDIR "${BUILDDIR}"

# Get toolchain
RUN apk cache sync `
    && apk --update-cache upgrade --no-cache `
    && apk add --no-cache `
                "openssl-dev" "pkgconf" "git" "musl-dev" "gcc" "make" `
    && apk cache clean `
    && rm -rf "/var/cache/apk" "/etc/apk/cache";
RUN curl https://sh.rustup.rs   -sSf | sh -s `
                                --component "cargo" `
                                --component "x86_64-unknown-linux-musl" `
                                --default-host "x86_64-unknown-linux-musl";

# Copying source and building
RUN git clone "https://github.com/puntopunto/xiu-rndfrk.git" --branch "ci" `
    && cd "xiu-rndfrk" `
    && git checkout -b "publish"

WORKDIR "${BUILDDIR}/xiu-rndfrk"
RUN "make local"
RUN "make build"

# ---

# 3. Run app
FROM base AS runner

# Args
ARG BUILDDIR
ARG APPDIR
ARG APPNAME
ARG USER

# CWD
WORKDIR "${APPDIR}"

# Copy app
COPY --link --from=builder  "/${BUILDDIR}/${TARGETDIR}/${APPNAME}", `
                            "/${BUILDDIR}/${TARGETDIR}/${HTTPSERVERDIR}", `
                            "/${BUILDDIR}/${TARGETDIR}/${PPRTMPSERVERDIR}" `
                            "/${APPDIR}"

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
