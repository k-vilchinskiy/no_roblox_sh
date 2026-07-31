#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$DIR/activity.sqlite"
LOGFILE="$DIR/activity_tracker.log"
CONFIG="$DIR/config.ini"
INTERVAL_SEC=5

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

applescript_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

trim() {
    printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
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

CREATE TABLE IF NOT EXISTS limit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day TEXT NOT NULL,
    event_time TEXT NOT NULL,
    app TEXT NOT NULL,
    group_name TEXT NOT NULL,
    limit_minutes INTEGER NOT NULL,
    total_seconds INTEGER NOT NULL,
    action TEXT NOT NULL,
    UNIQUE (day, app, group_name, action)
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

close_limited_app() {
    local app="$1"
    local app_escaped

    app_escaped="$(applescript_escape "$app")"

    /usr/bin/osascript \
        -e "display alert \"Лимит времени исчерпан\" message \"Приложение $app_escaped будет закрыто.\" buttons {\"OK\"} default button \"OK\" giving up after 30" \
        >/dev/null 2>&1 &

    /usr/bin/osascript -e "tell application \"$app_escaped\" to quit" >/dev/null 2>&1 || true
    sleep 2
    /usr/bin/pkill -x "$app" >/dev/null 2>&1 || true
}

record_limit_event() {
    local day="$1"
    local event_time="$2"
    local app="$3"
    local group_name="$4"
    local limit_min="$5"
    local total_sec="$6"
    local app_sql group_sql event_time_sql

    app_sql="$(sql_escape "$app")"
    group_sql="$(sql_escape "$group_name")"
    event_time_sql="$(sql_escape "$event_time")"

    /usr/bin/sqlite3 "$DB" "
INSERT OR IGNORE INTO limit_events (
    day,
    event_time,
    app,
    group_name,
    limit_minutes,
    total_seconds,
    action
)
VALUES (
    '$(sql_escape "$day")',
    '$event_time_sql',
    '$app_sql',
    '$group_sql',
    $limit_min,
    $total_sec,
    'closed'
);
"
}

enforce_activity_limits() {
    local day="$1"
    local app="$2"
    local line apps limit_min limit_sec app_name app_name_trimmed app_sql app_match total_sec condition event_time

    [ ! -f "$CONFIG" ] && return
    [ "$app" = "Unknown" ] && return

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [ -z "$line" ] && continue

        if [[ "$line" =~ ^\[(.*)\][[:space:]]*:[[:space:]]*([0-9]+)$ ]]; then
            apps="${BASH_REMATCH[1]}"
            limit_min="${BASH_REMATCH[2]}"
            limit_sec=$((limit_min * 60))
            if [ "$apps" = "*" ]; then
                total_sec="$(/usr/bin/sqlite3 "$DB" "SELECT COALESCE(SUM(seconds), 0) FROM hourly_usage WHERE day = '$(sql_escape "$day")';")"
            else
                app_match=0
                condition=""

                IFS=',' read -ra APP_NAMES <<< "$apps"
                for app_name in "${APP_NAMES[@]}"; do
                    app_name_trimmed="$(trim "$app_name")"
                    [ -z "$app_name_trimmed" ] && continue

                    if [ "$app" = "$app_name_trimmed" ]; then
                        app_match=1
                    fi

                    app_sql="$(sql_escape "$app_name_trimmed")"
                    if [ -z "$condition" ]; then
                        condition="app = '$app_sql'"
                    else
                        condition="$condition OR app = '$app_sql'"
                    fi
                done

                [ "$app_match" -eq 0 ] && continue
                [ -z "$condition" ] && continue

                total_sec="$(/usr/bin/sqlite3 "$DB" "SELECT COALESCE(SUM(seconds), 0) FROM hourly_usage WHERE day = '$(sql_escape "$day")' AND ($condition);")"
            fi

            if [ "$total_sec" -ge "$limit_sec" ]; then
                echo "$(date '+%H:%M:%S') - Лимит исчерпан: $app, группа [$apps], $total_sec/$limit_sec секунд" >> "$LOGFILE"
                event_time="$(date '+%Y-%m-%d %H:%M:%S')"
                record_limit_event "$day" "$event_time" "$app" "$apps" "$limit_min" "$total_sec"
                close_limited_app "$app"
                return
            fi
        else
            echo "$(date '+%H:%M:%S') - Неверная строка config.ini: $line" >> "$LOGFILE"
        fi
    done < "$CONFIG"
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

    enforce_activity_limits "$DAY" "$APP"

    sleep "$INTERVAL_SEC"
done
