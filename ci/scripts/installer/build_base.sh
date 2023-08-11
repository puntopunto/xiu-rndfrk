#! /bin/env sh

# Main installer
# ---
# Include and run other install steps
#
# TODO: logging.
# TODO: exception catching.
# ---

# Sources



. "./tasks/*"
. "./tasks/*"

# Check rust source
# if [ -f "../../" ] then

# Defaults
# Exit code
DEFAULT_EXIT_CODE=0
EXIT_CODE=$DEFAULT_EXIT_CODE


# Error codes
GLOBAL_FAILURE=1


# Main program
Main () {
    # Exec main logic

    update_apk.sh || EXIT_CODE=$GLOBAL_FAILURE;
    setup_timezone.sh || EXIT_CODE=$GLOBAL_FAILURE;

    return $EXIT_CODE
}
