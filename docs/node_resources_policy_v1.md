# Admiral Node Resources Policy v1

Status: Accepted for alpha release  
Scope: `admirald`, `admiral-fleet`, `admiralctl`, `admiral-flagship`, `admiral-harbor`  
Policy version: `node_resources_policy_v1`  
Primary goal: protect worker nodes from RAM and disk overcommitment while keeping provisioning behavior deterministic, auditable and simple for alpha.

---

## 1. Purpose

This policy defines how Admiral evaluates worker node capacity, health and eligibility for provisioning new customer applications.

For alpha release, Admiral must protect nodes using conservative RAM and disk commitment rules. CPU is tracked and limited at runtime through app tier quotas, but CPU does not block provisioning in this policy version.

The policy must be implemented as deterministic code. Given the same node metrics, committed resources and requested tier, all Admiral components must produce the same provisioning decision.

---

## 2. Core decisions

Admiral uses two separate node-level concepts:

1. **Node health**: whether the node is technically capable of continuing to operate existing apps.
2. **Provisioning availability**: whether the node is allowed to receive new apps.

A node may be healthy but not available for provisioning.

A node that is not healthy must never be available for provisioning.

---

## 3. Alpha resource model

For alpha release, the scheduler protects these resources:

- RAM
- Persistent disk capacity

For alpha release, the scheduler does not reject provisioning because of CPU commitment. CPU quota is still part of the tier definition and must be applied to the app runtime where supported.

### 3.1 Resource types

| Resource | Scheduler behavior | Runtime behavior |
|---|---|---|
| RAM | Hard commitment limit | Must be enforced through runtime/container/systemd limits where possible |
| Disk | Hard commitment limit plus emergency margin | Must be measured by `admiral-fleet`; app-level storage policy applies separately |
| CPU | Not a provisioning blocker in alpha | Must be configured as fractional quota per tier where possible |

---

## 4. Definitions

### 4.1 Physical node RAM

`node_total_ram_bytes` means total physical memory reported by the worker node.

Implementation source may be `/proc/meminfo`, cgroups-aware host metrics or an equivalent system API, but the value must represent host-level RAM available to the worker node.

### 4.2 Physical node disk

`node_total_disk_bytes` means total capacity of the filesystem or storage pool used for customer app persistent volumes.

It must not include unrelated filesystems that cannot store app data.

If Admiral stores app data under a specific path, for example `/var/lib/admiral/apps`, disk metrics must be based on the filesystem backing that path.

### 4.3 Used RAM

`node_used_ram_bytes` means RAM currently used on the node at metrics collection time.

This value is used for health evaluation only. It is not used as the primary admission-control value for new apps.

### 4.4 Used disk

`node_used_disk_bytes` means disk currently used on the app data filesystem or storage pool at metrics collection time.

This value is used for health evaluation only. It is not used as the primary admission-control value for new apps.

### 4.5 Committed RAM

`node_committed_ram_bytes` means the sum of RAM quotas assigned to all non-deleted apps on the node.

Apps counted in committed RAM:

- running apps
- paused apps
- suspended apps
- provisioning apps
- failed-provisioning apps that still reserve resources

Apps not counted in committed RAM:

- deleted apps
- fully deprovisioned apps
- apps whose resource reservation was explicitly released by `admirald`

### 4.6 Committed disk

`node_committed_disk_bytes` means the sum of commercial persistent disk quotas assigned to all non-deleted apps on the node.

This is based on tier quota, not current disk usage.

Apps counted in committed disk:

- running apps
- paused apps
- suspended apps
- provisioning apps
- failed-provisioning apps that still have persistent volumes or reservations

Apps not counted in committed disk:

- deleted apps
- fully deprovisioned apps
- apps whose persistent volume and resource reservation were explicitly released by `admirald`

### 4.7 Requested tier RAM

`requested_tier_ram_bytes` means RAM quota defined by the tier selected for the app being provisioned.

### 4.8 Requested tier disk

`requested_tier_disk_bytes` means persistent storage quota defined by the tier selected for the app being provisioned.

