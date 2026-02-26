#!/bin/bash
#
# emoji_importer.sh — Логика импорта эмодзи
#
# Модуль предоставляет функции для загрузки, скачивания и импорта
# отдельных эмодзи и пакетной обработки списков эмодзи.
#
# Зависимости:
#   - curl
#   - jq
#   - utils.sh
#   - rocketchat_api.sh
#   - yaml_parser.sh
#

# ------------------------------------------------------------------------------
# Функции для работы с отдельными эмодзи
# ------------------------------------------------------------------------------

# Скачивает изображение по URL во временный файл.
#
# Аргументы:
#   $1 — src: URL изображения
#
# Возвращает:
#   0 — если загрузка успешна (путь к файлу в stdout)
#   1 — если загрузка не удалась
#
# Пример:
#   temp_file=$(download_image "https://example.com/image.png")
download_image() {
    local src="$1"
    
    local temp_file
    temp_file=$(mktemp)
    
    if ! curl -sL "$src" -o "$temp_file"; then
        rm -f "$temp_file"
        echo "Ошибка загрузки изображения: ${src}" >&2
        return 1
    fi
    
    # Проверяем, что файл не пустой
    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        echo "Пустое изображение: ${src}" >&2
        return 1
    fi
    
    echo "$temp_file"
}

# Импортирует один эмодзи на сервер.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — name: Имя эмодзи
#   $3 — src: URL изображения
#   $4 — existing_emojis: Список существующих эмодзи (опционально)
#
# Возвращает:
#   0 — если импорт успешен или эмодзи уже существует
#   1 — если импорт не удался
#
# Пример:
#   import_emoji "$ROCKETCHAT_SERVER_URL" "smile" "https://..." "$existing"
import_emoji() {
    local server_url="$1"
    local name="$2"
    local src="$3"
    local existing_emojis="${4:-}"
    
    # Проверяем, существует ли уже эмодзи
    if [ -n "$existing_emojis" ]; then
        if echo "$existing_emojis" | grep -q "^${name}$"; then
            echo "Emoji ${name} уже существует, пропускаем"
            return 0
        fi
    fi
    
    # Скачиваем изображение
    local temp_file
    temp_file=$(download_image "$src") || return 1
    
    # Определяем тип контента
    local filename
    filename=$(basename "$src")
    local content_type
    content_type=$(get_content_type "$filename")
    
    # Загружаем эмодзи на сервер
    local error_msg
    if ! error_msg=$(api_create_emoji "$server_url" "$name" "$temp_file" "$content_type" 2>&1); then
        rm -f "$temp_file"
        echo "Ошибка импорта эмодзи ${name}: ${error_msg}" >&2
        return 1
    fi
    
    # Очищаем временный файл
    rm -f "$temp_file"
    
    echo "Успешно добавлен эмодзи: ${name}"
    return 0
}

# ------------------------------------------------------------------------------
# Функции пакетной обработки
# ------------------------------------------------------------------------------

