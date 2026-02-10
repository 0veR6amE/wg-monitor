#!/bin/bash
# Настройка прав доступа и безопасности

set -e

. /var/www/wg-monitor/config/config.sh

echo "Настройка прав доступа..."

# Создание пользователя если не существует
if ! id "wg-monitor" &>/dev/null; then
    useradd -r -s /bin/bash -m -d /home/wg-monitor wg-monitor
    echo "Пользователь wg-monitor создан"
fi

# Создание групп
usermod -a -G wg-monitor www-data || true

# Установка прав на каталоги
mkdir -p "$CACHE_DIR" "$LOG_DIR" "$WEB_ROOT"/{cgi-bin,public_html,config,logs}

# Основные права
chown -R wg-monitor:wg-monitor "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# Права на скрипты
chmod +x "$CGI_BIN"/*.sh

# Права на кэш и логи
chown -R wg-monitor:wg-monitor "$CACHE_DIR" "$LOG_DIR"
chmod -R 750 "$CACHE_DIR"
chmod -R 755 "$LOG_DIR"

# Создание файлов логов
touch "$WEB_ROOT"/logs/{access.log,error.log,cgi.log}
chown wg-monitor:wg-monitor "$WEB_ROOT"/logs/*.log
chmod 640 "$WEB_ROOT"/logs/*.log

# Настройка sudoers
echo "Настройка sudoers..."
cat > /tmp/wg-monitor-sudoers << EOF
# Разрешения для пользователя wg-monitor
Defaults:wg-monitor !requiretty
Defaults:wg-monitor !syslog

wg-monitor ALL=(ALL) NOPASSWD: \\
    $WG_CMD show $WG_INTERFACE dump, \\
    $PING_CMD -c $MAX_PING_PACKETS -W $PING_TIMEOUT *, \\
    $VNSTAT_CMD --json

# Логирование команд sudo
Defaults logfile=/var/log/sudo_wg_monitor.log
Defaults log_input, log_output
EOF

visudo -c -f /tmp/wg-monitor-sudoers && \
    cp /tmp/wg-monitor-sudoers /etc/sudoers.d/wg-monitor && \
    chmod 440 /etc/sudoers.d/wg-monitor

rm -f /tmp/wg-monitor-sudoers

# Настройка AppArmor если установлен
if command -v aa-status &>/dev/null; then
    echo "Настройка AppArmor..."
    cat > /etc/apparmor.d/local/usr.sbin.nginx << EOF
# WireGuard Monitor permissions
/var/www/wg-monitor/** r,
/var/cache/wg-monitor/** rw,
/var/log/wg-monitor/** rw,
/tmp/** rw,
EOF
    apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx
fi

# Настройка systemd журнала для пользователя wg-monitor
mkdir -p /etc/systemd/system/fcgiwrap-custom.service.d/
cat > /etc/systemd/system/fcgiwrap-custom.service.d/override.conf << EOF
[Service]
User=wg-monitor
Group=wg-monitor
LogLevelMax=debug
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wg-monitor
EOF

echo "Права доступа настроены успешно"