# Graft management plane: contract and first vertical slice

Status: proposed contract; local/mock-first. No live reconciler or deployment is authorized by this document.

## Purpose

Provide an administrative control plane for users, hosts/vessels, clankers/workloads, secret metadata, environment profiles, and access grants. Graft remains the workload-side delivery client. OpenBao remains the only durable store of secret values; Smallstep CA remains the certificate authority and identity issuance system.

The management plane records desired configuration and reconciles it to OpenBao. It must never claim a change is active until it has observed and verified the corresponding backend state.

## Invariants

- Secret values and private keys are never stored in the management database, its backups, event payloads, logs, or API responses. Secret writes go directly to OpenBao over a protected channel; the plane stores only the resulting reference and metadata.
- Profiles select alternative values for the same variable names. A profile is not a permission bundle.
- Authorization is an exact grant for a workload identity and a variable/profile pair. Profile-independent variables use an explicit unprofiled grant. Selection requests data; it does not confer authorization.
- Graft injects nothing unless the caller selects mappings explicitly. OpenBao policies, not frontend filtering, enforce access.
- Host/vessel and user/clanker principals are distinct identity classes. System services authenticate as their host/vessel manager; user services as their user/clanker manager. Do not claim per-unit identity isolation where a manager credential is shared.
- Desired state and observed state are distinct. New or changed grants, identities, and revocations remain pending until reconciliation and verification complete. Failed or uncertain verification is never reported as applied.
- Reconciler credentials are distinct from workload credentials, least-privileged for required operations, and never delivered to browser clients.
- Every administrative mutation is attributable, auditable, and versioned. Never log secret values or bearer credentials.

## Initial domain model

Identifiers are stable opaque IDs; names and labels are not authorization inputs.

- Principal: id, class (host_vessel or user_clanker), display name, lifecycle state, certificate identity reference, timestamps.
- Workload: id, owning principal, descriptive metadata, lifecycle state. A workload is a management grouping; do not imply it has a unique backend identity unless it actually does.
- Secret: id, non-secret description, OpenBao KV v2 mount/path reference, lifecycle state. No value field.
- Mapping: id, secret ID, profile (nullable for unprofiled), environment-variable name, OpenBao field, lifecycle state. Enforce unique variable/profile mapping in its scope.
- Grant: principal/workload identity scope, mapping or exact variable+profile pair, allowed operation (initially read only), lifecycle state. Reject wildcard grants in the first slice.
- Reconcile operation: immutable operation ID, desired revision, target backend/object, action, status, timestamps, safe error class, and observed backend version/hash metadata where available. Never include secret bytes or tokens.
- Audit event: actor, action, resource IDs, desired revision, outcome, timestamp, correlation ID. Redact credentials and secret values by construction.

## State and API behavior

Each mutable resource has a monotonically increasing desired revision. Reconciliation is idempotent for (resource, desired_revision) and serializes conflicting writes to the same OpenBao object/policy.

Expose desired state separately from observed status. A mutation returns the new revision and pending status; it does not synchronously pretend backend enforcement succeeded. Reconciliation records applied, failed, or unknown with a sanitized reason. unknown is required for timeouts or interrupted operations where backend outcome cannot be established; retry by reading backend state before applying again.

A removal/revocation is complete only after the backend no longer authorizes the old access and the reconciler has verified that state. Until then report pending or unknown, never revoked.

Use optimistic concurrency (If-Match/revision) for edits. Reject stale writes. Authenticate and authorize every management API action server-side; browser visibility is not authorization. Require explicit confirmation for secret replacement and access-grant changes in the eventual UI.

## Reconciliation contract

1. Read the desired revision and current backend state using a dedicated reconciler identity.
2. Validate references, principal class, mapping/profile syntax, exact grant scope, and policy bounds before mutation.
3. Apply the minimum OpenBao changes required for that revision. Never fetch secret values as part of policy reconciliation.
4. Read back the relevant backend state and verify exact policy/identity behavior, including absence of removed grants.
5. Persist observed status and backend revision/metadata, then append an audit event.
6. On partial failure, preserve the desired revision, report failure/unknown accurately, and retry idempotently. Do not silently roll desired state backward.

The initial mock must model OpenBao state transitions, errors, timeouts, idempotency, and read-back verification. It cannot establish real OpenBao semantics or security; live validation is a later, separately reviewed stage.

## First vertical slice

Implement one narrowly scoped flow using a fake OpenBao adapter and local database:

1. Create one non-secret secret reference and one mapping for an unprofiled canary variable.
2. Grant read access to one mock principal; verify that another principal is denied.
3. Submit a desired revision and observe pending.
4. Run reconciliation; verify exact mock policy and observe applied only after read-back.
5. Revoke the grant; verify access remains pending until mock backend confirms removal.
6. Exercise backend failure, timeout/unknown outcome, retry, duplicate request, stale revision, and audit redaction.

No actual canary value is needed: the slice manages metadata and mock policy only. Keep the adapter boundary explicit so a real OpenBao adapter can be added later without changing domain semantics.

## Delivery sequence

1. Review this contract against the existing Graft selector and authorization decisions.
2. Select the smallest existing product repository and inspect its stack/conventions before creating a service or frontend. Keep the first slice as a library/service test if no existing application shell is a natural fit.
3. Implement domain types, validation, migration/schema, mock adapter, reconciliation state machine, and tests before a UI.
4. Add a minimal admin API/CLI only if needed to demonstrate the slice; UI follows the verified API contract.
5. Review threat model, migration/data retention, backup handling, authentication, auditability, and operational recovery before any live backend adapter.
6. Separately plan live integration, credentials, network exposure, deployment, and homelab rollout. None is part of the mock milestone.

## Explicit non-goals for the first slice

- Storing secret values in the database, syncing them into browser state, or proxying secret reads through the management API.
- Issuing/revoking Step CA certificates or managing CA configuration.
- Live OpenBao writes, live policy changes, remote service changes, or deployment.
- Wildcard/profile-bundle permissions, arbitrary policy text, broad admin-token use, or a generic privileged broker.
- Multi-tenant SaaS, public internet exposure, and a feature-complete frontend.
- Claiming the mock proves real backend enforcement.

## Acceptance criteria

- Domain validation enforces exact profile/variable grants and disallows implicit access.
- Secret values and credentials cannot enter persisted records, audit events, logs, or API results; test with sentinel values.
- Reconciliation is idempotent and revision-aware; stale edits are rejected.
- Applied status requires read-back verification. Timeout/partial failure yields unknown or failed, never false success.
- Grant revocation stays pending until backend denial is observed.
- Mock tests cover allow/deny, failure, retry, duplicate operations, stale revisions, and audit redaction.
- No live service, credential, CA, OpenBao, or deployment is touched in this slice.
