#!/bin/bash
#
# main.sh — Точка входа для импорта эмодзи в Rocket.Chat
#
# Основной скрипт, который оркестрирует процесс импорта:
# загрузку конфигурации, аутентификацию, получение списка эмодзи
# и их загрузку на сервер.
#
# Использование:
#   ./main.sh [--help] [--no-prompt]
#
# Переменные окружения:
#   ROCKETCHAT_SERVER_URL — URL сервера Rocket.Chat
#   EMOJI_YAML_URL — URL YAML файла со списком эмодзи
#   ADMIN_USERNAME — Имя пользователя администратора
#   ADMIN_PASSWORD — Пароль администратора
#   DEBUG — Режим отладки (1 для включения)
#
# Зависимости:
#   - bash 4.0+
#   - curl
#   - jq
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Инициализация
# ------------------------------------------------------------------------------

# Определяем директорию со скриптом
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загружаем модули
# shellcheck source=./lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck source=./lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=./lib/prompt.sh
source "${SCRIPT_DIR}/lib/prompt.sh"
# shellcheck source=./lib/rocketchat_api.sh
source "${SCRIPT_DIR}/lib/rocketchat_api.sh"
# shellcheck source=./lib/yaml_parser.sh
source "${SCRIPT_DIR}/lib/yaml_parser.sh"
# shellcheck source=./lib/emoji_importer.sh
source "${SCRIPT_DIR}/lib/emoji_importer.sh"

# ------------------------------------------------------------------------------
# Обработчики сигналов
# ------------------------------------------------------------------------------

# Очищает временные файлы при выходе.
cleanup() {
    log_debug "Очистка временных файлов..."
    # Временные файлы создаются в функциях и удаляются там же,
    # но на всякий случай можно очистить /tmp от наших файлов
}

# Устанавливаем обработчики сигналов
trap cleanup EXIT
trap 'log_error "Прервано пользователем"; exit 130' INT
trap 'log_error "Прервано сигналом TERM"; exit 143' TERM

# ------------------------------------------------------------------------------
# Справка
# ------------------------------------------------------------------------------

# Выводит справку по использованию скрипта.
show_help() {
    cat << EOF
Импорт эмодзи в Rocket.Chat

Использование:
    $(basename "$0") [ОПЦИИ]

Опции:
    --help, -h      Показать эту справку и выйти
    --no-prompt     Не запрашивать значения, использовать только .env
    --version, -v   Показать версию
    --file, -f      Путь к YAML файлу (по умолчанию: output/form.yml)

Переменные окружения:
    ROCKETCHAT_SERVER_URL   URL сервера Rocket.Chat (обязательно)
    EMOJI_YAML_URL          URL YAML файла со списком эмодзи (обязательно)
    ADMIN_USERNAME          Имя пользователя администратора (обязательно)
    ADMIN_PASSWORD          Пароль администратора (обязательно)
    DEBUG                   Режим отладки: 0 или 1 (по умолчанию 0)

Примеры:
    # Использовать значения из .env
    $(basename "$0")

    # Использовать переменные окружения
    ROCKETCHAT_SERVER_URL=https://chat.example.com \\
    ADMIN_USERNAME=admin \\
    ADMIN_PASSWORD=secret \\
    $(basename "$0")

    # Использовать локальный YAML файл (по умолчанию output/form.yml)
    $(basename "$0")
    $(basename "$0") --file ./form.yml
    $(basename "$0") -f /path/to/emojis.yaml

    # Режим отладки
    DEBUG=1 $(basename "$0")

EOF
}

# ------------------------------------------------------------------------------
# Основная функция
# ------------------------------------------------------------------------------

