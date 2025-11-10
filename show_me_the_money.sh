#!/usr/bin/env bash
#
# gh-lockbox comprehensive test suite
# Tests every CLI operation end-to-end
#

set -euo pipefail  # Fail fast, no unset vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Cleanup temp files on exit
TEMP_FILES=()
cleanup() {
  for f in "${TEMP_FILES[@]}"; do
    rm -f "$f" 2>/dev/null || true
  done
  echo
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ Tests passed: ${TESTS_PASSED}/${TESTS_RUN}${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
trap cleanup EXIT

# Helper: Create temp file
temp_file() {
  local file
  file=$(mktemp)
  TEMP_FILES+=("$file")
  echo "$file"
}

# Helper: Run test
test_run() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}▶ Test $TESTS_RUN: $name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Helper: Assert success
test_pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ PASS${NC}"
}

# Helper: Assert value equals expected
assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-Value mismatch}"

  if [[ "$actual" == "$expected" ]]; then
    echo -e "${GREEN}  ✓ $msg${NC}"
  else
    echo -e "${RED}  ✗ $msg${NC}"
    echo -e "${RED}    Expected: $expected${NC}"
    echo -e "${RED}    Got:      $actual${NC}"
    exit 1
  fi
}

# Helper: Assert string contains substring
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-String should contain substring}"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "${GREEN}  ✓ $msg${NC}"
  else
    echo -e "${RED}  ✗ $msg${NC}"
    echo -e "${RED}    Expected to find: $needle${NC}"
    echo -e "${RED}    In: $haystack${NC}"
    exit 1
  fi
}

# Helper: Assert file exists
assert_file_exists() {
  local file="$1"
  local msg="${2:-File should exist: $file}"

  if [[ -f "$file" ]]; then
    echo -e "${GREEN}  ✓ $msg${NC}"
  else
    echo -e "${RED}  ✗ $msg${NC}"
    exit 1
  fi
}

# Helper: Remove test secrets (cleanup between tests)
cleanup_test_secrets() {
  local secrets=("$@")
  for secret in "${secrets[@]}"; do
    ./bin/gh-lockbox remove "$secret" 2>/dev/null || true
  done
}

#═══════════════════════════════════════════════════════════════════════════════
# TESTS START HERE
#═══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                               ║${NC}"
echo -e "${BLUE}║                💰 SHOW ME THE MONEY 💰 Test Suite 💰                          ║${NC}"
echo -e "${BLUE}║                                                                               ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"

#───────────────────────────────────────────────────────────────────────────────
# Test 1: Store and recover single secret
#───────────────────────────────────────────────────────────────────────────────
test_run "Store and recover single secret"

cleanup_test_secrets "TEST_SECRET_1"

# Store
./bin/gh-lockbox store TEST_SECRET_1 "my-secret-value-123"

# Recover
result=$(./bin/gh-lockbox recover TEST_SECRET_1 2>/dev/null || true)
assert_eq "$result" "my-secret-value-123" "Secret value should match"

cleanup_test_secrets "TEST_SECRET_1"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 2: Store and recover secret with special characters
#───────────────────────────────────────────────────────────────────────────────
test_run "Store and recover secret with special characters"

cleanup_test_secrets "TEST_SECRET_SPECIAL"

# Secret with spaces, quotes, special chars
secret_value="value with spaces & special!@#\$%^&*()"
./bin/gh-lockbox store TEST_SECRET_SPECIAL "$secret_value"

result=$(./bin/gh-lockbox recover TEST_SECRET_SPECIAL 2>/dev/null || true)
assert_eq "$result" "$secret_value" "Special characters should be preserved"

cleanup_test_secrets "TEST_SECRET_SPECIAL"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 3: Store and recover multi-line secret
#───────────────────────────────────────────────────────────────────────────────
test_run "Store and recover multi-line secret"

cleanup_test_secrets "TEST_SECRET_MULTILINE"

# Multi-line secret using heredoc
multiline_secret=$(cat <<'EOF'
line 1
line 2 with spaces
line 3 with special chars: !@#$
EOF
)

./bin/gh-lockbox store TEST_SECRET_MULTILINE "$multiline_secret"

result=$(./bin/gh-lockbox recover TEST_SECRET_MULTILINE 2>/dev/null || true)
assert_eq "$result" "$multiline_secret" "Multi-line secret should be preserved"

cleanup_test_secrets "TEST_SECRET_MULTILINE"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 4: Recover multiple secrets (JSON output)
#───────────────────────────────────────────────────────────────────────────────
test_run "Recover multiple secrets (JSON output)"

cleanup_test_secrets "TEST_MULTI_A" "TEST_MULTI_B" "TEST_MULTI_C"

# Store multiple secrets
./bin/gh-lockbox store TEST_MULTI_A "value-a"
./bin/gh-lockbox store TEST_MULTI_B "value-b"
./bin/gh-lockbox store TEST_MULTI_C "value-c"

# Recover multiple (should output JSON)
result=$(./bin/gh-lockbox recover TEST_MULTI_A TEST_MULTI_B TEST_MULTI_C 2>/dev/null || true)

