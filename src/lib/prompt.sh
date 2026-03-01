#!/bin/bash
#
# prompt.sh — Интерактивный ввод пользовательских данных
#
# Модуль предоставляет функции для запроса значений у пользователя
# через командную строку с поддержкой значений по умолчанию.
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------------------------

# Валидирует имя переменной окружения.
#
# Аргументы:
#   $1 — var_name: Имя переменной для проверки
#
# Возвращает:
#   0 — если имя валидно
#   1 — если имя невалидно
#
# Пример:
#   validate_var_name "MY_VAR" || return 1
validate_var_name() {
    local var_name="$1"

    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "Ошибка: невалидное имя переменной: $var_name" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Основные функции ввода
# ------------------------------------------------------------------------------

# Запрашивает значение у пользователя с опциональным значением по умолчанию.
#
# Аргументы:
#   $1 — prompt_text: Текст приглашения для ввода
#   $2 — default_value: Значение по умолчанию (может быть пустым)
#   $3 — var_name: Имя переменной для сохранения результата
#
# Поведение:
#   - Если значение по умолчанию указано, оно показывается в [квадратных скобках]
#   - Если пользователь вводит пустую строку, используется значение по умолчанию
#   - Результат экспортируется в переменную с именем var_name
#
# Пример:
#   prompt "Введите URL сервера: " "https://chat.example.com" "SERVER_URL"
#   echo "$SERVER_URL"
prompt() {
    local prompt_text="$1"
    local default_value="$2"
    local var_name="$3"
    local value

    # Валидируем имя переменной
    validate_var_name "$var_name" || return 1

    # Формируем приглашение с значением по умолчанию
    if [ -n "$default_value" ]; then
        echo -n "${prompt_text} [${default_value}]: "
    else
        echo -n "${prompt_text}: "
    fi

    # Читаем ввод пользователя
    read -r value

    # Используем значение по умолчанию, если ввод пуст
    if [ -z "$value" ] && [ -n "$default_value" ]; then
        value="$default_value"
    fi

    # Экспортируем результат в переменную
    export "$var_name"="$value"
}

# Запрашивает значение, скрывая ввод (для паролей).
#
# Аргументы:
#   $1 — prompt_text: Текст приглашения для ввода
#   $2 — var_name: Имя переменной для сохранения результата
#
# Пример:
#   prompt_secret "Введите пароль: " "PASSWORD"
#   echo "$PASSWORD"
prompt_secret() {
    local prompt_text="$1"
    local var_name="$2"
    local value

    # Валидируем имя переменной
    validate_var_name "$var_name" || return 1

    echo -n "${prompt_text}: "

    # Читаем ввод без отображения символов
    read -rs value
    echo ""  # Новая строка после ввода

    # Экспортируем результат в переменную
    export "$var_name"="$value"
}

# ------------------------------------------------------------------------------
# Функции для сбора всех конфигурационных данных
# ------------------------------------------------------------------------------

# Запрашивает все необходимые конфигурационные значения у пользователя.
#
# Аргументы:
#   $1 — default_server_url: URL сервера по умолчанию
#   $2 — default_yaml_url: URL YAML файла по умолчанию
#   $3 — default_username: Имя пользователя по умолчанию
#
# Устанавливает переменные окружения:
#   - ROCKETCHAT_SERVER_URL
#   - EMOJI_YAML_URL
#   - ROCKETCHAT_ADMIN_USERNAME
#   - ROCKETCHAT_ADMIN_PASSWORD
#
# Пример:
#   collect_all_config "" "" ""
collect_all_config() {
    local default_server_url="${1:-}"
    local default_yaml_url="${2:-}"
    local default_username="${3:-}"
    
    echo "=== Настройка импорта эмодзи ==="
    echo ""
    
    prompt "URL для YAML файла" "$default_yaml_url" "EMOJI_YAML_URL"
    prompt "Rocket.Chat сервер URL" "$default_server_url" "ROCKETCHAT_SERVER_URL"
    prompt "Rocket.Chat админ username" "$default_username" "ROCKETCHAT_ADMIN_USERNAME"
    prompt_secret "Rocket.Chat админ пароль" "ROCKETCHAT_ADMIN_PASSWORD"
    
    echo ""
}

# Подтверждает конфигурацию перед выполнением.
#
# Возвращает:
#   0 — если пользователь подтвердил
#   1 — если пользователь отменил
#
# Пример:
#   if ! confirm_config; then exit 0; fi
confirm_config() {
    local response
    
    echo ""
    echo "Конфигурация:"
    echo "  YAML URL: ${EMOJI_YAML_URL}"
    echo "  Server URL: ${ROCKETCHAT_SERVER_URL}"
    echo "  Username: ${ROCKETCHAT_ADMIN_USERNAME}"
    echo "  Password: [скрыто]"
    echo ""
    echo -n "Продолжить? (y/N): "
    
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Отменено пользователем"
        return 1
    fi
}
