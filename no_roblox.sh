#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
LOGFILE="$DIR/roblox_block.log"
CONFIG="$DIR/config.ini"
TIMER_FILE="$DIR/.roblox_spent" # Скрытый файл со временем в секундах
WARNING_FILE="$DIR/.roblox_warning_sent"

# Функция сброса таймера в полночь (или при старте, если день сменился)
check_day_reset() {
    TODAY=$(date +%Y-%m-%d)
    LAST_RESET=$(date -r "$TIMER_FILE" +%Y-%m-%d 2>/dev/null)
    if [ "$TODAY" != "$LAST_RESET" ]; then
        echo "0" > "$TIMER_FILE"
        rm -f "$WARNING_FILE"
        echo "$(date) - Таймер сброшен на новый день" >> "$LOGFILE"
    fi
}

[ ! -f "$TIMER_FILE" ] && echo "0" > "$TIMER_FILE"

while true; do
    # Дефолты
    ALWAYS_BLOCK=1
    ROBLOX_LIMIT_MIN=0
    SLEEP_START=""
    SLEEP_END=""
    WARNING_BEFORE_SEC=300
    
    [ -f "$CONFIG" ] && source "$CONFIG"
    check_day_reset

    CURRENT_HOUR=$(date +%H)
    SPENT_SEC=$(cat "$TIMER_FILE")
    LIMIT_SEC=$((ROBLOX_LIMIT_MIN * 60))
    
    SHOULD_KILL=0

    # ПРОВЕРКА 1: Принудительный блок
    if [ "$ALWAYS_BLOCK" == "1" ]; then
        SHOULD_KILL=1
    fi

    # ПРОВЕРКА 2: Комендантский час
    if [ -n "$SLEEP_START" ] && [ -n "$SLEEP_END" ]; then
        if [ "$CURRENT_HOUR" -ge "$SLEEP_START" ] || [ "$CURRENT_HOUR" -lt "$SLEEP_END" ]; then
            SHOULD_KILL=1
        fi
    fi

    # ПРОВЕРКА 3: Лимит времени
    if [ "$SPENT_SEC" -ge "$LIMIT_SEC" ] && [ "$LIMIT_SEC" -gt 0 ]; then
        SHOULD_KILL=1
    fi

    # ОСНОВНОЙ ЦИКЛ ОБНАРУЖЕНИЯ
    if pgrep -f "Roblox" > /dev/null; then
        if [ "$SHOULD_KILL" -eq 1 ]; then
            echo "$(date '+%H:%M:%S') - Roblox убит (лимит или время)" >> "$LOGFILE"
            pkill -9 -f "Roblox"
            osascript -e 'display notification "Лимит времени исчерпан!" with title "Система"'
        else
            REMAINING_SEC=$((LIMIT_SEC - SPENT_SEC))
            if [ "$LIMIT_SEC" -gt 0 ] && [ "$REMAINING_SEC" -le "$WARNING_BEFORE_SEC" ] && [ "$REMAINING_SEC" -gt 0 ] && [ ! -f "$WARNING_FILE" ]; then
                echo "$(date '+%H:%M:%S') - Показано предупреждение: осталось 5 минут" >> "$LOGFILE"
                osascript -e 'display notification "Осталось 5 минут Roblox" with title "Предупреждение"'
                echo "1" > "$WARNING_FILE"
            fi

            # Если еще можно играть — прибавляем 5 секунд к счетчику
            SPENT_SEC=$((SPENT_SEC + 5))
            echo "$SPENT_SEC" > "$TIMER_FILE"
        fi
    fi

    sleep 5
done
