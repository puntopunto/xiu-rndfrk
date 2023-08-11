#! /bin/env sh

# Main installer
# ---
# Include and run other install steps.
# ---

# Sources

. "tasks/update_apk.sh"
. "tasks/setup_timezone"

# Main program
function Main {
    update_apk;
    setup_timezone.sh;
}
