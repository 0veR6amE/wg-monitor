# 🛡️ WireGuard VPN Monitor

Простой и эффективный веб-интерфейс для мониторинга WireGuard VPN-сервера.

![WireGuard Monitor](https://img.shields.io/badge/Status-Active-green)
![License](https://img.shields.io/badge/License-MIT-blue)

## ✨ Возможности

- 📊 **Мониторинг трафика** (RX/TX) за день, месяц, прошлый месяц
- 👥 **Список клиентов** с информацией о подключениях
- 🔍 **Поиск и сортировка** клиентов по различным параметрам
- 🖥️ **Диагностика сети** (ping с сервера до клиента)
- 📈 **Визуализация данных** с помощью графиков
- 🔄 **Автообновление** данных каждые 30-60 секунд
- 🔒 **Защита паролем** (HTTP Basic Auth)
- 📱 **Адаптивный дизайн** для мобильных устройств

## 🚀 Быстрый старт

### Вариант 1: Автоматическая установка (рекомендуется)
```bash
git clone https://github.com/ваш-username/wg-monitor.git
cd wg-monitor
sudo chmod +x install.sh
sudo ./install.sh