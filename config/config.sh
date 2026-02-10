#!/bin/bash
# Конфигурационный файл мониторинга WireGuard

# Имя интерфейса WireGuard
WG_INTERFACE="wg0"

# Основной сетевой интерфейс сервера
SERVER_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Пути к утилитам
WG_CMD="/usr/bin/wg"
VNSTAT_CMD="/usr/bin/vnstat"
PING_CMD="/bin/ping"
DATE_CMD="/bin/date"

# Настройки кэширования
CACHE_ENABLED=true
CACHE_DIR="/var/cache/wg-monitor"
CACHE_TRAFFIC_TTL=30     # секунд
CACHE_CLIENTS_TTL=15     # секунд
CACHE_PING_TTL=5         # секунд

# Настройки логирования
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
LOG_DIR="/var/log/wg-monitor"
LOG_FILE="$LOG_DIR/wg-monitor.log"
AUDIT_LOG="$LOG_DIR/audit.log"

# Пути
WEB_ROOT="/var/www/wg-monitor"
CGI_BIN="$WEB_ROOT/cgi-bin"
PUBLIC_HTML="$WEB_ROOT/public_html"

# Параметры безопасности
MAX_PING_PACKETS=4
PING_TIMEOUT=2
ALLOWED_IP_RANGE="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# Email для уведомлений (опционально)
ADMIN_EMAIL=""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Инициализация кэша и логов
init_cache_and_logs() {
    mkdir -p "$CACHE_DIR"/{traffic,clients,ping}
    mkdir -p "$LOG_DIR"
    
    # Создание лог файлов если их нет
    touch "$LOG_FILE" "$AUDIT_LOG"
    chmod 640 "$LOG_FILE" "$AUDIT_LOG"
    chown wg-monitor:wg-monitor "$LOG_FILE" "$AUDIT_LOG"
    
    # Очистка старых кэш файлов (старше 7 дней)
    find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
}

# Экспорт функций для использования в скриптах
export -f init_cache_and_logs