### 4.9 Metrics freshness

`last_metrics_at` means the timestamp of the most recent accepted metrics report from `admiral-fleet` for the node.

Metrics are considered stale when:

```text
now - last_metrics_at > metrics_stale_after_seconds
```

Alpha default:

```text
metrics_stale_after_seconds = 180
```

---

## 5. Constants

The following constants define policy v1.

```text
RAM_COMMIT_RATIO = 0.80
DISK_SAFE_NODE_RATIO = 0.80
DISK_APP_EMERGENCY_MULTIPLIER = 1.20
NODE_RAM_HEALTH_CRITICAL_RATIO = 0.90
NODE_DISK_HEALTH_CRITICAL_RATIO = 0.90
METRICS_STALE_AFTER_SECONDS = 180
```

Derived disk commit ratio:

```text
DISK_COMMIT_RATIO = DISK_SAFE_NODE_RATIO / DISK_APP_EMERGENCY_MULTIPLIER
DISK_COMMIT_RATIO = 0.80 / 1.20
DISK_COMMIT_RATIO = 0.6666666667
```

Meaning: only approximately 66.66% of the app-data disk may be commercially committed to customer app quotas. The remaining capacity protects the node from app grace periods, emergency quota expansion, logs, runtime overhead and operational safety margin.

---

## 6. Node health policy

### 6.1 Health states

A node has exactly one health state:

```text
healthy
unhealthy
```

### 6.2 Healthy node

A node is healthy when all conditions below are true:

```text
fleet_status == online
metrics_are_fresh == true
node_ram_usage_ratio < NODE_RAM_HEALTH_CRITICAL_RATIO
node_disk_usage_ratio < NODE_DISK_HEALTH_CRITICAL_RATIO
manual_disabled == false
```

Where:

```text
node_ram_usage_ratio = node_used_ram_bytes / node_total_ram_bytes
node_disk_usage_ratio = node_used_disk_bytes / node_total_disk_bytes
```

### 6.3 Unhealthy node

A node is unhealthy when any condition below is true:

```text
fleet_status != online
metrics_are_fresh == false
node_ram_usage_ratio >= NODE_RAM_HEALTH_CRITICAL_RATIO
node_disk_usage_ratio >= NODE_DISK_HEALTH_CRITICAL_RATIO
manual_disabled == true
```

### 6.4 Health reason codes

When a node is unhealthy, `admirald` must store at least one reason code.

Allowed reason codes for alpha:

```text
fleet_offline
metrics_stale
ram_usage_critical
disk_usage_critical
manual_disabled
invalid_metrics
```

Reason code rules:

- `fleet_offline`: `admiral-fleet` is not connected or has not reported successfully.
- `metrics_stale`: last accepted metrics are older than `METRICS_STALE_AFTER_SECONDS`.
- `ram_usage_critical`: RAM usage is greater than or equal to 90%.
- `disk_usage_critical`: disk usage is greater than or equal to 90%.
- `manual_disabled`: an administrator manually disabled the node.
- `invalid_metrics`: reported metrics are missing, zero, negative, inconsistent or cannot be trusted.

---

## 7. Provisioning availability policy

### 7.1 Availability field

A node has a boolean provisioning availability field:

```text
available_for_provisioning = true | false
```

This field expresses whether the node can receive new apps.

### 7.2 Availability must be evaluated per requested tier

Provisioning availability depends on the requested tier.

A node may be available for a small tier and unavailable for a larger tier.

Therefore, the scheduler must evaluate availability with these inputs:

```text
node_id
requested_tier_ram_bytes
requested_tier_disk_bytes
```

A persisted `available_for_provisioning` field may exist for general display, but final provisioning decisions must recalculate availability against the requested tier.

### 7.3 RAM commit limit

RAM commit limit:

```text
node_ram_commit_limit_bytes = floor(node_total_ram_bytes * RAM_COMMIT_RATIO)
```

With alpha constants:

```text
node_ram_commit_limit_bytes = floor(node_total_ram_bytes * 0.80)
```

