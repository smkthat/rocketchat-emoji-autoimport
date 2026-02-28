#!/bin/bash
#
# utils.sh — Вспомогательные утилиты
#
# Модуль предоставляет общие функции для логирования, определения
# типа контента и других вспомогательных операций.
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Константы
# ------------------------------------------------------------------------------

readonly LOG_PREFIX="[emoji-import]"

# ------------------------------------------------------------------------------
# Функции логирования
# ------------------------------------------------------------------------------

# Выводит информационное сообщение в stdout.
#
# Аргументы:
#   message — Сообщение для вывода
#
# Пример:
#   log_info "Процесс запущен"
log_info() {
    local message="$1"
    echo "${LOG_PREFIX} INFO: ${message}"
}

# Выводит сообщение об ошибке в stderr.
#
# Аргументы:
#   message — Сообщение об ошибке
#
# Пример:
#   log_error "Не удалось подключиться"
log_error() {
    local message="$1"
    echo "${LOG_PREFIX} ERROR: ${message}" >&2
}

# Выводит отладочное сообщение (только если DEBUG=1).
#
# Аргументы:
#   message — Отладочное сообщение
#
# Пример:
#   log_debug "Значение переменной: $x"
log_debug() {
    local message="$1"
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "${LOG_PREFIX} DEBUG: ${message}" >&2
    fi
}

# ------------------------------------------------------------------------------
# Функции для работы с файлами
# ------------------------------------------------------------------------------

# Определяет MIME-тип файла по расширению.
#
# Аргументы:
#   filename — Имя файла или URL
#
# Возвращает:
#   Строку с MIME-типом (image/png, image/gif, image/jpeg)
#
# Пример:
#   get_content_type "image.png"  # вернёт "image/png"
get_content_type() {
    local filename="$1"

    # Валидируем входной параметр
    if [ -z "$filename" ]; then
        log_error "get_content_type: имя файла не может быть пустым"
        return 1
    fi

    # Sanitization: проверяем на path traversal
    if [[ "$filename" == *..* ]]; then
        log_error "get_content_type: невалидное имя файла (path traversal)"
        return 1
    fi

    # Удаляем query-параметры из URL если есть
    filename="${filename%%\?*}"

    # Извлекаем расширение
    local ext="${filename##*.}"

    # Конвертируем в нижний регистр
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        png)
            echo "image/png"
            ;;
        jpg|jpeg)
            echo "image/jpeg"
            ;;
        gif)
            echo "image/gif"
            ;;
        webp)
            echo "image/webp"
            ;;
        *)
            echo "application/octet-stream"
            ;;
    esac
}

# Создаёт временный файл и возвращает его путь.
#
# Возвращает:
#   0 — если файл создан успешно (путь в stdout)
#   1 — если не удалось создать файл
#
# Пример:
#   temp_file=$(create_temp_file) || exit 1
create_temp_file() {
    local temp_file
    if ! temp_file=$(mktemp 2>/dev/null); then
        log_error "Не удалось создать временный файл"
        return 1
    fi
    echo "$temp_file"
}

# Удаляет временный файл, если он существует.
#
# Аргументы:
#   file_path — Путь к файлу
#
# Пример:
#   cleanup_temp_file "/tmp/tmp.XXX"
cleanup_temp_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        rm -f "$file_path"
    fi
}

# ------------------------------------------------------------------------------
# Функции валидации
# ------------------------------------------------------------------------------

# Проверяет, что строка не пустая.
#
# Аргументы:
#   value — Значение для проверки
#   name — Имя переменной (для сообщения об ошибке)
#
# Возвращает:
#   0 — если значение не пустое
#   1 — если значение пустое
#
# Пример:
#   validate_not_empty "$URL" "URL"
validate_not_empty() {
    local value="$1"
    local name="$2"
    
    if [ -z "$value" ]; then
        log_error "${name} не может быть пустым"
        return 1
    fi
    return 0
}

# Проверяет, что URL начинается с http:// или https://.
#
# Аргументы:
#   url — URL для проверки
#
# Возвращает:
#   0 — если URL валидный
#   1 — если URL невалидный
#
# Пример:
#   validate_url "https://example.com"
validate_url() {
    local url="$1"
    
    if [[ ! "$url" =~ ^https?:// ]]; then
        log_error "Невалидный URL: ${url}"
        return 1
    fi
    return 0
}
