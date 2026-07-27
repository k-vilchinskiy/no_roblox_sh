#!/bin/bash

set -e

LABEL="com.user.activitytracker"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"

if [ ! -f "$PLIST_FILE" ]; then
    echo "Missing $PLIST_FILE"
    exit 1
fi

launchctl bootout "$DOMAIN" "$PLIST_FILE" 2>/dev/null || true

echo "Disabled $LABEL from $DOMAIN"
