# Step-by-Step Setup Guide

This guide walks through a full local Ubuntu setup for:

- OpenClaw
- Telegram
- n8n

It is written for the current repository layout and `setup.sh` flow.

## What You Will End Up With

At the end of this guide, you should have:

- OpenClaw running in Docker
- Telegram connected as the chat interface
- n8n running locally on your Ubuntu machine
- a working webhook path between OpenClaw and n8n
- a first end-to-end test from Telegram to n8n and back

## 1. Prepare The Ubuntu Machine

Use an Ubuntu machine with:

- sudo access
- outbound internet access
- at least 2 GB RAM recommended

The machine must be able to reach:

- Telegram
- OpenAI
- GitHub Container Registry
- any internal systems you want n8n to call

## 2. Create The Telegram Bot

In Telegram:

1. Open [@BotFather](https://t.me/botfather)
2. Run `/newbot`
3. Choose a bot name
4. Choose a bot username
5. Copy the bot token

You will use that token during the installer prompts.

## 3. Get Your Telegram User ID

In Telegram:

1. Open [@userinfobot](https://t.me/userinfobot)
2. Start the bot
3. Copy your numeric Telegram user ID

This repository uses a Telegram allowlist, so only the configured user ID can interact with the assistant.

## 4. Get Your OpenAI API Key

Create or copy an API key from [OpenAI](https://platform.openai.com/api-keys).

You will enter it during setup so the OpenClaw gateway can make model calls.

## 5. Get Your Sympla `S_TOKEN`

This POC uses Sympla-backed workflows through `n8n`, so you also need a valid Sympla API token.

The Sympla collection in this repository shows that the API uses:

- header name: `S_TOKEN`
- auth type: header API key
- base URL: `https://api.sympla.com.br/public/v1.5.1`

Store that token for the installer prompt.

## 6. Clone The Repository

On the Ubuntu machine:

```bash
git clone <your-repo-url>
cd openclaw-n8n-starter
```

If you already have the repository locally, just enter the repo directory.

## 7. Run The Installer

First, create the repo-local setup defaults file:

```bash
cp .env.example .env
```

Optionally fill in any values you already know in `.env`. The installer will only prompt for missing values.

By default, this repository builds a local OpenClaw image with Python 3, `pip`, `seaborn`, `matplotlib`, `pandas`, `numpy`, and `Pillow` already installed.

If you want to skip that local build and use the upstream image instead, set this in `.env` before running the installer:

```env
OPENCLAW_BUILD_LOCAL_IMAGE=false
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
```

Run:

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The script will ask for:

- Telegram Bot Token
- Telegram User ID
- OpenAI API Key
- Sympla `S_TOKEN`
- local hostname or IP for the n8n UI

The installer will then:

- install Docker and Docker Compose
- build the local Python-enabled OpenClaw image, unless you disable it in `.env`
- create the OpenClaw configuration
- create the Telegram channel configuration with your allowlisted user ID
- store the Sympla token in the local runtime environment
- create the n8n, Postgres, and Redis stack
- print the generated secrets and webhook information

## 8. Save The Installer Output

At the end of the install, save these values:

- `n8n URL`
- `Webhook URL`
- `Header Auth Name`
- `Header Auth Value`
- `OpenClaw Gateway Token`
- `Sympla base URL`

You will need them when creating the n8n workflow.

The installer also prints the Python tooling available inside `openclaw-gateway` and the suggested output directory for generated charts or images.

## 9. Open n8n In The Browser

Open:

```text
http://YOUR_HOST_OR_IP:5678
```

Then:

1. Create the initial n8n owner account
2. Log in to the n8n UI

This setup uses local HTTP for simplicity, so it is intended for trusted local or LAN testing.

## 9A. Verify Python Tooling In OpenClaw

If you want to confirm the Python runtime before testing the assistant, run:

```bash
cd /opt/openclaw
sudo docker compose exec openclaw-gateway python --version
sudo docker compose exec openclaw-gateway python -c "import seaborn, matplotlib, pandas; print(seaborn.__version__)"
```

Generated charts or images should be written inside the container under:

```text
/home/node/.openclaw/workspace/output
```

## 10. Import The Sympla Workflow Template

Import the workflow template stored in this repository:

```text
workflows/n8n/sympla-poc-workflow.json
```

In n8n:

1. Choose to import an existing workflow JSON file
2. Import `workflows/n8n/sympla-poc-workflow.json`
3. Save the workflow in n8n

After import, adjust the webhook path in the `Webhook` node so it matches the generated path printed by `setup.sh` or stored in `/opt/openclaw/.env` as `N8N_WEBHOOK_PATH`.

This workflow template expects these environment variables inside n8n:

- `SYMPLA_BASE_URL`
- `SYMPLA_S_TOKEN`
- `OPENCLAW_GATEWAY_TOKEN`
- `N8N_WEBHOOK_SECRET`

The installer writes these into `/opt/openclaw/.env` and injects them into the n8n containers.

## 11. Confirm The Telegram Bot Is Reachable

Open your Telegram bot and send a simple message such as:

```text
hello
```

If the bot does not respond yet, that is okay if you have not finished wiring the n8n workflow. The important thing is that the Telegram bot exists and the OpenClaw gateway is running.

## 12. Review The Inbound n8n Webhook

In the imported workflow:

1. Open the `Webhook` node
2. Set the path to the generated webhook path from the installer output
3. Confirm the workflow validates the `X-Webhook-Secret` header using `N8N_WEBHOOK_SECRET`

This webhook receives requests from OpenClaw.

The request body will look like this:

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

## 13. Review The Workflow Routing In n8n

After the `Webhook` node:

1. Add a `Switch` node
2. Route based on the `workflow` field

The imported workflow should already include these branches:

- `sympla_list_events`
- `sympla_lookup_participant_by_ticket`
- `sympla_checkin_participant`

For the first test, activate the two read-only branches first.

## 14. Validate The Read-Only Branches

The imported workflow should perform:

1. `sympla_list_events` -> `GET /events`
2. `sympla_lookup_participant_by_ticket` -> `GET /events/{event_id}/participants/ticketNumber/{ticket_number}`

Each branch should format the Sympla result into a short operator message with:

- `Status`
- `Findings`
- `Action taken`
- `Next step`

## 15. Confirm The Gated Check-In Path

The imported workflow should not execute check-in on the first request.

Expected behavior:

1. The operator requests `sympla_checkin_participant`
2. The workflow returns a confirmation-needed message
3. Only a second confirmed request should trigger the POST check-in call

The check-in endpoint should use:

```text
POST /events/{{event_id}}/participants/ticketNumber/{{ticket_number}}/checkin
```

## 16. Send The Result Back To OpenClaw

After the formatter node, add an `HTTP Request` node in n8n with:

- URL: `http://openclaw-gateway:18789/tools/invoke`
- Method: `POST`
- Header `Authorization`: `Bearer YOUR_GATEWAY_TOKEN`
- Header `Content-Type`: `application/json`

Example body:

```json
{
  "tool": "sessions_send",
  "args": {
    "sessionKey": "agent:main:main",
    "message": "Status: healthy. Findings: Payments API responded normally. Action taken: read-only check completed. Next step: no action required.",
    "timeoutSeconds": 0
  }
}
```

Use the gateway token printed by the installer.

## 17. Activate The Workflow

In n8n:

1. Save the workflow
2. Activate it

Once activated, OpenClaw can call it through the internal webhook URL.

## 18. Test End To End From Telegram

In Telegram, test in this order:

### Test 1: list events

```text
List my current Sympla events.
```

### Test 2: participant lookup

```text
Look up ticket QHWA-1Q-3G0J for event 123456.
```

### Test 3: gated check-in

```text
Check in ticket QHWA-1Q-3G0J for event 123456.
```

The check-in flow should first ask for confirmation before executing the action.

## 19. Add More Workflows

After the first end-to-end success, you can extend the same pattern to:

- order lookup
- participant lookup by participant ID
- event lookup by event ID
- other controlled Sympla actions

## 20. Useful Commands

View all logs:

```bash
cd /opt/openclaw
docker compose logs -f
```

View OpenClaw only:

```bash
cd /opt/openclaw
docker compose logs openclaw-gateway
```

View n8n only:

```bash
cd /opt/openclaw
docker compose logs n8n n8n-worker
```

Restart everything:

```bash
cd /opt/openclaw
docker compose restart
```

## 21. Change API Key, Sympla Token, Or Model Later

If you want to rotate the OpenAI key or Sympla token after installation:

1. Edit `/opt/openclaw/.env`
2. Update:
   - `OPENAI_API_KEY`
   - `SYMPLA_S_TOKEN`
3. Recreate the affected containers

Example:

```bash
sudo nano /opt/openclaw/.env
cd /opt/openclaw
sudo docker compose up -d --force-recreate openclaw-gateway
sudo docker compose up -d --force-recreate n8n n8n-worker
```

Use `up -d --force-recreate`, not only `restart`, because Docker may keep the old environment value if the containers are not recreated.

If you want to change the model:

1. Edit `/root/.openclaw/openclaw.json`
2. Update both:
   - `agents.defaults.model.primary`
   - the matching key under `agents.defaults.models`
3. Recreate the OpenClaw container

Example shape:

```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "openai/gpt-4.1-mini" },
      "models": { "openai/gpt-4.1-mini": {} }
    }
  }
}
```

Then run:

```bash
cd /opt/openclaw
sudo docker compose up -d --force-recreate openclaw-gateway
```

Do not rerun `setup.sh` only to rotate the API key, rotate the Sympla token, or change the model unless you want a full re-bootstrap, because the installer also regenerates other secrets such as the webhook secret and gateway token.

## 22. Troubleshooting

If Telegram does not respond:

- check the bot token
- check your Telegram user ID
- check OpenClaw logs
- confirm the Ubuntu machine has outbound internet access

If n8n does not load:

- confirm the host/IP is correct
- confirm port `5678` is open on the machine
- inspect `docker compose logs n8n`

If the webhook does not run:

- verify the webhook path
- verify `X-Webhook-Secret`
- verify the workflow is activated
- verify the HTTP Request node uses the correct gateway token
- verify `SYMPLA_S_TOKEN` is present in `/opt/openclaw/.env`
- verify the n8n containers were recreated after changing the Sympla token

## 23. What To Do Next

Once the first flow works, move in this order:

1. replace mock responses with real internal system calls
2. add clear output formatting
3. require explicit confirmations for write actions
4. validate the demo using [docs/demo-checklist.md](demo-checklist.md)
5. review [docs/production-concerns.md](production-concerns.md) before treating this as anything beyond a POC
6. replace demo event IDs and ticket numbers with real Sympla operator inputs

## Related Docs

- [README.md](../README.md)
- [docs/poc-workflows.md](poc-workflows.md)
- [docs/demo-checklist.md](demo-checklist.md)
- [docs/production-concerns.md](production-concerns.md)
- [workflows/n8n/sympla-poc-workflow.json](../workflows/n8n/sympla-poc-workflow.json)

