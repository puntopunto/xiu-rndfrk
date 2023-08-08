# syntax=docker/dockerfile:1
# escape=`

# XIU stream/restream server
# Test image

# ---

# 1. Base image
FROM --platform=${PLATFORM} alpine:${VERSION} AS base

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

# Workdir
WORKDIR "${BUILDDIR}"

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
WORKDIR "${BUILDDIR}/xiu-rndfrk"
RUN rustup self update
RUN rustup update
RUN make local
RUN make build

# ---

# 3. Run app
FROM base AS runner

# CWD
WORKDIR "${APPDIR}"

# Copy app
COPY --link --from=builder `
    "${TARGETAPP}", `
    "${HTTPSERVER}", `
    "${PPRTMPSERVER}" `
                        "${APPDIR}"

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
