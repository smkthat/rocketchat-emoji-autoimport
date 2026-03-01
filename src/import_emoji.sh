#!/bin/bash
#
# import_emoji.sh — Точка входа для импорта эмодзи в Rocket.Chat
#
# Основной скрипт, который оркестрирует процесс импорта:
# загрузку конфигурации, аутентификацию, получение списка эмодзи
# и их загрузку на сервер.
#
# Использование:
#   ./import_emoji.sh [--help] [--no-prompt] [--file <path>]
#
# Переменные окружения:
#   ROCKETCHAT_SERVER_URL — URL сервера Rocket.Chat
#   EMOJI_YAML_URL — URL YAML файла со списком эмодзи
#   ROCKETCHAT_ADMIN_USERNAME — Имя пользователя администратора
#   ROCKETCHAT_ADMIN_PASSWORD — Пароль администратора
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
    ROCKETCHAT_ADMIN_USERNAME          Имя пользователя администратора (обязательно)
    ROCKETCHAT_ADMIN_PASSWORD          Пароль администратора (обязательно)
    DEBUG                   Режим отладки: 0 или 1 (по умолчанию 0)

Примеры:
    # Использовать значения из .env
    $(basename "$0")

    # Использовать переменные окружения
    ROCKETCHAT_SERVER_URL=https://chat.example.com \\
    ROCKETCHAT_ADMIN_USERNAME=admin \\
    ROCKETCHAT_ADMIN_PASSWORD=secret \\
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
# Парсинг аргументов командной строки
# ------------------------------------------------------------------------------

# Парсит аргументы командной строки и устанавливает флаги.
#
# Аргументы:
#   $@ — аргументы командной строки
#
# Возвращает:
#   0 — если аргументы распарсены успешно
#   1 — если есть ошибка в аргументах
#
# Устанавливает глобальные переменные:
#   NO_PROMPT — флаг запрета интерактивных запросов
#   YAML_FILE — путь к YAML файлу
parse_arguments() {
    NO_PROMPT=0
    YAML_FILE="output/form.yml"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --no-prompt)
                NO_PROMPT=1
                shift
                ;;
            --version|-v)
                echo "emoji-importer version 1.0.0"
                exit 0
                ;;
            --file|-f)
                if [ -z "${2:-}" ]; then
                    log_error "Требуется аргумент для опции $1"
                    return 1
                fi
                YAML_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Неизвестная опция: $1"
                show_help
                return 1
                ;;
        esac
    done

    return 0
}

# ------------------------------------------------------------------------------
# Загрузка конфигурации
# ------------------------------------------------------------------------------

# Загружает .env файл и валидирует его.
#
# Возвращает:
#   0 — если файл загружен успешно
#   1 — если загрузка не удалась
load_configuration() {
    if ! load_env; then
        log_error "Не удалось загрузить .env файл"
        return 1
    fi

    return 0
}

# Проверяет и валидирует YAML файл.
#
# Аргументы:
#   $1 — yaml_file: путь к YAML файлу
#
# Возвращает:
#   0 — если файл валиден
#   1 — если файл не валиден
#
# Устанавливает:
#   YAML_FILE — абсолютный путь к файлу
validate_yaml_file() {
    local yaml_file="$1"

    # Проверяем существование файла
    if [ ! -f "$yaml_file" ]; then
        log_error "Файл не найден: ${yaml_file}"
        return 1
    fi

    # Проверяем расширение файла
    local file_ext="${yaml_file##*.}"
    if [ "$file_ext" != "yml" ] && [ "$file_ext" != "yaml" ]; then
        log_error "Неверное расширение файла: ${file_ext}"
        log_error "Ожидается .yml или .yaml"
        return 1
    fi

    # Преобразуем в абсолютный путь
    YAML_FILE="$(cd "$(dirname "$yaml_file")" && pwd)/$(basename "$yaml_file")"
    log_info "Используется локальный YAML файл: ${YAML_FILE}"

    return 0
}

# Запрашивает недостающие конфигурационные значения у пользователя.
#
# Возвращает:
#   0 — если все значения запрошены успешно
prompt_for_configuration() {
    # Запрашиваем только недостающие значения
    if [ -z "$ROCKETCHAT_SERVER_URL" ]; then
        prompt "Rocket.Chat сервер URL" "" "ROCKETCHAT_SERVER_URL"
    fi
    if [ -z "$ROCKETCHAT_ADMIN_USERNAME" ]; then
        prompt "Rocket.Chat админ username" "" "ROCKETCHAT_ADMIN_USERNAME"
    fi
    prompt_secret "Rocket.Chat админ пароль" "ROCKETCHAT_ADMIN_PASSWORD"

    echo ""
    return 0
}

