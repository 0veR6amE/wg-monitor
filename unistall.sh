#!/bin/bash
# Скрипт удаления WireGuard Monitor

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

confirm_uninstall() {
    echo -e "${YELLOW}Вы уверены, что хотите удалить WireGuard Monitor?${NC}"
    echo -e "${RED}Это действие необратимо!${NC}"
    read -p "Введите 'yes' для подтверждения: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Удаление отменено"
        exit 0
    fi
}

stop_services() {
    echo "Остановка служб..."
    systemctl stop fcgiwrap-custom 2>/dev/null || true
    systemctl disable fcgiwrap-custom 2>/dev/null || true
}

remove_files() {
    echo "Удаление файлов..."
    
    # Удаление веб-файлов
    rm -rf /var/www/wg-monitor
    
    # Удаление конфигурации Nginx
    rm -f /etc/nginx/sites-available/wg-monitor
    rm -f /etc/nginx/sites-enabled/wg-monitor
    
    # Восстановление дефолтного сайта
    if [ -f /etc/nginx/sites-available/default ]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    fi
    
    # Удаление systemd службы
    rm -f /etc/systemd/system/fcgiwrap-custom.service
    
    # Удаление sudoers
    rm -f /etc/sudoers.d/wg-monitor
    
    # Удаление паролей
    rm -f /root/wg-monitor-password.txt
}

reload_services() {
    echo "Перезагрузка служб..."
    systemctl daemon-reload
    nginx -t && systemctl restart nginx
}

main() {
    confirm_uninstall
    stop_services
    remove_files
    reload_services
    
    echo -e "${GREEN}Удаление завершено!${NC}"
    echo "Если вы хотите сохранить логи, скопируйте их из /var/www/wg-monitor/logs/"
}

main "$@"