#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
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

read -r -p "Enter your Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -r -p "Enter your Telegram User ID: " TELEGRAM_USER_ID
read -r -p "Enter your OpenAI API Key: " OPENAI_API_KEY

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -z "${DEFAULT_HOST}" ]; then
  DEFAULT_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

read -r -p "Enter the local hostname or IP for n8n [${DEFAULT_HOST}]: " N8N_HOST
N8N_HOST=${N8N_HOST:-$DEFAULT_HOST}
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_BASE_URL="${N8N_PROTOCOL}://${N8N_HOST}:${N8N_PORT}"

echo ""
echo "n8n will be available at: ${N8N_BASE_URL}"
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
apt install -y docker.io docker-compose-v2 git curl openssl

echo "=== Preparing Docker ==="
systemctl enable docker
systemctl start docker

echo "=== Creating directories ==="
mkdir -p /opt/openclaw
mkdir -p /root/.openclaw/workspace/skills/n8n-ops-workflows
mkdir -p /root/.openclaw/workspace/skills/ops-guardrails
mkdir -p /root/.openclaw/workspace/playbooks

echo "=== Building OpenClaw from source ==="
if [ ! -d /opt/openclaw-src/.git ]; then
  git clone https://github.com/openclaw/openclaw.git /opt/openclaw-src
fi
cd /opt/openclaw-src
docker build -t openclaw:local .
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
# Internal Ops Assistant POC Workflows

Approved workflows for this proof of concept:

1. service_status
   - Purpose: Check whether a known service or dependency is healthy.
   - Risk: Read-only.

2. record_lookup
   - Purpose: Look up a ticket, account, device, or job record.
   - Risk: Read-only.

3. failures_summary
   - Purpose: Summarize today's failures or exception signals.
   - Risk: Read-only.

4. low_risk_remediation
   - Purpose: Run a low-risk recovery action such as a restart or cache clear.
   - Risk: Write action. Explicit human confirmation required.

5. incident_escalation
   - Purpose: Create an escalation payload or incident handoff with context.
   - Risk: Write action. Explicit human confirmation required.
EOF

echo "=== Creating n8n ops workflow skill ==="
cat > /root/.openclaw/workspace/skills/n8n-ops-workflows/SKILL.md << EOF
---
name: n8n-ops-workflows
description: Trigger approved internal operations workflows through n8n. Use this for service checks, record lookups, failures summaries, low-risk remediation, and incident escalation.
---

# Approved workflow endpoint

Internal URL: \`http://n8n:5678/webhook/${N8N_WEBHOOK_PATH}\`

## Authentication

All requests MUST include:
- Header: \`X-Webhook-Secret\`
- Value: \`${N8N_WEBHOOK_SECRET}\`

## Approved workflows

- \`service_status\` for read-only service health checks
- \`record_lookup\` for read-only ticket, account, device, or job lookups
- \`failures_summary\` for read-only summaries of failures or exceptions
- \`low_risk_remediation\` for controlled low-risk write actions
- \`incident_escalation\` for escalation or handoff payload generation

## Request contract

Send JSON with this shape:

\`\`\`json
{
  "workflow": "service_status",
  "summary": "why this workflow is being used",
  "requiresConfirmation": false,
  "data": {
    "target": "service-or-record-id"
  }
}
\`\`\`

## How to call it

Use the \`exec\` tool with curl:

\`\`\`bash
curl -X POST "http://n8n:5678/webhook/${N8N_WEBHOOK_PATH}" \\
  -H "Content-Type: application/json" \\
  -H "X-Webhook-Secret: ${N8N_WEBHOOK_SECRET}" \\
  -d '{"workflow":"service_status","summary":"Check API health for the operator","requiresConfirmation":false,"data":{"target":"payments-api"}}'
\`\`\`

## Safety rules

- Only use approved workflow names.
- Ask for missing identifiers before running the workflow.
- Set \`requiresConfirmation\` to \`true\` for \`low_risk_remediation\` and \`incident_escalation\`.
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
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
N8N_HOST=${N8N_HOST}
N8N_PORT=${N8N_PORT}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_BASE_URL=${N8N_BASE_URL}
N8N_EDITOR_BASE_URL=${N8N_BASE_URL}
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
    image: openclaw:local
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
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${N8N_BASE_URL}/
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
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${N8N_BASE_URL}/
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
echo "POC workflows:"
echo "  - service_status"
echo "  - record_lookup"
echo "  - failures_summary"
echo "  - low_risk_remediation"
echo "  - incident_escalation"
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
echo "  3. Build the webhook workflow using the generated path and secret"
echo "  4. Message your Telegram bot to test the assistant"
echo ""
