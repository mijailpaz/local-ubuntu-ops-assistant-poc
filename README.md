# Local Ubuntu Ops Assistant POC

Telegram-first proof of concept for running an internal operations assistant on a local Ubuntu machine with OpenClaw and n8n.

## What This POC Demonstrates

- **OpenClaw** as the chat-facing assistant for internal operators
- **Telegram** as the simplest officer interface for a one-user or small allowlist pilot
- **n8n** as the workflow and tool orchestration layer
- **PostgreSQL + Redis** for n8n persistence and queue execution
- **Local Ubuntu** hosting so the assistant can sit near internal tools and data sources

## Architecture

```text
Operations officer
    │
    └── Telegram ───────► OpenClaw gateway
                              │
                              ▼
                            n8n
                              │
                              ▼
               Internal APIs, scripts, and data sources
```

## Why This Version Is Local-First

This starter is intentionally optimized for easy proof-of-concept testing on one Ubuntu machine:

- No DigitalOcean dependency
- No public `nip.io` hostname requirement
- No HTTPS reverse proxy required for the first demo
- OpenClaw remains internal to the Docker network
- n8n is exposed over local HTTP for quick setup

This is meant for evaluation on a trusted machine or LAN, not internet-facing production.

## Prerequisites

1. **Ubuntu 24.04 or similar** with sudo/root access and 2GB+ RAM recommended
2. **Telegram Bot Token** from [@BotFather](https://t.me/botfather)
3. **Telegram User ID** from [@userinfobot](https://t.me/userinfobot)
4. **OpenAI API Key** from [OpenAI](https://platform.openai.com/api-keys)
5. **Sympla `S_TOKEN`** for the Sympla-backed workflows
6. **Network access from the Ubuntu machine** to:
   - Telegram
   - OpenAI
   - Sympla API
   - any internal systems you want the POC to call

## Installation

Clone the repo onto your Ubuntu machine and run:

```bash
cp .env.example .env
# edit .env with any values you already know
chmod +x setup.sh
sudo ./setup.sh
```

The repo-local `.env` file is only used as installer input defaults. The generated runtime file still lives at `/opt/openclaw/.env`.

The script will ask only for values that are still missing:

- Telegram Bot Token
- Telegram User ID
- OpenAI API Key
- Sympla `S_TOKEN`
- Local hostname or IP address to use for the n8n UI

The installer will:

- install Docker and Docker Compose
- pull the official prebuilt OpenClaw Docker image
- create a Telegram-only OpenClaw config with an allowlist
- create a local n8n + Postgres + Redis stack
- add a workflow catalog and guardrail skills into the OpenClaw workspace

## After Installation

1. Open n8n at `http://YOUR_HOST_OR_IP:5678`
2. Create the initial n8n owner account in the browser
3. Import the Sympla workflow template from `workflows/n8n/sympla-poc-workflow.json`
4. Update the webhook path in the imported workflow to match the generated `N8N_WEBHOOK_PATH`
5. Message your Telegram bot
6. Test one read-only flow before trying the gated check-in action

## POC Workflow Set

The installer seeds the assistant workspace with a recommended workflow catalog:

- `sympla_list_events`
- `sympla_lookup_participant_by_ticket`
- `sympla_checkin_participant`

These are designed to demonstrate real Sympla-backed operator workflows while keeping the first write action behind an explicit confirmation step.

Detailed workflow guidance lives in [docs/poc-workflows.md](docs/poc-workflows.md).

## Connecting OpenClaw To n8n

The installer creates an OpenClaw skill named `n8n-ops-workflows` that calls an authenticated n8n webhook.

In n8n, create a **Webhook** node with:

- **Authentication**: Header Auth
- **Header Name**: `X-Webhook-Secret`
- **Header Value**: the generated value printed at the end of `setup.sh`
- **Path**: the generated webhook path printed at the end of `setup.sh`

The assistant will send payloads in this shape:

```json
{
  "workflow": "sympla_lookup_participant_by_ticket",
  "summary": "Verify a participant by ticket number",
  "requiresConfirmation": false,
  "data": {
    "event_id": "123456",
    "ticket_number": "QHWA-1Q-3G0J",
    "confirmed": false
  }
}
```

## Sympla Credential Handling

The Sympla workflows use the `S_TOKEN` API header shown in [Sympla API v1.5.1.postman_collection.json](Sympla%20API%20v1.5.1.postman_collection.json).

For this repository:

- store the token in `/opt/openclaw/.env` as `SYMPLA_S_TOKEN`
- let `n8n` read it from the runtime environment
- do not ask the Telegram operator to paste the token into chat

The imported workflow template expects:

- `SYMPLA_BASE_URL`
- `SYMPLA_S_TOKEN`
- `OPENCLAW_GATEWAY_TOKEN`
- `N8N_WEBHOOK_SECRET`

## Sending Messages Back To Telegram

Use an **HTTP Request** node in n8n:

- **URL**: `http://openclaw-gateway:18789/tools/invoke`
- **Method**: `POST`
- **Headers**:
  - `Authorization: Bearer YOUR_GATEWAY_TOKEN`
  - `Content-Type: application/json`

Example body:

```json
{
  "tool": "sessions_send",
  "args": {
    "sessionKey": "agent:main:main",
    "message": "Status: healthy. Findings: all checks passed.",
    "timeoutSeconds": 0
  }
}
```

## Guardrails In This POC

This repo now assumes a narrow internal-ops demo rather than an unrestricted assistant:

- Telegram access is limited to an allowlist
- Read-only workflows come first
- Write actions require explicit confirmation
- The webhook contract uses approved workflow names instead of arbitrary tasks
- n8n is used as the control point for internal actions

Recommended behavior guidance lives in [docs/demo-checklist.md](docs/demo-checklist.md).

## Local Testing Notes

- n8n is served over HTTP on the local machine for simplicity
- The setup disables secure cookies for n8n because this POC is not using HTTPS
- If you need public inbound webhooks later, add a tunnel, reverse proxy, or VPN layer
- For a production deployment, reintroduce HTTPS, stronger network controls, secrets management, and audited approval flows

## Changing API Key Or Model

If you need to update the OpenAI or Sympla key after installation, edit:

- `/opt/openclaw/.env`

Change:

```env
OPENAI_API_KEY=your-new-key
SYMPLA_S_TOKEN=your-new-sympla-token
```

Then recreate the affected containers so Docker picks up the new environment variables:

```bash
cd /opt/openclaw
docker compose up -d --force-recreate openclaw-gateway
docker compose up -d --force-recreate n8n n8n-worker
```

If you only restart the containers, Docker may keep using the old environment values.

If you want to change the model, edit:

- `/root/.openclaw/openclaw.json`

Update both:

- `agents.defaults.model.primary`
- the matching entry under `agents.defaults.models`

Current example from this repository:

```json
{
  "model": { "primary": "openai/gpt-4.1-mini" },
  "models": { "openai/gpt-4.1-mini": {} }
}
```

After changing the model config, restart or recreate the OpenClaw container:

```bash
cd /opt/openclaw
docker compose up -d --force-recreate openclaw-gateway
```

Do not rerun `setup.sh` just to rotate the API key or switch models unless you want a full re-bootstrap, because the installer also regenerates other secrets and tokens.

## Useful Commands

You can use the included `Makefile` from the repository root:

```bash
make help
```

Common targets:

```bash
make setup
make start
make stop
make restart
make recreate-gateway
make logs
make logs-openclaw
make logs-n8n
make ps
make cleanup
```

Destructive or host-level targets:

```bash
make reset
make reboot-host
```

Equivalent raw Docker commands:

```bash
# View all logs
cd /opt/openclaw
docker compose logs -f

# Restart the stack
docker compose restart

# Stop everything
docker compose down

# Start everything again
docker compose up -d

# Inspect OpenClaw logs only
docker compose logs openclaw-gateway

# Inspect n8n logs only
docker compose logs n8n n8n-worker
```

## Troubleshooting

**Telegram bot not responding?**

```bash
cd /opt/openclaw
docker compose logs openclaw-gateway
```

Check:

- the Telegram bot token is correct
- your Telegram user ID matches the allowlist
- the machine has outbound access to Telegram and OpenAI

**n8n not loading?**

```bash
cd /opt/openclaw
docker compose logs n8n
```

Check:

- you are opening the correct local URL
- port `5678` is reachable on the machine
- you completed the initial owner setup flow

**Webhook not working?**

Check:

- the webhook path matches the generated value
- the `X-Webhook-Secret` header is correct
- the workflow name is one of the approved POC names
- n8n can reach `http://openclaw-gateway:18789/tools/invoke`

## Next Docs

- [docs/setup-guide.md](docs/setup-guide.md)
- [docs/poc-workflows.md](docs/poc-workflows.md)
- [docs/demo-checklist.md](docs/demo-checklist.md)
- [docs/production-concerns.md](docs/production-concerns.md)
- [workflows/n8n/sympla-poc-workflow.json](workflows/n8n/sympla-poc-workflow.json)

## Disclaimer

This project is for testing and stakeholder demos. It is not production-ready as-is.

Before real internal deployment, you should add:

- HTTPS
- tighter host and network controls
- proper secrets management
- approval and audit workflows
- least-privilege service integrations

## Credits

- [OpenClaw](https://github.com/openclaw/openclaw)
- [n8n](https://n8n.io)
