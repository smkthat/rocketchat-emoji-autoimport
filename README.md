# Rocket.Chat Emoji Autoimport

Автоматизация массового импорта пользовательских эмодзи в Rocket.Chat. Скрипт загружает наборы эмодзи из GitHub-репозитория или локальных файлов, генерирует YAML-конфигурацию и загружает их на сервер через API.

## 🚀 Возможности

- ✅ Массовая загрузка эмодзи из GitHub-репозитория
- ✅ Генерация YAML-файла со списком эмодзи
- ✅ Пропуск уже существующих эмодзи
- ✅ Валидация MIME-типов и размеров файлов
- ✅ Интерактивный и автоматический режимы работы
- ✅ Локальный Rocket.Chat для тестирования (Docker)

## 📋 Требования

- **Bash 4.0+**
- **curl**, **jq**, **gh** (GitHub CLI)
- **Docker** & **Docker Compose** (для локального тестирования)

## 🛠️ Быстрый старт

### 1. Инициализация проекта

```bash
# Установить зависимости и создать .env
make init
```

### 2. Настройка конфигурации

Отредактируйте файл `.env`:

```bash
# URL вашего Rocket.Chat сервера
ROCKETCHAT_SERVER_URL=https://your-rocket-chat-url.com

# Учётные данные администратора
ROCKETCHAT_ADMIN_USERNAME=auser
ROCKETCHAT_ADMIN_PASSWORD=admin123ADMIN!@#

# Режим отладки (0 или 1)
DEBUG=0
```

### 3. Генерация файлов и импорт

```bash
# Сгенерировать urls.txt и form.yml
make gen-all

# Импортировать эмодзи (используя значения из .env)
make import-no-prompt
```

## 📖 Примеры использования

### Базовый импорт

```bash
# Полный цикл: генерация + импорт с интерактивным запросом конфигурации
make import
```

### Импорт с существующими настройками

```bash
# Использовать значения из .env без запросов
make import-no-prompt
```

### Пошаговая генерация

```bash
# 1. Получить список URL-адресов эмодзи из GitHub
make gen-urls

# 2. Сгенерировать YAML-файл из urls.txt
make gen-yml

# 3. Проверить содержимое output/form.yml
cat output/form.yml

# 4. Импортировать
make import-no-prompt
```

### Работа с локальным Rocket.Chat

```bash
# 1. Настроить и запустить локальный Rocket.Chat
make rocket-setup

# 2. Открыть http://localhost:3000 и создать администратора:
#    Username: auser
#    Password: admin123ADMIN!@#

# 3. Импортировать эмодзи на локальный сервер
ROCKETCHAT_SERVER_URL=http://localhost:3000 make import-no-prompt

# 4. Просмотреть логи при необходимости
make rocket-logs

# 5. Остановить сервер
make rocket-stop
```

### Отладка

```bash
# Запуск с подробным логированием
DEBUG=1 make import-no-prompt
```

### Проверка скриптов

```bash
# Проверить синтаксис всех bash-скриптов
make spellcheck

# Полная проверка (зависимости + синтаксис)
make check
```

## 📁 Структура проекта

```bash
rocketchat-emoji-autoimport/
├── src/                          # Исходные скрипты
│   ├── import_emoji.sh           # Точка входа для импорта
│   ├── generate_yml_data.sh      # Генератор YAML
│   └── lib/                      # Библиотеки
│       ├── utils.sh              # Логирование, утилиты
│       ├── config.sh             # Загрузка конфигурации
│       ├── prompt.sh             # Интерактивные запросы
│       ├── rocketchat_api.sh     # API клиент Rocket.Chat
│       ├── yaml_parser.sh        # Парсер YAML
│       └── emoji_importer.sh     # Логика загрузки эмодзи
├── scripts/                      # Вспомогательные скрипты
│   ├── banner.sh                 # ASCII-баннер
│   └── setup-rocketchat.sh       # Настройка локального Rocket.Chat
├── emoji/                        # Примеры эмодзи
├── output/                       # Сгенерированные файлы
│   ├── urls.txt                  # Список URL-адресов
│   └── form.yml                  # YAML для импорта
├── docker-compose.yml            # Конфигурация Docker
├── Makefile                      # Команды make
└── .env.example                  # Шаблон конфигурации
```

