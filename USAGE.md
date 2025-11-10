# Usage Guide

Comprehensive guide to using gh-lockbox for stateless secret recovery via GitHub Actions.

## Quick Reference

```bash
gh lockbox store <name>       # Store a secret (no PIN!)
gh lockbox recover <name>     # Recover a secret (auto temp key)
gh lockbox list               # List all secrets
gh lockbox remove <name>      # Remove a secret
gh lockbox cleanup-gists      # Cleanup old recovery gists
gh lockbox verify             # Verify installation (run tests)
gh lockbox help               # Show help
gh lockbox version            # Show version
```

## Detailed Usage

### Storing a Secret

Store any secret - it will be available in CI/CD and recoverable:

```bash
gh lockbox store my-api-key
```

You'll be prompted for:
1. **Secret value** (hidden input, no visual feedback)

That's it! No PIN needed.

The tool will:
- Store the secret in GitHub Secrets as `LOCKBOX_MY_API_KEY_VALUE`
- Create a recovery workflow at `.github/workflows/lockbox-recovery-my-api-key.yml`

**Important**: Commit and push the workflow file:

```bash
git add .github/workflows/lockbox-recovery-my-api-key.yml
git commit -m "Add lockbox recovery for my-api-key"
git push
```

**CI/CD Usage**: The secret is now available as a normal GitHub Secret:

```yaml
# .github/workflows/deploy.yml
name: Deploy
on: push

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy with secret
        env:
          API_KEY: ${{ secrets.LOCKBOX_MY_API_KEY_VALUE }}
        run: |
          deploy.sh
```

### Listing Secrets

View all stored lockbox secrets:

```bash
gh lockbox list
```

