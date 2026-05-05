#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.user.noroblox"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/$LABEL.plist"
SCRIPT_FILE="$DIR/no_roblox.sh"
ERROR_LOG="$DIR/roblox_error.log"

mkdir -p "$PLIST_DIR"

cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_FILE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$ERROR_LOG</string>
</dict>
</plist>
EOF

chmod +x "$SCRIPT_FILE"

echo "Created $PLIST_FILE"
echo "Run ./enable.sh to start the service."
