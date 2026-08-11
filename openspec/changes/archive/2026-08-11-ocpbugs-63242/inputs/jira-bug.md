# OCPBUGS-63242

**Summary:** MustGather CR stuck when the caseManagementAccountSecretRef field points to a Secret that doesn’t exist

**Type:** Bug  
**Status:** Closed  
**URL:** https://issues.redhat.com/browse/OCPBUGS-63242  
**Affected versions:** 4.21, 4.20

## Description of problem

MustGather silently fails when the `caseManagementAccountSecretRef` field points to a Secret that doesn’t exist in the cluster. When the Secret cannot be found, the MustGather CR becomes stuck.

There is no error surfaced on the MustGather resource. Error logs can only be found in the Operator log:

```
2025-10-16T07:52:33Z INFO mustgather-controller Error getting secret (case-management-creds)!
```

## Steps to Reproduce

1. Create a MustGather CR that references a non-existent secret via `uploadTarget.sftp.caseManagementAccountSecretRef` (example name: `mustgather-creds`) while that Secret is not present in the namespace.
2. Observe that nothing happens: no pod/job is created and the CR remains stuck with no error condition on the resource.
3. Operator logs show the secret was not found, e.g.:

```
ERROR mustgather-controller the secret mustgather-creds was not found in namespace must-gather-operator {"error": "Secret \"mustgather-creds\" not found"}
```

## Actual results

Nothing happens: no pod is created, no error message on the MustGather CR — it remains stuck.

## Expected results

When the Secret specified in the MustGather CR does not exist, an error message should be returned/surfaced directly (on the MustGather resource / to the user), not only in operator logs.

## Acceptance criteria

- Missing `caseManagementAccountSecretRef` Secret does not leave the MustGather CR stuck indefinitely with no user-visible error.
- The failure is surfaced on the MustGather CR (status/condition/error message) so users do not need to inspect operator pod logs to discover the cause.
