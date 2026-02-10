#!/bin/bash
. /var/www/wg-monitor/config/config.sh

echo "Content-type: application/json"
echo ""

# Получение статистики кэша
get_cache_stats() {
    local cache_size=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 || echo 0)
    local file_count=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    
    # Чтение логов для подсчета попаданий/промахов
    local hits=0
    local misses=0
    
    if [ -f "$WEB_ROOT/logs/access.log" ]; then
        hits=$(grep -c 'X-Cache-Status: HIT' "$WEB_ROOT/logs/access.log" 2>/dev/null || echo 0)
        misses=$(grep -c 'X-Cache-Status: MISS' "$WEB_ROOT/logs/access.log" 2>/dev/null || echo 0)
    fi
    
    cat <<EOF
{
    "size": $cache_size,
    "files": $file_count,
    "hits": $hits,
    "misses": $misses,
    "traffic_files": $(find "$CACHE_DIR/traffic" -type f 2>/dev/null | wc -l),
    "clients_files": $(find "$CACHE_DIR/clients" -type f 2>/dev/null | wc -l),
    "ping_files": $(find "$CACHE_DIR/ping" -type f 2>/dev/null | wc -l),
    "timestamp": "$(date +%s)"
}
EOF
}

get_cache_stats