## 🎯 Команды Make

| Команда                 | Описание                                     |
| ----------------------- | -------------------------------------------- |
| `make gen-all`          | Сгенерировать urls.txt и form.yml            |
| `make gen-urls`         | Получить URL-адреса эмодзи из GitHub         |
| `make gen-yml`          | Сгенерировать form.yml из urls.txt           |
| `make import`           | Импорт с интерактивным запросом конфигурации |
| `make import-no-prompt` | Импорт с использованием .env                 |
| `make rocket-setup`     | Настроить и запустить локальный Rocket.Chat  |
| `make rocket-start`     | Запустить остановленные контейнеры           |
| `make rocket-stop`      | Остановить контейнеры                        |
| `make rocket-reset`     | Удалить все данные Rocket.Chat               |
| `make rocket-logs`      | Просмотр логов контейнеров                   |
| `make spellcheck`       | Проверка синтаксиса bash-скриптов            |
| `make check`            | Полная проверка (зависимости + синтаксис)    |
| `make clean`            | Очистить output от сгенерированных файлов    |
| `make init`             | Инициализация проекта (deps + .env)          |
| `make install-deps`     | Установить отсутствующие зависимости         |
| `make check-deps`       | Проверить наличие зависимостей               |
| `make help`             | Показать справку по всем командам            |

## 📝 Формат YAML

Файл `form.yml` должен иметь следующую структуру:

```yaml
title: clippy
emojis:
  - name: smile
    src:  https://github.com/user/repo/raw/main/emoji/smile.png
  - name: laugh
    src:  https://github.com/user/repo/raw/main/emoji/laugh.gif
  - name: cry
    src:  https://github.com/user/repo/raw/main/emoji/cry.jpg
```

## 🔧 Поддерживаемые форматы эмодзи

| Формат | MIME-тип     |
| ------ | ------------ |
| PNG    | `image/png`  |
| GIF    | `image/gif`  |
| JPEG   | `image/jpeg` |
| WebP   | `image/webp` |

**Ограничения:**

- Максимальный размер файла: 1 MB
- Имя файла не должно содержать `..` (защита от path traversal)

## 🔐 Безопасность

- Учётные данные хранятся в `.env` (игнорируется git)
- Пароли вводятся через скрытый ввод (`read -rs`)
- Валидация MIME-типов перед загрузкой
- Проверка на path traversal в именах файлов
- Ограничение размера загружаемых файлов (1 MB)

## 🧪 Тестирование

### Локальное тестирование

```bash
# 1. Настроить локальный Rocket.Chat
make rocket-setup

# 2. Дождаться запуска (2-3 минуты)
#    Проверить статус: docker ps

# 3. Открыть http://localhost:3000
#    Создать администратора с credentials из .env

# 4. Импортировать эмодзи
make import-no-prompt

# 5. Проверить результат в веб-интерфейсе
```

### Отладка

```bash
# Включить подробное логирование
DEBUG=1 make import

# Просмотреть логи Rocket.Chat
make rocket-logs

# Проверить синтаксис скриптов
make spellcheck
```

## 📊 Обработка ошибок

| Ситуация              | Поведение                    |
| --------------------- | ---------------------------- |
| Эмодзи уже существует | Пропускается (⊖)             |
| Ошибка загрузки файла | Логирование, продолжение (✗) |
| Неверный MIME-тип     | Отклоняется до загрузки (✗)  |
| HTTP ошибка API       | Логирование, продолжение (✗) |
| Файл > 1 MB           | Пропускается с ошибкой       |

> Made with ❤️ by School 21
