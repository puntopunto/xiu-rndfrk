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

# Set TZ and default zone
# TODO: Move defaults to another file (logic level).
DEFAULT_ZONE="Africa/Nairobi"

function get_tz_settings () {
    # Get zone info from settings or user input
    # Placeholder at the moment.
    # TODO: all.
    return "Europe/Moscow"
}

# Set TZ
function set_tz () {
    tz=$get_tz_settings
    apk add "alpine-conf" &&
    setup-timezone -i ${tz} &&
    apk del "alpine-conf" &&
    set -e TZ=$tz &&
    EXIT_CODE=$DEFAULT_EXIT_CODE ||
    # Or catching failure
    # TODO: exception catching
    EXIT_CODE=$GENERAL_FAULT;

    return $EXIT_CODE;

}