# Главная точка входа скрипта.
#
# Возвращает:
#   0 — если все эмодзи успешно импортированы
#   1 — если произошла ошибка
main() {
    local no_prompt=0
    local yaml_file="output/form.yml"

    # Парсим аргументы командной строки
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --no-prompt)
                no_prompt=1
                shift
                ;;
            --version|-v)
                echo "emoji-importer version 1.0.0"
                exit 0
                ;;
            --file|-f)
                if [ -z "${2:-}" ]; then
                    log_error "Требуется аргумент для опции $1"
                    exit 1
                fi
                yaml_file="$2"
                shift 2
                ;;
            *)
                log_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log_info "Запуск импорта эмодзи..."

    # Загружаем .env файл
    if ! load_env; then
        log_error "Не удалось загрузить .env файл"
        exit 1
    fi

    # Если указан файл, используем его
    if [ -n "$yaml_file" ]; then
        # Проверяем существование файла
        if [ ! -f "$yaml_file" ]; then
            log_error "Файл не найден: ${yaml_file}"
            exit 1
        fi
        
        # Проверяем расширение файла
        local file_ext="${yaml_file##*.}"
        if [ "$file_ext" != "yml" ] && [ "$file_ext" != "yaml" ]; then
            log_error "Неверное расширение файла: ${file_ext}"
            log_error "Ожидается .yml или .yaml"
            exit 1
        fi
        
        # Преобразуем в абсолютный путь
        yaml_file="$(cd "$(dirname "$yaml_file")" && pwd)/$(basename "$yaml_file")"
        log_info "Используется локальный YAML файл: ${yaml_file}"
    fi

    # Если не режим --no-prompt и нет обязательных переменных, запрашиваем
    if [ "$no_prompt" -eq 0 ]; then
        # Запрашиваем только недостающие значения
        if [ -z "$ROCKETCHAT_SERVER_URL" ] || \
           [ -z "$ADMIN_USERNAME" ] || \
           [ -z "$ADMIN_PASSWORD" ]; then

            if [ -z "$ROCKETCHAT_SERVER_URL" ]; then
                prompt "Rocket.Chat сервер URL" "" "ROCKETCHAT_SERVER_URL"
            fi
            if [ -z "$ADMIN_USERNAME" ]; then
                prompt "Rocket.Chat админ username" "" "ADMIN_USERNAME"
            fi
            prompt_secret "Rocket.Chat админ пароль" "ADMIN_PASSWORD"

            echo ""
        fi
    fi

    # Валидируем конфигурацию
    if [ -z "$ROCKETCHAT_SERVER_URL" ] || \
       [ -z "$ADMIN_USERNAME" ] || \
       [ -z "$ADMIN_PASSWORD" ]; then
        log_error "Конфигурация невалидна. Проверьте переменные окружения."
        exit 1
    fi

    if ! validate_server_url; then
        exit 1
    fi

    log_debug "Конфигурация валидна"

    # Аутентификация в Rocket.Chat
    log_info "Аутентификация в Rocket.Chat..."
    if ! api_login "$ROCKETCHAT_SERVER_URL" "$ADMIN_USERNAME" "$ADMIN_PASSWORD"; then
        log_error "Не удалось аутентифицироваться"
        exit 1
    fi
    log_debug "Аутентификация успешна: user_id=${USER_ID}"

    # Получаем список существующих эмодзи
    log_info "Получение списка существующих эмодзи..."
    local existing_emojis
    existing_emojis=$(api_list_emoji_names "$ROCKETCHAT_SERVER_URL")

    local existing_count
    existing_count=$(count_existing_emojis "$existing_emojis")
    log_info "Найдено ${existing_count} существующих эмодзи"

    # Импортируем эмодзи
    log_info "Начало импорта..."
    echo ""

    if ! import_emojis_from_file "$ROCKETCHAT_SERVER_URL" "$yaml_file" "$existing_emojis"; then
        log_error "Импорт завершён с ошибками"
        exit 1
    fi

    echo ""
    log_info "Импорт завершён успешно!"

    return 0
}

# ------------------------------------------------------------------------------
# Запуск
# ------------------------------------------------------------------------------

# Запускаем main только если скрипт выполняется напрямую, а не source'ится
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
