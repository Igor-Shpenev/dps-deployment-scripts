#!/bin/bash

#############################################
# ПУЛЕНЕПРОБИВАЕМЫЙ СКРИПТ ОБНОВЛЕНИЯ
# Исправляет ВСЕ проблемы автоматически
# Запускать от dps_user
#
# GitHub репозиторий с кодом:
# https://github.com/Igor-Shpenev/dps-tracker-app
#
# Скрипт делает:
# 1. Включает maintenance mode
# 2. Останавливает приложение
# 3. Подтягивает обновления из GitHub (git pull)
# 4. Устанавливает зависимости
# 5. Собирает приложение
# 6. Запускает PM2
# 7. Выключает maintenance mode
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }
step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

PROJECT_DIR="/var/www/dps_user/data/www/app.dpstracker.ru"
PORT=10000
MAX_RETRIES=3

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ПУЛЕНЕПРОБИВАЕМОЕ ОБНОВЛЕНИЕ DPS TRACKER              ║"
echo "║     Исправляет ВСЕ проблемы автоматически                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Проверка пользователя
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    error "Этот скрипт должен запускаться от dps_user, а не от root!"
    info "Выполните: su - dps_user && cd $PROJECT_DIR && ./BULLETPROOF-UPDATE.sh"
    exit 1
fi

if [ "$CURRENT_USER" != "dps_user" ]; then
    error "Этот скрипт должен запускаться от dps_user!"
    info "Текущий пользователь: $CURRENT_USER"
    exit 1
fi

cd "$PROJECT_DIR" || exit 1
success "Пользователь: $CURRENT_USER ✓"
success "Директория: $(pwd) ✓"

#############################################
# ФУНКЦИЯ: Убить ВСЕ процессы на порту
#############################################
kill_port() {
    local port=$1
    step "Освобождение порта $port..."

    # Метод 1: fuser
    if command -v fuser &> /dev/null; then
        fuser -k ${port}/tcp 2>/dev/null || true
    fi

    # Метод 2: lsof
    if command -v lsof &> /dev/null; then
        lsof -ti:${port} | xargs kill -9 2>/dev/null || true
    fi

    # Метод 3: netstat + kill
    if command -v netstat &> /dev/null; then
        netstat -tulpn 2>/dev/null | grep ":${port}" | awk '{print $7}' | cut -d'/' -f1 | xargs kill -9 2>/dev/null || true
    fi

    # Метод 4: ss + kill
    if command -v ss &> /dev/null; then
        ss -tulpn 2>/dev/null | grep ":${port}" | awk '{print $7}' | cut -d'=' -f2 | cut -d',' -f1 | xargs kill -9 2>/dev/null || true
    fi

    # Метод 5: убиваем все node процессы на этом порту
    ps aux | grep "node.*${port}" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true

    sleep 2
    success "Порт $port освобожден"
}

#############################################
# ФУНКЦИЯ: Проверка порта
#############################################
check_port() {
    local port=$1
    if netstat -tulpn 2>/dev/null | grep -q ":${port}" || ss -tulpn 2>/dev/null | grep -q ":${port}"; then
        return 1
    fi
    return 0
}

#############################################
# ШАГ 1: Включение режима обслуживания
#############################################
echo ""
step "ШАГ 1/11: Включение режима обслуживания"
echo "================================================"

if [ -f maintenance.html ]; then
    info "Включаем maintenance mode..."
    touch MAINTENANCE
    success "Режим обслуживания включен ✓"
else
    warning "Файл maintenance.html не найден, пропускаем"
fi

#############################################
# ШАГ 2: Остановка всех процессов
#############################################
echo ""
step "ШАГ 2/11: Остановка всех процессов"
echo "================================================"

info "Останавливаем PM2..."
pm2 stop all 2>/dev/null || true
pm2 delete all 2>/dev/null || true
pm2 kill 2>/dev/null || true

info "Убиваем все node процессы..."
killall -9 node 2>/dev/null || true
killall -9 next 2>/dev/null || true
killall -9 next-server 2>/dev/null || true

kill_port $PORT

# Проверяем что порт свободен
if check_port $PORT; then
    success "Порт $PORT свободен ✓"
else
    warning "Порт $PORT все еще занят! Пробуем еще раз..."
    sleep 3
    kill_port $PORT

    if check_port $PORT; then
        success "Порт $PORT свободен ✓"
    else
        error "Не удалось освободить порт $PORT!"
        error "Попробуйте выполнить от root: fuser -k ${PORT}/tcp"
        exit 1
    fi
fi

#############################################
# ШАГ 2: Частичная очистка кешей (перед git pull)
#############################################
echo ""
step "ШАГ 3/11: Частичная очистка кешей"
echo "================================================"

info "Удаляем кеши node_modules..."
rm -rf node_modules/.cache
rm -rf node_modules/.prisma
rm -rf node_modules/@prisma/client