A node has enough RAM commitment capacity for a requested tier when:

```text
node_committed_ram_bytes + requested_tier_ram_bytes <= node_ram_commit_limit_bytes
```

### 7.4 Disk commit limit

Disk commit limit:

```text
node_disk_commit_limit_bytes = floor((node_total_disk_bytes * DISK_SAFE_NODE_RATIO) / DISK_APP_EMERGENCY_MULTIPLIER)
```

With alpha constants:

```text
node_disk_commit_limit_bytes = floor((node_total_disk_bytes * 0.80) / 1.20)
```

Equivalent:

```text
node_disk_commit_limit_bytes = floor(node_total_disk_bytes * 0.6666666667)
```

A node has enough disk commitment capacity for a requested tier when:

```text
node_committed_disk_bytes + requested_tier_disk_bytes <= node_disk_commit_limit_bytes
```

### 7.5 Availability decision

A node is available for provisioning the requested tier when all conditions below are true:

```text
node_health_status == healthy
node_committed_ram_bytes + requested_tier_ram_bytes <= node_ram_commit_limit_bytes
node_committed_disk_bytes + requested_tier_disk_bytes <= node_disk_commit_limit_bytes
```

If any condition fails:

```text
available_for_provisioning = false
```

### 7.6 Provisioning unavailability reason codes

When a node is not available for provisioning, `admirald` must record at least one reason code.

Allowed reason codes for alpha:

```text
node_unhealthy
insufficient_ram_commit_capacity
insufficient_disk_commit_capacity
metrics_stale
manual_disabled
invalid_requested_tier
```

Reason code rules:

- `node_unhealthy`: node health status is `unhealthy`.
- `insufficient_ram_commit_capacity`: requested tier would exceed RAM commit limit.
- `insufficient_disk_commit_capacity`: requested tier would exceed disk commit limit.
- `metrics_stale`: node metrics are stale.
- `manual_disabled`: node was disabled by administrator.
- `invalid_requested_tier`: requested tier has missing, zero, negative or invalid RAM/disk values.

---

## 8. Valid state matrix

| Health status | Available for provisioning | Valid? | Meaning |
|---|---:|---:|---|
| `healthy` | `true` | Yes | Node can run existing apps and accept new apps for the evaluated tier. |
| `healthy` | `false` | Yes | Node can run existing apps but cannot accept new apps for the evaluated tier. |
| `unhealthy` | `false` | Yes | Node must not accept new apps. Existing apps may be degraded or at risk. |
| `unhealthy` | `true` | No | Invalid state. Must be rejected or corrected to unavailable. |

Implementation rule:

```text
if node_health_status != healthy:
    available_for_provisioning = false
```

---

## 9. Scheduler policy

### 9.1 Node eligibility

When provisioning a new app, `admirald` must only consider nodes that satisfy all of the following:

```text
node_health_status == healthy
node_manual_disabled == false
metrics_are_fresh == true
node_committed_ram_bytes + requested_tier_ram_bytes <= node_ram_commit_limit_bytes
node_committed_disk_bytes + requested_tier_disk_bytes <= node_disk_commit_limit_bytes
```

### 9.2 Scheduler rejection

If no node satisfies the policy, provisioning must fail cleanly.

Required user-facing message:

```text
No hay nodos disponibles con capacidad suficiente para este tier.
```

Required internal error code:

```text
no_node_available_for_requested_tier
```

The failure must not create a partially provisioned app unless a resource reservation exists and is explicitly marked as failed and releasable.

### 9.3 Tie-breaking for alpha

When more than one node is eligible, alpha scheduler should prefer the node with the most remaining RAM commitment capacity after allocation.

Ordering rule:

```text
remaining_ram_after = node_ram_commit_limit_bytes - (node_committed_ram_bytes + requested_tier_ram_bytes)
remaining_disk_after = node_disk_commit_limit_bytes - (node_committed_disk_bytes + requested_tier_disk_bytes)
```

Sort eligible nodes by:

1. highest `remaining_ram_after`
2. highest `remaining_disk_after`
3. oldest `created_at` or lowest stable `node_id` for deterministic behavior

