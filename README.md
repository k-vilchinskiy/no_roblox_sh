# no_roblox

`no_roblox` - простой watchdog-скрипт для macOS, который ограничивает запуск Roblox.
Он нужен как замена стандартным ограничениям macOS, если они не блокируют Roblox надежно после окончания времени.

Скрипт работает в фоне через `launchd`, проверяет наличие процесса Roblox каждые 5 секунд и при необходимости завершает его.

## Что делает скрипт

- читает настройки из `config.ini`;
- ведет дневной счетчик времени игры в `.roblox_spent`;
- сбрасывает счетчик при смене дня;
- завершает Roblox, если включена постоянная блокировка;
- завершает Roblox во время комендантского часа;
- завершает Roblox, если дневной лимит времени исчерпан;
- пишет события в `roblox_block.log`.

## Настройка

Все основные настройки лежат в `config.ini`.

```ini
# 1 - блокировать всегда, 0 - учитывать лимит и время
ALWAYS_BLOCK=0

# Лимит на Roblox в минутах
ROBLOX_LIMIT_MIN=180

# Комендантский час
SLEEP_START=21
SLEEP_END=10
```

Параметры:

- `ALWAYS_BLOCK=1` - Roblox всегда будет закрываться сразу после запуска.
- `ALWAYS_BLOCK=0` - применяется дневной лимит и комендантский час.
- `ROBLOX_LIMIT_MIN=180` - разрешить 180 минут Roblox в день.
- `ROBLOX_LIMIT_MIN=0` - дневной лимит выключен.
- `SLEEP_START=21` и `SLEEP_END=10` - Roblox будет блокироваться с 21:00 до 10:00.

После изменения `config.ini` перезапускать сервис не обязательно: скрипт перечитывает конфиг в каждом цикле.

## Установка

Перейти в папку проекта:

```bash
cd /path/to/no_roblox
```

Создать LaunchAgent:

```bash
./install.sh
```

`install.sh` создает файл:

```text
~/Library/LaunchAgents/com.user.noroblox.plist
```

В plist автоматически записывается абсолютный путь к текущему `no_roblox.sh`.

## Запуск

Включить фоновый сервис:

```bash
./enable.sh
```

После этого `launchd` запустит `no_roblox.sh` и будет перезапускать его при завершении.

## Остановка

Выключить фоновый сервис:

```bash
./disable.sh
```

## Логи и файлы состояния

Основной лог:

```text
roblox_block.log
```

Ошибки запуска через `launchd`:

```text
roblox_error.log
```

Счетчик использованного времени за текущий день (в секундах):

```text
.roblox_spent
```

`roblox_block.log`, `roblox_error.log` и `.roblox_spent` не нужно коммитить в git: это рабочие файлы конкретного Mac.

## Проверка статуса

Проверить, загружен ли LaunchAgent:

```bash
launchctl list | grep com.user.noroblox
```

Если строки нет, сервис не запущен.

## Статистика активных приложений

Отдельный сервис `activity_tracker.sh` может собирать статистику активного приложения.
Он каждые 5 секунд определяет frontmost-приложение через `lsappinfo` и добавляет время в SQLite-базу `activity.sqlite`.
Если `lsappinfo` недоступен, скрипт пробует fallback через `osascript`; для него могут понадобиться разрешения в `System Settings -> Privacy & Security -> Accessibility` и `Automation`.
LaunchAgent запускается в `gui/$UID`, чтобы у него был доступ к пользовательской графической сессии.

Установить LaunchAgent:

```bash
(cd activity && ./install_activity_tracker.sh)
```

Включить сервис:

```bash
(cd activity && ./enable_activity_tracker.sh)
```

Выключить сервис:

```bash
(cd activity && ./disable_activity_tracker.sh)
```

Показать статистику за сегодня:

```bash
./activity/activity_report.sh
```

Показать статистику за конкретный день:

```bash
./activity/activity_report.sh 2026-07-26
```

Показать статистику по часам за сегодня:

```bash
./activity/activity_hourly_report.sh
```

Показать статистику по часам за конкретный день:

```bash
./activity/activity_hourly_report.sh 2026-07-26
```

Показать события закрытия приложений по лимитам:

```bash
./activity/activity_events_report.sh
```

macOS обычно уже содержит `/usr/bin/sqlite3`, поэтому отдельная установка SQLite не нужна.

### Лимиты приложений

Сервис статистики может также закрывать приложения после дневного лимита.
Лимиты задаются в `activity/config.ini`:

```ini
EXCLUDE_APPS=Finder,System Settings,Terminal,Activity Monitor
SLEEP_START=21
SLEEP_END=10
WARNING_BEFORE_SEC=300

[Roblox]: 180
[Google Chrome, Safari]: 60
[*]: 240
```

Число справа - минуты в день. В строке с несколькими приложениями лимит общий для всей группы.
Например `[Google Chrome, Safari]: 60` означает один общий час на браузеры.
`[*]: 240` означает общий дневной лимит активного времени всех приложений.
Имена приложений должны совпадать с именами из `activity_report.sh`.
`SLEEP_START` и `SLEEP_END` задают комендантский интервал по часам.
`EXCLUDE_APPS` никогда не закрываются лимитами или комендантским режимом.
`WARNING_BEFORE_SEC=300` показывает предупреждение за 5 минут до лимита.
