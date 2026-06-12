# Overdue Policy v1

## Purpose

This document defines the billing overdue policy for Admiral customer apps and subscriptions.

The policy applies to `admiral-harbor` as the customer-facing billing portal and to `admirald` as the operational control plane that enforces suspension and deprovisioning requests.

## Policy Summary

- If payment is not received on the expected date, the subscription enters overdue handling.
- The customer has **5 calendar days** of grace before the service is suspended.
- The customer then has **10 additional calendar days** before deprovisioning is requested.
- Total time from missed payment to deprovisioning is **15 calendar days**.
- The last successful backup must be retained for **15 additional calendar days** after the deprovisioning point.
- Total retention window for the last successful backup is therefore **30 calendar days** from the missed payment date.

## State Timeline

| Time since missed payment | Billing state | Platform action |
| --- | --- | --- |
| Day 0 | `payment_pending` / `past_due` | Notify the customer and start overdue tracking |
| Day 5 | `suspended` | Suspend the app if payment is still unresolved |
| Day 15 | `deprovision_requested` | Request deprovisioning if payment is still unresolved |
| Day 30 | backup retention window ends | The last retained successful backup may be pruned |

## Backup Retention Rules

1. Keep the most recent successful backup while the app remains active, suspended, or pending deprovision.
2. Do not delete the last successful backup before the full overdue lifecycle completes.
3. After deprovisioning is requested, retain that last successful backup for 15 additional calendar days.
4. Preserve any newer retention rules only if they are stricter than this minimum policy.

## Customer Consent Requirement

The customer must explicitly confirm these terms and conditions when creating an account.

That confirmation must be:

- visible before account creation is completed,
- stored as an auditable acceptance record,
- tied to the account creation timestamp,
- tied to the exact policy version accepted by the customer.

## Auditability Requirements

The platform must record:

- the account identifier,
- the policy version accepted,
- the acceptance timestamp,
- the source IP or request context when available,
- the overdue state transition timestamps,
- the backup retention start and end timestamps.

## Implementation Notes

- `admiral-harbor` is responsible for presenting and collecting the user acceptance.
- `admirald` is responsible for enforcing the operational state transitions.
- Payment-provider logic remains in Harbor and must stay isolated from low-level execution components.
- This policy is intentionally conservative to avoid immediate data loss after payment failure.

