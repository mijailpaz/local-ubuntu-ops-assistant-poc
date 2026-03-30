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
- The webhook uses `X-Webhook-Secret` header authentication.
- The workflow can branch on the `workflow` field.
- At least one read-only path is implemented.
- At least one confirmation-gated write path is implemented.

## Guardrail Checks

- Only approved workflow names are accepted.
- Ambiguous requests are rejected or clarified.
- Read-only requests run without confirmation.
- Write actions require explicit operator confirmation.
- Failures return a clear error message instead of silent failure.

## Suggested Demo Script

1. Show the local n8n instance running on Ubuntu.
2. Show the Telegram bot responding to the operator.
3. Ask for a read-only service status check.
4. Ask for a failure summary.
5. Request a low-risk remediation action.
6. Show the assistant asking for confirmation before the write action.
7. Confirm the action and show the result.
8. Show logs or execution history in n8n as the audit trail.

## Example Prompts

- `Check the status of the payments API.`
- `Look up ticket OPS-4312.`
- `Summarize failed jobs from today.`
- `Restart the staging worker service.`
- `Create an incident escalation for the overnight queue failures.`

## Stakeholder Talking Points

- The assistant runs on a local machine inside the trusted environment.
- Operators interact through a familiar chat tool instead of a new custom UI.
- Internal tools stay behind controlled workflows rather than direct free-form execution.
- The POC enhances operator speed while keeping a human in control for sensitive actions.

## Not In Scope Yet

- Internet-facing production hosting
- Full RBAC and enterprise identity integration
- Advanced secret rotation
- High-risk automations without approvals
- Multi-user team collaboration flows

Keep the first demo small and believable. A narrow, reliable POC is better than a broad but fragile one.