This keeps the alpha scheduler simple and deterministic.

---

## 10. Resource reservation policy

### 10.1 Reservation point

`admirald` must reserve RAM and disk commitment before ordering `admiral-fleet` to create app resources.

Reservation must be transactional.

A successful reservation increments or records:

```text
node_committed_ram_bytes += requested_tier_ram_bytes
node_committed_disk_bytes += requested_tier_disk_bytes
```

or creates an equivalent app resource allocation row that is included in commitment calculations.

### 10.2 Reservation states

Alpha allocation states:

```text
reserved
active
failed_releasable
released
```

Meaning:

- `reserved`: capacity reserved but app provisioning not completed yet.
- `active`: app exists and capacity remains committed.
- `failed_releasable`: provisioning failed and the reservation may be released.
- `released`: reservation no longer counts toward committed capacity.

### 10.3 Failed provisioning

If provisioning fails after reservation, `admirald` must mark the allocation as `failed_releasable` or release it immediately.

The system must not leak committed capacity indefinitely because of failed provisioning attempts.

### 10.4 Paused and suspended apps

Paused or suspended apps continue to count toward RAM and disk commitment unless the app is fully deprovisioned.

Reason: customer data and app entitlement remain allocated.

---

## 11. App-level storage policy interaction

This node resource policy is separate from the app storage policy.

The app storage policy may allow a grace period above the app commercial quota, protected by an emergency multiplier.

Node disk commitment is intentionally lower than physical disk capacity to reserve space for:

- app storage grace periods
- emergency quota margin
- filesystem overhead
- logs
- backups staging when applicable
- Podman/runtime metadata
- operational safety margin

Disk commitment formula:

```text
commercially_sellable_disk = (node_total_disk_bytes * 0.80) / 1.20
```

This means Admiral must not sell the full disk capacity as app quotas.

---

## 12. Metrics reporting requirements

### 12.1 `admiral-fleet` must report

`admiral-fleet` must periodically report node metrics to `admirald`.

Required fields:

```text
node_id
fleet_status
reported_at
node_total_ram_bytes
node_used_ram_bytes
node_total_disk_bytes
node_used_disk_bytes
```

Recommended fields for observability:

```text
node_available_ram_bytes
node_disk_available_bytes
cpu_count
load_average_1m
load_average_5m
load_average_15m
pod_count
app_count
```

### 12.2 Metrics validation

`admirald` must reject or mark as invalid metrics when:

```text
node_total_ram_bytes <= 0
node_total_disk_bytes <= 0
node_used_ram_bytes < 0
node_used_disk_bytes < 0
node_used_ram_bytes > node_total_ram_bytes
node_used_disk_bytes > node_total_disk_bytes
reported_at is missing
reported_at is too far in the future
```

Alpha tolerance for future timestamps:

```text
reported_at <= now + 60 seconds
```

Invalid metrics must cause the node to be considered unhealthy and unavailable for provisioning.

---

## 13. Data model requirements

### 13.1 Node fields

The node record should support these fields or equivalent computed values:

```text
id
name
status
manual_disabled
fleet_status
last_metrics_at
health_status
health_reason_codes
available_for_provisioning
unavailable_reason_codes
node_total_ram_bytes
node_used_ram_bytes
node_total_disk_bytes
node_used_disk_bytes
node_ram_commit_limit_bytes
node_disk_commit_limit_bytes
node_committed_ram_bytes
node_committed_disk_bytes
created_at
updated_at
```

### 13.2 App allocation fields

Each app should have an allocation record or equivalent fields:

```text
app_id
node_id
tier_id
allocated_ram_bytes
allocated_disk_bytes
allocated_cpu_quota
allocation_status
reserved_at
activated_at
released_at
```

### 13.3 Tier fields

Each tier must define:

```text
tier_id
name
ram_bytes
disk_bytes
cpu_quota
```

Validation rules:

```text
ram_bytes > 0
disk_bytes > 0
cpu_quota >= 0
```