# Импортирует список эмодзи из локального YAML файла.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — yaml_path: Путь к YAML файлу
#   $3 — existing_emojis: Список существующих эмодзи
#
# Возвращает:
#   0 — если все эмодзи обработаны (успешно или пропущены)
#   1 — если были критические ошибки
#
# Пример:
#   import_emojis_from_file "$ROCKETCHAT_SERVER_URL" "./form.yml" "$existing"
import_emojis_from_file() {
    local server_url="$1"
    local yaml_path="$2"
    local existing_emojis="$3"

    # Читаем и парсим YAML файл
    local yaml_content
    yaml_content=$(cat "$yaml_path") || {
        log_error "Не удалось прочитать файл: ${yaml_path}"
        return 1
    }

    local emoji_list
    emoji_list=$(parse_emoji_yaml "$yaml_content")

    local total_count
    total_count=$(count_emojis "$emoji_list")

    if [ "$total_count" -eq 0 ]; then
        echo "Эмодзи не найдены в YAML файле"
        return 0
    fi

    echo "Обработка ${total_count} эмодзи из файла..."

    local uploaded_count=0
    local skipped_count=0
    local error_count=0
    local current_index=0

    # Обрабатываем каждый эмодзи
    while IFS='|' read -r name src; do
        [ -z "$name" ] && continue

        ((current_index++)) || true
        echo "[${current_index}/${total_count}] Обработка: ${name}"

        # Проверяем, существует ли уже эмодзи
        if [ -n "$existing_emojis" ] && echo "$existing_emojis" | grep -q "^${name}$"; then
            echo "  → уже существует, пропускаем"
            ((skipped_count++)) || true
            continue
        fi

        # Скачиваем изображение
        local temp_file
        temp_file=$(download_image "$src")
        if [ $? -ne 0 ]; then
            ((error_count++)) || true
            continue
        fi

        # Определяем тип контента
        local filename
        filename=$(basename "$src")
        local content_type
        content_type=$(get_content_type "$filename")

        # Загружаем эмодзи на сервер
        if api_create_emoji "$server_url" "$name" "$temp_file" "$content_type"; then
            echo "  → успешно добавлен"
            ((uploaded_count++)) || true
        else
            echo "  → ошибка загрузки" >&2
            ((error_count++)) || true
        fi

        # Очищаем временный файл
        rm -f "$temp_file"

    done <<< "$emoji_list"

    # Выводим статистику
    echo ""
    echo "=== Результаты импорта ==="
    echo "  Всего: ${total_count}"
    echo "  Добавлено: ${uploaded_count}"
    echo "  Пропущено: ${skipped_count}"
    echo "  Ошибок: ${error_count}"

    # Возвращаем ошибку, если были неудачи
    if [ "$error_count" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Импортирует список эмодзи из YAML по URL.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — yaml_url: URL YAML файла
#   $3 — existing_emojis: Список существующих эмодзи
#
# Возвращает:
#   0 — если все эмодзи обработаны (успешно или пропущены)
#   1 — если были критические ошибки
#
# Пример:
#   import_all_emojis "$ROCKETCHAT_SERVER_URL" "$EMOJI_YAML_URL" "$existing"
import_all_emojis() {
    local server_url="$1"
    local yaml_url="$2"
    local existing_emojis="$3"

    # Загружаем и парсим YAML
    local emoji_list
    emoji_list=$(parse_emoji_yaml_url "$yaml_url") || return 1

    local total_count
    total_count=$(count_emojis "$emoji_list")

    if [ "$total_count" -eq 0 ]; then
        echo "Эмодзи не найдены в YAML файле"
        return 0
    fi

    echo "Обработка ${total_count} эмодзи из YAML..."

    local uploaded_count=0
    local skipped_count=0
    local error_count=0
    local current_index=0

    # Обрабатываем каждый эмодзи
    while IFS='|' read -r name src; do
        [ -z "$name" ] && continue

        ((current_index++)) || true
        echo "[${current_index}/${total_count}] Обработка: ${name}"

        # Проверяем, существует ли уже эмодзи
        if [ -n "$existing_emojis" ] && echo "$existing_emojis" | grep -q "^${name}$"; then
            echo "  → уже существует, пропускаем"
            ((skipped_count++)) || true
            continue
        fi

        # Скачиваем изображение
        local temp_file
        temp_file=$(download_image "$src")
        if [ $? -ne 0 ]; then
            ((error_count++)) || true
            continue
        fi

        # Определяем тип контента
        local filename
        filename=$(basename "$src")
        local content_type
        content_type=$(get_content_type "$filename")

        # Загружаем эмодзи на сервер
        if api_create_emoji "$server_url" "$name" "$temp_file" "$content_type"; then
            echo "  → успешно добавлен"
            ((uploaded_count++)) || true
        else
            echo "  → ошибка загрузки" >&2
            ((error_count++)) || true
        fi

        # Очищаем временный файл
        rm -f "$temp_file"

    done <<< "$emoji_list"

    # Выводим статистику
    echo ""
    echo "=== Результаты импорта ==="
    echo "  Всего: ${total_count}"
    echo "  Добавлено: ${uploaded_count}"
    echo "  Пропущено: ${skipped_count}"
    echo "  Ошибок: ${error_count}"

    # Возвращаем ошибку, если были неудачи
    if [ "$error_count" -gt 0 ]; then
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Функции статистики
# ------------------------------------------------------------------------------

# Подсчитывает количество существующих эмодзи.
#
# Аргументы:
#   $1 — emoji_list: Список имён эмодзи (newline-separated)
#
# Возвращает:
#   Количество эмодзи
#
# Пример:
#   count=$(count_existing_emojis "$existing_emojis")
count_existing_emojis() {
    local emoji_list="$1"
    
    if [ -z "$emoji_list" ]; then
        echo 0
        return
    fi
    
    echo "$emoji_list" | grep -c . || echo 0
}
