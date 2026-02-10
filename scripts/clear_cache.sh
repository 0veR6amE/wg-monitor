#!/bin/bash
. /var/www/wg-monitor/config/config.sh

echo "Content-type: application/json"
echo ""

# Проверка авторизации (базовая)
if [ -z "$REMOTE_USER" ]; then
    echo '{"status": "error", "message": "Требуется авторизация"}'
    exit 1
fi

# Очистка кэша
clear_cache() {
    local cache_type=$1
    
    case $cache_type in
        "all")
            rm -rf "$CACHE_DIR"/*
            mkdir -p "$CACHE_DIR"/{traffic,clients,ping}
            echo "Весь кэш очищен"
            ;;
        "traffic")
            rm -rf "$CACHE_DIR/traffic"/*
            echo "Кэш трафика очищен"
            ;;
        "clients")
            rm -rf "$CACHE_DIR/clients"/*
            echo "Кэш клиентов очищен"
            ;;
        "ping")
            rm -rf "$CACHE_DIR/ping"/*
            echo "Кэш ping очищен"
            ;;
        *)
            echo "Неизвестный тип кэша"
            return 1
            ;;
    esac
}

# Получение параметра
CACHE_TYPE="all"
if [ "$REQUEST_METHOD" = "GET" ]; then
    IFS='&' read -ra PARAMS <<< "$QUERY_STRING"
    for param in "${PARAMS[@]}"; do
        IFS='=' read -r key value <<< "$param"
        if [ "$key" = "type" ]; then
            CACHE_TYPE="$value"
            break
        fi
    done
fi

# Логирование
audit_log "CACHE_CLEAR | TYPE=$CACHE_TYPE | USER=$REMOTE_USER"

# Очистка
if clear_cache "$CACHE_TYPE"; then
    cat <<EOF
{
    "status": "success",
    "message": "Кэш успешно очищен",
    "type": "$CACHE_TYPE",
    "timestamp": "$(date +%s)"
}
EOF
else
    cat <<EOF
{
    "status": "error",
    "message": "Ошибка при очистке кэша",
    "type": "$CACHE_TYPE"
}
EOF
fi