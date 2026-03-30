#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ENV_FILE="${SCRIPT_DIR}/.env"

if [ -f "${SETUP_ENV_FILE}" ]; then
  # Load repo-local setup defaults without changing the generated runtime env file location.
  set -a
  # shellcheck disable=SC1090
  source "${SETUP_ENV_FILE}"
  set +a
fi

echo ""
echo "==============================================="
echo "  Local Ubuntu OpenClaw + n8n Ops Assistant"
echo "  Telegram-first POC bootstrap"
echo "==============================================="
echo ""

#######################################
# COLLECT USER INPUT
#######################################

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  read -r -p "Enter your Telegram Bot Token: " TELEGRAM_BOT_TOKEN
fi

if [ -z "${TELEGRAM_USER_ID:-}" ]; then
  read -r -p "Enter your Telegram User ID: " TELEGRAM_USER_ID
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  read -r -p "Enter your OpenAI API Key: " OPENAI_API_KEY
fi

if [ -z "${SYMPLA_S_TOKEN:-}" ]; then
  read -r -p "Enter your Sympla S_TOKEN [optional, required for Sympla workflows]: " SYMPLA_S_TOKEN
fi

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -z "${DEFAULT_HOST}" ]; then
  DEFAULT_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

if [ -z "${N8N_HOST:-}" ]; then
  read -r -p "Enter the local hostname or IP for n8n [${DEFAULT_HOST}]: " N8N_HOST
  N8N_HOST=${N8N_HOST:-$DEFAULT_HOST}
fi

N8N_PORT=${N8N_PORT:-5678}
N8N_PROTOCOL=${N8N_PROTOCOL:-http}
N8N_BASE_URL="${N8N_PROTOCOL}://${N8N_HOST}:${N8N_PORT}"
OPENCLAW_IMAGE=${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}

echo ""
echo "n8n will be available at: ${N8N_BASE_URL}"
echo "OpenClaw image: ${OPENCLAW_IMAGE}"
echo ""

#######################################
# AUTO-GENERATED SECRETS
#######################################
GATEWAY_TOKEN=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
N8N_WEBHOOK_SECRET=$(openssl rand -hex 32)
N8N_WEBHOOK_PATH=$(cat /proc/sys/kernel/random/uuid)

echo "=== Installing dependencies ==="
apt update
apt install -y docker.io docker-compose-v2 curl openssl

echo "=== Preparing Docker ==="
systemctl enable docker
systemctl start docker

echo "=== Creating directories ==="
mkdir -p /opt/openclaw
mkdir -p /root/.openclaw/workspace/skills/n8n-ops-workflows
mkdir -p /root/.openclaw/workspace/skills/ops-guardrails
mkdir -p /root/.openclaw/workspace/playbooks

echo "=== Pulling OpenClaw image ==="
docker pull "${OPENCLAW_IMAGE}"
cd /opt/openclaw

echo "=== Creating OpenClaw config ==="
cat > /root/.openclaw/openclaw.json << EOF
{
  "messages": {"ackReactionScope": "group-mentions"},
  "agents": {
    "defaults": {
      "maxConcurrent": 4,
      "subagents": {"maxConcurrent": 8},
      "compaction": {"mode": "safeguard"},
      "workspace": "/home/node/.openclaw/workspace",
      "model": {"primary": "openai/gpt-4.1-mini"},
      "models": {"openai/gpt-4.1-mini": {}}
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {"mode": "token", "token": "${GATEWAY_TOKEN}"},
    "port": 18789,
    "bind": "lan",
    "tailscale": {"mode": "off", "resetOnExit": false},
    "remote": {"token": "${GATEWAY_TOKEN}"}
  },
  "plugins": {"entries": {"telegram": {"enabled": true}}},
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "${TELEGRAM_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": ["${TELEGRAM_USER_ID}"]
    }
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "session-memory": {"enabled": true},
        "command-logger": {"enabled": true}
      }
    }
  }
}
EOF

echo "=== Creating POC workflow catalog ==="
cat > /root/.openclaw/workspace/playbooks/poc-workflows.md << EOF
# Internal Ops Assistant POC Workflows (Sympla)

