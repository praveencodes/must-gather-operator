# Bug Fix Plan
**Bug**: OCPBUGS-63242 — MustGather CR stuck when caseManagementAccountSecretRef points to a missing Secret
**Root Cause**: Secret NotFound branch in MustGather `Reconcile` returns `reconcile.Result{}, nil` without status/`ManageError`, silencing a user-correctable failure (rca-report.md §4).

## 0. Inputs Acknowledged

| Input | Status |
|-------|--------|
| rca-report.md | PROVIDED — `openspec/changes/ocpbugs-63242/rca-report.md` |
| bug-report.md | PROVIDED |
| repro-verification-report.md | PROVIDED |
| constitution.md | PROVIDED — generated once to `openspec/inputs/constitution.md` (was missing) |
| agents.md | PROVIDED — `openspec/inputs/agents.md` |
| AgentRoutingMode | PROVIDED |

## 1. Root Cause Summary

When the Job does not yet exist, reconciler looks up `spec.uploadTarget.sftp.caseManagementAccountSecretRef`. On `errors.IsNotFound`, it logs and returns empty success without updating MustGather status. Job creation is skipped and the CR appears stuck; users must read operator logs (rca High confidence).

### Affected Code Paths

| Path | Role |
|------|------|
| `controllers/mustgather/mustgather_controller.go` (`Reconcile`, Secret lookup ~L169–184) | Defective NotFound handling |
| `controllers/mustgather/mustgather_controller_test.go` (`reconcile_job_not_found_user_secret_missing_no_requeue`) | Encodes silent success; needs regression rewrite |
| `api/v1alpha1/mustgather_types.go` | Status fields already available — no schema change planned |

## 2. Fix Approach

### Strategy
In the pre-Job Secret lookup NotFound path, stop returning empty success. Surface a durable user-visible failure on the MustGather using the existing reconciler error path (`ManageError` or equivalent status update already used in this controller), keep Job creation skipped, and update unit tests to assert no Job **and** failed/error status (or condition) mentioning the missing Secret.

### Minimal Blast Radius Justification
Root cause is a single return path. Status types already exist. Job template, upload script, and CRD schema are not required to fix silent failure. Scope matches rca §6.

### Alternative Approaches Considered
| Approach | Why rejected |
|----------|--------------|
| Requeue forever on missing Secret without status | Still log-only / stuck; does not meet expected user-visible error |
| New CRD field or webhook-only rejection | Larger blast radius; NotFound is runtime cluster state, not schema |
| Copy Secret / invent replication | Out of scope; violates constitution Secret-reference principle for this fix |

## 3. Files to Change

| File | Change Type | Purpose | Confidence |
|------|------------|---------|------------|
| `controllers/mustgather/mustgather_controller.go` | Modify | Replace Secret NotFound empty-success with status-surfacing error path | High |
| `controllers/mustgather/mustgather_controller_test.go` | Modify | Assert no Job + user-visible failure for missing Secret; retire silent-success expectations | High |

## 4. Regression Test Strategy

### Unit Tests
- Scenario: MustGather with SFTP `caseManagementAccountSecretRef` naming a non-existent Secret; Job absent.
- Expect: no Job created; MustGather status/condition/reason indicates Secret not found; reconcile does not leave CR with empty status after handling.
- Update/replace `reconcile_job_not_found_user_secret_missing_no_requeue` accordingly.

### Regression E2E Test (if applicable)
N/A — unit/fake-client coverage is sufficient to catch this root cause (controller branch). Optional e2e deferred unless SME requests it (§8).

### Existing Test Impact
`reconcile_job_not_found_user_secret_missing_no_requeue` currently expects `expectError: false` and empty post-checks — must be updated to the new surfaced-failure contract. Other create-job-with-secret cases should remain green.

### Verification
- `go test ./controllers/mustgather/ -run 'Secret|Reconcile' -count=1`
- `make go-test` (or package-scoped equivalent)
- Re-run missing-Secret repro scenario from repro-verification-report.md; expect user-visible failure on CR and still no Job

## 5. Rollback Plan

Working-folder mode: `git revert <fix-commit>` on `fix/ocpbugs-63242` (or discard uncommitted changes). No CRD/data migration. After revert, prior silent-NotFound behavior returns.

## 6. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Status helper choice differs from maintainer preference | Condition shape / events differ from other operators | §8 SME decision; default to existing `ManageError` pattern |
| Changing test from silent success breaks CI assumptions | Test failures | Update only the missing-Secret case; keep happy-path create tests |
| Non-NotFound Secret errors still under-surface status | Partial user blindness on transient Get errors | Optional follow-up; out of minimal scope unless §8 expands |
| Predicates may not re-reconcile after status-only update | User must recreate CR after fixing Secret | Document; CR generation unchanged; optional Event for visibility |

## 7. Verification Matrix

| Verification | Command | Traces to |
|-------------|---------|-----------|
| Build passes | `make go-build` | constitution.md |
| Unit tests pass | `make go-test` or `go test ./controllers/mustgather/...` | constitution.md / root cause fix |
| Regression test passes | `go test ./controllers/mustgather/ -run 'missing|Secret|Reconcile' -count=1` | rca-report.md |
| Repro steps pass | Fake-client missing-Secret scenario: no Job + status error populated | bug-report.md / repro-verification-report.md |

## 8. Open Questions / SME Decisions

1. **Status surfacing helper**: Prefer `ManageError` (existing in-file pattern) vs a dedicated validation-failure status helper (`Failed` + `Completed=true` style from harness docs)?  
   - **Ask**: SME / maintainers  
   - **Default if unanswered**: Use `ManageError` for minimal consistency with baseline controller call sites.

2. **Scope of Secret Get failures**: Should non-NotFound Secret Get errors also call the same status path (today they `Requeue: true` with raw `err`)?  
   - **Ask**: SME  
   - **Default if unanswered**: Fix NotFound only (root-cause minimal scope).

3. **E2E**: Add an e2e case for missing Secret, or unit-only?  
   - **Ask**: SME  
   - **Default if unanswered**: Unit-only (plan §4).
