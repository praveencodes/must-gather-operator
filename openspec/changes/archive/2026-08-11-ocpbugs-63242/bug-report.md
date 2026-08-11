# Bug Context Report: MustGather CR stuck when caseManagementAccountSecretRef points to a missing Secret

**Bug ID**: OCPBUGS-63242

**Severity**: [UNKNOWN]

**Priority**: [UNKNOWN]

**Created**: [UNKNOWN]

**Status**: Draft

**Linked Epic**: [UNKNOWN — no Epic linked on OCPBUGS-63242]

**Input**: Jira Bug ticket: "OCPBUGS-63242" (`inputs/jira-bug.md`, `inputs/jira.yaml`)

## Bug Description

When a MustGather custom resource references a `caseManagementAccountSecretRef` Secret that does not exist in the CR’s namespace, the MustGather remains stuck: no gather Job/pod is created, and no user-visible error is recorded on the MustGather resource. The failure is only visible in the operator pod logs.

## Steps to Reproduce

1. Install/run the must-gather / support-log-gather operator on an OpenShift 4.20 or 4.21 cluster (as reported). Ensure the operator is reconciled in namespace `must-gather-operator` (or equivalent).
2. Confirm the target Secret does **not** exist, for example:
   ```bash
   oc get secret mustgather-creds -n must-gather-operator
   ```
   Expect `NotFound`.
3. Create a MustGather CR that references that missing Secret (example from the ticket):
   ```yaml
   apiVersion: operator.openshift.io/v1alpha1
   kind: MustGather
   metadata:
     name: support-log-gather-jitli
     namespace: must-gather-operator
   spec:
     serviceAccountRef:
       name: must-gather-operator
     uploadTarget:
       type: SFTP
       sftp:
         caseID: "04230315"
         caseManagementAccountSecretRef:
           name: mustgather-creds
   ```
   ```bash
   oc create -f supportloggather-uploadTarget.yaml
   ```
4. Observe CR and workloads:
   ```bash
   oc get mustgather support-log-gather-jitli -n must-gather-operator -o yaml
   oc get jobs,pods -n must-gather-operator
   oc logs -n must-gather-operator deploy/must-gather-operator
   ```
   Confirm: no Job/pod for the MustGather, CR has no user-visible error status/condition for the missing Secret, while operator logs report the Secret was not found.

## Expected Behavior

When the Secret named by `spec.uploadTarget.sftp.caseManagementAccountSecretRef` does not exist, the failure should be surfaced **directly to the user on the MustGather resource** (status/condition and/or reason message), so operators do not need to inspect operator pod logs to discover the problem. [INFERRED from Stage 0 quality issue — ticket says “error message … returned directly”; exact surface (status condition vs Event vs both) is not specified in Jira.]

## Actual Behavior

- Nothing user-visible progresses: no MustGather Job/pod is created.
- The MustGather CR remains present (with finalizer) and does not show an error message/status explaining the missing Secret.
- Operator logs contain the failure, for example:
  ```
  ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}
  ```
  and/or earlier-style:
  ```
  INFO mustgather-controller Error getting secret (case-management-creds)!
  ```

## Environment

- **Platform**: OpenShift 4.20 / 4.21 (reported). Kubernetes version / cloud provider: [UNKNOWN]
- **Operator Version**: support-log-gather-operator / must-gather-operator v4.20.0 CSV observed in repro notes (`support-log-gather-operator.v4.20.0`); broader version matrix: [UNKNOWN]
- **Cluster Topology**: [UNKNOWN]
- **Architecture**: [UNKNOWN]
- **Configuration**: MustGather with `uploadTarget.type: SFTP` and `caseManagementAccountSecretRef` pointing at a non-existent Secret in the CR namespace; Secret intentionally absent
- **Network**: [UNKNOWN] (not implicated by the report)
- **Reproducibility**: Always, when the referenced Secret is absent [INFERRED — ticket “How reproducible” was empty; Stage 0 flagged this]

## Error Evidence

Source: reporter operator logs (Jira OCPBUGS-63242)

```
2025-10-28T06:10:29Z ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}
```

Source: earlier ticket note

```
2025-10-16T07:52:33Z INFO mustgather-controller Error getting secret (case-management-creds)!
```

