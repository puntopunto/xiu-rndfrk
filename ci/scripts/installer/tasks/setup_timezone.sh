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
# DEFAULT_ZONE="Africa/Nairobi"
# CURRENT_ZONE=$DEFAULT_ZONE
_TEST_ZONE="Europe/Moscow"


get_tz_settings () {
    # Get zone info from settings or user input
    #
    # Placeholder at the moment.
    # Get for first argument zone name in 'UTC' format,
    # set 'CURRENT_ZONE' global variable.
    # TODO: all.
    # ---
    # Set exit code
    exit_code=$DEFAULT_EXIT_CODE

    # Error list
    _err_0=false
    _err_1=$GENERAL_FAULT;
    _err_2=2

    # Set current error code
    err_code=$_err_1;

    # Getting zone
    # TODO: logic.
    # zone=$1
    zone=$_TEST_ZONE
    
    # Check zone and set 'CURRENT_ZONE' var
    if $zone; then
        CURRENT_ZONE=$zone;
        err_code=$_err_0;

    else
        CURRENT_ZONE=false;
        err_code=$_err_2;
    fi;

    # Check errors, set exit code 
    if [ ! $CURRENT_ZONE ] && [ $err_code != "$($_err_0 || $_err_1)" ]; then
        exit_code=$_err_2
    fi;

    return $exit_code;
}


# Set TZ
set_tz () {
    # Set TZ in image and container env vars
    if [ "$(get_tz_settings)" != $DEFAULT_EXIT_CODE ]; then
        tz=$CURRENT_ZONE;

    fi

    apk add "alpine-conf";
    setup-timezone -i "${tz}";
    apk del "alpine-conf";
    set -e TZ="$tz";
    EXIT_CODE=$DEFAULT_EXIT_CODE ||
    # Or catching failure
    # TODO: exception catching
    EXIT_CODE=$GENERAL_FAULT;

    return $EXIT_CODE;

}
