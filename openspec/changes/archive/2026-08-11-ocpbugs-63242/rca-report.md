# Root Cause Analysis Report
**Bug**: OCPBUGS-63242 — MustGather CR stuck when caseManagementAccountSecretRef points to a missing Secret
**Analysis Date**: 2026-08-11
**Root Cause Identified**: Yes

## 0. Inputs Acknowledged
| Input | Status |
|-------|--------|
| repro-verification-report.md | `openspec/changes/ocpbugs-63242/repro-verification-report.md` |
| bug-report.md | `openspec/changes/ocpbugs-63242/bug-report.md` |
| ard-context.md | NOT_PROVIDED (no Epic-linked development PRs on the Jira ticket) |
| pr-diffs/ | NOT_PROVIDED (0 PRs ingested from ticket) |
| agents.md | `openspec/inputs/agents.md` (from [PR #379](https://github.com/openshift/must-gather-operator/pull/379); change copy under `inputs/AGENTS.md`) |
| Baseline code | working folder @ `0ff4e004fabb57afc9aa26e93639f2674e04bace` |

## 1. Failure Path Analysis

### Symptom
MustGather remains stuck with no Job/pod and no user-visible error on the CR when `caseManagementAccountSecretRef` names a Secret that does not exist. Failure appears only in operator logs. Cited from `repro-verification-report.md` (Bug Confirmed: Yes).

### Failure Trace

1. **Observable stuck CR / no Job** — from repo-local repro:
   `job get err=jobs.batch "support-log-gather-jitli" not found`; `mustgather status="" reason="" conditions=0`
   - Source: repro-verification-report.md §1 Step 4; `evidence/repro-go-test.log`

2. **Reconcile returns success with no requeue** — controller finishes without surfacing an error to the client or status subresource:
   `reconcile result={Requeue:false RequeueAfter:0s} err=<nil>`
   - Source: same evidence log
   - Evidence: matches existing suite case `reconcile_job_not_found_user_secret_missing_no_requeue` (`expectError: false`, empty `reconcile.Result{}`)

3. **Secret NotFound branch logs then exits without status update** — when Job is absent, reconciler looks up the case-management Secret; on `IsNotFound` it logs and returns empty success:
   ```go
   // controllers/mustgather/mustgather_controller.go:177-180 (baseline 0ff4e00)
   if errors.IsNotFound(err) {
       log.Error(err, fmt.Sprintf("the secret %s was not found in namespace %s", secretName, instance.Namespace))
       return reconcile.Result{}, nil
   }
   ```
   - Evidence: reporter log `the secret mustgather-creds was not found...` matches this log line; Job creation at lines 187–195 is never reached

4. **Root Cause**: On missing `caseManagementAccountSecretRef` Secret, the reconciler **swallows** the NotFound error (`return reconcile.Result{}, nil`) instead of calling the existing error/status path used elsewhere (`ManageError` / equivalent status update). That prevents Job creation **and** leaves MustGather status empty, so users only see operator logs.
   - Source: `controllers/mustgather/mustgather_controller.go` ~L169–180 (`Reconcile`)
   - Evidence: contrast with other failure paths in the same function that call `r.ManageError(ctx, instance, err)` (e.g. job lookup errors L166, job create errors L191); non-NotFound secret errors requeue with `err` (L182–183) but still do not use `ManageError`

### Evidence Summary
- **Log evidence**: Jira/repro — `ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}` (2025-10-28T06:10:29Z)
- **Code evidence**: `mustgather_controller.go:169-180` NotFound → empty success; Job create gated after successful secret get (L187+); status fields exist on API (`MustGatherStatus.Status/Reason/Conditions` in `api/v1alpha1/mustgather_types.go`)
- **PR evidence**: NOT_PROVIDED from ticket; introduction point unknown. Agentic docs (PR #379 copies under `inputs/harness-docs/`) describe intended validation/error surfacing patterns (see §2)

## 2. ARD Intent vs Actual Behavior

### Original Intent (from PR descriptions)
- Ticket-linked development PR ARD: **unavailable**.
- From agentic docs (PR #379 `harness-docs`, not from a fix commit):
  - Domain doc: Secret existence/credential validation should set Failed status / conditions (`domain/mustgather.md` — runtime validations set status to Failed / `ReconcileError` with validation-style reasons).
  - Architecture doc: user-actionable Secret errors should go through `ManageError` (sets `ReconcileError` condition, Warning event) (`architecture/components.md`).
  - API: `MustGatherStatus` exposes `Status`, `Reason`, `Conditions` for observed state (`mustgather_types.go`).

### Actual Behavior (baseline `0ff4e00`)
Missing Secret → log Error → `return reconcile.Result{}, nil` → no Job → empty MustGather status → user sees silent stuck CR (repro confirmed).

### Divergence Point
`controllers/mustgather/mustgather_controller.go` Secret NotFound handler (~L178–180): treats a **user-correctable configuration error** as a quiet no-op success, diverging from both (a) other reconcile error handling in the same file via `ManageError`, and (b) documented intent that Secret validation failures surface on the CR.

## 3. PR Diff Comparison

### Original PR Changes
NOT_PROVIDED — no Epic-linked PRs on OCPBUGS-63242; cannot attribute introduction to a specific PR number from ticket inputs.

### Current Code State
Analyzed at pinned baseline `0ff4e00` only (per change constraint). Secret lookup NotFound branch returns empty success as shown above.

### Change That Introduced the Bug
**Omission / incorrect error handling in the Secret pre-create gate**: the NotFound path logs but does not update MustGather status or return a managed error. Existing unit test `reconcile_job_not_found_user_secret_missing_no_requeue` encodes and locks in “no error / no requeue” without asserting user-visible status — an **existing test gap** that allowed the silent failure to persist.

## 4. Root Cause Statement

**Root Cause**: The MustGather reconciler’s case-management Secret NotFound branch returns `reconcile.Result{}, nil` without updating MustGather status (and without `ManageError`), so a missing `caseManagementAccountSecretRef` Secret produces a stuck CR with operator-log-only diagnosis.

**Type**: Missing error handling (incorrect assumption that logging alone is sufficient for a terminal user-correctable failure)

**Introduced by**: Unknown (no ticket-linked introducing PR); present at baseline `0ff4e00`

**Why this is root cause and not a symptom**:
- Symptom = stuck CR / no Job / empty status / log-only error.
- Root cause = the NotFound handler that suppresses the failure. Changing only that handling path to surface the error on the CR (and not pretend success) addresses the reporter’s expected result; Job absence and empty status are direct consequences of that return.

## 5. Affected Components
| Component | File/Package | Impact | Agent (from AGENTS.md) |
|-----------|-------------|--------|----------------------|
| MustGather reconciler | `controllers/mustgather/mustgather_controller.go` | Defective Secret NotFound handling; must surface status/error | `OperatorController_Agent` |
| Controller unit tests | `controllers/mustgather/mustgather_controller_test.go` | Case `reconcile_job_not_found_user_secret_missing_no_requeue` encodes silent success; needs regression assertions for status/error surfacing | `Testing_Agent` |
| MustGather status API | `api/v1alpha1/mustgather_types.go` | Status fields already exist; consumed by fix for user-visible error — no API change required unless new condition type is chosen | `API_Agent` |
| Job template | `controllers/mustgather/template.go` | Not defective for this bug; Job never reached | `JobTemplate_Agent` (N/A for code change) |

## 6. Fix Recommendation

### Fix Area
- **Files to modify**:
  - `controllers/mustgather/mustgather_controller.go` (primary)
  - `controllers/mustgather/mustgather_controller_test.go` (regression)
- **Changes needed**:
  - On Secret NotFound (and likely other terminal Secret lookup/validation failures before Job create), do **not** return empty success.
  - Surface a durable user-visible failure on the MustGather (status `Reason`/`Status`/`Conditions` and/or Warning Event) using the controller’s existing error/status helpers (e.g. `ManageError` or the project’s validation-failure status pattern described in harness docs).
  - Ensure Job creation remains skipped when the Secret is missing.
  - Align unit tests: missing Secret must assert no Job **and** non-empty failed/error status (or condition), not merely `expectError: false` with empty checks.
- **Minimal blast radius**: Localized to the pre-Job Secret lookup branch and its tests; no Job template, upload script, or CRD schema change required for the core fix.

### Regression Prevention
- **Unit test needed**: Reconcile MustGather with SFTP `caseManagementAccountSecretRef` pointing at a non-existent Secret → assert: no Job created; MustGather status/condition/reason indicates Secret not found; reconcile does not silently succeed without status update.
- **E2E test needed**: Optional — create MustGather with fake Secret name on a cluster; assert CR shows failure without requiring operator log inspection.
- **Existing test gap**: `reconcile_job_not_found_user_secret_missing_no_requeue` only checks no requeue/no error and has empty `postTestChecks`, so it never required user-visible failure signaling.

## 7. Assessment Confidence
- **Root cause confidence**: High
- **Evidence quality**: Strong — failure path fully traced with repro logs + exact baseline code lines; matches reporter log text. Introducing PR unknown due to missing Epic/PR inputs.
- **Unresolved questions**:
  - Exact status shape preferred by maintainers (`ManageError` / `ReconcileError` vs dedicated validation Failed status) — harness docs favor user-visible Failed/validation-style status; confirm during planning.
  - Whether non-NotFound Secret Get errors should also call `ManageError` (today they requeue with raw `err` and may also under-surface status).
- **Alternative hypotheses** (ruled out):
  - **RBAC preventing Job create**: Ruled out — reconcile never reaches Job create; Secret Get NotFound returns first.
  - **Wrong namespace for Secret**: Behavior is “not found in CR namespace”; even if namespace policy were debated, swallowing NotFound without status would still leave users blind.
  - **Finalizer-only stuck unrelated to Secret**: Ruled out — repro shows empty status specifically when Secret is omitted; Job absent as direct consequence.
  - **Upload container failure**: Ruled out — Job/pod never created.

## Quality Self-Check

- [x] Root cause distinct from symptom
- [x] Failure trace has ≥2 steps between symptom and root cause
- [x] Claims cite repro logs and baseline code paths
- [x] Affected components map to real files + AGENTS.md agents
- [x] Fix recommendation names files and logic without writing code
- [x] ARD/PR gap noted; harness-doc intent used as secondary design reference only
- [x] Alternatives considered and ruled out
- [x] Confidence High with introducing-PR unknown called out
- [x] Root cause explains all repro symptoms (no Job, empty status, log-only error)