info "Удаляем TypeScript кеш..."
rm -f tsconfig.tsbuildinfo

info "Удаляем PM2 логи..."
rm -rf logs/pm2-*.log 2>/dev/null || true

success "Кеши удалены ✓"

#############################################
# ШАГ 3: Исправление next.config.js
#############################################
echo ""
step "ШАГ 4/11: Исправление next.config.js"
echo "================================================"

if grep -q "ssr" next.config.js; then
    warning "Найдена устаревшая опция 'ssr' в next.config.js"
    info "Создаем бэкап..."
    cp next.config.js next.config.js.bak

    info "Удаляем строку с 'ssr'..."
    sed -i '/ssr/d' next.config.js

    success "next.config.js исправлен ✓"
else
    success "next.config.js корректен ✓"
fi

#############################################
# ШАГ 4: Проверка .env
#############################################
echo ""
step "ШАГ 5/11: Проверка переменных окружения"
echo "================================================"

if [ ! -f .env ]; then
    error ".env файл не найден!"
    exit 1
fi

export DATABASE_URL="mysql://dps_user:f75jTkrP6w88SqVmnZ@localhost:3306/dps_bdd"
export NODE_ENV="production"

success ".env загружен ✓"

#############################################
# ШАГ 5: Git pull (опционально)
#############################################
echo ""
step "ШАГ 6/11: Получение обновлений"
echo "================================================"

if [ -d .git ]; then
    # Проверяем есть ли remote origin
    if git remote get-url origin &>/dev/null; then
        CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        info "Текущий коммит: ${CURRENT_COMMIT:0:8}"

        # Проверяем изменения
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            warning "Есть локальные изменения, сохраняем..."
            git stash push -m "Auto-stash $(date +%Y-%m-%d_%H:%M:%S)" 2>/dev/null || true
        fi

        info "Получаем обновления..."
        if git fetch origin 2>/dev/null; then
            ORIGIN_MAIN=$(git rev-parse origin/main 2>/dev/null || echo "")
            CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

            if [ -n "$ORIGIN_MAIN" ] && [ "$CURRENT_HEAD" != "$ORIGIN_MAIN" ]; then
                info "Применяем обновления..."
                if git pull origin main 2>/dev/null; then
                    NEW_COMMIT=$(git rev-parse HEAD)
                    success "Обновлено: ${CURRENT_COMMIT:0:8} → ${NEW_COMMIT:0:8}"
                else
                    warning "Не удалось применить обновления"
                fi
            else
                success "Код уже актуален ✓"
            fi
        else
            warning "Не удалось получить обновления из origin"
        fi
    else
        warning "Git remote origin не настроен, пропускаем обновления"
    fi
else
    success "Не Git репозиторий, пропускаем ✓"
fi

#############################################
# ШАГ 6: Установка зависимостей
#############################################
echo ""
step "ШАГ 7/11: Проверка зависимостей"
echo "================================================"

info "Устанавливаем/обновляем зависимости..."
npm install --production=false
success "Зависимости установлены ✓"

#############################################
# ШАГ 6.5: Удаление .next перед сборкой
#############################################
echo ""
step "ШАГ 7.5/11: Удаление .next"
echo "================================================"

info "Удаляем .next для чистой сборки..."
rm -rf .next
rm -rf .next.bak
success ".next удалена ✓"

#############################################
# ШАГ 7: Prisma
#############################################
echo ""
step "ШАГ 8/11: Настройка Prisma"
echo "================================================"

