#!/bin/bash
# Создание и смена паролей для доступа

set -e

. /var/www/wg-monitor/config/config.sh

PASSWORD_FILE="$WEB_ROOT/.htpasswd"

echo "Настройка паролей для WireGuard Monitor"

# Проверка наличия файла паролей
if [ -f "$PASSWORD_FILE" ]; then
    echo "Текущие пользователи:"
    cut -d: -f1 "$PASSWORD_FILE"
    
    read -p "Хотите добавить нового пользователя? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Имя пользователя: " username
        htpasswd "$PASSWORD_FILE" "$username"
        echo "Пользователь $username добавлен"
    fi
    
    read -p "Хотите сменить пароль существующего пользователя? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Имя пользователя: " username
        htpasswd "$PASSWORD_FILE" "$username"
        echo "Пароль для $username изменен"
    fi
else
    echo "Создание нового файла паролей..."
    read -p "Имя пользователя (по умолчанию: admin): " username
    username=${username:-admin}
    
    htpasswd -c "$PASSWORD_FILE" "$username"
    
    # Права на файл паролей
    chown wg-monitor:wg-monitor "$PASSWORD_FILE"
    chmod 640 "$PASSWORD_FILE"
    
    echo "Пользователь $username создан"
fi

# Создание хеша для быстрой проверки (опционально)
if command -v md5sum &>/dev/null; then
    md5sum "$PASSWORD_FILE" > "$PASSWORD_FILE.md5"
fi

echo "Пароли настроены. Файл: $PASSWORD_FILE"