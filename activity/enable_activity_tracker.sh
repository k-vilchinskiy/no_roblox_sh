#!/bin/bash

set -e

LABEL="com.user.activitytracker"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -f "$PLIST_FILE" ]; then
    echo "Missing $PLIST_FILE"
    echo "Run ./install_activity_tracker.sh first."
    exit 1
fi

launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

echo "Enabled $LABEL"
