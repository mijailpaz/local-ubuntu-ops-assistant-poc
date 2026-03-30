.PHONY: help init check-stack setup start stop restart recreate recreate-gateway logs logs-openclaw logs-n8n ps config pull cleanup reset reboot-host

STACK_DIR ?= /opt/openclaw
COMPOSE_CMD = sudo docker compose --env-file "$(STACK_DIR)/.env" -f "$(STACK_DIR)/docker-compose.yml"

help:
	@echo "Common commands:"
	@echo "  make init             Create .env from .env.example and edit it in nano"
	@echo "  make setup            Run the local Ubuntu installer"
	@echo "  make start            Start the stack"
	@echo "  make stop             Stop the stack"
	@echo "  make restart          Restart running containers"
	@echo "  make recreate         Recreate the full stack"
	@echo "  make recreate-gateway Recreate only openclaw-gateway"
	@echo "  make logs             Tail all logs"
	@echo "  make logs-openclaw    Tail OpenClaw gateway logs"
	@echo "  make logs-n8n         Tail n8n and worker logs"
	@echo "  make ps               Show container status"
	@echo "  make config           Render effective compose config"
	@echo "  make pull             Pull image updates"
	@echo "  make cleanup          Remove stopped containers and unused volumes"
	@echo "  make reset            Remove the stack and local state"
	@echo "  make reboot-host      Reboot the Ubuntu machine"

init:
	@if [ ! -f .env ]; then cp .env.example .env; fi
	nano .env

check-stack:
	@test -f "$(STACK_DIR)/docker-compose.yml" || (echo "Missing $(STACK_DIR)/docker-compose.yml. Run 'make setup' first."; exit 1)
	@test -f "$(STACK_DIR)/.env" || (echo "Missing $(STACK_DIR)/.env. Run 'make setup' first."; exit 1)

setup:
	chmod +x setup.sh
	sudo ./setup.sh

start: check-stack
	$(COMPOSE_CMD) up -d

stop: check-stack
	$(COMPOSE_CMD) down

restart: check-stack
	$(COMPOSE_CMD) restart

recreate: check-stack
	$(COMPOSE_CMD) up -d --force-recreate

recreate-gateway: check-stack
	$(COMPOSE_CMD) up -d --force-recreate openclaw-gateway

logs: check-stack
	$(COMPOSE_CMD) logs -f

logs-openclaw: check-stack
	$(COMPOSE_CMD) logs -f openclaw-gateway

logs-n8n: check-stack
	$(COMPOSE_CMD) logs -f n8n n8n-worker

ps: check-stack
	$(COMPOSE_CMD) ps

config: check-stack
	$(COMPOSE_CMD) config

pull: check-stack
	$(COMPOSE_CMD) pull

cleanup:
	sudo docker container prune -f
	sudo docker volume prune -f

reset: check-stack
	$(COMPOSE_CMD) down -v --remove-orphans
	sudo rm -rf "$(STACK_DIR)"
	sudo rm -rf /root/.openclaw

reboot-host:
	sudo reboot
