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

## 5. Clone The Repository

On the Ubuntu machine:

```bash
git clone <your-repo-url>
cd openclaw-n8n-starter
```

If you already have the repository locally, just enter the repo directory.

## 6. Run The Installer

Run:

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The script will ask for:

- Telegram Bot Token
- Telegram User ID
- OpenAI API Key
- local hostname or IP for the n8n UI

The installer will then:

- install Docker and Docker Compose
- pull the official prebuilt OpenClaw image
- create the OpenClaw configuration
- create the Telegram channel configuration with your allowlisted user ID
- create the n8n, Postgres, and Redis stack
- print the generated secrets and webhook information

## 7. Save The Installer Output

At the end of the install, save these values:

- `n8n URL`
- `Webhook URL`
- `Header Auth Name`
- `Header Auth Value`
- `OpenClaw Gateway Token`

You will need them when creating the n8n workflow.

## 8. Open n8n In The Browser

Open:

```text
http://YOUR_HOST_OR_IP:5678
```

Then:

1. Create the initial n8n owner account
2. Log in to the n8n UI

This setup uses local HTTP for simplicity, so it is intended for trusted local or LAN testing.

## 9. Confirm The Telegram Bot Is Reachable

Open your Telegram bot and send a simple message such as:

```text
hello
```

If the bot does not respond yet, that is okay if you have not finished wiring the n8n workflow. The important thing is that the Telegram bot exists and the OpenClaw gateway is running.

## 10. Create The Inbound n8n Webhook

In n8n:

1. Create a new workflow
2. Add a `Webhook` node
3. Set the path to the generated webhook path from the installer output
4. Configure header authentication:
  - Header name: `X-Webhook-Secret`                                                                                                                                                                                                                                                                                                                                                                                 
  - Header value: use the printed secret

This webhook receives requests from OpenClaw.

The request body will look like this:

```json
{
  "workflow": "service_status",
  "summary": "Check API health for the operator",
  "requiresConfirmation": false,
  "data": {
    "target": "payments-api"
  }
}
```

## 11. Add Workflow Routing In n8n

After the `Webhook` node:

1. Add a `Switch` node
2. Route based on the `workflow` field

Recommended first branches:

- `service_status`
- `record_lookup`
- `failures_summary`

For the first test, implement only `service_status`.

## 12. Build A Minimal `service_status` Flow

For a simple first validation:

1. From the `service_status` branch, add a `Set` node
2. Return a mock structured response such as:

```json
{
  "status": "healthy",
  "findings": "Payments API responded normally.",
  "actionTaken": "Read-only check completed.",
  "nextStep": "No action required."
}
```

This proves the integration works before connecting real internal systems.

## 13. Send The Result Back To OpenClaw

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

## 14. Activate The Workflow

In n8n:

1. Save the workflow
2. Activate it

Once activated, OpenClaw can call it through the internal webhook URL.

## 15. Test End To End From Telegram

In Telegram, send a prompt such as:

```text
Check the status of the payments API.
```

Expected flow:

1. Telegram sends your message to OpenClaw
2. OpenClaw decides to call the `n8n-ops-workflows` skill
3. The skill sends a request to the n8n webhook
4. n8n processes the `service_status` branch
5. n8n calls `sessions_send`
6. The result comes back to you in Telegram

## 16. Add More Workflows

After the first end-to-end success, add:

- `record_lookup`
- `failures_summary`
- `low_risk_remediation`
- `incident_escalation`

Use explicit confirmation for:

- `low_risk_remediation`
- `incident_escalation`

Those are intended to be write actions.

## 17. Useful Commands

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

## 18. Change API Key Or Model Later

If you want to rotate the OpenAI key after installation:

1. Edit `/opt/openclaw/.env`
2. Update the `OPENAI_API_KEY` value
3. Recreate the OpenClaw container

Example:

```bash
sudo nano /opt/openclaw/.env
cd /opt/openclaw
sudo docker compose up -d --force-recreate openclaw-gateway
```

Use `up -d --force-recreate`, not only `restart`, because Docker may keep the old environment value if the container is not recreated.

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

Do not rerun `setup.sh` only to rotate the API key or change the model unless you want a full re-bootstrap, because the installer also regenerates other secrets such as the webhook secret and gateway token.

## 19. Troubleshooting

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

## 20. What To Do Next

Once the first flow works, move in this order:

1. replace mock responses with real internal system calls
2. add clear output formatting
3. require explicit confirmations for write actions
4. validate the demo using [docs/demo-checklist.md](demo-checklist.md)
5. review [docs/production-concerns.md](production-concerns.md) before treating this as anything beyond a POC

## Related Docs

- [README.md](../README.md)
- [docs/poc-workflows.md](poc-workflows.md)
- [docs/demo-checklist.md](demo-checklist.md)
- [docs/production-concerns.md](production-concerns.md)

