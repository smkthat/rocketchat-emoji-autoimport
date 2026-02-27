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

file="output/urls.txt"

# Проверка существования файла
if [[ ! -f "$file" ]]; then
    echo "Файл не найден: ${file}" >&2
    exit 1
fi

# Проверка, не пуст ли файл (игнорируя пустые строки)
if ! grep -q -v '^$' "$file"; then
    echo "Файл пустой: ${file}" >&2
    exit 1
fi

echo "title: clippy"
echo "emojis:"

# Читаем файл построчно
while IFS= read -r link || [[ -n "$link" ]]; do
    # Пропускаем пустые строки
    [[ -z "$link" ]] && continue

    # Извлекаем имя (аналог pathinfo)
    filename=$(basename "$link")
    name="${filename%.*}"

    echo "  - name: $name"
    echo "    src:  $link"
done < "$file"
