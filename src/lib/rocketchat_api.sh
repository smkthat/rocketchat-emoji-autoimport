#!/bin/bash
#
# rocketchat_api.sh — API клиент для Rocket.Chat
#
# Модуль предоставляет функции для взаимодействия с Rocket.Chat API:
# аутентификация, получение списка эмодзи, загрузка новых эмодзи.
#
# Зависимости:
#   - curl
#   - jq
#

# ------------------------------------------------------------------------------
# Глобальные переменные сессии
# ------------------------------------------------------------------------------

# Токен аутентификации (устанавливается после login)
AUTH_TOKEN=""

# ID пользователя (устанавливается после login)
USER_ID=""

# ------------------------------------------------------------------------------
# Функции аутентификации
# ------------------------------------------------------------------------------

# Выполняет аутентификацию в Rocket.Chat и сохраняет токены сессии.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — username: Имя пользователя
#   $3 — password: Пароль
#
# Устанавливает глобальные переменные:
#   - AUTH_TOKEN: Токен аутентификации
#   - USER_ID: ID пользователя
#
# Возвращает:
#   0 — если аутентификация успешна
#   1 — если аутентификация не удалась
#
# Пример:
#   api_login "https://chat.example.com" "admin" "password"
api_login() {
    local server_url="$1"
    local username="$2"
    local password="$3"

    local login_response
    local response_http_code
    local json_data

    # Формируем JSON с чувствительными данными в переменной (не в командной строке)
    json_data=$(printf '{"user":"%s","password":"%s"}' "$username" "$password")

    # Выполняем запрос на аутентификацию
    login_response=$(curl -s -w "\n%{http_code}" -X POST "${server_url}/api/v1/login" \
        -H "Content-Type: application/json" \
        --data-binary "$json_data")

    # Последняя строка — HTTP код
    response_http_code=$(echo "$login_response" | tail -n1)
    login_response=$(echo "$login_response" | sed '$d')
    
    # Проверяем HTTP статус
    if [ "$response_http_code" != "200" ]; then
        local error_message
        error_message=$(echo "$login_response" | jq -r '.message // "Неизвестная ошибка"')
        echo "Ошибка аутентификации (HTTP ${response_http_code}): ${error_message}" >&2
        return 1
    fi
    
    # Извлекаем токены
    AUTH_TOKEN=$(echo "$login_response" | jq -r '.data.authToken')
    USER_ID=$(echo "$login_response" | jq -r '.data.userId')
    
    # Проверяем, что токены извлечены
    if [ "$AUTH_TOKEN" = "null" ] || [ -z "$AUTH_TOKEN" ]; then
        echo "Не удалось извлечь authToken из ответа сервера" >&2
        return 1
    fi
    
    if [ "$USER_ID" = "null" ] || [ -z "$USER_ID" ]; then
        echo "Не удалось извлечь userId из ответа сервера" >&2
        return 1
    fi
    
    return 0
}

# ------------------------------------------------------------------------------
# Функции для работы с эмодзи
# ------------------------------------------------------------------------------

# Получает список имён существующих эмодзи на сервере.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#
# Возвращает:
#   Список имён эмодзи (по одному в строке)
#
# Пример:
#   existing_emojis=$(api_list_emoji_names "$ROCKETCHAT_SERVER_URL")
api_list_emoji_names() {
    local server_url="$1"
    
    local response
    response=$(curl -s "${server_url}/api/v1/emoji-custom.list" \
        -H "X-Auth-Token: ${AUTH_TOKEN}" \
        -H "X-User-Id: ${USER_ID}")
    
    # Извлекаем имена эмодзи из ответа
    # Структура: { emojis: { update: [{ name: "..." }, ...] } }
    echo "$response" | jq -r '.emojis.update[].name' 2>/dev/null || echo ""
}

# Загружает новый эмодзи на сервер.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — name: Имя эмодзи
#   $3 — image_path: Путь к файлу изображения
#   $4 — content_type: MIME-тип изображения (опционально)
#
# Возвращает:
#   0 — если загрузка успешна
#   1 — если загрузка не удалась
#
# Пример:
#   api_create_emoji "$ROCKETCHAT_SERVER_URL" "smile" "/tmp/smile.png" "image/png"
#
# Документация API:
#   https://github.com/FXinnovation/RocketChat-docs/tree/master/developer-guides/rest-api/emoji-custom/create
api_create_emoji() {
    local server_url="$1"
    local name="$2"
    local image_path="$3"
    local content_type="${4:-application/octet-stream}"
    
    local filename
    filename=$(basename "$image_path")
    
    local response
    response=$(curl -s -X POST "${server_url}/api/v1/emoji-custom.create" \
        -H "X-Auth-Token: ${AUTH_TOKEN}" \
        -H "X-User-Id: ${USER_ID}" \
        -F "name=${name}" \
        -F "aliases=" \
        -F "emoji=@${image_path};filename=${filename};type=${content_type}")
    
    local success
    success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Неизвестная ошибка"')
        echo "${error_msg}" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------------------------

# Проверяет, существует ли эмодзи с данным именем в списке.
#
# Аргументы:
#   $1 — name: Имя эмодзи для проверки
#   $2 — emoji_list: Список имён эмодзи (newline-separated)
#
# Возвращает:
#   0 — если эмодзи существует
#   1 — если эмодзи не найден
#
# Пример:
#   if emoji_exists "smile" "$existing_emojis"; then ... fi
emoji_exists() {
    local name="$1"
    local emoji_list="$2"
    
    echo "$emoji_list" | grep -q "^${name}$"
}
