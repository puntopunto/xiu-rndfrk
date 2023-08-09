# syntax=docker/dockerfile:1
# escape=`

# XIU stream/restream server
# Test image

# Base image args
ARG PLATFORM
ARG VERSION
# ---

# 1. Base image
FROM --platform=${PLATFORM} alpine:${VERSION} AS base

# Local args
ARG tz
ARG builddir
ARG uid
ARG user

# Base setup
RUN apk cache sync `
    && apk --update-cache upgrade --no-cache `
    && apk add "alpine-conf" `
    && setup-timezone -i ${tz} `
    && apk del "alpine-conf" `
    && apk cache clean`
    && rm -rf "/var/cache/apk" "/etc/apk/cache" `
    && adduser `
    --uid ${uid} `
    --gecos "Special no-login user for app." `
    --shell "/sbin/nologin" `
    --home "/nonexistent" `
    --no-create-home `
    --disabled-password `
    ${user};

# ---

# 2. Build app
FROM base AS builder

# Local args
ARG builddir

# Workdir
WORKDIR "${builddir}"

# Get deps and toolchain
RUN apk cache sync apk --update-cache upgrade --no-cache;
RUN apk add --no-cache `
    "openssl-dev" "curl" "pkgconf" "git" "musl-dev" "gcc" "make";
RUN apk cache clean && rm -rf "/var/cache/apk" "/etc/apk/cache";
RUN curl https://sh.rustup.rs -sSf | sh -s -- `
    --quiet `
    -y `
    --default-toolchain "stable-x86_64-unknown-linux-musl" `
    --default-host "x86_64-unknown-linux-musl" `
    --profile "minimal" `
    --component "cargo" `
    --component "x86_64-unknown-linux-musl";

# Copying source
RUN git clone "https://github.com/puntopunto/xiu-rndfrk.git" --branch "ci" `
    && cd "xiu-rndfrk" `
    && git checkout -b "publish"

# Build app
WORKDIR "${builddir}/xiu-rndfrk"
RUN rustup self update
RUN rustup update
RUN make local
RUN make build

# ---

# 3. Run app
FROM base AS runner

# Local args
ARG appdir
ARG app
ARG web
ARG pprtmp
ARG user



# CWD
WORKDIR "${appdir}"

# Copy app
COPY --link --from=builder "${app}", "${web}", "${pprtmp}" "${appdir}"

# Switch user
USER ${user}

# Ports
EXPOSE "80"
EXPOSE "80/udp"
EXPOSE "443"
EXPOSE "1935"
EXPOSE "1935/udp"
EXPOSE "8000"
EXPOSE "8000/udp"

# Set health-check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 `
    CMD [ "ping 8.8.8.8" ]

# Start app in exec mode
ENTRYPOINT [ "xiu" ]
