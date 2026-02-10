class WireGuardMonitor {
    constructor() {
        this.clients = [];
        this.trafficData = {
            today: null,
            month: null,
            lastmonth: null
        };
        this.chart = null;
        this.sortConfig = {
            field: 'last_handshake',
            direction: 'desc'
        };
        this.init();
    }

    init() {
        this.updateServerTime();
        this.loadInitialData();
        this.setupEventListeners();
        this.setupAutoRefresh();
        
        // Инициализация графика
        this.initChart();
    }

    updateServerTime() {
        const now = new Date();
        document.getElementById('server-time').textContent = 
            `Серверное время: ${now.toLocaleTimeString('ru-RU')}`;
    }

    async loadInitialData() {
        await Promise.all([
            this.loadTrafficData('today'),
            this.loadClientsData(),
            this.updatePingClientSelect()
        ]);
        this.updateLastUpdateTime();
    }

    async loadTrafficData(period) {
        try {
            const response = await fetch(`/cgi-bin/get_server_traffic.sh?period=${period}`);
            const data = await response.json();
            this.trafficData[period] = data;
            
            if (period === 'today') {
                this.updateTrafficDisplay(data);
                this.updateChart(data);
            }
        } catch (error) {
            console.error('Ошибка загрузки трафика:', error);
        }
    }

    updateTrafficDisplay(data) {
        document.getElementById('traffic-rx').textContent = data.rx;
        document.getElementById('traffic-tx').textContent = data.tx;
    }

    async loadClientsData() {
        try {
            const response = await fetch('/cgi-bin/get_wg_clients.sh');
            this.clients = await response.json();
            this.renderClientsTable();
            this.updateClientCount();
            this.updatePingClientSelect();
        } catch (error) {
            console.error('Ошибка загрузки клиентов:', error);
        }
    }

    renderClientsTable() {
        const tbody = document.getElementById('clients-tbody');
        const searchTerm = document.getElementById('client-search').value.toLowerCase();
        
        // Фильтрация и сортировка
        let filteredClients = this.clients.filter(client => 
            client.name.toLowerCase().includes(searchTerm) ||
            client.ip.toLowerCase().includes(searchTerm)
        );
        
        filteredClients.sort((a, b) => {
            let aValue = a[this.sortConfig.field];
            let bValue = b[this.sortConfig.field];
            
            if (this.sortConfig.field.includes('_raw')) {
                aValue = parseFloat(aValue) || 0;
                bValue = parseFloat(bValue) || 0;
            }
            
            if (this.sortConfig.direction === 'asc') {
                return aValue > bValue ? 1 : -1;
            } else {
                return aValue < bValue ? 1 : -1;
            }
        });
        
        // Отрисовка
        tbody.innerHTML = filteredClients.map(client => `
            <tr class="fade-in">
                <td>
                    <span class="status-indicator ${client.last_handshake === 'Never' ? 'status-inactive' : 'status-active'}"></span>
                    ${this.escapeHtml(client.name)}
                </td>
                <td><code>${this.escapeHtml(client.public_key)}</code></td>
                <td><code>${this.escapeHtml(client.ip)}</code></td>
                <td>${this.formatTime(client.last_handshake)}</td>
                <td class="text-success">${client.transfer_rx}</td>
                <td class="text-warning">${client.transfer_tx}</td>
                <td>
                    <button onclick="monitor.pingClient('${this.escapeHtml(client.ip)}')" class="btn-primary" style="padding: 5px 10px; font-size: 12px;">
                        <i class="fas fa-network-wired"></i> Ping
                    </button>
                </td>
            </tr>
        `).join('');
        
        // Обновление сортировки в заголовках
        this.updateSortIndicators();
    }

    updateSortIndicators() {
        document.querySelectorAll('th').forEach(th => {
            const field = th.dataset.sort;
            if (field) {
                const icon = th.querySelector('i');
                icon.className = 'fas fa-sort';
                if (field === this.sortConfig.field) {
                    icon.className = this.sortConfig.direction === 'asc' 
                        ? 'fas fa-sort-up' 
                        : 'fas fa-sort-down';
                }
            }
        });
    }

    updateClientCount() {
        const count = this.clients.length;
        document.getElementById('client-count').textContent = 
            `${count} ${this.getPluralForm(count, ['клиент', 'клиента', 'клиентов'])}`;
    }

    async updatePingClientSelect() {
        const select = document.getElementById('ping-client-select');
        const currentValue = select.value;
        
        select.innerHTML = '<option value="">Выберите клиента...</option>' +
            this.clients.map(client => 
                `<option value="${this.escapeHtml(client.ip)}" ${currentValue === client.ip ? 'selected' : ''}>
                    ${this.escapeHtml(client.name)} (${this.escapeHtml(client.ip)})
                </option>`
            ).join('');
    }

    async pingClient(ip) {
        const output = document.getElementById('ping-output');
        output.textContent = 'Выполняется ping...';
        
        try {
            const response = await fetch(`/cgi-bin/ping_client.sh?ip=${encodeURIComponent(ip)}`);
            const result = await response.text();
            output.textContent = result;
        } catch (error) {
            output.textContent = `Ошибка: ${error.message}`;
        }
    }

    initChart() {
        const ctx = document.getElementById('trafficChart').getContext('2d');
        this.chart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'],
                datasets: [{
                    label: 'Получено (RX)',
                    data: [0, 0, 0, 0, 0, 0],
                    borderColor: 'rgb(75, 192, 192)',
                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                    tension: 0.4
                }, {
                    label: 'Отправлено (TX)',
                    data: [0, 0, 0, 0, 0, 0],
                    borderColor: 'rgb(255, 99, 132)',
                    backgroundColor: 'rgba(255, 99, 132, 0.2)',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'top',
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            callback: function(value) {
                                return value + ' MB';
                            }
                        }
                    }
                }
            }
        });
    }

    updateChart(data) {
        if (this.chart && data) {
            // Здесь можно добавить логику обновления данных графика
            // Например, получить исторические данные и обновить chart.data.datasets
        }
    }

    setupEventListeners() {
        // Переключение периодов трафика
        document.querySelectorAll('.period-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.period-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.loadTrafficData(btn.dataset.period);
            });
        });

        // Поиск клиентов
        document.getElementById('client-search').addEventListener('input', () => {
            this.renderClientsTable();
        });

        // Сортировка таблицы
        document.querySelectorAll('th[data-sort]').forEach(th => {
            th.addEventListener('click', () => {
                const field = th.dataset.sort;
                if (this.sortConfig.field === field) {
                    this.sortConfig.direction = this.sortConfig.direction === 'asc' ? 'desc' : 'asc';
                } else {
                    this.sortConfig.field = field;
                    this.sortConfig.direction = 'desc';
                }
                this.renderClientsTable();
            });
        });

        // Выбор сортировки
        document.getElementById('sort-by').addEventListener('change', (e) => {
            this.sortConfig.field = e.target.value === 'name' ? 'name' : 
                                  e.target.value === 'traffic' ? 'transfer_rx_raw' : 'last_handshake';
            this.renderClientsTable();
        });

        // Кнопка пинга
        document.getElementById('ping-btn').addEventListener('click', () => {
            const select = document.getElementById('ping-client-select');
            const ip = select.value;
            if (ip) {
                this.pingClient(ip);
            }
        });

        // Модальное окно
        const modal = document.getElementById('client-modal');
        const closeBtn = modal.querySelector('.close');
        
        closeBtn.addEventListener('click', () => {
            modal.style.display = 'none';
        });

        window.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.style.display = 'none';
            }
        });
    }

    setupAutoRefresh() {
        // Обновление данных каждые 30 секунд
        setInterval(() => {
            this.loadTrafficData('today');
            this.loadClientsData();
            this.updateServerTime();
            this.updateLastUpdateTime();
        }, 30000);

        // Обновление времени каждую секунду
        setInterval(() => {
            this.updateServerTime();
        }, 1000);
    }

    updateLastUpdateTime() {
        const now = new Date();
        document.getElementById('last-update').textContent = 
            `Обновлено: ${now.toLocaleTimeString('ru-RU')}`;
    }

    // Вспомогательные методы
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    formatTime(timestamp) {
        if (timestamp === 'Never') return '<span class="text-danger">Никогда</span>';
        
        const date = new Date(timestamp);
        const now = new Date();
        const diff = now - date;
        
        if (diff < 60000) return '<span class="text-success">Только что</span>';
        if (diff < 3600000) return `<span class="text-success">${Math.floor(diff / 60000)} мин назад</span>`;
        if (diff < 86400000) return `<span class="text-warning">${Math.floor(diff / 3600000)} час назад</span>`;
        
        return date.toLocaleString('ru-RU');
    }

    getPluralForm(n, forms) {
        n = Math.abs(n) % 100;
        const n1 = n % 10;
        if (n > 10 && n < 20) return forms[2];
        if (n1 > 1 && n1 < 5) return forms[1];
        if (n1 === 1) return forms[0];
        return forms[2];
    }
}

// Функция для копирования команды ping
function copyCommand() {
    const command = document.getElementById('ping-command');
    navigator.clipboard.writeText(command.textContent).then(() => {
        const btn = event.target.closest('button');
        const originalHtml = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-check"></i> Скопировано!';
        btn.style.background = 'var(--success)';
        
        setTimeout(() => {
            btn.innerHTML = originalHtml;
            btn.style.background = '';
        }, 2000);
    });
}

// Инициализация при загрузке страницы
document.addEventListener('DOMContentLoaded', () => {
    window.monitor = new WireGuardMonitor();
});