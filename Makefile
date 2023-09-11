COPY_CONF_FILES = sh ./update_project_conf.sh;

# if [ -f .env ]

not_spport:
	echo "input make <local|online|build|clean|check>";

# build local source codes
config_offline:
	cd ./confs && $(COPY_CONF_FILES) "offline";

# pull the online crates codes and build
config_online:
	cd ./confs && $(COPY_CONF_FILES) "online";

update_dependencies:
	cargo update

check:
	cargo clippy --fix --allow-dirty --allow-no-vcs

clean:
	cargo clean

build:
	cargo build

build-musl-release:
	cargo build --target "x86_64-unknown-linux-musl" --release