For alpha, `cpu_quota` may be zero or nullable only if CPU quota enforcement is not implemented yet. Once tiers are commercial, CPU quota should be explicit.

---

## 14. Calculation pseudocode

### 14.1 Metrics freshness

```text
metrics_are_fresh = last_metrics_at is not null
                    and now - last_metrics_at <= METRICS_STALE_AFTER_SECONDS
```

### 14.2 Health evaluation

```text
function evaluate_node_health(node):
    reasons = []

    if node.manual_disabled == true:
        reasons.append("manual_disabled")

    if node.fleet_status != "online":
        reasons.append("fleet_offline")

    if node.last_metrics_at is null or now - node.last_metrics_at > METRICS_STALE_AFTER_SECONDS:
        reasons.append("metrics_stale")

    if metrics_invalid(node):
        reasons.append("invalid_metrics")

    if metrics_valid(node):
        ram_usage_ratio = node.node_used_ram_bytes / node.node_total_ram_bytes
        disk_usage_ratio = node.node_used_disk_bytes / node.node_total_disk_bytes

        if ram_usage_ratio >= NODE_RAM_HEALTH_CRITICAL_RATIO:
            reasons.append("ram_usage_critical")

        if disk_usage_ratio >= NODE_DISK_HEALTH_CRITICAL_RATIO:
            reasons.append("disk_usage_critical")

    if len(reasons) == 0:
        return "healthy", []

    return "unhealthy", reasons
```

### 14.3 Commit limit calculation

```text
function calculate_commit_limits(node):
    ram_commit_limit = floor(node.node_total_ram_bytes * 0.80)
    disk_commit_limit = floor((node.node_total_disk_bytes * 0.80) / 1.20)

    return ram_commit_limit, disk_commit_limit
```

### 14.4 Provisioning availability evaluation

```text
function evaluate_node_for_tier(node, tier):
    reasons = []

    if tier.ram_bytes <= 0 or tier.disk_bytes <= 0:
        return false, ["invalid_requested_tier"]

    health_status, health_reasons = evaluate_node_health(node)

    if health_status != "healthy":
        reasons.append("node_unhealthy")

        if "metrics_stale" in health_reasons:
            reasons.append("metrics_stale")

        if "manual_disabled" in health_reasons:
            reasons.append("manual_disabled")

    ram_commit_limit, disk_commit_limit = calculate_commit_limits(node)

    if node.node_committed_ram_bytes + tier.ram_bytes > ram_commit_limit:
        reasons.append("insufficient_ram_commit_capacity")

    if node.node_committed_disk_bytes + tier.disk_bytes > disk_commit_limit:
        reasons.append("insufficient_disk_commit_capacity")

    if len(reasons) == 0:
        return true, []

    return false, reasons
```

### 14.5 Scheduler selection

```text
function select_node_for_app(nodes, tier):
    eligible_nodes = []

    for node in nodes:
        available, reasons = evaluate_node_for_tier(node, tier)

        if available:
            ram_commit_limit, disk_commit_limit = calculate_commit_limits(node)

            remaining_ram_after = ram_commit_limit - (node.node_committed_ram_bytes + tier.ram_bytes)
            remaining_disk_after = disk_commit_limit - (node.node_committed_disk_bytes + tier.disk_bytes)

            eligible_nodes.append({
                "node": node,
                "remaining_ram_after": remaining_ram_after,
                "remaining_disk_after": remaining_disk_after,
            })

    if len(eligible_nodes) == 0:
        return error("no_node_available_for_requested_tier")

    sort eligible_nodes by:
        remaining_ram_after descending,
        remaining_disk_after descending,
        node.created_at ascending,
        node.id ascending

    return eligible_nodes[0].node
```

---

## 15. Examples

### 15.1 8 GB RAM node

```text
node_total_ram_bytes = 8 GB
RAM_COMMIT_RATIO = 0.80
node_ram_commit_limit = 6.4 GB
```

If existing committed RAM is 5.5 GB:

```text
requested tier RAM = 1 GB
5.5 GB + 1 GB = 6.5 GB
6.5 GB > 6.4 GB
```