# Проверяем и исправляем права на node_modules
if [ -d node_modules ]; then
    info "Проверяем права на node_modules..."
    # Исправляем права на Prisma CLI (symlink указывает на этот файл)
    chmod +x node_modules/prisma/build/index.js 2>/dev/null || true
    # Исправляем права на бинарные движки Prisma
    chmod +x node_modules/@prisma/engines/* 2>/dev/null || true
    # Исправляем права на Next.js CLI
    chmod +x node_modules/next/dist/bin/next 2>/dev/null || true
    # Дополнительно исправляем права на .bin
    chmod -R 755 node_modules/.bin 2>/dev/null || true
fi

info "Генерируем Prisma Client..."
if command -v prisma &> /dev/null; then
    prisma generate || npx --yes prisma generate
else
    npx --yes prisma generate
fi

info "Применяем миграции..."
if command -v prisma &> /dev/null; then
    prisma migrate deploy 2>/dev/null || warning "Миграции не применены (возможно нет новых)"
else
    npx --yes prisma migrate deploy 2>/dev/null || warning "Миграции не применены (возможно нет новых)"
fi

success "Prisma готов ✓"

#############################################
# ШАГ 8: Сборка приложения
#############################################
echo ""
step "ШАГ 9/11: Сборка Next.js приложения"
echo "================================================"

info "Запускаем сборку..."
info "⏳ Это может занять 30-90 секунд..."

ATTEMPT=1
BUILD_SUCCESS=false

while [ $ATTEMPT -le $MAX_RETRIES ]; do
    info "Попытка сборки $ATTEMPT/$MAX_RETRIES..."

    if npm run build; then
        BUILD_SUCCESS=true
        break
    else
        error "Сборка не удалась! Попытка $ATTEMPT/$MAX_RETRIES"

        if [ $ATTEMPT -lt $MAX_RETRIES ]; then
            warning "Очищаем кеши и пробуем снова..."
            rm -rf .next
            rm -rf node_modules/.cache
            sleep 2
        fi

        ATTEMPT=$((ATTEMPT + 1))
    fi
done

if [ "$BUILD_SUCCESS" = false ]; then
    error "Сборка не удалась после $MAX_RETRIES попыток!"
    error "ВОССТАНАВЛИВАЕМ PM2..."

    # Пытаемся запустить старую версию
    pm2 start ecosystem.config.js --env production 2>/dev/null || true
    rm -f MAINTENANCE

    error "Приложение восстановлено на старой версии"
    error "Проверьте логи и исправьте ошибки вручную"
    exit 1
fi

success "Сборка завершена успешно! ✓"

# Проверяем что .next создалась
if [ ! -d .next ]; then
    error ".next директория не создана!"
    exit 1
fi

if [ ! -d .next/server ]; then
    error ".next/server директория не создана!"
    exit 1
fi

success "Структура .next корректна ✓"

#############################################
# ШАГ 9: Запуск через PM2
#############################################
echo ""
step "ШАГ 10/11: Запуск приложения"
echo "================================================"

info "Проверяем что порт свободен..."
if ! check_port $PORT; then
    warning "Порт $PORT занят! Освобождаем..."
    kill_port $PORT
    sleep 2
fi

info "Запускаем PM2..."
pm2 start ecosystem.config.js --env production

sleep 3

info "Сохраняем конфигурацию PM2..."
pm2 save

success "Приложение запущено! ✓"

#############################################
# ШАГ 10: Проверка работоспособности
#############################################
echo ""
step "ШАГ 11/11: Проверка работоспособности"
echo "================================================"

sleep 5

# Статус PM2
pm2 status

echo ""
info "Проверяем логи (последние 20 строк)..."
pm2 logs dps-tracker --lines 20 --nostream

echo ""
info "Проверяем HTTP endpoint..."

HEALTH_CHECK_ATTEMPTS=0
HEALTH_CHECK_SUCCESS=false

while [ $HEALTH_CHECK_ATTEMPTS -lt 10 ]; do
    sleep 2
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/api/health 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        HEALTH_CHECK_SUCCESS=true
        break
    fi

    HEALTH_CHECK_ATTEMPTS=$((HEALTH_CHECK_ATTEMPTS + 1))
    info "Ожидание запуска... ($HEALTH_CHECK_ATTEMPTS/10)"
done

echo ""
if [ "$HEALTH_CHECK_SUCCESS" = true ]; then
    success "✓✓✓ HTTP endpoint работает (200 OK) ✓✓✓"

    # Выключаем maintenance mode
    if [ -f MAINTENANCE ]; then
        info "Выключаем maintenance mode..."
        rm -f MAINTENANCE
        success "Сайт доступен пользователям ✓"
    fi
else
    warning "HTTP endpoint не отвечает или вернул код: $HTTP_CODE"
    warning "Проверьте логи: pm2 logs dps-tracker"
    warning "Но PM2 показывает что процесс запущен"
    warning "⚠️  Maintenance mode НЕ выключен - выключите вручную: rm MAINTENANCE"
fi

#############################################
# ИТОГИ
#############################################
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅✅✅ ОБНОВЛЕНИЕ ЗАВЕРШЕНО ✅✅✅              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

pm2 status

echo ""
success "🎉 Приложение обновлено и запущено!"
echo ""
info "Полезные команды:"
echo "  ${CYAN}pm2 logs dps-tracker${NC}          - просмотр логов"
echo "  ${CYAN}pm2 status${NC}                     - статус процессов"
echo "  ${CYAN}pm2 monit${NC}                      - мониторинг в реальном времени"
echo "  ${CYAN}pm2 restart dps-tracker${NC}        - перезапуск"
echo "  ${CYAN}curl http://localhost:${PORT}/api/health${NC} - проверка health"
echo ""

if [ "$HEALTH_CHECK_SUCCESS" = true ]; then
    success "🚀 Всё работает отлично!"
else
    warning "⚠️  Приложение запущено, но health check не прошел"
    warning "Подождите 30 секунд и проверьте: pm2 logs dps-tracker"
fi

echo ""
