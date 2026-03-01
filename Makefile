.DEFAULT_GOAL := help

.PHONY: help clean auth import-help rocket-help \
	gen-all import import-no-prompt \
	urls yml gen-urls gen-yml \
	check-deps install-deps init \
	rocket-setup rocket-start rocket-stop rocket-reset rocket-logs spellcheck \


# Detect OS
UNAME_S := $(shell uname -s)

# Paths
CWD_ABSOLUTE := $(shell pwd)
SRC_PATH = ${CWD_ABSOLUTE}/src
OUTPUT_PATH = ${CWD_ABSOLUTE}/output
HELPER_SCRIPTS_PATH = ${CWD_ABSOLUTE}/scripts

# Vars
GIT_USER?=smkthat
GIT_REPO?=rocketchat-emoji-autoimport
GIT_REPO_PATH=repos/${GIT_USER}/${GIT_REPO}

LINE = "$(shell printf '%.0s-' {1..60})"

# Category: Основыне цели

gen-all: gen-urls gen-yml  ## Сгенерировать все необходимые файлы

import: gen-all  ## Импорт из output/form.yml с запросом конфигурации
	@${SRC_PATH}/import_emoji.sh --file ${OUTPUT_PATH}/form.yml

import-no-prompt: gen-all  ## Импорт из output/form.yml используя .env (без запроса)
	@${SRC_PATH}/import_emoji.sh --file ${OUTPUT_PATH}/form.yml --no-prompt

# Category: Вспомогательные цели

urls:  ## Получить список URL-адресов всех emoji в stdout
	@gh api ${GIT_REPO_PATH}/contents/emoji \
		| jq -r '.[].download_url'

yml: ## Получить данные для YAML в stdout
	@${SRC_PATH}/generate_yml_data.sh

gen-urls:  ## Сгенерировать URL-адреса всех emoji в output/urls.txt
	@mkdir -p ${OUTPUT_PATH}
	@make urls > ${OUTPUT_PATH}/urls.txt

gen-yml:  ## Сгенерировать output/form.yml файл со списком эмодзи
	@mkdir -p ${OUTPUT_PATH}
	@if [ ! -f ${OUTPUT_PATH}/urls.txt ]; then \
		echo "Ошибка: ${OUTPUT_PATH}/urls.txt не найден." >&2; \
		echo "Сначала выполните: make gen-urls или make gen-all" >&2; \
		exit 1; \
	fi
	@if [ ! -s ${OUTPUT_PATH}/urls.txt ]; then \
		echo "Ошибка: ${OUTPUT_PATH}/urls.txt пуст." >&2; \
		echo "Проверьте наличие emoji в репозитории" >&2; \
		exit 1; \
	fi
	@make yml > ${OUTPUT_PATH}/form.yml

# Category: Зависимости

check-deps:  ## Проверить наличие необходимых зависимостей
	@echo "Проверка зависимостей..."
	@command -v bash >/dev/null 2>&1 || { echo "  ✗ bash не найден"; exit 1; } && echo "  ✓ bash"
	@command -v curl >/dev/null 2>&1 || { echo "  ✗ curl не найден"; exit 1; } && echo "  ✓ curl"
	@command -v jq >/dev/null 2>&1 || { echo "  ✗ jq не найден"; exit 1; } && echo "  ✓ jq"
	@command -v gh >/dev/null 2>&1 || { echo "  ✗ gh не найден"; exit 1; } && echo "  ✓ gh"
	@echo "Все зависимости установлены."

