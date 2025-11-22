#!/bin/bash

#############################################
# ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ
# Когда ВСЁ СЛОМАЛОСЬ - этот скрипт спасет
# Запускать ОТ ROOT!
#
# GitHub репозиторий с кодом:
# https://github.com/Igor-Shpenev/dps-tracker-app
#
# После этого скрипта запустите от dps_user:
# ./BULLETPROOF-UPDATE.sh
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║           ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ DPS TRACKER           ║${NC}"
echo -e "${RED}║              Используй только в крайнем случае!           ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка что запущен от root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[✗]${NC} Этот скрипт ДОЛЖЕН запускаться от root!"
    echo "Выполните: sudo ./EMERGENCY-FIX.sh"
    exit 1
fi

PROJECT_DIR="/var/www/dps_user/data/www/app.dpstracker.ru"

echo -e "${YELLOW}[!]${NC} Этот скрипт:"
echo "  1. Убьет ВСЕ процессы Node.js"
echo "  2. Освободит порт 10000"
echo "  3. Удалит все PM2 процессы (root и dps_user)"
echo "  4. Исправит права на файлы"
echo "  5. Очистит все кеши"
echo ""
read -p "Продолжить? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/7]${NC} Убиваем все PM2 демоны..."
pm2 kill 2>/dev/null || true
su - dps_user -c "pm2 kill" 2>/dev/null || true
echo -e "${GREEN}✓${NC} PM2 остановлен"

echo ""
echo -e "${YELLOW}[2/7]${NC} Убиваем все Node.js процессы..."
killall -9 node 2>/dev/null || true
killall -9 next 2>/dev/null || true
killall -9 next-server 2>/dev/null || true
echo -e "${GREEN}✓${NC} Все Node процессы убиты"

echo ""
echo -e "${YELLOW}[3/7]${NC} Освобождаем порт 10000..."
fuser -k 10000/tcp 2>/dev/null || true
lsof -ti:10000 | xargs kill -9 2>/dev/null || true
echo -e "${GREEN}✓${NC} Порт 10000 свободен"

sleep 2

echo ""
echo -e "${YELLOW}[4/7]${NC} Исправляем права на файлы..."
cd "$PROJECT_DIR" || exit 1
chown -R dps_user:dps_user .
chmod -R 755 .
find . -type f -exec chmod 644 {} \; 2>/dev/null || true
chmod +x *.sh 2>/dev/null || true
echo -e "${GREEN}✓${NC} Права исправлены"

echo ""
echo -e "${YELLOW}[5/7]${NC} Удаляем все кеши..."
rm -rf .next
rm -rf node_modules/.cache
rm -rf node_modules/.prisma
rm -rf node_modules/@prisma/client
rm -f tsconfig.tsbuildinfo
echo -e "${GREEN}✓${NC} Кеши очищены"

echo ""
echo -e "${YELLOW}[6/7]${NC} Исправляем next.config.js..."
if grep -q "ssr" next.config.js; then
    cp next.config.js next.config.js.emergency-backup
    sed -i '/ssr/d' next.config.js
    echo -e "${GREEN}✓${NC} next.config.js исправлен"
else
    echo -e "${GREEN}✓${NC} next.config.js в порядке"
fi

echo ""
echo -e "${YELLOW}[7/7]${NC} Проверяем что порт свободен..."
if netstat -tulpn 2>/dev/null | grep -q ":10000" || ss -tulpn 2>/dev/null | grep -q ":10000"; then
    echo -e "${RED}✗${NC} Порт 10000 все еще занят!"
    echo "Процессы на порту:"
    netstat -tulpn 2>/dev/null | grep ":10000" || ss -tulpn 2>/dev/null | grep ":10000"
    echo ""
    echo "Попробуйте:"
    echo "  lsof -ti:10000 | xargs kill -9"
else
    echo -e "${GREEN}✓${NC} Порт 10000 свободен"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}ВАЖНО:${NC} Теперь запустите обновление ОТ dps_user:"
echo ""
echo "  su - dps_user"
echo "  cd $PROJECT_DIR"
echo "  ./BULLETPROOF-UPDATE.sh"
echo ""
