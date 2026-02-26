#!/bin/bash
#
# scripts/setup-rocketchat.sh — Настройка локального Rocket.Chat для тестирования
#
# Использование:
#   ./scripts/setup-rocketchat.sh [setup|start|stop|reset|logs]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker не найден. Установите Docker."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose не найден. Установите Docker Compose."
        exit 1
    fi
}

setup() {
    print_info "Настройка локального Rocket.Chat..."
    
    cd "$PROJECT_ROOT"
    
    # Проверка Docker
    check_docker
    
    # Создание .env если не существует
    if [ ! -f ".env" ]; then
        print_info "Создание .env файла..."
        cat > .env << 'EOF'
# Rocket.Chat сервер
ROCKETCHAT_SERVER_URL=http://localhost:3000

# Учётные данные администратора
# (устанавливаются при первом запуске через веб-интерфейс)
# Пример:
ADMIN_USERNAME=auser
ADMIN_PASSWORD=admin123ADMIN!@#

# Режим отладки
DEBUG=0
EOF
        print_info ".env файл создан. Отредактируйте при необходимости."
    fi
    
    print_info "Запуск контейнеров..."
    
    # Запуск Docker Compose
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    print_info "Rocket.Chat запускается..."
    print_warn "Первый запуск может занять 2-3 минуты."
    print_info ""
    print_info "Откройте http://localhost:3000 в браузере"
    print_info "Для завершения настройки создайте учётную запись администратора:"
    print_info "  Username: auser"
    print_info "  Password: admin123ADMIN!@#"
    print_info ""
    print_info "После настройки добавьте в .env:"
    print_info "  ROCKETCHAT_SERVER_URL=http://localhost:3000"
    print_info "  ADMIN_USERNAME=auser"
    print_info "  ADMIN_PASSWORD=admin123ADMIN!@#"
}

start() {
    print_info "Запуск Rocket.Chat..."
    cd "$PROJECT_ROOT"
    
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    print_info "Готово!"
}

stop() {
    print_info "Остановка Rocket.Chat..."
    cd "$PROJECT_ROOT"
    
    if docker compose version &> /dev/null; then
        docker compose down
    else
        docker-compose down
    fi
    
    print_info "Остановлено."
}

reset() {
    print_warn "Это удалит все данные Rocket.Chat!"
    echo -n "Продолжить? (y/N): "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Отменено."
        exit 0
    fi
    
    print_info "Сброс Rocket.Chat..."
    cd "$PROJECT_ROOT"
    
    if docker compose version &> /dev/null; then
        docker compose down -v
    else
        docker-compose down -v
    fi
    
    print_info "Данные удалены. Запустите './scripts/setup-rocketchat.sh setup' для повторной настройки."
}

logs() {
    cd "$PROJECT_ROOT"
    
    if docker compose version &> /dev/null; then
        docker compose logs -f "$@"
    else
        docker-compose logs -f "$@"
    fi
}

status() {
    cd "$PROJECT_ROOT"
    
    print_info "Статус контейнеров:"
    if docker compose version &> /dev/null; then
        docker compose ps
    else
        docker-compose ps
    fi
    
    echo ""
    print_info "Проверка доступности Rocket.Chat..."
    if curl -s http://localhost:3000/api/info > /dev/null 2>&1; then
        print_info "Rocket.Chat доступен: http://localhost:3000"
    else
        print_warn "Rocket.Chat ещё не готов. Подождите немного."
    fi
}

# Главная
case "${1:-help}" in
    setup)
        setup
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    reset)
        reset
        ;;
    logs)
        logs "${@:2}"
        ;;
    status)
        status
        ;;
    help|*)
        echo "Использование: $0 {setup|start|stop|reset|logs|status}"
        echo ""
        echo "Команды:"
        echo "  setup   — Первоначальная настройка и запуск"
        echo "  start   — Запустить остановленные контейнеры"
        echo "  stop    — Остановить контейнеры"
        echo "  reset   — Удалить все данные и остановить (требует подтверждения)"
        echo "  logs    — Просмотр логов"
        echo "  status  — Проверка статуса контейнеров"
        echo ""
        ;;
esac
