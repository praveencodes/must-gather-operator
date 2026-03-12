FIPS_ENABLED=true

include boilerplate/generated-includes.mk

.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update


# Coverage-instrumented build (excluded from production). Use for coverage runs only.
# Builds with -cover and the coverage server (build tag "coverage") so the binary
# serves coverage data over HTTP for collection by the cluster's coverage producer.
COVERAGE_TAGS=coverage
ifeq (${FIPS_ENABLED}, true)
go-build-coverage: ensure-fips
COVERAGE_TAGS=coverage,fips_enabled
endif
.PHONY: go-build-coverage
go-build-coverage: ## Build coverage-instrumented binary (for use in coverage runs only)
	${GOENV} go build -cover -covermode=atomic -coverpkg=./... -tags=$(COVERAGE_TAGS) ${GOBUILDFLAGS} -o build/_output/bin/$(OPERATOR_NAME)-coverage .

# Build the coverage container image (non-production). Pass SOURCE_GIT_COMMIT and
# SOURCE_GIT_URL so downstream tooling can map coverage to source (see COVERAGE.md).
# Optionally: SOFTWARE_GROUP and SOFTWARE_KEY for report routing (e.g. openshift-4.21, ose-must-gather-operator).
#   make docker-build-coverage SOFTWARE_GROUP=openshift-4.21 SOFTWARE_KEY=ose-must-gather-operator
.PHONY: docker-build-coverage
docker-build-coverage:
	$(CONTAINER_ENGINE) build -f build/Dockerfile.coverage \
		--build-arg SOURCE_GIT_COMMIT=$$(git rev-parse HEAD) \
		--build-arg SOURCE_GIT_URL=$$(git config --get remote.origin.url || echo "") \
		--build-arg SOFTWARE_GROUP=openshift-4.21 \
  		--build-arg SOFTWARE_KEY=ose-must-gather-operator \
		-t $(OPERATOR_IMAGE_URI)-coverage .

# Utilize Kind or modify the e2e tests to load the image locally, enabling compatibility with other vendors.
E2E_TIMEOUT ?= 1h
.PHONY: test-e2e  # Run the e2e tests against a Kind k8s instance that is spun up.
test-e2e:
	go test \
	-timeout $(E2E_TIMEOUT) \
	-count 1 \
	-v \
	-p 1 \
	-tags e2e \
	./test/e2e \
	-ginkgo.v \
	-ginkgo.show-node-events