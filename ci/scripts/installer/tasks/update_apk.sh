#! /bin/env sh
# Apk updater
#
# TODO: add logging.
# ---

# Define err codes
# TODO: these codes.
GENERAL_FAULT=1

# Set default and program exit codes
# TODO: Move defaults to another file (logic level).
DEFAULT_EXIT_CODE=0
EXIT_CODE=$DEFAULT_EXIT_CODE

# Update APK
function update_apk () {
    # Upgrading
    apk cache sync &&
    apk update &&
    apk upgrade --no-cache &&
    EXIT_CODE=$DEFAULT_EXIT_CODE ||
    # Or catching failure
    # TODO: exception catching
    EXIT_CODE=$GENERAL_FAULT;

    return $EXIT_CODE;
}
