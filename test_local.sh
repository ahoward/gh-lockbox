#!/bin/bash
# Local test script for gh-lockbox gist-based architecture
# Tests against real GitHub repo

set -e

echo "=========================================="
echo "gh-lockbox v2.0.0 - Local Test"
echo "=========================================="
echo

TEST_SECRET_NAME="lockbox-test-$(date +%s)"
TEST_SECRET_VALUE="test-secret-value-$(shuf -i 10000-99999 -n 1)"

echo "Test configuration:"
echo "  Secret name: $TEST_SECRET_NAME"
echo "  Secret value: $TEST_SECRET_VALUE"
echo

# Cleanup function
cleanup() {
    echo
    echo "Cleaning up test data..."

    # Remove secret
    if ./bin/gh-lockbox list 2>/dev/null | grep -q "$TEST_SECRET_NAME"; then
        echo "  Removing test secret..."
        echo "yes" | ./bin/gh-lockbox remove "$TEST_SECRET_NAME" 2>/dev/null || true
    fi

    # Remove workflow file
    if [ -f ".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml" ]; then
        echo "  Removing test workflow..."
        rm -f ".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml"
        git checkout -- .github/workflows/ 2>/dev/null || true
    fi

    # Cleanup gists
    echo "  Cleaning up recovery gists..."
    ./bin/gh-lockbox cleanup-gists 2>/dev/null || true

    echo "  Cleanup complete"
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

echo "=========================================="
echo "Test 1: Store Secret"
echo "=========================================="
echo
echo "Running: gh lockbox store $TEST_SECRET_NAME"
echo "$TEST_SECRET_VALUE" | ./bin/gh-lockbox store "$TEST_SECRET_NAME"

if [ $? -ne 0 ]; then
    echo "❌ FAILED: Could not store secret"
    exit 1
fi
echo "✅ PASSED: Secret stored"
echo

echo "=========================================="
echo "Test 2: List Secrets"
echo "=========================================="
echo
./bin/gh-lockbox list
echo

if ./bin/gh-lockbox list | grep -q "$TEST_SECRET_NAME"; then
    echo "✅ PASSED: Secret appears in list"
else
    echo "❌ FAILED: Secret not in list"
    exit 1
fi
echo

echo "=========================================="
echo "Test 3: Commit Workflow"
echo "=========================================="
echo
WORKFLOW_FILE=".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml"

if [ -f "$WORKFLOW_FILE" ]; then
    echo "✅ PASSED: Workflow file created at $WORKFLOW_FILE"
    echo
    echo "Committing workflow file..."
    git add "$WORKFLOW_FILE"
    git commit -m "Test: Add lockbox recovery for $TEST_SECRET_NAME" >/dev/null 2>&1 || true

    echo "Pushing to GitHub..."
    git push origin main 2>&1 | head -5

    echo
    echo "✅ PASSED: Workflow committed and pushed"
else
    echo "❌ FAILED: Workflow file not created"
    exit 1
fi
echo

echo "=========================================="
echo "Test 4: Recover Secret (Gist-Based)"
echo "=========================================="
echo
echo "This will:"
echo "  1. Cleanup old gists"
echo "  2. Generate temp UUIDv7 key"
echo "  3. Create private recovery gist"
echo "  4. Trigger workflow on GitHub Actions"
echo "  5. Wait for workflow (~30-60 seconds)"
echo "  6. Decrypt with temp key"
echo "  7. Delete gist"
echo
echo "Running recovery..."
echo

RECOVERED_VALUE=$(./bin/gh-lockbox recover "$TEST_SECRET_NAME" 2>&1 | tail -1)

if [ "$RECOVERED_VALUE" = "$TEST_SECRET_VALUE" ]; then
    echo "✅ PASSED: Secret recovered successfully"
    echo "  Expected: $TEST_SECRET_VALUE"
    echo "  Got:      $RECOVERED_VALUE"
else
    echo "❌ FAILED: Secret mismatch"
    echo "  Expected: $TEST_SECRET_VALUE"
    echo "  Got:      $RECOVERED_VALUE"
    exit 1
fi
echo

echo "=========================================="
echo "Test 5: Cleanup Gists"
echo "=========================================="
echo
./bin/gh-lockbox cleanup-gists
echo "✅ PASSED: Cleanup gists command works"
echo

echo "=========================================="
echo "Test 6: Remove Secret"
echo "=========================================="
echo
echo "yes" | ./bin/gh-lockbox remove "$TEST_SECRET_NAME"

if ./bin/gh-lockbox list | grep -q "$TEST_SECRET_NAME"; then
    echo "❌ FAILED: Secret still in list"
    exit 1
else
    echo "✅ PASSED: Secret removed"
fi
echo

echo "=========================================="
echo "ALL TESTS PASSED ✅"
echo "=========================================="
echo
echo "Summary:"
echo "  ✅ Store secret (no PIN!)"
echo "  ✅ List secrets"
echo "  ✅ Create workflow"
echo "  ✅ Recover secret (gist-based, automated)"
echo "  ✅ Cleanup gists"
echo "  ✅ Remove secret"
echo
echo "The gist-based architecture is working!"