# Verify JSON contains all secrets
assert_contains "$result" "TEST_MULTI_A" "JSON should contain TEST_MULTI_A"
assert_contains "$result" "TEST_MULTI_B" "JSON should contain TEST_MULTI_B"
assert_contains "$result" "TEST_MULTI_C" "JSON should contain TEST_MULTI_C"
assert_contains "$result" "value-a" "JSON should contain value-a"
assert_contains "$result" "value-b" "JSON should contain value-b"
assert_contains "$result" "value-c" "JSON should contain value-c"

# Parse JSON and verify values
value_a=$(echo "$result" | jq -r '.TEST_MULTI_A')
value_b=$(echo "$result" | jq -r '.TEST_MULTI_B')
value_c=$(echo "$result" | jq -r '.TEST_MULTI_C')

assert_eq "$value_a" "value-a" "TEST_MULTI_A value should match"
assert_eq "$value_b" "value-b" "TEST_MULTI_B value should match"
assert_eq "$value_c" "value-c" "TEST_MULTI_C value should match"

cleanup_test_secrets "TEST_MULTI_A" "TEST_MULTI_B" "TEST_MULTI_C"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 5: Recover all secrets (no args)
#───────────────────────────────────────────────────────────────────────────────
test_run "Recover all secrets (no args, JSON output)"

cleanup_test_secrets "TEST_ALL_1" "TEST_ALL_2"

# Store test secrets
./bin/gh-lockbox store TEST_ALL_1 "all-value-1"
./bin/gh-lockbox store TEST_ALL_2 "all-value-2"

# Recover all (no args)
result=$(./bin/gh-lockbox recover 2>/dev/null || true)

# Should output JSON with at least our test secrets
assert_contains "$result" "TEST_ALL_1" "Should contain TEST_ALL_1"
assert_contains "$result" "TEST_ALL_2" "Should contain TEST_ALL_2"

cleanup_test_secrets "TEST_ALL_1" "TEST_ALL_2"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 6: List secrets
#───────────────────────────────────────────────────────────────────────────────
test_run "List secrets"

cleanup_test_secrets "TEST_LIST_1" "TEST_LIST_2"

# Store test secrets
./bin/gh-lockbox store TEST_LIST_1 "list-value-1"
./bin/gh-lockbox store TEST_LIST_2 "list-value-2"

# List secrets
result=$(./bin/gh-lockbox list)

assert_contains "$result" "TEST_LIST_1" "List should contain TEST_LIST_1"
assert_contains "$result" "TEST_LIST_2" "List should contain TEST_LIST_2"

cleanup_test_secrets "TEST_LIST_1" "TEST_LIST_2"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 7: Remove secret
#───────────────────────────────────────────────────────────────────────────────
test_run "Remove secret"

cleanup_test_secrets "TEST_REMOVE"

# Store secret
./bin/gh-lockbox store TEST_REMOVE "remove-value"

# Verify it exists
list_before=$(./bin/gh-lockbox list)
assert_contains "$list_before" "TEST_REMOVE" "Secret should exist before removal"

# Remove it (with --force to skip confirmation)
./bin/gh-lockbox remove TEST_REMOVE --force

# Verify it's gone
list_after=$(./bin/gh-lockbox list)
if [[ "$list_after" == *"TEST_REMOVE"* ]]; then
  echo -e "${RED}  ✗ Secret should be removed${NC}"
  exit 1
else
  echo -e "${GREEN}  ✓ Secret removed successfully${NC}"
fi

test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 8: dotenv pull (all secrets → .env file)
#───────────────────────────────────────────────────────────────────────────────
test_run "dotenv pull (secrets → .env file)"

cleanup_test_secrets "TEST_DOTENV_A" "TEST_DOTENV_B"

# Create temp .env file
env_file=$(temp_file)

# Store test secrets
./bin/gh-lockbox store TEST_DOTENV_A "dotenv-value-a"
./bin/gh-lockbox store TEST_DOTENV_B "dotenv-value-b"

# Pull to .env file
./bin/gh-lockbox dotenv pull "$env_file"

# Verify file exists and contains secrets
assert_file_exists "$env_file" ".env file should be created"
env_content=$(cat "$env_file")
assert_contains "$env_content" "TEST_DOTENV_A=dotenv-value-a" "Should contain TEST_DOTENV_A"
assert_contains "$env_content" "TEST_DOTENV_B=dotenv-value-b" "Should contain TEST_DOTENV_B"

cleanup_test_secrets "TEST_DOTENV_A" "TEST_DOTENV_B"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 9: dotenv push (.env file → secrets)
#───────────────────────────────────────────────────────────────────────────────
test_run "dotenv push (.env file → secrets)"

cleanup_test_secrets "TEST_PUSH_X" "TEST_PUSH_Y" "TEST_PUSH_Z"

# Create .env file
env_file=$(temp_file)
cat > "$env_file" <<'EOF'
TEST_PUSH_X=push-value-x
TEST_PUSH_Y=push-value-y
TEST_PUSH_Z=push-value-z
EOF