# Валидирует конфигурацию после загрузки.
#
# Возвращает:
#   0 — если конфигурация валидна
#   1 — если конфигурация невалидна
validate_configuration() {
    if [ -z "$ROCKETCHAT_SERVER_URL" ] || \
       [ -z "$ROCKETCHAT_ADMIN_USERNAME" ] || \
       [ -z "$ROCKETCHAT_ADMIN_PASSWORD" ]; then
        log_error "Конфигурация невалидна. Проверьте переменные окружения."
        return 1
    fi

    if ! validate_server_url; then
        return 1
    fi

    log_debug "Конфигурация валидна"
    return 0
}

# ------------------------------------------------------------------------------
# Аутентификация
# ------------------------------------------------------------------------------

# Выполняет аутентификацию в Rocket.Chat.
#
# Возвращает:
#   0 — если аутентификация успешна
#   1 — если аутентификация не удалась
authenticate() {
    log_info "Аутентификация в Rocket.Chat..."
    if ! api_login "$ROCKETCHAT_SERVER_URL" "$ROCKETCHAT_ADMIN_USERNAME" "$ROCKETCHAT_ADMIN_PASSWORD"; then
        log_error "Не удалось аутентифицироваться"
        return 1
    fi
    log_debug "Аутентификация успешна: user_id=${USER_ID}"

    return 0
}

# ------------------------------------------------------------------------------
# Импорт эмодзи
# ------------------------------------------------------------------------------

# Получает список существующих эмодзи и выводит информацию.
#
# Возвращает:
#   0 — если список получен успешно
#
# Устанавливает:
#   EXISTING_EMOJIS — список существующих эмодзи
#   EXISTING_COUNT — количество существующих эмодзи
get_existing_emojis() {
    log_info "Получение списка существующих эмодзи..."
    EXISTING_EMOJIS=$(api_list_emoji_names "$ROCKETCHAT_SERVER_URL")

    EXISTING_COUNT=$(count_existing_emojis "$EXISTING_EMOJIS")
    log_info "Найдено ${EXISTING_COUNT} существующих эмодзи"

    return 0
}

# Выполняет импорт эмодзи из YAML файла.
#
# Аргументы:
#   $1 — yaml_file: путь к YAML файлу
#
# Возвращает:
#   0 — если импорт успешен
#   1 — если импорт не удался
perform_import() {
    local yaml_file="$1"

    log_info "Начало импорта..."

    if ! import_emojis_from_file "$ROCKETCHAT_SERVER_URL" "$yaml_file" "$EXISTING_EMOJIS"; then
        log_error "Импорт завершён с ошибками"
        return 1
    fi

    log_info "Импорт завершён успешно!"

    return 0
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
    log_info "Запуск импорта эмодзи..."

    # Парсим аргументы командной строки
    if ! parse_arguments "$@"; then
        exit 1
    fi

    # Загружаем конфигурацию
    if ! load_configuration; then
        exit 1
    fi

    # Валидируем YAML файл
    if ! validate_yaml_file "$YAML_FILE"; then
        exit 1
    fi

    # Запрашиваем конфигурацию если нужно
    if [ "$NO_PROMPT" -eq 0 ]; then
        if [ -z "$ROCKETCHAT_SERVER_URL" ] || \
           [ -z "$ROCKETCHAT_ADMIN_USERNAME" ] || \
           [ -z "$ROCKETCHAT_ADMIN_PASSWORD" ]; then
            prompt_for_configuration
        fi
    fi

    # Валидируем конфигурацию
    if ! validate_configuration; then
        exit 1
    fi

    # Аутентификация
    if ! authenticate; then
        exit 1
    fi

    # Получаем список существующих эмодзи
    if ! get_existing_emojis; then
        exit 1
    fi

    # Выполняем импорт
    if ! perform_import "$YAML_FILE"; then
        exit 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Запуск
# ------------------------------------------------------------------------------

# Запускаем main только если скрипт выполняется напрямую, а не source'ится
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
