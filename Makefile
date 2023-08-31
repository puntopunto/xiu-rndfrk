COPY_CONF_FILES = sh ./update_project_conf.sh

# if [ -f .env ]

not_spport:
	echo "input make <local|online|build|clean|check>"

# build local source codes
local:
	cd ./confs && $(COPY_CONF_FILES) "local"

# pull the online crates codes and build
online:
	cd ./confs && $(COPY_CONF_FILES) "online"

check:
	cargo clippy --fix --allow-dirty --allow-no-vcs

clean:
	cargo clean

build:
	cargo build

test-build-musl:
	cargo build --target "x86_64-unknown-linux-musl" --release

build-default:
	cargo build \
		--quiet \
		--target-dir "/build/target" \
		--out-dir "/build/release"

test-build-default-platform:
	cargo build --release
