#!/bin/bash
# WireGuard Monitor - Автоматический установщик
# Версия: 1.0.0

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
LOG_FILE="/tmp/wg-monitor-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}     WireGuard Monitor установка       ${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Проверка прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Пожалуйста, запустите скрипт с sudo: sudo $0"
        exit 1
    fi
}

# Проверка системы
check_system() {
    print_status "Проверка системы..."
    
    # Проверка дистрибутива
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    print_status "Операционная система: $OS $VER"
    
    # Проверка архитектуры
    ARCH=$(uname -m)
    print_status "Архитектура: $ARCH"
    
    # Проверка свободного места
    FREE_SPACE=$(df -h /var | tail -1 | awk '{print $4}')
    print_status "Свободное место в /var: $FREE_SPACE"
}

# Установка зависимостей
install_dependencies() {
    print_status "Установка зависимостей..."
    
    apt-get update -qq
    
    # Основные пакеты
    apt-get install -y -qq \
        nginx \
        fcgiwrap \
        vnstat \
        curl \
        wget \
        git \
        sudo \
        bc
    
    # Проверка установки
    for cmd in nginx fcgiwrap vnstat; do
        if command -v $cmd &> /dev/null; then
            print_success "$cmd установлен"
        else
            print_error "$cmd не установлен"
            exit 1
        fi
    done
}

# Создание структуры каталогов
create_directories() {
    print_status "Создание структуры каталогов..."
    
    mkdir -p /var/www/wg-monitor/{public_html,cgi-bin,config,logs}
    mkdir -p /var/www/wg-monitor/public_html/{css,js,assets}
    
    # Копирование файлов
    cp -r public_html/* /var/www/wg-monitor/public_html/
    cp -r cgi-bin/* /var/www/wg-monitor/cgi-bin/
    cp -r config/* /var/www/wg-monitor/config/
    
    print_success "Файлы скопированы"
}

# Настройка пользователя
setup_user() {
    print_status "Настройка пользователя wg-monitor..."
    
    if id "wg-monitor" &>/dev/null; then
        print_warning "Пользователь wg-monitor уже существует"
    else
        useradd -r -s /bin/bash wg-monitor
        print_success "Пользователь wg-monitor создан"
    fi
    
    usermod -a -G wg-monitor www-data
}

# Настройка прав
setup_permissions() {
    print_status "Настройка прав доступа..."
    
    chown -R wg-monitor:wg-monitor /var/www/wg-monitor
    chmod -R 755 /var/www/wg-monitor
    chmod +x /var/www/wg-monitor/cgi-bin/*.sh
    
    # Права на логи
    touch /var/www/wg-monitor/logs/{access.log,error.log}
    chown wg-monitor:wg-monitor /var/www/wg-monitor/logs/*
    chmod 644 /var/www/wg-monitor/logs/*
    
    print_success "Права настроены"
}

# Настройка sudoers
setup_sudoers() {
    print_status "Настройка sudoers..."
    
    SUDOERS_FILE="/etc/sudoers.d/wg-monitor"
    
    cat > "$SUDOERS_FILE" << EOF
# Разрешения для пользователя wg-monitor
wg-monitor ALL=(ALL) NOPASSWD: /usr/bin/wg show wg0 dump, /bin/ping -c 4 *
Defaults:wg-monitor !requiretty
EOF
    
    chmod 440 "$SUDOERS_FILE"
    
    # Проверка синтаксиса
    if visudo -c -f "$SUDOERS_FILE"; then
        print_success "Sudoers настроен"
    else
        print_error "Ошибка в sudoers файле"
        rm -f "$SUDOERS_FILE"
    fi
}

# Настройка Nginx
setup_nginx() {
    print_status "Настройка Nginx..."
    
    # Создаем отдельный файл для log_format
    LOG_FORMAT_FILE="/etc/nginx/conf.d/log-format.conf"
    cat > "$LOG_FORMAT_FILE" << 'EOF'
log_format json_log escape=json '{"time":"$time_local",'
                                '"remote_addr":"$remote_addr",'
                                '"remote_user":"$remote_user",'
                                '"request":"$request",'
                                '"status":"$status",'
                                '"body_bytes_sent":"$body_bytes_sent",'
                                '"request_time":"$request_time",'
                                '"http_referrer":"$http_referer",'
                                '"http_user_agent":"$http_user_agent"}';
EOF
    
    NGINX_CONF="/etc/nginx/sites-available/wg-monitor"
    
    # Копирование конфигурации (без директивы log_format внутри server)
    cp config/nginx-wg-monitor.conf "$NGINX_CONF"
    
    # Создаем директории для логов и кэша
    mkdir -p /var/www/wg-monitor/logs /var/cache/nginx/wg
    chown -R www-data:www-data /var/www/wg-monitor/logs /var/cache/nginx
    
    # Активация сайта
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    
    # Удаление дефолтного сайта
    if [ -f /etc/nginx/sites-enabled/default ]; then
        rm /etc/nginx/sites-enabled/default
    fi
    
    # Проверка конфигурации
    if nginx -t; then
        print_success "Конфигурация Nginx проверена"
        systemctl reload nginx
    else
        print_error "Ошибка в конфигурации Nginx"
        exit 1
    fi
}

# Настройка fcgiwrap
setup_fcgiwrap() {
    print_status "Настройка fcgiwrap..."
    
    if [ -f systemd/fcgiwrap-custom.service ]; then
        cp systemd/fcgiwrap-custom.service /etc/systemd/system/
    fi
    
    systemctl daemon-reload
    systemctl enable fcgiwrap-custom
    systemctl restart fcgiwrap-custom
    
    print_success "fcgiwrap настроен"
}

# Настройка vnstat
setup_vnstat() {
    print_status "Настройка vnstat..."
    
    # Определение сетевого интерфейса
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [ -z "$INTERFACE" ]; then
        print_warning "Не удалось определить сетевой интерфейс"
        return
    fi
    
    print_status "Определен интерфейс: $INTERFACE"
    
    # Обновление конфигурации
    sed -i "s/SERVER_INTERFACE=.*/SERVER_INTERFACE=\"$INTERFACE\"/" /var/www/wg-monitor/config/config.sh
    
    # Инициализация vnstat
    vnstat -u -i "$INTERFACE" 2>/dev/null || true
    
    # Запуск службы
    systemctl enable vnstat
    systemctl restart vnstat
    
    print_success "vnstat настроен для интерфейса $INTERFACE"
}

