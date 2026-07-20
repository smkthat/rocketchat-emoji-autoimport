#!/bin/bash
#
# generate_yml_data.sh — Генерация YAML файла со списком эмодзи
#
# Читает output/urls.txt и генерирует YAML формат для импорта.
#
# Использование:
#   ./src/generate_yml_data.sh > output/form.yml
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------------------------

# Проверяет существование и содержимое файла с URL-адресами.
#
# Аргументы:
#   $1 — file: путь к файлу
#
# Возвращает:
#   0 — если файл существует и не пуст
#   1 — если файл не найден или пуст
validate_urls_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Файл не найден: ${file}" >&2
        return 1
    fi

    # Проверка, не пуст ли файл (игнорируя пустые строки)
    if ! grep -q -v '^$' "$file"; then
        echo "Файл пустой: ${file}" >&2
        return 1
    fi

    return 0
}

# Генерирует YAML запись для одного эмодзи.
#
# Аргументы:
#   $1 — url: URL изображения
#
# Выводит:
#   YAML запись формата:
#     - name: <имя>
#       src:  <url>
generate_emoji_entry() {
    local url="$1"
    local filename
    local name

    filename=$(basename "$url")
    name="${filename%.*}"

    echo "  - name: $name"
    echo "    src:  $url"
}

# ------------------------------------------------------------------------------
# Основная функция
# ------------------------------------------------------------------------------

main() {
    local file="output/urls.txt"

    # Проверка файла
    if ! validate_urls_file "$file"; then
        exit 1
    fi

    # Заголовок YAML
    echo "title: clippy"
    echo "emojis:"

    # Читаем файл построчно
    while IFS= read -r link || [[ -n "$link" ]]; do
        # Пропускаем пустые строки
        [[ -z "$link" ]] && continue

        generate_emoji_entry "$link"
    done < "$file"
}

main
