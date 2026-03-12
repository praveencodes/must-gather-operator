# Coverage reporting for Must Gather Operator

This document describes how to build and run the operator with **coverage instrumentation** so that coverage data can be collected and rendered as reports (including line-level reports with links to source) when the operator runs on a **coverage-instrumented OpenShift cluster**.

Production binaries are **not** instrumented: the coverage server and `-cover` build are excluded by default via the Go build tag `coverage`.

---

## 1. What is included

- **`coverage_server.go`** (build tag `coverage`): HTTP server that serves Go coverage data (metadata + counters) and identification headers. Only compiled when building with `-tags=coverage`.
- **`coverage_stub.go`** (build tag `!coverage`): Stub that keeps `coverageEnabled` and `startCoverageServer()` defined for the default build; production binaries stay uninstrumented.
- **Non-production build**: `make go-build-coverage` builds a binary with `-cover` and the coverage server.
- **Coverage image**: `make docker-build-coverage` (or `build/Dockerfile.coverage`) produces an image that runs this binary and sets **SOURCE_GIT_COMMIT** and **SOURCE_GIT_URL** (and optionally **SOFTWARE_GROUP** / **SOFTWARE_KEY**) in the runtime environment so downstream tooling can map coverage back to the exact source tree.

---

## 2. Build the coverage binary (local)

```bash
make go-build-coverage
```

Output: `build/_output/bin/must-gather-operator-coverage`. Do not use this binary in production.

---

## 3. Build the coverage container image

From the repo root:

```bash
make docker-build-coverage
```

This builds the image with:

- **SOURCE_GIT_COMMIT** and **SOURCE_GIT_URL** set from the current git commit and remote URL so that rendering tooling can map coverage data to the exact source (required for line-level reports with links to code).
- Optionally, you can pass **SOFTWARE_GROUP** and **SOFTWARE_KEY** to route reports (e.g. OpenShift uses values like `openshift-4.21` and `ose-etcd` for Jira/team mapping). To set them in the image, build with:

  ```bash
  $(CONTAINER_ENGINE) build -f build/Dockerfile.coverage \
    --build-arg SOURCE_GIT_COMMIT=$(git rev-parse HEAD) \
    --build-arg SOURCE_GIT_URL=$(git config --get remote.origin.url) \
    --build-arg SOFTWARE_GROUP=openshift-4.21 \
    --build-arg SOFTWARE_KEY=ose-must-gather-operator \
    -t <your-registry>/must-gather-operator:coverage .
  ```

You can also set **SOFTWARE_GROUP** and **SOFTWARE_KEY** at runtime (e.g. via Deployment env) instead of at build time.

---

## 4. How to generate a coverage report

The workflow is:

1. **Use a coverage-instrumented OpenShift cluster**  
   The cluster must be built/configured so that the kubelet (or a dedicated “producer”) discovers containers that expose coverage data and collects it.

2. **Install the operator using the coverage image**  
   Deploy the must-gather-operator so that its pod(s) use the **coverage** image (the one built with `make docker-build-coverage` or `build/Dockerfile.coverage`), not the production image.  
   - Ensure **SOURCE_GIT_COMMIT** and **SOURCE_GIT_URL** are set in the pod’s environment (they are set in the coverage Dockerfile; override via Deployment if needed).  
   - Optionally set **SOFTWARE_GROUP** and **SOFTWARE_KEY** for routing.

3. **Discovery and upload**  
   On a coverage-instrumented cluster, the kubelet’s producer discovers containers that listen on a port and return coverage data (e.g. the Go coverage server in this operator). It collects coverage from them and uploads it together with platform components.

4. **Rendering**  
   Downstream analysis/rendering tooling consumes the uploaded data. If **SOURCE_GIT_COMMIT** and **SOURCE_GIT_URL** are present, the tooling can map coverage back to the exact source tree and produce **detailed, line-level reports with links to the actual code**. Without these, reports can still show coverage percentages but will not be able to retrieve and display the source files.  
   The rendered report will include the layered product (must-gather-operator) coverage along with platform coverage.

**Summary:** Build the coverage image → install the operator with that image on a coverage-instrumented cluster → run the cluster and operator as usual → the producer collects coverage → use your rendering pipeline to generate the report. The report will include this operator’s coverage when the rendering process supports the format and the env vars are set.

---

## 5. Coverage server behaviour

- The coverage server listens on a port (default **53700**; override with **COVERAGE_PORT**) and serves:
  - **GET /coverage** – returns coverage metadata and counters (JSON).
  - **GET /health** – simple health check.
- **HEAD** requests to any path return identification headers so clients can recognise a coverage server:
  - **X-Art-Coverage-Server**, **X-Art-Coverage-Pid**, **X-Art-Coverage-Binary**
  - **X-Art-Coverage-Source-Commit**, **X-Art-Coverage-Source-Url** (from **SOURCE_GIT_COMMIT**, **SOURCE_GIT_URL**)
  - **X-Art-Coverage-Software-Group**, **X-Art-Coverage-Software-Key** (if **SOFTWARE_GROUP** / **SOFTWARE_KEY** or **__doozer_group** / **__doozer_key** are set)

The producer records these headers (e.g. in `info.json`) so that rendering can attribute and link coverage to the correct source and team.

---

## 6. Non-Go programs

The same cluster coverage flow can support other runtimes: any container that listens on a port and returns data in a supported format can be integrated as long as the rendering process supports that format.
