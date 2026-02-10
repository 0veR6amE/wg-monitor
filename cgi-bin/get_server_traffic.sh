#!/bin/bash
. /var/www/wg-monitor/config/config.sh

# Инициализация кэша и логов
init_cache_and_logs

# Функции логирования
log_debug() { [ "$LOG_LEVEL" = "DEBUG" ] && echo "[DEBUG] $1" >> "$LOG_FILE"; }
log_info() { echo "[INFO] $1" >> "$LOG_FILE"; }
log_warn() { echo "[WARN] $1" >> "$LOG_FILE"; }
log_error() { echo "[ERROR] $1" >> "$LOG_FILE"; }

# Функция аудита
audit_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1 | $REMOTE_ADDR | $HTTP_USER_AGENT" >> "$AUDIT_LOG"
}

# Функция кэширования
cache_get() {
    local cache_key=$1
    local cache_file="$CACHE_DIR/traffic/$cache_key"
    
    if [ -f "$cache_file" ] && [ "$CACHE_ENABLED" = "true" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        local ttl=$CACHE_TRAFFIC_TTL
        
        if [ $age -lt $ttl ]; then
            log_debug "Кэш HIT: $cache_key (возраст: ${age}с)"
            cat "$cache_file"
            echo "X-Cache-Status: HIT" >&2
            return 0
        else
            log_debug "Кэш EXPIRED: $cache_key (возраст: ${age}с)"
        fi
    fi
    return 1
}

cache_set() {
    local cache_key=$1
    local data=$2
    local cache_file="$CACHE_DIR/traffic/$cache_key"
    
    echo "$data" > "$cache_file"
    chown wg-monitor:wg-monitor "$cache_file"
    log_debug "Кэш SET: $cache_key"
}

# Основная функция получения трафика
get_traffic_data() {
    local period=$1
    local result=""
    
    case $period in
        "today")
            result=$(vnstat -i "$SERVER_INTERFACE" --json 2>/dev/null | \
                     jq -r '.interfaces[0].traffic.day | sort_by(.date.day) | last | .rx, .tx' 2>/dev/null || \
                     echo "0 0")
            ;;
        "month")
            result=$(vnstat -i "$SERVER_INTERFACE" --json 2>/dev/null | \
                     jq -r '.interfaces[0].traffic.month | sort_by(.date.month) | last | .rx, .tx' 2>/dev/null || \
                     echo "0 0")
            ;;
        "lastmonth")
            local last_month=$(date -d "last month" +"%Y-%m")
            result=$(vnstat -i "$SERVER_INTERFACE" --json 2>/dev/null | \
                     jq -r --arg month "$last_month" \
                     '.interfaces[0].traffic.month[] | select(.date.month == $month) | .rx, .tx' 2>/dev/null || \
                     echo "0 0")
            ;;
        "custom")
            # Заглушка для произвольного периода
            result="0 0"
            ;;
        *)
            result="0 0"
            ;;
    esac
    
    echo "$result"
}

# Форматирование байтов
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1099511627776 ]; then  # 1 TB
        echo "$(echo "scale=2; $bytes / 1099511627776" | bc) TB"
    elif [ "$bytes" -ge 1073741824 ]; then    # 1 GB
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then       # 1 MB
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then          # 1 KB
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# Парсинг результата
parse_traffic() {
    local data=$1
    local rx=$(echo "$data" | awk '{print $1}')
    local tx=$(echo "$data" | awk '{print $2}')
    
    # Проверка на валидность
    if ! [[ "$rx" =~ ^[0-9]+$ ]] || ! [[ "$tx" =~ ^[0-9]+$ ]]; then
        rx=0
        tx=0
        log_warn "Некорректные данные трафика: $data"
    fi
    
    local rx_formatted=$(format_bytes "$rx")
    local tx_formatted=$(format_bytes "$tx")
    
    cat <<EOF
{
    "rx": "$rx_formatted",
    "tx": "$tx_formatted",
    "rx_raw": $rx,
    "tx_raw": $tx,
    "timestamp": "$(date +%s)",
    "period": "$PERIOD"
}
EOF
}

# Основная логика
echo "Content-type: application/json"
echo "X-Powered-By: WireGuard-Monitor"
echo ""

# Аудит запроса
audit_log "TRAFFIC_QUERY | PERIOD=$QUERY_STRING"

# Получение периода из query string
PERIOD=$(echo "$QUERY_STRING" | sed -n 's/.*period=\([^&]*\).*/\1/p')
PERIOD=${PERIOD:-today}

# Генерация ключа кэша
CACHE_KEY=$(echo -n "$PERIOD:$SERVER_INTERFACE" | md5sum | cut -d' ' -f1)

# Проверка кэша
if cache_get "$CACHE_KEY"; then
    exit 0
fi

# Получение данных
START_TIME=$(date +%s%N)
traffic_data=$(get_traffic_data "$PERIOD")
END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

log_info "TRAFFIC | Период: $PERIOD | Время: ${DURATION}ms | Данные: $traffic_data"

# Парсинг и вывод
result=$(parse_traffic "$traffic_data")

# Сохранение в кэш
cache_set "$CACHE_KEY" "$result"

# Вывод результата
echo "$result"
echo "X-Execution-Time: ${DURATION}ms" >&2
echo "X-Cache-Status: MISS" >&2