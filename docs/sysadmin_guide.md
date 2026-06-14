# Admiral Harbor Sysadmin Guide

This document describes the operational behavior of Harbor after installation on a single-node Admiral setup.

## Key files

- `/etc/admiral/harbor.env`
- `/etc/admiral/harbor.smtp.env`
- `/etc/admiral/secrets`
- `/etc/admiral/tls/`

## Customer signup

- Public signup is exposed in the UI at `/auth/register`.
- New signups are created in `pending` state.
- Pending accounts cannot log in or deploy applications.
- A customer becomes active by either of these paths:
- email confirmation through the signup link, or
- manual approval by a Harbor administrator.

## SMTP configuration

- Harbor does not send email unless SMTP is configured.
- The Harbor service reads SMTP settings from `/etc/admiral/harbor.smtp.env`.
- After changing that file, restart the service:

```bash
systemctl restart admiral-harbor
```

- Required settings:
  - `HARBOR_SMTP_HOST`
  - `HARBOR_SMTP_PORT`
  - `HARBOR_SMTP_USERNAME`
  - `HARBOR_SMTP_PASSWORD`
  - `HARBOR_SMTP_USE_TLS`
  - `HARBOR_SMTP_USE_SSL`
  - `HARBOR_EMAIL_CONFIRMATION_TTL_HOURS`

- If SMTP is not available or mail delivery fails, the customer remains pending and an admin can approve the account manually.

## Admin review

- Pending customer accounts are reviewed in the admin UI at `/admin/review-user`.
- The review queue exists so Harbor can approve users even when the confirmation email does not arrive.
- Admin actions:
  - approve customer
  - reject customer

## Admin instances

- Harbor admins can create internal admin instances without PayPal billing.
- This flow is separate from customer signup and does not change customer billing rules.

## Catalog editing

- Catalog app logos are uploaded locally.
- Supported formats are PNG and JPG/JPEG.
- Customer-facing catalog views do not show CPU, RAM, or storage.
- Technical sizing may remain visible in admin-only views.

## Operational notes

- Do not create Harbor admins from the UI.
- Bootstrap admin accounts are created by the installation workflow and the `harborctl` operational path.
- If you update SMTP, review queue behavior, or signup state handling, restart Harbor and verify the login and approval flows.
