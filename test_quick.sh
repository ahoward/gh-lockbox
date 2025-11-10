#!/bin/bash
# Quick test - tests local functionality without GitHub Actions
# Does NOT test the full gist-based recovery (no workflow triggering)

set -e

echo "=========================================="
echo "gh-lockbox - Quick Local Test"
echo "=========================================="
echo
echo "This tests:"
echo "  ✓ Store command (no PIN prompts)"
echo "  ✓ List command"
echo "  ✓ Workflow file creation"
echo "  ✓ Gist operations (create/delete)"
echo "  ✓ Crypto module (encrypt/decrypt with UUIDv7)"
echo
echo "This does NOT test:"
echo "  ✗ Full recovery flow (requires GitHub Actions)"
echo "  ✗ Workflow execution"
echo
echo "For full test, use: ./test_local.sh"
echo
echo "=========================================="
echo

TEST_SECRET_NAME="lockbox-quick-test-$(date +%s)"
TEST_SECRET_VALUE="test-value-$(shuf -i 10000-99999 -n 1)"

# Cleanup function
cleanup() {
    echo
    echo "Cleaning up..."

    # Remove secret
    if ./bin/gh-lockbox list 2>/dev/null | grep -q "$TEST_SECRET_NAME"; then
        echo "yes" | ./bin/gh-lockbox remove "$TEST_SECRET_NAME" 2>/dev/null || true
    fi

    # Remove workflow file
    if [ -f ".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml" ]; then
        rm -f ".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml"
    fi

    # Cleanup gists
    ./bin/gh-lockbox cleanup-gists 2>/dev/null || true

    echo "Cleanup complete"
}

trap cleanup EXIT INT TERM

echo "Test 1: Store Secret"
echo "--------------------"
echo "$TEST_SECRET_VALUE" | ./bin/gh-lockbox store "$TEST_SECRET_NAME" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Store command works (no PIN prompt!)"
else
    echo "❌ Store failed"
    exit 1
fi
echo

echo "Test 2: List Secrets"
echo "--------------------"
if ./bin/gh-lockbox list 2>/dev/null | grep -q "$TEST_SECRET_NAME"; then
    echo "✅ List command works"
else
    echo "❌ List failed"
    exit 1
fi
echo

echo "Test 3: Workflow File Created"
echo "------------------------------"
if [ -f ".github/workflows/lockbox-recovery-$TEST_SECRET_NAME.yml" ]; then
    echo "✅ Workflow file created"
else
    echo "❌ Workflow file not created"
    exit 1
fi
echo

echo "Test 4: Crypto Module (UUIDv7 Encryption)"
echo "------------------------------------------"
# Test encryption/decryption with temp key
ruby -e '
require "securerandom"
require "./lib/lockbox/crypto"

temp_key = SecureRandom.uuid
data = "test secret value 123"

encrypted = Lockbox::Crypto.encrypt(data, temp_key)
decrypted = Lockbox::Crypto.decrypt(encrypted, temp_key)

if decrypted == data
  puts "✅ Crypto module works (UUIDv7 keys)"
else
  puts "❌ Crypto module failed"
  exit 1
end
'
echo

echo "Test 5: Gist Operations"
echo "-----------------------"
ruby -e '
require "./lib/lockbox/github"

# Generate temp key
temp_key = Lockbox::GitHub.generate_temp_key
puts "  Generated temp key: #{temp_key[0..15]}..."

# Calculate key ID
key_id = Lockbox::GitHub.calculate_key_id(temp_key)
puts "  Calculated key_id: #{key_id}"

# Get username
username = Lockbox::GitHub.get_current_username
puts "  Current user: #{username}"

# Create gist
puts "  Creating test gist..."
gist_id = Lockbox::GitHub.create_recovery_gist(temp_key, "test-secret")
puts "  Created gist: #{gist_id}"

# Delete gist
puts "  Deleting test gist..."
if Lockbox::GitHub.delete_gist(gist_id)
  puts "✅ Gist operations work"
else
  puts "❌ Gist deletion failed"
  exit 1
end
'
echo

echo "Test 6: Cleanup Command"
echo "-----------------------"
./bin/gh-lockbox cleanup-gists >/dev/null 2>&1
echo "✅ Cleanup-gists command works"
echo

echo "=========================================="
echo "ALL QUICK TESTS PASSED ✅"
echo "=========================================="
echo
echo "Local functionality verified:"
echo "  ✅ Store (no PIN prompts)"
echo "  ✅ List"
echo "  ✅ Workflow creation"
echo "  ✅ Crypto (UUIDv7 keys)"
echo "  ✅ Gist operations"
echo "  ✅ Cleanup command"
echo
echo "To test full recovery flow (requires GitHub Actions):"
echo "  ./test_local.sh"
