#!/bin/bash
#
# yaml_parser.sh — Парсинг YAML файлов со списком эмодзи
#
# Модуль предоставляет функции для загрузки и парсинга YAML файлов,
# содержащих список эмодзи с их именами и URL изображений.
#
# Ожидаемый формат YAML:
#   emojis:
#     - name: emoji_name
#       src: https://example.com/image.png
#
# Ограничения парсера:
#   - Поддерживает только простые YAML структуры (name + src)
#   - Не поддерживает YAML алиасы
#   - Не поддерживает вложенные структуры
#   - Не поддерживает кавычки в значениях
#   - Для сложных YAML файлов используйте yq
#
# Зависимости:
#   - curl
#   - awk (стандартный)
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Функции парсинга YAML
# ------------------------------------------------------------------------------

# Загружает YAML файл по URL и возвращает его содержимое.
#
# Аргументы:
#   $1 — yaml_url: URL YAML файла
#
# Возвращает:
#   0 — если загрузка успешна (содержимое в stdout)
#   1 — если загрузка не удалась
#
# Пример:
#   yaml_content=$(fetch_yaml "https://example.com/emojis.yaml")
fetch_yaml() {
    local yaml_url="$1"
    
    local response
    local http_code
    
    # Загружаем YAML с проверкой HTTP статуса
    response=$(curl -s -w "\n%{http_code}" -L "$yaml_url")
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    if [ "$http_code" != "200" ]; then
        echo "Ошибка загрузки YAML (HTTP ${http_code}): ${yaml_url}" >&2
        return 1
    fi
    
    echo "$response"
}

# Парсит YAML содержимое и извлекает пары name|src.
#
# Аргументы:
#   $1 — yaml_content: Содержимое YAML файла (строка)
#
# Возвращает:
#   Список строк формата "name|src" (по одной паре в строке)
#
# Пример:
#   emoji_list=$(parse_emoji_yaml "$yaml_content")
#   while IFS='|' read -r name src; do ... done <<< "$emoji_list"
parse_emoji_yaml() {
    local yaml_content="$1"
    
    # Используем awk для парсинга простой YAML структуры
    # Ожидаем формат:
    #   - name: xxx
    #     src: yyy
    echo "$yaml_content" | awk '
        # Пропускаем пустые строки и комментарии
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        
        # Обрабатываем строку с именем эмодзи
        /^[[:space:]]*- name:/ {
            # Извлекаем имя после "- name:"
            gsub(/^[[:space:]]*- name:[[:space:]]*/, "")
            gsub(/[[:space:]]*$/, "")
            current_name = $0
            next
        }
        
        # Обрабатываем строку с именем эмодзи (без дефиса, продолжение списка)
        /^[[:space:]]*name:/ {
            gsub(/^[[:space:]]*name:[[:space:]]*/, "")
            gsub(/[[:space:]]*$/, "")
            current_name = $0
            next
        }
        
        # Обрабатываем строку с URL источника
        /^[[:space:]]*src:/ {
            gsub(/^[[:space:]]*src:[[:space:]]*/, "")
            gsub(/[[:space:]]*$/, "")
            current_src = $0
            
            # Выводим пару, если оба значения установлены
            if (current_name != "" && current_src != "") {
                print current_name "|" current_src
                current_name = ""
            }
            next
        }
    '
}

# Загружает и парсит YAML файл за один вызов.
#
# Аргументы:
#   $1 — yaml_url: URL YAML файла
#
# Возвращает:
#   0 — если успешно (список name|src в stdout)
#   1 — если ошибка
#
# Пример:
#   emoji_list=$(parse_emoji_yaml_url "$EMOJI_YAML_URL")
parse_emoji_yaml_url() {
    local yaml_url="$1"
    
    local yaml_content
    yaml_content=$(fetch_yaml "$yaml_url") || return 1
    
    parse_emoji_yaml "$yaml_content"
}

# Подсчитывает количество эмодзи в списке.
#
# Аргументы:
#   $1 — emoji_list: Список name|src (newline-separated)
#
# Возвращает:
#   Количество эмодзи (число)
#
# Пример:
#   count=$(count_emojis "$emoji_list")
count_emojis() {
    local emoji_list="$1"
    
    if [ -z "$emoji_list" ]; then
        echo 0
        return
    fi
    
    echo "$emoji_list" | grep -c . || echo 0
}

# ------------------------------------------------------------------------------
# Функции для работы с отдельными эмодзи
# ------------------------------------------------------------------------------

# Извлекает имя эмодзи из строки name|src.
#
# Аргументы:
#   $1 — emoji_entry: Строка формата "name|src"
#
# Возвращает:
#   Имя эмодзи
#
# Пример:
#   name=$(get_emoji_name "smile|https://...")
get_emoji_name() {
    local emoji_entry="$1"
    echo "$emoji_entry" | cut -d'|' -f1
}

# Извлекает URL изображения из строки name|src.
#
# Аргументы:
#   $1 — emoji_entry: Строка формата "name|src"
#
# Возвращает:
#   URL изображения
#
# Пример:
#   src=$(get_emoji_src "smile|https://...")
get_emoji_src() {
    local emoji_entry="$1"
    echo "$emoji_entry" | cut -d'|' -f2
}
