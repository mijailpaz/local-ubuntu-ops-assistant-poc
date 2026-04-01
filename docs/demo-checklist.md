# Demo Checklist

Use this checklist to validate the local Ubuntu operations assistant proof of concept before showing it to stakeholders.

## Environment Checks

- `setup.sh` completed without errors.
- Docker containers are running.
- n8n opens at `http://YOUR_HOST_OR_IP:5678`.
- The n8n owner account has been created.
- The Telegram bot responds to the allowlisted test user.

## Minimum Workflow Setup

- The inbound n8n webhook exists with the generated path.
- The imported Sympla workflow template is present in n8n.
- The workflow validates `X-Webhook-Secret`.
- The workflow can branch on the `workflow` field.
- The Sympla `S_TOKEN` is configured in the runtime environment.
- Two read-only Sympla paths are implemented.
- One confirmation-gated Sympla action is implemented.

## Guardrail Checks

- Only approved workflow names are accepted.
- Ambiguous requests are rejected or clarified.
- Read-only requests run without confirmation.
- Write actions require explicit operator confirmation.
- Failures return a clear error message instead of silent failure.

## Suggested Demo Script

1. Show the local n8n instance running on Ubuntu.
2. Show the Telegram bot responding to the operator.
3. Ask for the current Sympla event list.
4. Look up a participant by ticket number.
5. Request a participant check-in.
6. Show the assistant asking for confirmation before the write action.
7. Confirm the check-in and show the result.
8. Show logs or execution history in n8n as the audit trail.

## Example Prompts

- `List my current Sympla events.`
- `Look up ticket QHWA-1Q-3G0J for event 123456.`
- `Check in ticket QHWA-1Q-3G0J for event 123456.`
- `Confirm the Sympla check-in.`

## Stakeholder Talking Points

- The assistant runs on a local machine inside the trusted environment.
- Operators interact through a familiar chat tool instead of a new custom UI.
- OpenClaw handles the chat experience while `n8n` handles deterministic workflow execution.
- Internal tools stay behind controlled workflows rather than direct free-form execution.
- The POC enhances operator speed while keeping a human in control for sensitive actions.

## Not In Scope Yet

- Internet-facing production hosting
- Full RBAC and enterprise identity integration
- Advanced secret rotation
- High-risk automations without approvals
- Multi-user team collaboration flows
- Broad Sympla coverage beyond the first three workflows

Keep the first demo small and believable. A narrow, reliable POC is better than a broad but fragile one.
