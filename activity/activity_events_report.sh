#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$DIR/activity.sqlite"
DAY="${1:-$(date +%Y-%m-%d)}"

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

if [ ! -f "$DB" ]; then
    echo "No activity database found: $DB"
    exit 1
fi

DAY_ESCAPED="$(sql_escape "$DAY")"

/usr/bin/sqlite3 -header -column "$DB" "
SELECT
    event_time,
    app,
    group_name,
    action,
    limit_minutes,
    ROUND(total_seconds / 60.0, 1) AS total_minutes
FROM limit_events
WHERE day = '$DAY_ESCAPED'
ORDER BY event_time DESC;
"