Source: CR observation (reporter) — MustGather exists with finalizer, `uploadTarget.sftp.caseManagementAccountSecretRef.name: mustgather-creds`, no user-facing error fields populated for the missing Secret; no Job/pod created.

## Feature Context (from Linked Epic)

### Epic: [UNKNOWN] — MustGather SFTP upload credential handling (feature area inferred from bug text)

MustGather automates collection of diagnostic must-gather data and optional upload to Red Hat case management via SFTP. Credentials are supplied by a Secret referenced from `spec.uploadTarget.sftp.caseManagementAccountSecretRef`.

### Original Design Intent (ARD)

- [UNKNOWN] — No linked Epic and no development PR URLs were provided on the Jira Bug ticket; ARD cannot be extracted from PR descriptions without inventing sources.
- Observable API intent from CRD types (not ARD): `CaseManagementAccountSecretRef` is required on `SFTPSpec`, and MustGather status supports `Status`, `Reason`, and `Conditions` fields for observed state.

## Development PR Context

### PRs that implemented the feature

| PR | Title | Author | Merged | Key Changes |
|----|-------|--------|--------|-------------|
| [UNKNOWN] | [UNKNOWN] | [UNKNOWN] | [UNKNOWN] | No Epic-linked development PRs available on the ticket |

### PR Diff Summary

- No Epic-linked PR diffs available to ingest. Downstream RCA should use repository inspection at the agreed baseline commit (`0ff4e004fabb57afc9aa26e93639f2674e04bace`) rather than fabricated PR history.

### Key Code Paths Affected

(Observed at baseline checkout `0ff4e00` — file roles only; not a root-cause claim.)

- `controllers/mustgather/mustgather_controller.go`: reconciles MustGather; looks up the case-management Secret before creating the Job; logs when the Secret is missing.
- `controllers/mustgather/template.go`: builds the Job/pod template that consumes upload credentials from the Secret reference.
- `api/v1alpha1/mustgather_types.go`: defines `UploadTarget` / `SFTPSpec.CaseManagementAccountSecretRef` and `MustGatherStatus` (`Status`, `Reason`, `Conditions`, `Completed`).
- `controllers/mustgather/mustgather_controller_test.go`: controller tests covering Secret presence/absence and Job creation paths.

## Assumptions

- **A-001**: Severity/Priority are unset in Jira (Stage 0 missing_element); treat operational impact as user-blocking for MustGather upload setup (CR stuck with silent failure) without assigning an official severity label.
- **A-002**: No linked Epic exists on OCPBUGS-63242 (Stage 0 missing_element); feature context is limited to MustGather SFTP credential Secret handling described in the bug text and API types.
- **A-003**: Platform/topology/architecture are unset (Stage 0 missing_element); bug is independent of cluster topology and is triggered solely by a missing referenced Secret.
- **A-004**: Failure is always reproducible whenever `caseManagementAccountSecretRef` names a Secret that does not exist in the CR namespace (addresses empty “How reproducible”).
- **A-005**: “Error message returned directly” means a durable, user-visible signal on the MustGather object (status `Reason` and/or `Conditions`, and optionally an Event)—not only operator logs (addresses Stage 0 specificity gap).
- **A-006**: Reporter namespace `must-gather-operator` and Secret name `mustgather-creds` are representative; any namespace/Secret name with the same missing-Secret condition should exhibit the same stuck behavior.
- **A-007**: Original development PR ARD/diffs are unavailable from the ticket; RCA must rely on code at baseline commit `0ff4e00` and must not use later fix commits as guidance.

## Quality Self-Check

- [x] Steps to reproduce are numbered and can be followed by an engineer with no prior context
- [x] Expected and actual behavior are both explicitly stated
- [x] Error evidence includes raw logs, messages, or stack traces (not just descriptions)
- [x] Linked Epic identified as [UNKNOWN]; design intent not fabricated from missing PRs
- [x] PR diff summary explicitly states no Epic-linked PRs were available
- [x] At most 2 [NEEDS INVESTIGATION] markers remain (none used)
- [x] Every [UNKNOWN] field has a corresponding Assumption entry
- [x] No root cause speculation — only observable facts and aggregated context
