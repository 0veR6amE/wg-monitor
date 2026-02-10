#!/bin/bash
# Мониторинг ресурсов и производительности

set -e

. /var/www/wg-monitor/config/config.sh

LOG_FILE="$LOG_DIR/resources.log"

# Функция логирования
log_resource() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Проверка использования диска
check_disk() {
    local usage=$(df -h "$WEB_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
    local cache_usage=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    
    if [ "$usage" -gt 90 ]; then
        log_resource "WARNING: Диск заполнен на $usage%"
        return 1
    fi
    
    log_resource "DISK: Использовано $usage%, Кэш: $cache_usage"
    echo "Диск: $usage% заполнено, Кэш: $cache_usage"
}

# Проверка памяти
check_memory() {
    local total=$(free -m | awk '/^Mem:/{print $2}')
    local used=$(free -m | awk '/^Mem:/{print $3}')
    local percent=$((used * 100 / total))
    
    if [ "$percent" -gt 90 ]; then
        log_resource "WARNING: Память заполнена на $percent%"
        return 1
    fi
    
    log_resource "MEMORY: Использовано ${used}MB из ${total}MB ($percent%)"
    echo "Память: ${used}MB/${total}MB ($percent%)"
}

# Проверка нагрузки CPU
check_cpu() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local cores=$(nproc)
    
    log_resource "CPU: Нагрузка $load (ядер: $cores)"
    echo "CPU: Нагрузка $load"
}

# Проверка служб
check_services() {
    local services=("nginx" "fcgiwrap-custom")
    local all_ok=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_resource "SERVICE: $service работает"
        else
            log_resource "ERROR: $service не работает"
            all_ok=false
        fi
    done
    
    $all_ok && echo "Службы: OK" || echo "Службы: Ошибка"
    return $all_ok
}

# Проверка кэша
check_cache() {
    local cache_files=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    local cache_size=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1)
    local cache_hits=0
    local cache_misses=0
    
    if [ -f "$WEB_ROOT/logs/access.log" ]; then
        cache_hits=$(grep -c 'X-Cache-Status: HIT' "$WEB_ROOT/logs/access.log" 2>/dev/null || echo 0)
        cache_misses=$(grep -c 'X-Cache-Status: MISS' "$WEB_ROOT/logs/access.log" 2>/dev/null || echo 0)
    fi
    
    local hit_rate=0
    if [ $((cache_hits + cache_misses)) -gt 0 ]; then
        hit_rate=$((cache_hits * 100 / (cache_hits + cache_misses)))
    fi
    
    log_resource "CACHE: Файлов: $cache_files, Размер: $cache_size, Hit rate: $hit_rate%"
    echo "Кэш: $cache_files файлов ($((cache_size/1024))KB), Hit rate: $hit_rate%"
}

# Проверка сетевых интерфейсов
check_network() {
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        local wg_status=$(wg show "$WG_INTERFACE" 2>/dev/null | grep -c "peer:")
        log_resource "NETWORK: WireGuard $WG_INTERFACE: $wg_status пиров"
        echo "WireGuard: $wg_status активных пиров"
    else
        log_resource "WARNING: Интерфейс $WG_INTERFACE не найден"
        echo "WireGuard: Интерфейс не найден"
        return 1
    fi
}

# Очистка старых логов
cleanup_logs() {
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
    find "$WEB_ROOT/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    log_resource "CLEANUP: Старые логи очищены"
}

# Основная функция
main() {
    echo "=== Мониторинг ресурсов WireGuard Monitor ==="
    echo "Время: $(date)"
    echo "----------------------------------------"
    
    check_disk
    check_memory
    check_cpu
    check_services
    check_cache
    check_network
    cleanup_logs
    
    echo "----------------------------------------"
    echo "Логи: $LOG_FILE"
    echo "Кэш: $CACHE_DIR"
}

# Запуск
main "$@"