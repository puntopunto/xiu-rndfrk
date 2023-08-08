#! /usr/bin/env sh

# Rust installer
# Installs Rustup, Cargo and platform toolchain.

# Vars import
# Using dotenv file (default '.env' in project root)
. "/.env"

curl $RUSTUPINIT -sSf | sh -s -- \
                        --quiet \
                        -y \
                        --default-toolchain $TOOLCHAIN \
                        --default-host $TARGET_HOST \
                        --profile $TOOLCHAIN_PROFILE \
                        --component ${COMPONENTS[@]};
