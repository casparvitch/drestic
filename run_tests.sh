#!/bin/bash
# run_tests.sh
# A simple script to run all Bats-core tests in the 'tests/' directory.

set -euo pipefail

# Check if Bats-core is installed
if ! command -v bats &>/dev/null; then
	echo "Error: Bats-core is not installed."
	echo "Please install it by following the instructions in README.md (Testing section)."
	exit 1
fi

# Find the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

echo "--- Running Bats Tests ---"
echo "Bats version: $(bats --version)"
echo "Tests directory: ${REPO_ROOT}/tests/"

# Disable pretty printing of failures to prevent hangs in certain environments
# This prevents Bats from trying to read source files for failed lines.
export BATS_NO_PRETTY_PRINT_FAILURES=true
# Run the basic tests from the main tests directory
echo "Starting Bats tests for basic.bats..."
bats "${REPO_ROOT}/tests/basic.bats"
echo "Bats tests for basic.bats completed."

echo "--- All Bats Tests Completed ---"
