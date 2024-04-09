#!/bin/bash
set -euo pipefail

if (( $EUID != 0 )); then
    echo "Error: Please run with sudo"
    exit 1
fi

BINARY="$(stat -f "%N" ${1})"

if [[ ! -f "${BINARY}" ]]; then
  echo "Error: No file found at ${BINARY}"
  exit 1
fi

echo "Making sure the file is executable .. "
chmod +x "${BINARY}"

echo "Installing launch agent .. "
sed -e "s|%%BINARYPATH%%|${BINARY}|g" org.inonio.setleds.plist.template > /Library/LaunchDaemons/org.inonio.setleds.plist

echo "Setting launch agent permissions .. "
chown root:wheel /Library/LaunchDaemons/org.inonio.setleds.plist

echo "Enabling the launch configuration .. "
launchctl load -w /Library/LaunchDaemons/org.inonio.setleds.plist

echo "Starting the job .. "
launchctl start /Library/LaunchDaemons/org.inonio.setleds.plist || :

echo "All done! Numlock functionality should now be restored."