# Создание файла паролей
create_password() {
    print_status "Создание файла паролей..."
    
    PASSWORD_FILE="/var/www/wg-monitor/.htpasswd"
    
    # Запрос пароля
    echo -e "\n${YELLOW}Настройка пароля администратора:${NC}"
    echo -e "${BLUE}По умолчанию: логин=admin, пароль=admin${NC}"
    read -p "Хотите изменить пароль? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -sp "Введите новый пароль для admin: " PASSWORD
        echo
        read -sp "Повторите пароль: " PASSWORD_CONFIRM
        echo
        
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            print_error "Пароли не совпадают"
            exit 1
        fi
        
        if [ -z "$PASSWORD" ]; then
            PASSWORD="admin"
            print_warning "Используется пароль по умолчанию"
        fi
    else
        PASSWORD="admin"
    fi
    
    # Создание файла паролей
    echo "admin:$(openssl passwd -crypt "$PASSWORD")" > "$PASSWORD_FILE"
    chown wg-monitor:wg-monitor "$PASSWORD_FILE"
    chmod 640 "$PASSWORD_FILE"
    
    print_success "Файл паролей создан"
    
    # Сохранение пароля в файл (только для отладки)
    if [ "$PASSWORD" != "admin" ]; then
        echo "Ваш пароль: $PASSWORD" > /root/wg-monitor-password.txt
        chmod 600 /root/wg-monitor-password.txt
        print_warning "Пароль сохранен в /root/wg-monitor-password.txt"
    fi
}