Decision:

```text
available_for_provisioning = false
reason = insufficient_ram_commit_capacity
```

### 15.2 100 GB app-data disk node

```text
node_total_disk_bytes = 100 GB
DISK_SAFE_NODE_RATIO = 0.80
DISK_APP_EMERGENCY_MULTIPLIER = 1.20
node_disk_commit_limit = (100 GB * 0.80) / 1.20
node_disk_commit_limit = 66.66 GB
```

If existing committed disk is 60 GB:

```text
requested tier disk = 5 GB
60 GB + 5 GB = 65 GB
65 GB <= 66.66 GB
```

Decision:

```text
sufficient_disk_commit_capacity = true
```

If requested tier disk is 10 GB:

```text
60 GB + 10 GB = 70 GB
70 GB > 66.66 GB
```

Decision:

```text
available_for_provisioning = false
reason = insufficient_disk_commit_capacity
```

### 15.3 Healthy but not available

Node metrics:

```text
fleet_status = online
node_ram_usage = 55%
node_disk_usage = 50%
metrics_are_fresh = true
```

Node commitment:

```text
RAM commit limit = 6.4 GB
RAM already committed = 6.0 GB
requested tier RAM = 1.0 GB
```

Decision:

```text
health_status = healthy
available_for_provisioning = false
reason = insufficient_ram_commit_capacity
```

This is a valid state.

### 15.4 Unhealthy is never available

Node metrics:

```text
fleet_status = online
node_ram_usage = 92%
node_disk_usage = 50%
metrics_are_fresh = true
```

Decision:

```text
health_status = unhealthy
health_reason = ram_usage_critical
available_for_provisioning = false
unavailable_reason = node_unhealthy
```

Even if committed resources appear available, the node must not receive new apps.

---

## 16. Operational behavior by component

### 16.1 `admiral-fleet`

Responsibilities:

- Collect node RAM and disk metrics.
- Report metrics periodically to `admirald`.
- Report app-level disk usage separately under the app storage policy.
- Execute provisioning, pause, resume and deprovisioning commands from `admirald`.
- Not make commercial billing decisions.
- Not decide grace periods.
- Not decide whether a node is commercially sellable.

### 16.2 `admirald`

Responsibilities:

- Store node metrics.
- Validate metrics.
- Calculate node health.
- Calculate node commit limits.
- Calculate node provisioning eligibility.
- Reserve capacity transactionally before provisioning.
- Select eligible node for new apps.
- Reject provisioning cleanly when no eligible node exists.
- Expose node health and availability to `admiralctl`, `admiral-flagship` and `admiral-harbor`.

### 16.3 `admiralctl`

Responsibilities:

- Show node health.
- Show node availability.
- Show committed RAM and disk.
- Show commit limits.
- Show reason codes when node is unavailable.
- Allow administrators to manually disable or enable a node if supported in alpha.

### 16.4 `admiral-flagship`

Responsibilities:

- Show node list with clear health and provisioning availability.
- Show capacity bars for committed RAM and committed disk.
- Show actual usage separately from committed capacity.
- Show reason codes and operational warnings.
- Avoid hiding the distinction between healthy and available for provisioning.

### 16.5 `admiral-harbor`

Responsibilities:

- Not expose low-level node internals to customers.
- Show a clean provisioning failure message if no node can host the selected tier.
- Not decide scheduler placement.
- Not calculate node availability directly.

---

## 17. API behavior requirements

### 17.1 Node metrics ingestion

`admirald` should expose or implement an internal endpoint/action equivalent to:

```text
POST /internal/fleet/nodes/{node_id}/metrics
```

Payload must include required metrics defined in this policy.

On success:

```text
metrics accepted
node health recalculated
node availability cache updated if applicable
```

On invalid metrics:

```text
metrics rejected or stored as invalid
node marked unhealthy
node marked unavailable for provisioning
reason includes invalid_metrics
```

### 17.2 Node list response

Node list APIs should expose at least:

```text
node_id
name
fleet_status
health_status
health_reason_codes
available_for_provisioning
unavailable_reason_codes
node_total_ram_bytes
node_used_ram_bytes
node_ram_commit_limit_bytes
node_committed_ram_bytes
node_total_disk_bytes
node_used_disk_bytes
node_disk_commit_limit_bytes
node_committed_disk_bytes
last_metrics_at
```

### 17.3 Provision app response

If provisioning succeeds:

```text
app created
node selected
resources reserved
fleet provisioning command issued
```

If provisioning fails because no node is eligible:

```text
error_code = no_node_available_for_requested_tier
message = No hay nodos disponibles con capacidad suficiente para este tier.
```

---

## 18. Audit and event requirements

`admirald` should emit auditable events for node status changes and provisioning decisions.

Required event types:

```text
node_metrics_received
node_metrics_rejected
node_health_changed
node_provisioning_availability_changed
node_capacity_reserved
node_capacity_released
node_provisioning_rejected_no_capacity
node_manually_disabled
node_manually_enabled
```

Each event should include:

```text
event_type
node_id
timestamp
previous_value
new_value
reason_codes
related_app_id
related_tier_id
actor_type
actor_id
```

For automated decisions:

```text
actor_type = system
actor_id = admirald
```

---

## 19. Alpha non-goals

The following are explicitly outside policy v1:

- CPU-based scheduler rejection.
- Complex bin-packing optimization.
- Predictive autoscaling.
- Cross-node live migration.
- Automatic tenant evacuation.
- Storage class selection.
- Multi-disk placement optimization.
- Kubernetes-style requests/limits abstraction.
- Billing calculation.

These may be added in later policy versions.

---

## 20. Acceptance criteria

This policy is correctly implemented when all statements below are true.

### 20.1 Health

- A node with fresh metrics, online fleet, RAM usage below 90%, disk usage below 90% and not manually disabled is `healthy`.
- A node with stale metrics is `unhealthy`.
- A node with RAM usage greater than or equal to 90% is `unhealthy`.
- A node with disk usage greater than or equal to 90% is `unhealthy`.
- A manually disabled node is `unhealthy`.
- An unhealthy node is never available for provisioning.

### 20.2 RAM commitment

- `node_ram_commit_limit_bytes` equals `floor(node_total_ram_bytes * 0.80)`.
- A requested tier is rejected for a node when committed RAM plus requested RAM exceeds the RAM commit limit.
- Current RAM usage does not increase sellable capacity.
- Paused and suspended apps continue to count toward committed RAM.

### 20.3 Disk commitment

- `node_disk_commit_limit_bytes` equals `floor((node_total_disk_bytes * 0.80) / 1.20)`.
- A requested tier is rejected for a node when committed disk plus requested disk exceeds the disk commit limit.
- Current disk usage does not increase sellable capacity.
- Paused and suspended apps continue to count toward committed disk.

### 20.4 Provisioning

- `admirald` only selects nodes that are healthy and have sufficient RAM and disk commitment capacity.
- If no eligible node exists, provisioning fails with `no_node_available_for_requested_tier`.
- Capacity is reserved transactionally before fleet provisioning begins.
- Failed provisioning does not leak capacity reservations indefinitely.

### 20.5 Observability

- Operators can see actual RAM/disk usage separately from committed RAM/disk.
- Operators can see why a node is unhealthy.
- Operators can see why a node is not available for provisioning.
- State changes emit auditable events.

---

## 21. Final rule summary

For alpha release, a node can receive a new app only if all of the following are true:

```text
fleet_status == online
metrics_are_fresh == true
manual_disabled == false
node_used_ram_bytes / node_total_ram_bytes < 0.90
node_used_disk_bytes / node_total_disk_bytes < 0.90
node_committed_ram_bytes + requested_tier_ram_bytes <= floor(node_total_ram_bytes * 0.80)
node_committed_disk_bytes + requested_tier_disk_bytes <= floor((node_total_disk_bytes * 0.80) / 1.20)
```

If any condition fails, the node must not be used for provisioning the requested app.

