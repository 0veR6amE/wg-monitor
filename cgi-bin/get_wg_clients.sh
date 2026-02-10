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

# Функция кэширования
cache_get() {
    local cache_key=$1
    local cache_file="$CACHE_DIR/clients/$cache_key"
    
    if [ -f "$cache_file" ] && [ "$CACHE_ENABLED" = "true" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        local ttl=$CACHE_CLIENTS_TTL
        
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
    local cache_file="$CACHE_DIR/clients/$cache_key"
    
    echo "$data" > "$cache_file"
    chown wg-monitor:wg-monitor "$cache_file"
    log_debug "Кэш SET: $cache_key"
}

# Получение данных о клиентах
get_clients_data() {
    sudo "$WG_CMD" show "$WG_INTERFACE" dump 2>/dev/null || {
        log_error "Не удалось получить данные WireGuard"
        echo ""
    }
}

# Получение имени клиента из конфига
get_client_name() {
    local public_key=$1
    local config_file="/etc/wireguard/$WG_INTERFACE.conf"
    
    if [ -f "$config_file" ]; then
        # Ищем публичный ключ и берем комментарий над ним
        grep -B1 "$public_key" "$config_file" | grep -E "^# " | head -n1 | sed 's/# //' | xargs
    fi
}

# Форматирование трафика
format_traffic() {
    local bytes=$1
    if [ "$bytes" -ge 1099511627776 ]; then
        echo "$(echo "scale=2; $bytes / 1099511627776" | bc) TB"
    elif [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# Парсинг данных клиентов
parse_clients() {
    local clients="["
    local first=true
    local total_clients=0
    local total_rx=0
    local total_tx=0
    
    get_clients_data | while IFS=$'\t' read -r public_key preshared_key endpoint allowed_ips latest_handshake transfer_rx transfer_tx persistent_keepalive; do
        # Пропускаем первую строку (сервер)
        if [ -z "$public_key" ] || [[ "$public_key" == $(sudo "$WG_CMD" show "$WG_INTERFACE" public-key 2>/dev/null) ]]; then
            continue
        fi
        
        ((total_clients++))
        total_rx=$((total_rx + transfer_rx))
        total_tx=$((total_tx + transfer_tx))
        
        # Получение имени
        local client_name=$(get_client_name "$public_key")
        client_name=${client_name:-"Клиент $total_clients"}
        
        # Форматирование времени
        local last_handshake
        if [ "$latest_handshake" -eq "0" ]; then
            last_handshake="Never"
        else
            last_handshake=$(date -d @"$latest_handshake" "+%Y-%m-%d %H:%M:%S")
        fi
        
        # Форматирование трафика
        local rx_formatted=$(format_traffic "$transfer_rx")
        local tx_formatted=$(format_traffic "$transfer_tx")
        
        if [ "$first" = true ]; then
            first=false
        else
            clients+=","
        fi
        
        clients+=$(cat <<EOF
{
    "name": "$(echo "$client_name" | sed 's/"/\\"/g')",
    "public_key": "${public_key:0:8}...",
    "ip": "$allowed_ips",
    "last_handshake": "$last_handshake",
    "transfer_rx": "$rx_formatted",
    "transfer_tx": "$tx_formatted",
    "transfer_rx_raw": $transfer_rx,
    "transfer_tx_raw": $transfer_tx,
    "endpoint": "$endpoint",
    "status": "$([ "$latest_handshake" -gt $(date -d "5 minutes ago" +%s) ] && echo "online" || echo "offline")"
}
EOF
        )
    done
    
    clients+="]"
    
    # Добавляем метаданные
    cat <<EOF
{
    "clients": $clients,
    "meta": {
        "total": $total_clients,
        "total_rx": "$(format_traffic $total_rx)",
        "total_tx": "$(format_traffic $total_tx)",
        "timestamp": "$(date +%s)",
        "wg_interface": "$WG_INTERFACE"
    }
}
EOF
}

# Основная логика
echo "Content-type: application/json"
echo "X-Powered-By: WireGuard-Monitor"
echo ""

# Аудит
audit_log "CLIENTS_QUERY"

# Кэширование
CACHE_KEY="clients_$(date +%Y%m%d_%H%M%S)"

if cache_get "$CACHE_KEY"; then
    exit 0
fi

# Получение данных
START_TIME=$(date +%s%N)
result=$(parse_clients)
END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

log_info "CLIENTS | Время: ${DURATION}ms | Клиентов: $(echo "$result" | jq '.meta.total' 2>/dev/null || echo 0)"

# Сохранение в кэш
cache_set "$CACHE_KEY" "$result"

# Вывод
echo "$result"
echo "X-Execution-Time: ${DURATION}ms" >&2
echo "X-Cache-Status: MISS" >&2