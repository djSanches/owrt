#!/bin/sh
# Включает zapret2, если в подписках forkop больше 3 серверов, иначе выключает.
# Запускать по cron раз в час. Если forkop не отвечает, состояние zapret2 не трогаем.

THRESHOLD=3                       # включать, если серверов БОЛЬШЕ этого числа
ZAPRET_INIT=/etc/init.d/zapret2
TAG="forkop-zapret"

log() { logger -t "$TAG" "$*"; echo "$*"; }

[ -x "$ZAPRET_INIT" ] || { log "zapret2 не установлен ($ZAPRET_INIT)"; exit 1; }
command -v forkop >/dev/null 2>&1 || { log "forkop не найден"; exit 1; }
command -v ucode  >/dev/null 2>&1 || { log "ucode не найден"; exit 1; }

# Сумма серверов во всех подписках (providers) sing-box из forkop, через Clash API
count_servers() {
    forkop clash_api GET /providers/proxies 2>/dev/null | ucode -e '
        let fs = require("fs");
        let out = json(fs.stdin.read("all"));
        if (type(out) != "object" || out.status != 200)
            exit(2);
        let body = json(out.body);
        if (type(body) != "object")
            exit(2);
        let n = 0;
        for (let name, p in (body.providers ?? {}))
            n += length(p?.proxies ?? []);
        print(n, "\n");
    '
}

COUNT=$(count_servers) || { log "не удалось получить список серверов из forkop, ничего не меняю"; exit 0; }
case "$COUNT" in ''|*[!0-9]*) log "странный ответ: '$COUNT', ничего не меняю"; exit 0;; esac

if "$ZAPRET_INIT" status >/dev/null 2>&1; then RUNNING=1; else RUNNING=0; fi

if [ "$COUNT" -gt "$THRESHOLD" ]; then
    if [ "$RUNNING" -eq 0 ]; then
        log "серверов: $COUNT (> $THRESHOLD) — включаю zapret2"
        "$ZAPRET_INIT" enable  >/dev/null 2>&1
        "$ZAPRET_INIT" start   >/dev/null 2>&1
    else
        log "серверов: $COUNT (> $THRESHOLD) — zapret2 уже включён"
    fi
else
    if [ "$RUNNING" -eq 1 ]; then
        log "серверов: $COUNT (<= $THRESHOLD) — отключаю zapret2"
        "$ZAPRET_INIT" stop    >/dev/null 2>&1
        "$ZAPRET_INIT" disable >/dev/null 2>&1
        # как в Zapret Manager: добиваем оставшиеся процессы
        for pid in $(pgrep -f /opt/zapret2 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
    else
        log "серверов: $COUNT (<= $THRESHOLD) — zapret2 уже выключен"
    fi
fi
