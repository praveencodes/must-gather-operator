# Repro Verification Report
**Bug**: OCPBUGS-63242 — MustGather CR stuck when caseManagementAccountSecretRef points to a missing Secret
**Verified on**: 2026-08-11
**Bug Confirmed**: Yes

## 0. Inputs & Environment
- Bug report: `openspec/changes/ocpbugs-63242/bug-report.md`
- Repo: https://github.com/openshift/must-gather-operator (working-folder mode), branch: `fix/ocpbugs-63242`, commit: `0ff4e004fabb57afc9aa26e93639f2674e04bace`
- Environment: no live MustGather create permissions on connected cluster; reproduction via fake-client controller unit tests at baseline commit + user-provided operator logs from Jira
- Log source: `repo-local tests/envtest` + `user-provided logs`
- Execution mode: Cursor agent chat / repo-local (hybrid with Jira log evidence)
- agents.md: `openspec/inputs/agents.md` (copied to `openspec/changes/ocpbugs-63242/inputs/AGENTS.md`)

## 1. Reproduction Steps Executed

### Step 1: Install/run operator on OpenShift 4.20/4.21 (reported)
- **Action taken**: Checked kube access (`oc whoami` → `pravekum`). Namespace `must-gather-operator` exists. Attempted MustGather API access; cluster exposes `mustgathers.managed.openshift.io` and user lacks create/list permission. Repo-local fake-client reconcile used instead of live operator install at baseline `0ff4e00`.
- **Observed result**: Live cluster create path unavailable (Forbidden). Switched to repo-local reproduction.
- **Expected result**: Operator available for CR create (live) or equivalent controller reconcile harness (repo-local).
- **Status**: SKIP (live) / PASS (repo-local substitute documented)
- **Evidence**:
  ```
  Error from server (Forbidden): mustgathers.managed.openshift.io is forbidden
  Warning: the server doesn't have a resource type 'mustgathers' in group 'operator.openshift.io'
  oc auth can-i create mustgathers -n must-gather-operator → no
  ```

### Step 2: Confirm target Secret does not exist
- **Action taken**: In fake-client fixture, only MustGather + ClusterVersion objects were seeded — Secret `mustgather-creds` intentionally omitted (mirrors `oc get secret mustgather-creds` → NotFound).
- **Observed result**: Secret absent from client; reconcile secret Get returns NotFound.
- **Expected result**: Secret not present.
- **Status**: PASS
- **Evidence**: Test seed objects = MustGather + ClusterVersion only (no Secret). Existing suite case `reconcile_job_not_found_user_secret_missing_no_requeue` also omits Secret.

### Step 3: Create MustGather CR referencing missing Secret
- **Action taken**: Reconciled MustGather named `support-log-gather-jitli` in namespace `must-gather-operator` with `uploadTarget.sftp.caseManagementAccountSecretRef.name: mustgather-creds` (same shape as Jira YAML) via controller `Reconcile` against fake client.
- **Observed result**: Reconcile completed with `err=<nil>`, `Requeue=false`, `RequeueAfter=0s`.
- **Expected result** (bug actual): CR accepted / reconcile does not surface failure to caller; job not created.
- **Status**: PASS (matches reported actual behavior)
- **Evidence** (`openspec/changes/ocpbugs-63242/evidence/repro-go-test.log`):
  ```
  reconcile result={Requeue:false RequeueAfter:0s} err=<nil>
  ```

### Step 4: Observe CR, jobs/pods, and operator logs
- **Action taken**: After reconcile, Get Job and MustGather status; compared with Jira operator log excerpts.
- **Observed result**:
  - Job: `jobs.batch "support-log-gather-jitli" not found`
  - MustGather status: `status="" reason="" completed=false conditions=0` (no user-visible error)
  - Existing unit test `reconcile_job_not_found_user_secret_missing_no_requeue` PASSes with `expectError=false` / empty `reconcile.Result{}`
  - Jira user-provided operator logs match missing-Secret message
- **Expected result** (bug report expected behavior): user-visible error on MustGather — **not observed** (failure confirms bug)
- **Status**: FAIL vs expected fixed behavior; PASS as confirmation of reported bug
- **Evidence**:
  ```
  job get err=jobs.batch "support-log-gather-jitli" not found
  mustgather status="" reason="" completed=false conditions=0
  OCPBUGS-63242 signature confirmed: no job, reconcile success/no requeue, empty MustGather status/reason/conditions
  --- PASS: TestOCPBUGS63242_MissingSecretLeavesMustGatherStuck
  --- PASS: TestReconcile/reconcile_job_not_found_user_secret_missing_no_requeue
  ```
  User-provided (Jira):
  ```
  2025-10-28T06:10:29Z ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}
  ```

## 2. Logs Captured

### Operator Logs
```
# User-provided (Jira OCPBUGS-63242) — live cluster from reporter
2025-10-28T06:10:29Z ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}

# Earlier ticket note
2025-10-16T07:52:33Z INFO mustgather-controller Error getting secret (case-management-creds)!
```

### Kubernetes Events
```
N/A — live cluster create/list Forbidden; repo-local fake client has no Event recorder assertions for this path.
```

### Error Traces
```
# Repo-local reconcile observation (2026-08-11, commit 0ff4e00)
reconcile result={Requeue:false RequeueAfter:0s} err=<nil>
job get err=jobs.batch "support-log-gather-jitli" not found
mustgather status="" reason="" completed=false conditions=0
```

## 3. Failure Signature
Missing `caseManagementAccountSecretRef` Secret → reconcile returns success with no requeue, **no Job created**, and **MustGather status/reason/conditions remain empty** while operator logs (reporter) show Secret not found.
- **Error type**: wrong state / silent failure (missing resource not surfaced on CR)
- **Error location**: `mustgather-controller` reconcile path that looks up the case-management Secret before Job creation (`controllers/mustgather/mustgather_controller.go`)
- **Trigger condition**: `spec.uploadTarget.sftp.caseManagementAccountSecretRef.name` names a Secret that does not exist in the CR namespace
- **Frequency**: every time (Always) under the missing-Secret condition

## 4. Environment Details
- Platform: Reporter OCP 4.20/4.21; local verify via Go unit/fake-client (no live MustGather API write access)
- Operator version: baseline source `0ff4e00`; reporter CSV note `support-log-gather-operator.v4.20.0`
- Configuration: SFTP uploadTarget with non-existent `mustgather-creds` Secret
- Prerequisites: MustGather CR with UploadTarget SFTP Secret ref; Secret absent
- Differences from reported environment: verified in-process with fake client instead of live operator pod; failure signature matches reporter logs + stuck CR symptoms

## 5. Reproduction Confidence
- **Reproducibility**: Always
- **Confidence level**: High
- **Notes**: Live cluster CR create was Forbidden; confirmation combines deterministic controller fake-client behavior at the exact baseline commit with reporter operator log text. Temporary repro harness was executed then removed from the tree (evidence retained under `evidence/repro-go-test.log`). Existing suite already encodes the no-requeue missing-secret case.

## 6. Assessment Limitations
- Could not create/list MustGather on the connected cluster (RBAC Forbidden; API group mismatch vs `operator.openshift.io`)
- No live Kubernetes Events captured
- Operator log lines for the local run are inferred from reconcile outcomes + Jira-provided logs (fake client does not emit the same logr sink to stdout in the captured test log beyond t.Log)
- Cluster topology/arch from reporter remain unknown (per bug-report assumptions)
