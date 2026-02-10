class CacheManager {
    constructor() {
        this.cacheStats = {
            hits: 0,
            misses: 0,
            size: 0
        };
        this.init();
    }

    init() {
        this.loadStats();
        this.setupCacheControls();
    }

    async loadStats() {
        try {
            const response = await fetch('/cgi-bin/cache_stats.sh');
            const data = await response.json();
            this.cacheStats = data;
            this.updateDisplay();
        } catch (error) {
            console.warn('Не удалось загрузить статистику кэша:', error);
        }
    }

    updateDisplay() {
        const hitRate = this.calculateHitRate();
        document.getElementById('cache-hit-rate').textContent = `${hitRate}%`;
        document.getElementById('cache-size').textContent = this.formatSize(this.cacheStats.size);
        document.getElementById('cache-hits').textContent = this.cacheStats.hits;
        document.getElementById('cache-misses').textContent = this.cacheStats.misses;
    }

    calculateHitRate() {
        const total = this.cacheStats.hits + this.cacheStats.misses;
        return total > 0 ? Math.round((this.cacheStats.hits / total) * 100) : 0;
    }

    formatSize(bytes) {
        if (bytes >= 1073741824) {
            return (bytes / 1073741824).toFixed(2) + ' GB';
        } else if (bytes >= 1048576) {
            return (bytes / 1048576).toFixed(2) + ' MB';
        } else if (bytes >= 1024) {
            return (bytes / 1024).toFixed(2) + ' KB';
        }
        return bytes + ' B';
    }

    setupCacheControls() {
        // Кнопка очистки кэша
        document.getElementById('clear-cache-btn')?.addEventListener('click', async () => {
            if (confirm('Очистить весь кэш?')) {
                await this.clearCache('all');
            }
        });

        // Автоматическое обновление статистики
        setInterval(() => this.loadStats(), 30000);
    }

    async clearCache(type = 'all') {
        try {
            const response = await fetch(`/cgi-bin/clear_cache.sh?type=${type}`);
            const result = await response.json();
            
            if (result.status === 'success') {
                alert('Кэш успешно очищен');
                this.loadStats();
            } else {
                alert('Ошибка при очистке кэша: ' + result.message);
            }
        } catch (error) {
            alert('Ошибка сети при очистке кэша');
        }
    }
}

// Инициализация при загрузке страницы
document.addEventListener('DOMContentLoaded', () => {
    window.cacheManager = new CacheManager();
});