#!/bin/bash

set -e

LABEL="com.user.activitytracker"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -f "$PLIST_FILE" ]; then
    echo "Missing $PLIST_FILE"
    exit 1
fi

launchctl unload "$PLIST_FILE" 2>/dev/null || true

echo "Disabled $LABEL"