install-deps:  ## Установить отсутствующие зависимости (Homebrew для macOS, apt для Linux)
	@echo "Проверка и установка отсутствующих зависимостей..."
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		echo "  macOS определен, используем Homebrew..."; \
		command -v brew >/dev/null 2>&1 || { echo "Homebrew не найден. Установите: https://brew.sh"; exit 1; }; \
		command -v jq >/dev/null 2>&1 || { echo "  → Установка jq..."; brew install jq; } || true; \
		command -v gh >/dev/null 2>&1 || { echo "  → Установка gh..."; brew install gh; } || true; \
		command -v curl >/dev/null 2>&1 || { echo "  → Установка curl..."; brew install curl; } || true; \
	elif [ "$(UNAME_S)" = "Linux" ]; then \
		echo "  Linux определен, используем apt..."; \
		command -v apt-get >/dev/null 2>&1 || { echo "apt-get не найден. Используйте другую систему установки."; exit 1; }; \
		PKG_NEEDED=""; \
		command -v jq >/dev/null 2>&1 || { echo "  → jq отсутствует"; PKG_NEEDED="$$PKG_NEEDED jq"; }; \
		command -v gh >/dev/null 2>&1 || { echo "  → gh отсутствует"; PKG_NEEDED="$$PKG_NEEDED gh"; }; \
		command -v curl >/dev/null 2>&1 || { echo "  → curl отсутствует"; PKG_NEEDED="$$PKG_NEEDED curl"; }; \
		if [ -n "$$PKG_NEEDED" ]; then \
			echo "Установка:$$PKG_NEEDED"; \
			sudo apt-get update; \
			sudo apt-get install -y $$PKG_NEEDED; \
		else \
			echo "  ✓ Все зависимости уже установлены."; \
		fi; \
	else \
		echo "✗ Неподдерживаемая ОС: $(UNAME_S)"; \
		exit 1; \
	fi
	@echo "Готово."

init: install-deps  ## Установить зависимости и создать .env (если отсутствует)
	@if [ ! -f .env ]; then \
		echo "Создание .env из .env.example..."; \
		grep -v '^#' .env.example | grep -v '^$$' > .env; \
		echo "  ✓ .env создан"; \
	else \
		echo "  ✓ .env уже существует"; \
	fi
	@echo "Инициализация завершена."

# Category: Тестирование

rocket-setup:  ## Настроить и запустить локальный Rocket.Chat (Docker)
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh setup

rocket-start:  ## Запустить Rocket.Chat
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh start

rocket-stop:  ## Остановить Rocket.Chat
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh stop

rocket-reset:  ## Сбросить Rocket.Chat (удалить все данные)
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh reset

rocket-logs:  ## Просмотреть логи Rocket.Chat
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh logs

spellcheck:  ## Проверить синтаксис bash-скриптов в src/ и scripts/
	@echo "Проверка синтаксиса bash-скриптов..."
	@echo "  src/:"
	@for file in ${SRC_PATH}/*.sh; do \
		if [ -f "$$file" ]; then \
			bash -n "$$file" && echo "    ✓ $$file" || exit 1; \
		fi \
	done
	@echo "  ${SRC_PATH}/lib/:"
	@for file in src/lib/*.sh; do \
		if [ -f "$$file" ]; then \
			bash -n "$$file" && echo "    ✓ $$file" || exit 1; \
		fi \
	done
	@echo "  scripts/:"
	@for file in ${HELPER_SCRIPTS_PATH}/*.sh; do \
		if [ -f "$$file" ]; then \
			bash -n "$$file" && echo "    ✓ $$file" || exit 1; \
		fi \
	done
	@echo "Все скрипты прошли проверку."

lint: check-deps spellcheck  ## Проверить зависимости и синтаксис скриптов
	@echo "Полная проверка проекта завершена."

# Category: Утилиты

clean: ## Очистить output от txt и yml/yaml файлов
	@rm -f \
		${OUTPUT_PATH}/*.txt \
		${OUTPUT_PATH}/*.yml \
		${OUTPUT_PATH}/*.yaml 
	@echo "Очистка выполнена."

import-help: ## Показать справку по импорту (import_emoji.sh)
	@${SRC_PATH}/import_emoji.sh --help

rocket-help: ## Показать справку по установке локального Rocket.Chat (setup-rocketchat.sh)
	@${HELPER_SCRIPTS_PATH}/setup-rocketchat.sh --help

auth:  ## Аутентификация в GitHub CLI (интерактив)
	@gh auth login

help:  ## Показать это сообщение
	@${HELPER_SCRIPTS_PATH}/banner.sh
	@echo
	@echo
	@echo "Использование: make <цель>"
	@echo
	@awk 'BEGIN {FS = ":.*?## "} \
		/^# Category:/ {printf "\n  %s ↴\n%s\n", substr($$0, 13), $(LINE)} \
		/^[a-zA-Z0-9_-]+:.*?## / {printf "  %-17s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
