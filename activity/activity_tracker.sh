#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$DIR/activity.sqlite"
LOGFILE="$DIR/activity_tracker.log"
INTERVAL_SEC=5

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

init_db() {
    /usr/bin/sqlite3 "$DB" "
CREATE TABLE IF NOT EXISTS hourly_usage (
    day TEXT NOT NULL,
    hour INTEGER NOT NULL,
    app TEXT NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (day, hour, app)
);
"
}

get_frontmost_app() {
    local front output status

    if command -v /usr/bin/lsappinfo >/dev/null 2>&1; then
        front="$(/usr/bin/lsappinfo front 2>/dev/null)"
        if [ -n "$front" ]; then
            output="$(/usr/bin/lsappinfo info -only name "$front" 2>/dev/null | sed -n 's/^"LSDisplayName"="\(.*\)"$/\1/p')"
            if [ -n "$output" ]; then
                printf "%s" "$output"
                return 0
            fi
        fi
    fi

    output="$(/usr/bin/osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>&1)"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "$(date '+%H:%M:%S') - Не удалось получить активное приложение: $output" >> "$LOGFILE"
        return 1
    fi

    printf "%s" "$output"
}

init_db

while true; do
    DAY="$(date +%Y-%m-%d)"
    HOUR="$(date +%H)"
    UPDATED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
    APP="$(get_frontmost_app)"

    if [ -z "$APP" ]; then
        APP="Unknown"
    fi

    APP_ESCAPED="$(sql_escape "$APP")"
    UPDATED_AT_ESCAPED="$(sql_escape "$UPDATED_AT")"

    if ! /usr/bin/sqlite3 "$DB" "
INSERT INTO hourly_usage (day, hour, app, seconds, updated_at)
VALUES ('$DAY', $HOUR, '$APP_ESCAPED', $INTERVAL_SEC, '$UPDATED_AT_ESCAPED')
ON CONFLICT(day, hour, app) DO UPDATE SET
    seconds = seconds + $INTERVAL_SEC,
    updated_at = '$UPDATED_AT_ESCAPED';
"; then
        echo "$(date '+%H:%M:%S') - Не удалось записать статистику для приложения: $APP" >> "$LOGFILE"
    fi

    sleep "$INTERVAL_SEC"
done
