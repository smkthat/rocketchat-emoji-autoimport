#!/bin/bash
#
# config.sh — Загрузка конфигурации и переменных окружения
#
# Модуль отвечает за загрузку переменных из .env файла,
# установку значений по умолчанию и валидацию конфигурации.
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Переменные окружения (значения по умолчанию)
# ------------------------------------------------------------------------------

# URL Rocket.Chat сервера
: "${ROCKETCHAT_SERVER_URL:=}"

# URL YAML файла со списком эмодзи
: "${EMOJI_YAML_URL:=}"

# Учётные данные администратора
: "${ADMIN_USERNAME:=}"
: "${ADMIN_PASSWORD:=}"

# Режим отладки (0 или 1)
: "${DEBUG:=0}"

# ------------------------------------------------------------------------------
# Функции загрузки конфигурации
# ------------------------------------------------------------------------------

# Загружает переменные окружения из файла .env
#
# Файл .env должен находиться в корневой директории проекта.
# Комментарии (строки с #) и пустые строки игнорируются.
#
# Возвращает:
#   0 — если файл загружен успешно или файл не существует
#   1 — если файл существует, но не читается
#
# Пример:
#   load_env
load_env() {
    local env_file=".env"

    if [ ! -f "$env_file" ]; then
        return 0
    fi

    if [ ! -r "$env_file" ]; then
        echo "Ошибка: файл ${env_file} существует, но не читается" >&2
        return 1
    fi

    # Загружаем переменные из .env построчно
    while IFS='=' read -r line; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Извлекаем имя переменной и значение
        local var_name="${line%%=*}"
        local var_value="${line#*=}"
        
        # Trim whitespace from var_name
        var_name="${var_name#"${var_name%%[![:space:]]*}"}"
        var_name="${var_name%"${var_name##*[![:space:]]}"}"
        
        # Экспортируем переменную
        export "$var_name"="$var_value"
    done < "$env_file"

    return 0
}

# ------------------------------------------------------------------------------
# Функции валидации конфигурации
# ------------------------------------------------------------------------------

# Проверяет наличие всех обязательных переменных окружения.
#
# Обязательные переменные:
#   - ROCKETCHAT_SERVER_URL
#   - EMOJI_YAML_URL
#   - ADMIN_USERNAME
#   - ADMIN_PASSWORD
#
# Возвращает:
#   0 — если все переменные установлены
#   1 — если хотя бы одна переменная отсутствует
#
# Пример:
#   if ! validate_config; then exit 1; fi
validate_config() {
    local has_error=0

    # Проверяем каждую обязательную переменную
    if [ -z "$ROCKETCHAT_SERVER_URL" ]; then
        echo "Отсутствует обязательная переменная: ROCKETCHAT_SERVER_URL" >&2
        has_error=1
    fi

    if [ -z "$EMOJI_YAML_URL" ]; then
        echo "Отсутствует обязательная переменная: EMOJI_YAML_URL" >&2
        has_error=1
    fi

    if [ -z "$ADMIN_USERNAME" ]; then
        echo "Отсутствует обязательная переменная: ADMIN_USERNAME" >&2
        has_error=1
    fi

    if [ -z "$ADMIN_PASSWORD" ]; then
        echo "Отсутствует обязательная переменная: ADMIN_PASSWORD" >&2
        has_error=1
    fi

    return $has_error
}

# Проверяет валидность URL сервера Rocket.Chat.
#
# Возвращает:
#   0 — если URL валидный
#   1 — если URL невалидный
#
# Пример:
#   validate_server_url
validate_server_url() {
    local url="$ROCKETCHAT_SERVER_URL"

    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "Невалидный URL сервера: ${url}" >&2
        return 1
    fi

    return 0
}

# Проверяет валидность URL YAML файла.
#
# Возвращает:
#   0 — если URL валидный
#   1 — если URL невалидный
#
# Пример:
#   validate_yaml_url
validate_yaml_url() {
    local url="$EMOJI_YAML_URL"
    
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "Невалидный URL YAML файла: ${url}" >&2
        return 1
    fi
    
    return 0
}

# ------------------------------------------------------------------------------
# Функции вывода конфигурации
# ------------------------------------------------------------------------------

# Выводит текущую конфигурацию (без чувствительных данных).
#
# Пример:
#   print_config
print_config() {
    echo "Конфигурация:"
    echo "  ROCKETCHAT_SERVER_URL: ${ROCKETCHAT_SERVER_URL}"
    echo "  EMOJI_YAML_URL: ${EMOJI_YAML_URL}"
    echo "  ADMIN_USERNAME: ${ADMIN_USERNAME}"
    echo "  ADMIN_PASSWORD: [скрыто]"
    echo "  DEBUG: ${DEBUG}"
}
