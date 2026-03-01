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

set -euo pipefail

# ------------------------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------------------------

# Выводит статус обработки эмодзи в однострочном формате.
#
# Аргументы:
#   $1 — current: Текущий индекс
#   $2 — total: Всего эмодзи
#   $3 — name: Имя эмодзи
#   $4 — symbol: Символ статуса (✓, ⊖, ✗)
#   $5 — message: Сообщение статуса
#   $6 — max_name_len: Максимальная длина имени (опционально, по умолчанию 30)
#
# Пример:
#   print_status 1 10 "smile" "✓" "добавлен"
print_status() {
    local current="$1"
    local total="$2"
    local name="$3"
    local symbol="$4"
    local message="$5"
    local max_name_len="${6:-30}"
    
    printf "[%3d/%d] Обработка: %-${max_name_len}s %s %s\n" "$current" "$total" "$name" "$symbol" "$message"
}

# Проверяет, что MIME тип разрешён для загрузки.
#
# Аргументы:
#   $1 — content_type: MIME тип для проверки
#
# Возвращает:
#   0 — если тип разрешён
#   1 — если тип запрещён
#
# Пример:
#   validate_content_type "image/png" || return 1
validate_content_type() {
    local content_type="$1"
    local allowed_types="image/png image/gif image/jpeg image/webp"

    # Проверяем, что тип входит в список разрешённых
    for allowed in $allowed_types; do
        if [ "$content_type" = "$allowed" ]; then
            return 0
        fi
    done

    log_error "Недопустимый MIME тип: ${content_type} (разрешены: ${allowed_types})"
    return 1
}

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
    local max_size=1048576  # 1 MB (максимальный размер для эмодзи)

    temp_file=$(mktemp)

    # Загружаем файл с ограничением размера (прекращает загрузку при превышении)
    if ! curl -sL --max-filesize "$max_size" "$src" -o "$temp_file" 2>/dev/null; then
        local curl_exit=$?
        rm -f "$temp_file"
        if [ $curl_exit -eq 63 ]; then
            echo "Файл превышает максимальный размер 1 MB: ${src}" >&2
        else
            echo "Ошибка загрузки изображения: ${src}" >&2
        fi
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
    local temp_file=""

    # Проверяем, существует ли уже эмодзи
    if [ -n "$existing_emojis" ]; then
        # Используем grep -Fx для точного совпадения всей строки (без интерпретации спецсимволов)
        if echo "$existing_emojis" | grep -Fxq "$name"; then
            echo "Emoji ${name} уже существует, пропускаем"
            return 0
        fi
    fi

    # Скачиваем изображение
    temp_file=$(download_image "$src") || return 1

    # Определяем тип контента
    local filename
    filename=$(basename "$src")
    
    # Sanitization: проверяем на path traversal
    if [[ "$filename" == *..* ]]; then
        log_error "Невалидное имя файла (path traversal): ${filename}"
        rm -f "$temp_file"
        return 1
    fi
    
    local content_type
    content_type=$(get_content_type "$filename")

    # Валидируем MIME тип перед загрузкой
    validate_content_type "$content_type" || {
        rm -f "$temp_file"
        return 1
    }

    # Загружаем эмодзи на сервер
    local error_msg
    if ! error_msg=$(api_create_emoji "$server_url" "$name" "$temp_file" "$content_type" 2>&1); then
        rm -f "$temp_file"
        echo "Ошибка импорта эмодзи ${name}: ${error_msg}" >&2
        return 1
    fi

    # Очищаем временный файл сразу после использования
    rm -f "$temp_file"

    echo "Успешно добавлен эмодзи: ${name}"
    return 0
}

# ------------------------------------------------------------------------------
# Функции пакетной обработки
# ------------------------------------------------------------------------------

