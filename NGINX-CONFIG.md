# Настройка Nginx для Maintenance Mode

## Добавьте в конфигурацию Nginx

Откройте конфиг сайта:
```bash
nano /etc/nginx/sites-available/app.dpstracker.ru
```

Добавьте **В НАЧАЛО** блока `server {}` (сразу после `server {`):

```nginx
server {
    # ... существующие настройки ...

    # Проверка maintenance mode
    set $maintenance 0;
    if (-f /var/www/dps_user/data/www/app.dpstracker.ru/MAINTENANCE) {
        set $maintenance 1;
    }

    # Показываем страницу обслуживания
    if ($maintenance = 1) {
        return 503;
    }

    # Страница ошибки 503
    error_page 503 @maintenance;

    location @maintenance {
        root /var/www/dps_user/data/www/app.dpstracker.ru;
        try_files /maintenance.html =503;
    }

    # ... остальной конфиг ...
}
```

## Проверка и перезагрузка

```bash
# Проверить конфиг
nginx -t

# Перезагрузить Nginx
systemctl reload nginx
```

## Ручное включение/выключение

```bash
# Включить maintenance mode
touch /var/www/dps_user/data/www/app.dpstracker.ru/MAINTENANCE

# Выключить maintenance mode
rm /var/www/dps_user/data/www/app.dpstracker.ru/MAINTENANCE
```

## Как это работает

1. Скрипт создаёт файл `MAINTENANCE` перед остановкой приложения
2. Nginx видит этот файл и показывает `maintenance.html`
3. После успешного запуска скрипт удаляет файл `MAINTENANCE`
4. Nginx снова проксирует запросы к приложению
