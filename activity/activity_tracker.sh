#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$DIR/activity.sqlite"
LOGFILE="$DIR/activity_tracker.log"
CONFIG="$DIR/config.ini"
INTERVAL_SEC=5
EXCLUDE_APPS=""
SLEEP_START=""
SLEEP_END=""
WARNING_BEFORE_SEC=300

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

applescript_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

trim() {
    printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

load_settings() {
    local line key value

    EXCLUDE_APPS=""
    SLEEP_START=""
    SLEEP_END=""
    WARNING_BEFORE_SEC=300

    [ ! -f "$CONFIG" ] && return

    while IFS='=' read -r key value; do
        key="${key%%#*}"
        key="$(trim "$key")"
        value="${value%%#*}"
        value="$(trim "$value")"

        case "$key" in
            EXCLUDE_APPS)
                EXCLUDE_APPS="$value"
                ;;
            SLEEP_START|SLEEP_END|WARNING_BEFORE_SEC)
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    eval "$key=$value"
                fi
                ;;
        esac
    done < "$CONFIG"
}

is_excluded_app() {
    local app="$1"
    local excluded excluded_trimmed

    [ -z "$EXCLUDE_APPS" ] && return 1

    IFS=',' read -ra EXCLUDED_NAMES <<< "$EXCLUDE_APPS"
    for excluded in "${EXCLUDED_NAMES[@]}"; do
        excluded_trimmed="$(trim "$excluded")"
        if [ "$app" = "$excluded_trimmed" ]; then
            return 0
        fi
    done

    return 1
}

is_sleep_time() {
    local current_hour="$1"

    [ -z "$SLEEP_START" ] && return 1
    [ -z "$SLEEP_END" ] && return 1

    if [ "$SLEEP_START" -eq "$SLEEP_END" ]; then
        return 1
    fi

    if [ "$SLEEP_START" -lt "$SLEEP_END" ]; then
        [ "$current_hour" -ge "$SLEEP_START" ] && [ "$current_hour" -lt "$SLEEP_END" ]
    else
        [ "$current_hour" -ge "$SLEEP_START" ] || [ "$current_hour" -lt "$SLEEP_END" ]
    fi
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

show_limit_warning() {
    local app="$1"
    local remaining_sec="$2"
    local app_escaped remaining_min

    app_escaped="$(applescript_escape "$app")"
    remaining_min=$(((remaining_sec + 59) / 60))

    /usr/bin/osascript \
        -e "display alert \"Time limit warning\" message \"About $remaining_min minutes left for $app_escaped.\" buttons {\"OK\"} default button \"OK\" giving up after 30" \
        >/dev/null 2>&1 &
}

record_limit_event() {
    local day="$1"
    local event_time="$2"
    local app="$3"
    local group_name="$4"
    local limit_min="$5"
    local total_sec="$6"
    local action="$7"
    local app_sql group_sql event_time_sql

    [ -z "$action" ] && action="closed"

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
    '$(sql_escape "$action")'
);
SELECT changes();
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

            if [ "$total_sec" -lt "$limit_sec" ] && [ $((limit_sec - total_sec)) -le "$WARNING_BEFORE_SEC" ]; then
                event_time="$(date '+%Y-%m-%d %H:%M:%S')"
                if [ "$(record_limit_event "$day" "$event_time" "$app" "$apps" "$limit_min" "$total_sec" "warning")" = "1" ]; then
                    echo "$(date '+%H:%M:%S') - Warning shown: $app, group [$apps], $total_sec/$limit_sec seconds" >> "$LOGFILE"
                    show_limit_warning "$app" "$((limit_sec - total_sec))"
                fi
            fi

            if [ "$total_sec" -ge "$limit_sec" ]; then
                echo "$(date '+%H:%M:%S') - Лимит исчерпан: $app, группа [$apps], $total_sec/$limit_sec секунд" >> "$LOGFILE"
                event_time="$(date '+%Y-%m-%d %H:%M:%S')"
                record_limit_event "$day" "$event_time" "$app" "$apps" "$limit_min" "$total_sec" "closed" >/dev/null
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

    load_settings

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

    if [ "$APP" != "Unknown" ] && ! is_excluded_app "$APP"; then
        if is_sleep_time "$HOUR"; then
            echo "$(date '+%H:%M:%S') - Sleep time: closing $APP" >> "$LOGFILE"
            record_limit_event "$DAY" "$UPDATED_AT" "$APP" "SLEEP_TIME" 0 0 "closed" >/dev/null
            close_limited_app "$APP"
        else
            enforce_activity_limits "$DAY" "$APP"
        fi
    fi

    sleep "$INTERVAL_SEC"
done