# Обрабатывает список эмодзи из YAML данных.
#
# Аргументы:
#   $1 — server_url: URL Rocket.Chat сервера
#   $2 — emoji_list: Список name|src (newline-separated)
#   $3 — existing_emojis: Список существующих эмодзи
#   $4 — show_progress: Показывать прогресс (0 или 1)
#
# Возвращает:
#   0 — если все эмодзи обработаны (успешно или пропущены)
#   1 — если были критические ошибки
#
# Пример:
#   import_emoji_list "$SERVER_URL" "$emoji_list" "$existing" 1
import_emoji_list() {
    local server_url="$1"
    local emoji_list="$2"
    local existing_emojis="$3"
    local show_progress="${4:-0}"
    local temp_file=""

    local total_count
    total_count=$(count_emojis "$emoji_list")

    if [ "$total_count" -eq 0 ]; then
        echo "Эмодзи не найдены в YAML файле"
        return 0
    fi

    # Вычисляем максимальную длину имени для форматирования вывода
    local max_name_len=0
    local temp_name=""
    while IFS='|' read -r temp_name _; do
        [ -z "$temp_name" ] && continue
        local name_len=${#temp_name}
        if [ "$name_len" -gt "$max_name_len" ]; then
            max_name_len="$name_len"
        fi
    done <<< "$emoji_list"

    local uploaded_count=0
    local skipped_count=0
    local error_count=0
    local current_index=0

    # Обрабатываем каждый эмодзи
    while IFS='|' read -r name src; do
        [ -z "$name" ] && continue

        ((current_index++)) || true

        local status_msg=""
        local status_symbol=""

        # Проверяем, существует ли уже эмодзи
        if [ -n "$existing_emojis" ] && echo "$existing_emojis" | grep -Fxq "$name"; then
            status_symbol="⊖"
            status_msg="уже существует"
            ((skipped_count++)) || true
            if [ "$show_progress" -eq 1 ] || [ "${DEBUG:-0}" = "1" ]; then
                print_status "$current_index" "$total_count" "$name" "$status_symbol" "$status_msg" "$max_name_len"
            fi
            continue
        fi

        # Скачиваем изображение
        temp_file=$(download_image "$src")
        if [ $? -ne 0 ]; then
            status_symbol="✗"
            status_msg="ошибка загрузки файла"
            ((error_count++)) || true
            if [ "$show_progress" -eq 1 ]; then
                print_status "$current_index" "$total_count" "$name" "$status_symbol" "$status_msg" "$max_name_len"
            fi
            rm -f "$temp_file" 2>/dev/null || true
            continue
        fi

        # Определяем тип контента
        local filename
        filename=$(basename "$src")

        # Sanitization: проверяем на path traversal
        if [[ "$filename" == *..* ]]; then
            log_error "Невалидное имя файла (path traversal): ${filename}"
            rm -f "$temp_file"
            status_symbol="✗"
            status_msg="невалидное имя файла"
            ((error_count++)) || true
            if [ "$show_progress" -eq 1 ]; then
                print_status "$current_index" "$total_count" "$name" "$status_symbol" "$status_msg" "$max_name_len"
            fi
            continue
        fi

        local content_type
        content_type=$(get_content_type "$filename")

        # Валидируем MIME тип перед загрузкой
        if ! validate_content_type "$content_type"; then
            rm -f "$temp_file"
            status_symbol="✗"
            status_msg="недопустимый MIME тип"
            ((error_count++)) || true
            if [ "$show_progress" -eq 1 ]; then
                print_status "$current_index" "$total_count" "$name" "$status_symbol" "$status_msg" "$max_name_len"
            fi
            continue
        fi

        # Загружаем эмодзи на сервер
        local error_msg=""
        if api_create_emoji "$server_url" "$name" "$temp_file" "$content_type" 2>&1; then
            status_symbol="✓"
            status_msg="добавлен"
            ((uploaded_count++)) || true
        else
            error_msg=$(api_create_emoji "$server_url" "$name" "$temp_file" "$content_type" 2>&1 | head -c 50)
            status_symbol="✗"
            status_msg="ошибка: ${error_msg}"
            ((error_count++)) || true
        fi

        if [ "$show_progress" -eq 1 ] || [ "${DEBUG:-0}" = "1" ]; then
            print_status "$current_index" "$total_count" "$name" "$status_symbol" "$status_msg" "$max_name_len"
        fi

        # Немедленно очищаем временный файл после использования
        rm -f "$temp_file"
        temp_file=""

    done <<< "$emoji_list"

    # Выводим статистику
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

    import_emoji_list "$server_url" "$emoji_list" "$existing_emojis" 0
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

    echo "Обработка эмодзи из YAML..."
    echo ""

    import_emoji_list "$server_url" "$emoji_list" "$existing_emojis" 0
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
