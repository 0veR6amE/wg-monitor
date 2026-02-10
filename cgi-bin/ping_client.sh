#!/bin/bash
. /var/www/wg-monitor/config/config.sh

# Инициализация кэша и логов
init_cache_and_logs

# Функции логирования
log_debug() { [ "$LOG_LEVEL" = "DEBUG" ] && echo "[DEBUG] $1" >> "$LOG_FILE"; }
log_info() { echo "[INFO] $1" >> "$LOG_FILE"; }
log_error() { echo "[ERROR] $1" >> "$LOG_FILE"; }

audit_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1 | $REMOTE_ADDR | $HTTP_USER_AGENT" >> "$AUDIT_LOG"
}

# Валидация IP
validate_ip() {
    local ip=$1
    
    # Проверка формата
    if ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Проверка октетов
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            return 1
        fi
    done
    
    # Проверка разрешенных диапазонов
    local allowed=0
    for range in $(echo "$ALLOWED_IP_RANGE" | tr ',' ' '); do
        if ipcalc -c "$ip/$range" &>/dev/null; then
            allowed=1
            break
        fi
    done
    
    [ "$allowed" -eq 1 ]
}

# Функция кэширования
cache_get() {
    local cache_key=$1
    local cache_file="$CACHE_DIR/ping/$cache_key"
    
    if [ -f "$cache_file" ] && [ "$CACHE_ENABLED" = "true" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        local ttl=$CACHE_PING_TTL
        
        if [ $age -lt $ttl ]; then
            log_debug "Кэш HIT: $cache_key (возраст: ${age}с)"
            cat "$cache_file"
            echo "X-Cache-Status: HIT" >&2
            return 0
        fi
    fi
    return 1
}

cache_set() {
    local cache_key=$1
    local data=$2
    local cache_file="$CACHE_DIR/ping/$cache_key"
    
    echo "$data" > "$cache_file"
    chown wg-monitor:wg-monitor "$cache_file"
    log_debug "Кэш SET: $cache_key"
}

# Основная логика
echo "Content-type: text/plain"
echo "X-Powered-By: WireGuard-Monitor"
echo ""

# Получение IP из параметров
IP=""
if [ "$REQUEST_METHOD" = "GET" ]; then
    IFS='&' read -ra PARAMS <<< "$QUERY_STRING"
    for param in "${PARAMS[@]}"; do
        IFS='=' read -r key value <<< "$param"
        if [ "$key" = "ip" ]; then
            IP=$(echo "$value" | sed 's/%20/ /g; s/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\\\x\1/g' | xargs -0 printf "%b")
            break
        fi
    done
fi

# Аудит запроса
audit_log "PING_QUERY | IP=$IP"

# Проверка IP
if [ -z "$IP" ]; then
    echo "ERROR: Не указан IP адрес"
    log_error "PING: Не указан IP"
    exit 1
fi

if ! validate_ip "$IP"; then
    echo "ERROR: Неверный IP адрес или адрес не из разрешенного диапазона"
    log_error "PING: Неверный IP: $IP"
    exit 1
fi

# Генерация ключа кэша
CACHE_KEY=$(echo -n "ping_$IP" | md5sum | cut -d' ' -f1)

# Проверка кэша
if cache_get "$CACHE_KEY"; then
    exit 0
fi

# Выполнение ping
START_TIME=$(date +%s%N)
result=$(sudo "$PING_CMD" -c "$MAX_PING_PACKETS" -W "$PING_TIMEOUT" "$IP" 2>&1)
END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

# Проверка результата
if echo "$result" | grep -q "100% packet loss"; then
    status="FAIL"
    log_info "PING | IP: $IP | Статус: FAIL | Время: ${DURATION}ms"
elif echo "$result" | grep -q "received, 0% packet loss"; then
    status="OK"
    log_info "PING | IP: $IP | Статус: OK | Время: ${DURATION}ms"
else
    status="UNKNOWN"
    log_warn "PING | IP: $IP | Статус: UNKNOWN | Время: ${DURATION}ms"
fi

# Форматирование вывода
output="[$(date '+%Y-%m-%d %H:%M:%S')] Ping тест: $IP"
output+=$'\n'$'\n'"$result"
output+=$'\n'$'\n'"Статус: $status"
output+=$'\n'"Время выполнения: ${DURATION}ms"

# Сохранение в кэш
if [ "$status" = "OK" ] || [ "$status" = "FAIL" ]; then
    cache_set "$CACHE_KEY" "$output"
fi

# Вывод
echo "$output"
echo "X-Execution-Time: ${DURATION}ms" >&2
echo "X-Cache-Status: MISS" >&2