Approved workflows for this proof of concept:

1. sympla_list_events
   - Purpose: List organizer events from Sympla.
   - Risk: Read-only.

2. sympla_lookup_participant_by_ticket
   - Purpose: Look up a Sympla participant using an event ID and ticket number.
   - Risk: Read-only.

3. sympla_checkin_participant
   - Purpose: Perform a participant check-in in Sympla using an event ID and ticket number.
   - Risk: Write action. Explicit human confirmation required.
EOF

echo "=== Creating n8n ops workflow skill ==="
cat > /root/.openclaw/workspace/skills/n8n-ops-workflows/SKILL.md << EOF
---
name: n8n-ops-workflows
description: Trigger approved Sympla-backed workflows through n8n. Use this for event listing, participant lookup by ticket number, and gated participant check-in.
---

# Approved workflow endpoint

Internal URL: \`http://n8n:5678/webhook/${N8N_WEBHOOK_PATH}\`

## Authentication

All requests MUST include:
- Header: \`X-Webhook-Secret\`
- Value: \`${N8N_WEBHOOK_SECRET}\`

## Approved workflows

- \`sympla_list_events\` for read-only event listing
- \`sympla_lookup_participant_by_ticket\` for read-only participant lookup using \`event_id\` and \`ticket_number\`
- \`sympla_checkin_participant\` for a gated participant check-in action

## Request contract

Send JSON with this shape:

\`\`\`json
{
  "workflow": "sympla_lookup_participant_by_ticket",
  "summary": "why this Sympla workflow is being used",
  "requiresConfirmation": false,
  "data": {
    "event_id": "123456",
    "ticket_number": "QHWA-1Q-3G0J",
    "confirmed": false
  }
}
\`\`\`

## Authentication model

- The operator should never be asked for the Sympla \`S_TOKEN\` in Telegram.
- \`n8n\` reads the Sympla token from its runtime environment.
- This keeps Telegram focused on operator inputs such as \`event_id\`, \`ticket_number\`, and explicit confirmation.

## How to call it

Use the \`exec\` tool with curl:

\`\`\`bash
curl -X POST "http://n8n:5678/webhook/${N8N_WEBHOOK_PATH}" \\
  -H "Content-Type: application/json" \\
  -H "X-Webhook-Secret: ${N8N_WEBHOOK_SECRET}" \\
  -d '{"workflow":"sympla_lookup_participant_by_ticket","summary":"Check a participant by ticket number","requiresConfirmation":false,"data":{"event_id":"123456","ticket_number":"QHWA-1Q-3G0J","confirmed":false}}'
\`\`\`

## Safety rules

- Only use approved workflow names.
- Ask for missing identifiers before running the workflow.
- Use \`requiresConfirmation: true\` for \`sympla_checkin_participant\`.
- Only execute \`sympla_checkin_participant\` when the operator has explicitly confirmed the action.
- Never invent workflow results. Report tool failures clearly.
EOF

echo "=== Creating ops guardrail skill ==="
cat > /root/.openclaw/workspace/skills/ops-guardrails/SKILL.md << EOF
---
name: ops-guardrails
description: Guardrails for an internal operations assistant proof of concept. Use this when handling operational requests or before triggering a workflow.
---

# Operating rules

- Treat the user as an authenticated internal operator only if they are on the Telegram allowlist.
- Prefer read-only workflows first.
- Before any write action, summarize the intended impact and ask for explicit confirmation.
- If a request is ambiguous, ask a clarifying question instead of guessing.
- If a tool is unavailable or unauthorized, say so plainly.

# Response style

Return concise, structured responses with:
- Status
- Findings
- Action taken
- Suggested next step
EOF

echo "=== Creating .env file ==="
cat > /opt/openclaw/.env << EOF
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
SYMPLA_BASE_URL=https://api.sympla.com.br/public/v1.5.1
SYMPLA_S_TOKEN=${SYMPLA_S_TOKEN}
N8N_HOST=${N8N_HOST}
N8N_PORT=${N8N_PORT}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_BASE_URL=${N8N_BASE_URL}
N8N_EDITOR_BASE_URL=${N8N_BASE_URL}
N8N_WEBHOOK_PATH=${N8N_WEBHOOK_PATH}
N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
EOF

echo "=== Creating docker-compose.yml ==="
cat > /opt/openclaw/docker-compose.yml << 'COMPOSEFILE'
networks:
  backend:
    internal: true
  egress:

volumes:
  n8n_data:
  postgres_data:

services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE}
    container_name: openclaw-gateway
    restart: unless-stopped
    command: ["node", "dist/index.js", "gateway"]
    user: "1000:1000"
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - /root/.openclaw:/home/node/.openclaw
    networks:
      - backend
      - egress

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${N8N_BASE_URL}/
      - SYMPLA_BASE_URL=${SYMPLA_BASE_URL}
      - SYMPLA_S_TOKEN=${SYMPLA_S_TOKEN}
      - N8N_WEBHOOK_PATH=${N8N_WEBHOOK_PATH}
      - N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
      - N8N_LISTEN_ADDRESS=0.0.0.0
      - N8N_SECURE_COOKIE=false
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      - postgres
      - redis
    networks:
      - backend
      - egress

  n8n-worker:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n-worker
    restart: unless-stopped
    command: worker
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${N8N_BASE_URL}/
      - SYMPLA_BASE_URL=${SYMPLA_BASE_URL}
      - SYMPLA_S_TOKEN=${SYMPLA_S_TOKEN}
      - N8N_WEBHOOK_PATH=${N8N_WEBHOOK_PATH}
      - N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
      - N8N_LISTEN_ADDRESS=0.0.0.0
      - N8N_SECURE_COOKIE=false
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      - postgres
      - redis
      - n8n
    networks:
      - backend

  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - backend
COMPOSEFILE

echo "=== Setting permissions ==="
chown -R 1000:1000 /root/.openclaw

echo "=== Starting services ==="
cd /opt/openclaw
docker compose up -d

echo ""
echo "========================================"
echo "  SETUP COMPLETE!"
echo "========================================"
echo ""
echo "n8n URL: ${N8N_BASE_URL}"
echo "Complete the n8n owner account setup in your browser after the stack starts."
echo ""
echo "----------------------------------------"
echo "n8n Webhook Configuration:"
echo "----------------------------------------"
echo "  Webhook URL: http://n8n:5678/webhook/${N8N_WEBHOOK_PATH}"
echo "  Header Auth Name: X-Webhook-Secret"
echo "  Header Auth Value: ${N8N_WEBHOOK_SECRET}"
echo ""
echo "----------------------------------------"
echo "OpenClaw Gateway Token: ${GATEWAY_TOKEN}"
echo "----------------------------------------"
echo ""
if [ -n "${SYMPLA_S_TOKEN}" ]; then
  echo "Sympla token configured: yes"
else
  echo "Sympla token configured: no"
fi
echo "Sympla base URL: https://api.sympla.com.br/public/v1.5.1"
echo ""
echo "POC workflows:"
echo "  - sympla_list_events"
echo "  - sympla_lookup_participant_by_ticket"
echo "  - sympla_checkin_participant"
echo ""
echo "To send messages from n8n to OpenClaw/Telegram:"
echo ""
echo "  URL: http://openclaw-gateway:18789/tools/invoke"
echo "  Method: POST"
echo "  Headers:"
echo "    Authorization: Bearer ${GATEWAY_TOKEN}"
echo "    Content-Type: application/json"
echo "  Body:"
echo '    {"tool":"sessions_send","args":{"sessionKey":"agent:main:main","message":"Hello from n8n!","timeoutSeconds":0}}'
echo ""
echo "Next steps:"
echo "  1. Open ${N8N_BASE_URL}"
echo "  2. Create your n8n owner account"
echo "  3. Import the Sympla n8n workflow template from this repository"
echo "  4. Update the webhook path in n8n to ${N8N_WEBHOOK_PATH}"
echo "  5. Message your Telegram bot to test the assistant"
echo ""
