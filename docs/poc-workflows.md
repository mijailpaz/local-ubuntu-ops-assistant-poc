# POC Workflow Catalog

This document defines the first Sympla-backed workflow set for the local Ubuntu operations assistant proof of concept.

Each workflow is intentionally narrow, demo-friendly, and tied to a real Sympla API endpoint.

## Design Rules

- Start with workflows that are easy to verify live.
- Prefer read-only actions first.
- Require explicit confirmation before any state-changing action.
- Keep API credentials out of Telegram prompts.
- Return structured operator summaries instead of raw API JSON.

## Workflow 1: `sympla_list_events`

**Purpose**

List the organizer events available through the Sympla API.

**Sympla endpoint**

`GET /events`

**Typical prompt**

`List my current Sympla events.`

**Suggested inputs**

- none required for the first version

**Suggested output**

- status
- total events found
- top few event names and identifiers
- next suggested step

**Risk**

Read-only

## Workflow 2: `sympla_lookup_participant_by_ticket`

**Purpose**

Look up a participant using an event ID and ticket number.

**Sympla endpoint**

`GET /events/{{event_id}}/participants/ticketNumber/{{ticket_number}}`

**Typical prompt**

`Look up ticket QHWA-1Q-3G0J for event 123456.`

**Suggested inputs**

- `event_id`
- `ticket_number`

**Suggested output**

- participant found or not found
- participant/ticket details
- check-in status if present
- next suggested step

**Risk**

Read-only

## Workflow 3: `sympla_checkin_participant`

**Purpose**

Perform a participant check-in using an event ID and ticket number.

**Sympla endpoint**

`POST /events/{{event_id}}/participants/ticketNumber/{{ticket_number}}/checkin`

**Typical prompt**

`Check in ticket QHWA-1Q-3G0J for event 123456.`

**Suggested inputs**

- `event_id`
- `ticket_number`
- explicit confirmation

**Suggested output**

- confirmation requested or received
- check-in executed or blocked
- Sympla outcome
- next suggested step

**Risk**

Write action. Explicit operator confirmation required before execution.

## Credential Model

The operator should not be asked for the Sympla `S_TOKEN` in Telegram.

Instead:

- store `SYMPLA_S_TOKEN` in the local runtime configuration
- let `n8n` inject the `S_TOKEN` header automatically
- keep the Telegram conversation focused on business inputs such as `event_id`, `ticket_number`, and confirmation

## Suggested n8n Pattern

Use one inbound webhook and route on the `workflow` field:

1. Webhook node receives the OpenClaw payload.
2. Validate the `X-Webhook-Secret`.
3. Switch node branches on `workflow`.
4. Each branch calls the relevant Sympla endpoint with `S_TOKEN` from environment.
5. A formatter node builds a short structured result.
6. An HTTP Request node sends the result back through `sessions_send`.

## Response Format

Keep replies concise and operator-friendly:

- `Status`
- `Findings`
- `Action taken`
- `Next step`

This keeps the POC useful for operators and easy to demo.