# Push .env to GitHub Secrets
./bin/gh-lockbox dotenv push "$env_file"

# Verify secrets were created
list_result=$(./bin/gh-lockbox list)
assert_contains "$list_result" "TEST_PUSH_X" "Should contain TEST_PUSH_X"
assert_contains "$list_result" "TEST_PUSH_Y" "Should contain TEST_PUSH_Y"
assert_contains "$list_result" "TEST_PUSH_Z" "Should contain TEST_PUSH_Z"

# Verify values
x_value=$(./bin/gh-lockbox recover TEST_PUSH_X 2>/dev/null || true)
y_value=$(./bin/gh-lockbox recover TEST_PUSH_Y 2>/dev/null || true)
z_value=$(./bin/gh-lockbox recover TEST_PUSH_Z 2>/dev/null || true)

assert_eq "$x_value" "push-value-x" "TEST_PUSH_X value should match"
assert_eq "$y_value" "push-value-y" "TEST_PUSH_Y value should match"
assert_eq "$z_value" "push-value-z" "TEST_PUSH_Z value should match"

cleanup_test_secrets "TEST_PUSH_X" "TEST_PUSH_Y" "TEST_PUSH_Z"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 10: dotenv roundtrip (push → pull, verify identical)
#───────────────────────────────────────────────────────────────────────────────
test_run "dotenv roundtrip (push → pull → verify)"

cleanup_test_secrets "TEST_ROUNDTRIP_1" "TEST_ROUNDTRIP_2"

# Create original .env
original_env=$(temp_file)
cat > "$original_env" <<'EOF'
TEST_ROUNDTRIP_1=roundtrip-value-1
TEST_ROUNDTRIP_2=roundtrip-value-2
EOF

# Push to GitHub
./bin/gh-lockbox dotenv push "$original_env"

# Pull back to new file
pulled_env=$(temp_file)
./bin/gh-lockbox dotenv pull "$pulled_env"

# Verify pulled file contains our secrets
pulled_content=$(cat "$pulled_env")
assert_contains "$pulled_content" "TEST_ROUNDTRIP_1=roundtrip-value-1" "Roundtrip TEST_ROUNDTRIP_1"
assert_contains "$pulled_content" "TEST_ROUNDTRIP_2=roundtrip-value-2" "Roundtrip TEST_ROUNDTRIP_2"

cleanup_test_secrets "TEST_ROUNDTRIP_1" "TEST_ROUNDTRIP_2"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 11: Secret with spaces in value
#───────────────────────────────────────────────────────────────────────────────
test_run "Secret with spaces in value"

cleanup_test_secrets "TEST_SPACES"

./bin/gh-lockbox store TEST_SPACES "this value has many    spaces"

result=$(./bin/gh-lockbox recover TEST_SPACES 2>/dev/null || true)
assert_eq "$result" "this value has many    spaces" "Spaces should be preserved"

cleanup_test_secrets "TEST_SPACES"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 12: Secret name normalization (lowercase → UPPERCASE)
#───────────────────────────────────────────────────────────────────────────────
test_run "Secret name normalization (lowercase → UPPERCASE)"

cleanup_test_secrets "TEST_NORMALIZE"

# Store with lowercase
./bin/gh-lockbox store test-normalize "normalized-value"

# List should show UPPERCASE
list_result=$(./bin/gh-lockbox list)
assert_contains "$list_result" "TEST_NORMALIZE" "Should normalize to TEST_NORMALIZE"

# Recover with lowercase should still work
result=$(./bin/gh-lockbox recover test-normalize 2>/dev/null || true)
assert_eq "$result" "normalized-value" "Should recover with lowercase name"

cleanup_test_secrets "TEST_NORMALIZE"
test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 13: Cleanup ephemeral private keys
#───────────────────────────────────────────────────────────────────────────────
test_run "Cleanup ephemeral private keys"

# Cleanup command should run without errors
./bin/gh-lockbox cleanup

echo -e "${GREEN}  ✓ Cleanup command executed successfully${NC}"

test_pass

#───────────────────────────────────────────────────────────────────────────────
# Test 14: Empty secret value (edge case)
#───────────────────────────────────────────────────────────────────────────────
test_run "Empty secret value (should fail gracefully)"

cleanup_test_secrets "TEST_EMPTY"

# Attempt to store empty value (should fail)
if ./bin/gh-lockbox store TEST_EMPTY "" 2>/dev/null; then
  echo -e "${RED}  ✗ Should not allow empty secret value${NC}"
  exit 1
else
  echo -e "${GREEN}  ✓ Correctly rejects empty secret value${NC}"
fi

test_pass

#═══════════════════════════════════════════════════════════════════════════════
# ALL TESTS COMPLETE
#═══════════════════════════════════════════════════════════════════════════════

echo
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                               ║${NC}"
echo -e "${GREEN}║                   💰💰💰 SHOW ME THE MONEY! 💰💰💰                              ║${NC}"
echo -e "${GREEN}║                        ALL TESTS PASSED! 🎉                                   ║${NC}"
echo -e "${GREEN}║                                                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