Output shows:
- Repository name
- List of secrets with workflow status
- `✓` = workflow file exists
- `✗` = workflow file missing (secret can't be recovered)

Example:
```
Repository: ahoward/my-project

Lockbox secrets (3):
  ✓ my-api-key
  ✓ database-password
  ✗ old-secret

Note: ✗ indicates missing workflow file
```

### Recovering a Secret

Recover a secret from any device with git clone + gh auth:

```bash
gh lockbox recover my-api-key
```

**Behind the scenes (fully automated):**
1. Cleanup old recovery gists (if any)
2. Generate temp UUIDv7 key (128-bit entropy)
3. Create private recovery gist with temp key
4. Trigger recovery workflow on GitHub Actions
5. Workflow searches your gists for temp key
6. Workflow encrypts secret with temp key
7. Wait for workflow completion (~30-60 seconds)
8. Retrieve encrypted blob from workflow logs
9. Decrypt with temp key (no user input!)
10. Delete recovery gist (temp key gone forever)
11. Output the secret

**No PIN prompt! Fully automated!**

The secret is output to stdout, so you can:

```bash
# Display in terminal
gh lockbox recover my-api-key

# Save to file
gh lockbox recover my-api-key > secret.txt

# Use in a script
API_KEY=$(gh lockbox recover my-api-key)

# Pipe to another command
gh lockbox recover ssh-key | ssh-add -

# Bootstrap new laptop
gh lockbox recover ssh-key > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa
gh lockbox recover gpg-key | gpg --import
```

### Removing a Secret

Remove a secret and its recovery workflow:

```bash
gh lockbox remove my-api-key
```

You'll be asked to confirm. Then the tool will:
- Remove `LOCKBOX_MY_API_KEY_VALUE` from GitHub Secrets
- Delete `.github/workflows/lockbox-recovery-my-api-key.yml`

**Remember to commit**:

```bash
git add .github/workflows/
git commit -m "Remove lockbox recovery for my-api-key"
git push
```

### Cleanup Recovery Gists

Manually cleanup old recovery gists (normally done automatically):

```bash
gh lockbox cleanup-gists
```

This will:
- List all `gh-lockbox-recovery-*` gists for your user
- Delete each one
- Show count of deleted gists

**When to use:**
- After a failed recovery (gist not auto-deleted)
- To verify no old gists exist
- For cleanup before uninstalling

**Auto-cleanup happens:**
- At start of every `recover` command
- On `at_exit` if recovery is interrupted
- So manual cleanup is rarely needed

### Verifying Installation

Run automated tests against your real GitHub repository:

```bash
gh lockbox verify
```

**Note:** This command needs updating for the new gist-based architecture. It currently expects PINs and will fail. Use with caution or skip until updated.

The verify command will:
- Store a test secret
- Create test workflow
- Test encryption/decryption
- Cleanup test data
- Report results (8 tests total)

All test data is cleaned up automatically.

## Common Workflows

### Bootstrap a New Laptop

```bash
# Clone your dotfiles/secrets repo
git clone git@github.com:me/dotfiles.git
cd dotfiles

# Install gh-lockbox
gh extension install ahoward/gh-lockbox

# Recover all your secrets
gh lockbox recover ssh-key > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa
gh lockbox recover gpg-key | gpg --import
gh lockbox recover aws-credentials > ~/.aws/credentials
gh lockbox recover npm-token
```

### Onboard New Team Member

```bash
# New team member clones project
git clone git@github.com:team/project.git
cd project

# They recover all secrets (workflows already in repo)
gh lockbox list
gh lockbox recover database-password
gh lockbox recover api-key
gh lockbox recover deploy-key
```

### Emergency Secret Recovery

```bash
# DBA left company, nobody knows production DB password
# But it's in GitHub Secrets and DB is running

# Recover the password
gh lockbox recover PROD_DB_PASSWORD
# → oldpassword123

# Change database password
psql -c "ALTER USER postgres PASSWORD 'newpassword456'"

# Update secret in GitHub
gh secret set PROD_DB_PASSWORD --body "newpassword456"

# Done! Crisis averted.
```

### Migrate Secrets to Password Manager

```bash
# You have 50 repos with secrets, want to consolidate

for repo in $(gh repo list --limit 100 | awk '{print $1}'); do
  cd $repo

  # Recover all secrets from this repo
  for secret in $(gh lockbox list 2>/dev/null | grep '✓' | awk '{print $2}'); do
    value=$(gh lockbox recover $secret)

    # Store in 1Password
    op create item \
      --category=password \
      --title="$repo/$secret" \
      --field="value=$value"
  done
done

# All secrets now in 1Password
# Original repos still work (secrets unchanged)
```

## Security Best Practices

### For Personal Use

1. **Enable 2FA** on your GitHub account
2. **Use gh lockbox for**:
   - SSH keys, GPG keys
   - API tokens for personal projects
   - Development credentials
3. **Don't use for**:
   - Production secrets (use proper secret management)
   - Compliance-required secrets (PCI, HIPAA, etc.)

### For Team Use

1. **Branch protection** for `.github/workflows/`
   ```yaml
   branches:
     - name: main
       protection:
         required_pull_request_reviews:
           required_approving_review_count: 2
   ```

2. **CODEOWNERS** for workflow files
   ```
   # .github/CODEOWNERS
   .github/workflows/* @org/security-team
   ```

3. **Audit workflow runs** monthly
   ```bash
   gh run list --workflow lockbox-recovery-*
   ```

4. **Educate team** on security model:
   - Secrets are plaintext in GitHub Secrets (for CI/CD)
   - Recovery creates temp keys (10-second lifetime)
   - Gists are private (only owner can read)
   - Auto-cleanup removes temp keys

### What's Protected

✅ **Workflow log exposure** - Only encrypted blobs in logs
✅ **Temp key exposure** - 10-second lifetime, auto-deleted
✅ **Fork attacks** - Secrets don't inherit to forks
✅ **Malicious workflows** - Branch protection + CODEOWNERS

### What's NOT Protected

❌ **Compromised GitHub account** - Can read secrets directly
❌ **Malicious workflow modifications** - Use branch protection!
❌ **Active recovery interception** - Requires compromised account during 10-second window

## Troubleshooting

### "Secret not found"

The secret doesn't exist in GitHub Secrets.

**Solution:**
```bash
# List secrets to verify name
gh lockbox list

# Store the secret if missing
gh lockbox store secret-name
```

### "Recovery workflow not found"

The workflow file is missing or not committed.

**Solution:**
```bash
# gh-lockbox will create it automatically
gh lockbox recover secret-name

# It will tell you to commit the workflow
git add .github/workflows/lockbox-recovery-secret-name.yml
git commit -m "Add lockbox recovery for secret-name"
git push

# Then run recover again
gh lockbox recover secret-name
```

### "Failed to create gist"

GitHub CLI or permissions issue.

**Solution:**
```bash
# Check gh CLI authentication
gh auth status

# Re-login if needed
gh auth login

# Verify you can create gists
gh gist create --help
```

### "Workflow failed"

The recovery workflow failed on GitHub Actions.

**Solution:**
```bash
# Check workflow logs
gh run list --workflow lockbox-recovery-secret-name
gh run view <run-id>

# Common causes:
# - Workflow file not committed/pushed
# - Secret doesn't exist in repo
# - Gist not found (already deleted)
```

### "No recovery gists found"

During cleanup or recovery, no gists were found.

**Solution:**
- This is normal! Gists are auto-deleted after recovery
- Only an issue if recovery fails mid-process
- Run `gh lockbox cleanup-gists` to verify all clean

## Advanced Usage

### Works with Existing Repos!

**gh-lockbox can recover secrets from repos that already have secrets set:**

```bash
# You have an old repo with secrets.DATABASE_PASSWORD set years ago
cd old-project

# Install gh-lockbox
gh extension install ahoward/gh-lockbox

# Recover the secret (creates workflow automatically)
gh lockbox recover DATABASE_PASSWORD
# → Creates .github/workflows/lockbox-recovery-database-password.yml
# → Prompts you to commit it
# → You commit, push, run again
# → Gets the secret!

# Your CI/CD keeps using secrets.DATABASE_PASSWORD_VALUE
# No changes needed to existing workflows
```

### Multiple Repos

Store secrets in one repo, use lockbox in another:

```bash
# Repo A: where secrets are stored
cd repo-a
gh lockbox store shared-api-key

# Repo B: different repo, can recover if you have access
cd repo-b
# Can't use lockbox here (different repo)
# But could copy workflow file and adapt it
```

**Note**: Currently gh-lockbox works per-repo. Multi-repo support planned for future version.

### Scripting

Use in scripts for automation:

```bash
#!/bin/bash
set -e

# Recover multiple secrets
DB_PASSWORD=$(gh lockbox recover db-password)
API_KEY=$(gh lockbox recover api-key)
DEPLOY_KEY=$(gh lockbox recover deploy-key)

# Use them
psql "postgresql://user:$DB_PASSWORD@localhost/db"
curl -H "Authorization: Bearer $API_KEY" https://api.example.com
ssh-add <(echo "$DEPLOY_KEY")
```

## Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| `store <name>` | Store a secret | `gh lockbox store api-key` |
| `recover <name>` | Recover a secret | `gh lockbox recover api-key` |
| `list` | List all secrets | `gh lockbox list` |
| `remove <name>` | Remove a secret | `gh lockbox remove api-key` |
| `cleanup-gists` | Cleanup recovery gists | `gh lockbox cleanup-gists` |
| `verify` | Run tests | `gh lockbox verify` |
| `help` | Show help | `gh lockbox help` |
| `version` | Show version | `gh lockbox version` |

## More Information

- **GitHub**: https://github.com/ahoward/gh-lockbox
- **README**: Full overview and quick start
- **PROPOSAL-GIST-RECOVERY.md**: Architecture details
- **SECURITY-v2.md**: Security model and threat analysis
- **CHANGELOG.md**: Version history