# Проверка WireGuard
check_wireguard() {
    print_status "Проверка WireGuard..."
    
    if command -v wg &> /dev/null; then
        WG_INTERFACE=$(grep -o "WG_INTERFACE=.*" /var/www/wg-monitor/config/config.sh | cut -d'"' -f2)
        
        if [ -f "/etc/wireguard/$WG_INTERFACE.conf" ]; then
            print_success "WireGuard найден (интерфейс: $WG_INTERFACE)"
        else
            print_warning "Конфигурация WireGuard не найдена"
            print_warning "Измените WG_INTERFACE в /var/www/wg-monitor/config/config.sh"
        fi
    else
        print_warning "WireGuard не установлен"
        print_warning "Установите: apt install wireguard"
    fi
}

# Запуск служб
start_services() {
    print_status "Запуск служб..."
    
    systemctl restart nginx
    systemctl restart fcgiwrap-custom
    
    # Проверка статуса
    for service in nginx fcgiwrap-custom; do
        if systemctl is-active --quiet "$service"; then
            print_success "$service запущен"
        else
            print_error "$service не запущен"
            systemctl status "$service"
        fi
    done
}

# Финальная проверка
final_check() {
    print_status "Финальная проверка..."
    
    # Проверка доступности
    sleep 2
    if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "401\|200"; then
        print_success "Сайт доступен (требуется аутентификация)"
    else
        print_error "Сайт недоступен"
    fi
    
    # Проверка CGI скриптов
    if sudo -u wg-monitor /var/www/wg-monitor/cgi-bin/get_wg_clients.sh 2>&1 | grep -q "Content-type"; then
        print_success "CGI скрипты работают"
    else
        print_warning "CGI скрипты могут требовать настройки"
    fi
}

# Показать информацию
show_info() {
    print_header
    
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}✅ Установка завершена успешно!${NC}\n"
    echo -e "${BLUE}Информация о системе:${NC}"
    echo -e "  Панель мониторинга:  ${GREEN}http://$IP_ADDRESS${NC}"
    echo -e "  Логин:               ${YELLOW}admin${NC}"
    echo -e "  Пароль:              ${YELLOW}(установленный вами пароль)${NC}"
    echo -e "  Логи установки:      ${BLUE}$LOG_FILE${NC}\n"
    
    echo -e "${BLUE}Каталоги:${NC}"
    echo -e "  Веб-файлы:           /var/www/wg-monitor/public_html/"
    echo -e "  CGI скрипты:         /var/www/wg-monitor/cgi-bin/"
    echo -e "  Конфигурация:        /var/www/wg-monitor/config/"
    echo -e "  Логи:                /var/www/wg-monitor/logs/\n"
    
    echo -e "${BLUE}Полезные команды:${NC}"
    echo -e "  Просмотр логов:      ${GREEN}tail -f /var/www/wg-monitor/logs/*.log${NC}"
    echo -e "  Перезапуск:          ${GREEN}systemctl restart nginx fcgiwrap-custom${NC}"
    echo -e "  Статус служб:        ${GREEN}systemctl status nginx fcgiwrap-custom${NC}"
    echo -e "  Удаление:            ${GREEN}sudo ./uninstall.sh${NC}\n"
    
    echo -e "${YELLOW}⚠️  Не забудьте сменить пароль по умолчанию!${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Главная функция
main() {
    print_header
    
    check_root
    check_system
    install_dependencies
    create_directories
    setup_user
    setup_permissions
    setup_sudoers
    setup_nginx
    setup_fcgiwrap
    setup_vnstat
    create_password
    check_wireguard
    start_services
    final_check
    show_info
}

# Обработка ошибок
trap 'print_error "Прервано пользователем"; exit 1' INT TERM

# Запуск
main "$@"
