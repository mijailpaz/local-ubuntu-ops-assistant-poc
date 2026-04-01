#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

STACK_DIR="/opt/openclaw"
ENV_FILE="${STACK_DIR}/.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Missing ${ENV_FILE}. Run 'make setup' first."
  exit 1
fi

if [ -f "${REPO_ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${REPO_ENV_FILE}"
  set +a
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

DEFAULT_API_BASE_URL="${N8N_API_BASE_URL:-${N8N_BASE_URL}/api/v1}"

if [ -z "${N8N_API_BASE_URL:-}" ]; then
  read -r -p "Enter the n8n API base URL [${DEFAULT_API_BASE_URL}]: " N8N_API_BASE_URL
  N8N_API_BASE_URL=${N8N_API_BASE_URL:-$DEFAULT_API_BASE_URL}
fi

if [ -z "${N8N_API_KEY:-}" ]; then
  read -r -p "Enter the n8n API key for OpenClaw: " N8N_API_KEY
fi

if [ -z "${N8N_API_KEY}" ]; then
  echo "N8N_API_KEY cannot be empty."
  exit 1
fi

update_env_var() {
  local key="$1"
  local value="$2"
  local file="$3"
  local escaped_value

  escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')

  if grep -q "^${key}=" "$file"; then
    sed -i "s/^${key}=.*/${key}=${escaped_value}/" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

update_env_var "N8N_API_BASE_URL" "${N8N_API_BASE_URL}" "${ENV_FILE}"
update_env_var "N8N_API_KEY" "${N8N_API_KEY}" "${ENV_FILE}"

echo "=== Recreating openclaw-gateway with n8n API settings ==="
cd "${STACK_DIR}"
docker compose up -d --force-recreate openclaw-gateway

echo ""
echo "n8n API authoring access is now configured for OpenClaw."
echo "Base URL: ${N8N_API_BASE_URL}"
echo "The OpenClaw gateway has been recreated to pick up the new environment variables."
