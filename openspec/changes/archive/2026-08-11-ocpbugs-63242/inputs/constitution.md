# Must-Gather Operator Constitution

**AgentRoutingMode:** PROVIDED

**Version**: 1.0.0 | **Ratified**: 2026-08-11 | **Last Amended**: 2026-08-11

> Generated once for change `ocpbugs-63242` because no repo `constitution.md` was present.
> Derived from baseline checkout `0ff4e00`, `openspec/inputs/agents.md` (PR #379), and `CLAUDE.md`.

## Core Principles

### I. Follow Existing Reconciler Error Surfacing
User-visible reconcile failures should use existing `ReconcilerBase` helpers (`ManageError` / `ManageSuccess`) already used throughout the MustGather controller, rather than inventing a parallel status API.

**Evidence:** `controllers/mustgather/mustgather_controller.go` — multiple `return r.ManageError(ctx, instance, err)` call sites

### II. Minimal Blast Radius for Bug Fixes
Change only the defective path and co-located regression tests. Do not refactor Job template, upload script, or API schema unless required by the root cause.

**Evidence:** Single reconciler + Job template split in `controllers/mustgather/`; bug scope localized to Secret pre-create gate

### III. Test Gates via Makefile / Package Tests
Verify with established targets: `make go-test` / `go test ./controllers/mustgather/...`. Co-generate unit regression coverage with controller fixes.

**Evidence:** `CLAUDE.md` / `Makefile` boilerplate targets; `controllers/mustgather/*_test.go` fake-client suite

### IV. Generated Code Discipline
Do not hand-edit `zz_generated.*` or generated CRD YAML; run `make generate` / `make manifests` when API types change.

**Evidence:** `api/v1alpha1/zz_generated.deepcopy.go`; agents.md critical patterns

### V. Secrets Stay User-Supplied References
Case-management credentials are referenced from the CR namespace Secret; do not invent new secret-copy schemes for this fix unless baseline code already requires it for the changed path.

**Evidence:** Secret Get by `instance.Namespace` + name in `mustgather_controller.go`; agents.md / harness-docs SecretKeyRef guidance

### VI. Baseline Pin for This Bugfix
Implementation and analysis for OCPBUGS-63242 remain on working-folder branch at `0ff4e00` unless the user directs otherwise. Do not copy post-fix commits as the solution source.

**Evidence:** `openspec/changes/ocpbugs-63242/inputs/jira.yaml` `base_commit`

## Additional Constraints

- **Stack:** Go + controller-runtime operator — **Evidence:** `go.mod`, `main.go`
- **FIPS:** Prefer keeping FIPS-enabled build posture — **Evidence:** `CLAUDE.md` / Makefile `FIPS_ENABLED`
- **Working-folder mode:** No fork/draft PR unless user requests — **Evidence:** `inputs/jira.yaml` `use_working_folder_as_repo: true`

## Development Workflow

| Activity | Requirement | Evidence |
|----------|-------------|----------|
| Local unit tests | `make go-test` or `go test ./controllers/mustgather/...` | `CLAUDE.md`, agents.md |
| Lint | `make lint` when feasible | `CLAUDE.md` |
| Codegen | `make generate` + `make manifests` after API edits | agents.md |
| PR / review | Standard OpenShift review; working-folder mode may skip draft PR | jira.yaml working-folder mode |

## Agent Routing

| Agent ID | When to route |
|----------|----------------|
| `OperatorController_Agent` | Reconciler / status / Secret lookup error handling |
| `Testing_Agent` | Unit/envtest regression for missing Secret |
| `API_Agent` | Only if status/condition API types must change |
| `JobTemplate_Agent` | Out of scope unless Job template implicated |

See `openspec/inputs/agents.md` for full roster and verification matrix.

## Governance

This constitution complements `openspec/inputs/agents.md` and repo `CLAUDE.md`. On conflict: constitution non-negotiables win for process; RCA wins for root-cause scope; agents.md wins for agent IDs.
