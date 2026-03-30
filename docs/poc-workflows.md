# POC Workflow Catalog

This document defines the recommended first workflow set for the local Ubuntu operations assistant proof of concept.

Each workflow is intentionally narrow, demo-friendly, and easy to explain to stakeholders.

## Design Rules

- Start with workflows that are easy to verify.
- Prefer read-only actions first.
- Require explicit confirmation before any state-changing action.
- Return structured output instead of raw logs.
- Keep each workflow backed by a specific internal script, API, or query.

## Workflow 1: `service_status`

**Purpose**

Check whether a known service, endpoint, queue, or dependency is healthy.

**Typical prompt**

`Check the status of the payments API.`

**Suggested inputs**

- `target`
- `environment`

**Suggested output**

- status: healthy, degraded, or down
- key findings
- last check timestamp
- next suggested step

**Risk**

Read-only

## Workflow 2: `record_lookup`

**Purpose**

Look up a ticket, account, device, job, or batch record in an internal system.

**Typical prompt**

`Look up ticket OPS-4312 and summarize the latest update.`

**Suggested inputs**

- `recordType`
- `recordId`

**Suggested output**

- record found or not found
- summary of current state
- owner or assignee
- last updated timestamp

**Risk**

Read-only

## Workflow 3: `failures_summary`

**Purpose**

Summarize failures, exceptions, or alerts for the current day or a requested window.

**Typical prompt**

`Summarize failed jobs from today.`

**Suggested inputs**

- `source`
- `timeWindow`
- `severity`

**Suggested output**

- total failures
- grouped causes
- most recent failure
- suggested operator follow-up

**Risk**

Read-only

## Workflow 4: `low_risk_remediation`

**Purpose**

Execute a controlled low-risk action such as restarting a service, clearing a cache, or re-running a job.

**Typical prompt**

`Restart the staging worker service.`

**Suggested inputs**

- `target`
- `environment`
- `requestedAction`

**Suggested output**

- confirmation received
- action taken
- outcome
- rollback or next check

**Risk**

Write action. Explicit operator confirmation required before execution.

## Workflow 5: `incident_escalation`

**Purpose**

Create an escalation record or handoff payload with a concise summary of the issue.

**Typical prompt**

`Create an incident escalation for the overnight queue failures.`

**Suggested inputs**

- `incidentTitle`
- `summary`
- `affectedSystem`
- `severity`

**Suggested output**

- escalation prepared or created
- summary used
- destination team or queue
- reference ID

**Risk**

Write action. Explicit operator confirmation required before execution.

## Suggested n8n Pattern

Use one inbound webhook and route on the `workflow` field:

1. Webhook node receives the OpenClaw payload.
2. Switch node branches on `workflow`.
3. Each branch calls one internal tool or API wrapper.
4. A final formatter node builds a short structured result.
5. An HTTP Request node sends the result back through `sessions_send`.

## Response Format

Keep replies concise and operator-friendly:

- `Status`
- `Findings`
- `Action taken`
- `Next step`

This makes the POC feel operational rather than like a generic chatbot.
