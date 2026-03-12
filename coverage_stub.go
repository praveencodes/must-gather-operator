//go:build !coverage

package main

// coverageEnabled is false when the binary is built without the coverage build tag.
// Production builds do not include the coverage server.
const coverageEnabled = false

// startCoverageServer is a no-op when coverage is disabled.
func startCoverageServer() {}
