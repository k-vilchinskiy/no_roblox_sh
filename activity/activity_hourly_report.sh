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
    printf('%02d:00', hour) AS hour,
    app,
    seconds,
    ROUND(seconds / 60.0, 1) AS minutes,
    ROUND(seconds / 3600.0, 2) AS hours,
    updated_at
FROM hourly_usage
WHERE day = '$DAY_ESCAPED'
ORDER BY hour ASC, seconds DESC, app ASC;
"
