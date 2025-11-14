# gh-lockbox

Store secrets in GitHub Secrets. Recover them anywhere with the `gh` CLI. No master keys to manage, no files to sync, no servers to run.

**The problem it solves:** You need secrets on multiple machines. Every encryption tool requires managing a master key file (`.sekrets.key`, `master.key`, etc.). gh-lockbox uses GitHub Actions as an ephemeral encryption service - generate temporary keys per recovery, use them once, delete them. The "key" is your GitHub authentication, which you already have.

```bash
# Store a secret
gh-lockbox store api-key

# Recover it on any machine
gh-lockbox recover api-key

# Sync all secrets to .env file
gh-lockbox dotenv pull
```

---

## Quick Start

**1. Install**

```bash
# Try it first
git clone https://github.com/ahoward/gh-lockbox.git
cd gh-lockbox
./bin/gh-lockbox verify    # runs tests, ~10 seconds

# Install as gh extension
gh extension install ahoward/gh-lockbox
```

**Requirements:** `gh` CLI (authenticated), Ruby 2.7+, GitHub repo with Actions enabled.

**2. Store your first secret**

```bash
# Navigate to any GitHub repo
cd your-project

# Store a secret
gh-lockbox store api-key
# (prompts for value, stores in GitHub Secrets as API_KEY)
```

What just happened:
- Your secret → GitHub Secrets (encrypted at rest by GitHub)
- A recovery workflow was created at `.github/workflows/lockbox-api-key.yml`
- The workflow was committed and pushed

**3. Recover it**

```bash
# On the same machine, or any other machine with gh CLI
gh-lockbox recover api-key
# (triggers workflow, downloads encrypted secret, decrypts, outputs value)
```

What just happened:
- Generated ephemeral RSA-2048 keypair locally
- Created temporary branch `lockbox-recovery-{timestamp}`
- Triggered workflow with public key
- Workflow encrypted secret with RSA + AES-256-GCM
- Downloaded encrypted artifact, decrypted with private key
- Deleted private key and temporary branch

**4. Use in CI/CD**

Your secrets are normal GitHub Secrets, so they work in workflows immediately:

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - env:
          API_KEY: ${{ secrets.API_KEY }}
        run: ./deploy.sh
```

That's the basic workflow. Now let's understand the concepts.

---

## Understanding gh-lockbox

### Concept 1: Secrets are stored as GitHub Secrets

When you run `gh-lockbox store api-key`, two things happen:

1. The secret value is stored in GitHub Secrets (same as `gh secret set API_KEY`)
2. A recovery workflow file is created and committed to your repo

This means:
- ✅ Secrets work immediately in CI/CD
- ✅ Secrets are encrypted at rest by GitHub
- ✅ No special prefix or wrapper needed

### Concept 2: Recovery uses ephemeral keys

The problem with traditional encrypted config: where do you store the decryption key?

gh-lockbox's approach:
1. Generate RSA keypair **locally** when you run `recover`
2. Send public key to GitHub Actions workflow
3. Workflow encrypts secret with your public key
4. Download encrypted artifact, decrypt with private key
5. Delete private key immediately

The private key exists for ~30 seconds and never leaves your machine. No key management needed.

### Concept 3: Secret name normalization

GitHub requires secret names be `UPPERCASE_WITH_UNDERSCORES`. gh-lockbox normalizes automatically:

```bash
gh-lockbox store api-key        # → secrets.API_KEY
gh-lockbox store my.db.password # → secrets.MY_DB_PASSWORD
gh-lockbox store STRIPE_TOKEN   # → secrets.STRIPE_TOKEN
```

When recovering, use either form:
```bash
gh-lockbox recover api-key       # works
gh-lockbox recover API_KEY       # also works
```

### Concept 4: Recovery works with ANY GitHub Secret

You don't need to use `gh-lockbox store` first. If you already have secrets in your repo (created via `gh secret set`, GitHub UI, Terraform, etc.), you can recover them:

```bash
# Recover a secret you created through GitHub UI
gh-lockbox recover DATABASE_PASSWORD

# Recover ALL secrets as JSON
gh-lockbox recover

# Sync all secrets to .env file
gh-lockbox dotenv pull
```

This makes gh-lockbox useful for:
- Bootstrapping new laptops from existing repos
- Onboarding new team members
- Recovering forgotten production secrets (then rotating them!)
- Migrating secrets from GitHub to other tools

---

## Practical Workflows

### New laptop bootstrap

```bash
# Clone your dotfiles repo
git clone git@github.com:yourname/dotfiles.git && cd dotfiles

# Recover all secrets to .env
gh-lockbox dotenv pull
# ✓ Appended 15 secrets to .env

# Source them
export $(cat .env | xargs)

# Or recover specific secrets
gh-lockbox recover ssh-key > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa
gh-lockbox recover gpg-key | gpg --import
```

### Team onboarding

```bash
# New developer joins, clones repo
git clone git@github.com:yourorg/api-service.git && cd api-service

# Get all secrets needed for development
gh-lockbox dotenv pull
# ✓ Appended 21 secrets to .env

# Start developing
npm run dev  # uses .env automatically
```

### CI/CD integration

Secrets stored with gh-lockbox are normal GitHub Secrets:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          API_KEY: ${{ secrets.API_KEY }}
        run: npm test
```

No special gh-lockbox integration needed in CI/CD.

### .env file bidirectional sync

```bash
# Pull secrets from GitHub → .env file
gh-lockbox dotenv pull
# ✓ Appended 21 secrets to .env

# Edit .env file locally
echo "NEW_API_KEY=sk_live_xyz123" >> .env
vim .env  # make changes

# Push changes back to GitHub
gh-lockbox dotenv push
# ✓ Pushed 22 secrets to GitHub

# Now available in CI/CD immediately
```

The `dotenv pull` command **appends** to your .env file with clear comment markers - it never clobbers existing content.

### Emergency secret recovery

```bash
# Production database password is lost
gh-lockbox recover PROD_DB_PASSWORD
# → outputs the password

# Important: Rotate it immediately after recovery!
```

---

## Command Reference

```bash
# Store secrets
gh-lockbox store <name> [value]    # Store secret (prompts if no value)

# Recover secrets
gh-lockbox recover [name...]       # Recover one or more secrets
gh-lockbox recover                 # Recover ALL secrets as JSON

# .env file sync
gh-lockbox dotenv pull [file]      # Pull all secrets to .env (default: .env)
gh-lockbox dotenv push [file]      # Push .env secrets to GitHub
gh-lockbox dotenvx pull [file]     # Same as dotenv, ensures dotenvx installed
gh-lockbox dotenvx push [file]     # Same as dotenv push

# Management
gh-lockbox list                    # List all secret names
gh-lockbox remove <name>           # Delete secret from GitHub

# Maintenance
gh-lockbox cleanup                 # Clean up temporary files
gh-lockbox verify                  # Run test suite
gh-lockbox help                    # Show help
```

### Examples

```bash
# Store with prompt
gh-lockbox store stripe-key
# Enter secret value: sk_live_abc123xyz
# ✓ Stored: STRIPE_KEY

# Store from stdin
echo "secret_value" | gh-lockbox store api-key

# Recover to variable
export API_KEY=$(gh-lockbox recover api-key)

# Recover multiple
gh-lockbox recover api-key db-password stripe-key

# Recover all as JSON
gh-lockbox recover > secrets.json
jq -r '.API_KEY' secrets.json

# List all secrets
gh-lockbox list

# Remove a secret
gh-lockbox remove api-key

# Sync to custom .env file
gh-lockbox dotenv pull .env.production
gh-lockbox dotenv push .env.local
```

---

## How It Works (Technical Details)

### Store Phase

```
1. User runs: gh-lockbox store api-key
2. User enters secret value
3. Secret stored in GitHub Secrets as: API_KEY
4. Recovery workflow created: .github/workflows/lockbox-api-key.yml
5. Workflow committed and pushed
```

The secret is stored as plaintext in GitHub Secrets (encrypted at rest by GitHub). This is intentional - it makes secrets work immediately in CI/CD without any special handling.

### Recovery Phase

```
1. User runs: gh-lockbox recover api-key
2. Acquire distributed lock (prevents concurrent recovery conflicts)
3. Generate ephemeral RSA-2048 keypair locally
4. Create temporary branch: lockbox-recovery-{timestamp}
5. Commit recovery workflow to branch
6. Push branch, trigger workflow with public key as input
7. Workflow runs:
   - Reads secret from: secrets.API_KEY
   - Generates random AES-256-GCM session key
   - Encrypts session key with RSA public key
   - Encrypts secret value with session key
   - Commits encrypted JSON to branch
8. Download encrypted JSON from branch
9. Decrypt session key with RSA private key
10. Decrypt secret value with session key
11. Output secret value
12. Delete private key, delete branch, release lock
```

### Why Git Commits Instead of Artifacts?

Early versions used GitHub Actions artifacts (blob storage). This had race conditions due to eventual consistency - the artifact might not be ready when the client tried to download it.

Using git commits eliminates this entirely:
- Commits are immediately consistent
- Built-in cleanup (delete branch = delete all recovery data)
- Natural isolation (branch per recovery = no conflicts)
- No timing windows or retry logic needed

### Cryptography

**Hybrid encryption (RSA + AES):**
- RSA-2048 keypair generated locally per recovery
- AES-256-GCM session key generated by workflow
- Session key encrypted with RSA public key
- Secret value encrypted with AES-256-GCM
- AES-256-GCM provides authenticated encryption (tamper detection)

**Key lifetime:**
- Private key: ~30 seconds (generation → decryption → deletion)
- Public key: sent to workflow, never reused
- Session key: generated per recovery, never reused

**Brute force resistance:**
- RSA-2048: ~2^2048 possible keys (~10^617 years to crack)
- AES-256-GCM: 2^256 possible keys
- These are industry-standard security levels

### Concurrency Control

Multiple simultaneous recoveries could conflict on the same branch. gh-lockbox uses git-based distributed locking:

```
1. Try to create lock branch: lockbox-lock-{secret-name}
2. If creation succeeds → acquired lock
3. If creation fails (branch exists) → wait and retry
4. Perform recovery
5. Delete lock branch → release lock
```

This prevents race conditions without requiring any external coordination service.

---

## Security Model

**Threat Model: Development secrets and CI/CD**

gh-lockbox is designed for:
- Personal encryption keys, SSH keys, GPG keys
- Development API tokens and credentials
- Team shared secrets (non-production)
- Cross-device secret recovery
- CI/CD secrets

gh-lockbox is **NOT** designed for:
- PCI/HIPAA compliance requiring hardware HSMs
- Production secrets requiring sub-second rotation
- Airgapped environments
- Organizations with "no GitHub dependencies" policies

### What's Protected

✅ **Secrets at rest**: Encrypted by GitHub (AES-256)
✅ **Secrets in transit**: TLS (GitHub's infrastructure)
✅ **Recovery confidentiality**: Hybrid encryption (RSA-2048 + AES-256-GCM)
✅ **Fork attacks**: Secrets not in repo, recovery requires repo access
✅ **Concurrent recovery**: Distributed locking prevents conflicts

### What's NOT Protected

❌ **Compromised GitHub account**: Attacker can read secrets directly via GitHub API
❌ **Malicious workflow modification**: Use branch protection + CODEOWNERS
❌ **Active recovery interception**: Requires compromised account during ~30s window
❌ **Workflow logs**: Contain encrypted blobs (not a vulnerability - they're encrypted)

### Security Best Practices

**Use branch protection:**
```yaml
# .github/CODEOWNERS
.github/workflows/lockbox-*.yml @your-security-team
```

Require reviews for workflow changes. This prevents unauthorized workflow modifications.

**Audit workflow runs:**
GitHub provides audit logs for all workflow runs. Monitor for unexpected recovery operations.

**Rotate recovered secrets:**
If you recover a production secret in an emergency, rotate it immediately after.

**Don't commit .env files:**
Add to `.gitignore`:
```
.env
.env.local
.env.*.local
```

---

## Comparison with Other Tools

### vs. `gh secret set`

GitHub's native CLI can store secrets but not read them back:
```bash
gh secret set API_KEY    # ✅ Store
gh secret get API_KEY    # ❌ Not supported
```

gh-lockbox makes secrets recoverable while keeping them usable in CI/CD.

### vs. Encrypted files in repo (sekrets, senv, Rails credentials)

Traditional approach:
```bash
# Store encrypted config in repo
sekrets edit config/secrets.yml.enc

# Problem: Need .sekrets.key file on every machine
# Solution: Store .sekrets.key in... wait, where?
```

gh-lockbox eliminates the key management problem by using ephemeral keys.

### vs. Password managers (1Password, LastPass, Bitwarden)

Password managers are great for personal passwords. Use them!

gh-lockbox is for secrets that live in code repositories:
- Needed by multiple developers
- Used in CI/CD
- Tied to project lifecycle

Many teams use both: password manager for personal credentials, gh-lockbox for shared project secrets.

### vs. Secret management services (Vault, AWS Secrets Manager)

These are enterprise solutions with enterprise complexity:
- Vault: Requires running servers, databases, unsealing ceremonies
- AWS Secrets Manager: $0.40/secret/month + API charges

gh-lockbox is for smaller teams who need:
- Zero infrastructure
- Zero ongoing costs
- Simplicity over enterprise features

**Until your IPO:** Use gh-lockbox.
**After your IPO:** You'll have a security team to run Vault.

---

## Advanced Usage

### Multi-environment secrets

Use separate repos or branches:

```bash
# Development secrets
cd ~/dev/myapp-dev
gh-lockbox dotenv pull .env.development

# Production secrets (separate repo!)
cd ~/dev/myapp-prod-secrets
gh-lockbox dotenv pull .env.production
```

### Scripted secret access

```bash
#!/bin/bash
# Deploy script that needs secrets

cd /path/to/repo

# Get all secrets as JSON
SECRETS=$(gh-lockbox recover)

# Extract specific values
API_KEY=$(echo "$SECRETS" | jq -r '.API_KEY')
DB_URL=$(echo "$SECRETS" | jq -r '.DATABASE_URL')

# Use in deployment
curl -H "Authorization: Bearer $API_KEY" ...
```

### Migrate secrets between repos

```bash
# Export from old repo
cd old-repo
gh-lockbox recover > /tmp/secrets.json

# Import to new repo
cd new-repo
jq -r 'to_entries[] | "\(.key)=\(.value)"' /tmp/secrets.json > .env
gh-lockbox dotenv push

# Clean up
rm /tmp/secrets.json
```

### Backup secrets to password manager

```bash
# Export all secrets
gh-lockbox recover > secrets-backup.json

# Import to 1Password (example)
jq -r 'to_entries[] | "\(.key)=\(.value)"' secrets-backup.json | \
while IFS='=' read -r name value; do
  op item create --category=password \
    --title="myrepo/$name" \
    --field="password=$value"
done

# Clean up
shred -u secrets-backup.json
```

---

## Troubleshooting

### "GitHub CLI (gh) is not installed"

Install gh: https://cli.github.com/

Then authenticate:
```bash
gh auth login
```

### "Not in a git repository"

gh-lockbox requires a GitHub repository:
```bash
git init
gh repo create
git push -u origin main
```

### "GitHub Actions is not enabled"

Enable Actions in your repo settings: `Settings → Actions → General → Allow all actions`

### Recovery timeout

If recovery takes >5 minutes, check:
```bash
# View workflow run status
gh run list --workflow=lockbox-recovery

# View logs
gh run view <run-id> --log
```

Common issues:
- GitHub Actions quota exceeded (check Settings → Billing)
- Workflow permissions (Settings → Actions → Workflow permissions → Read and write)

### Lock timeout

If recovery waits >60 seconds for lock:
```bash
# Check for stale locks
git branch -r | grep lockbox-lock

# Force release (only if no other recovery is running!)
git push origin --delete lockbox-lock-<secret-name>
```

### "Secret not found"

List available secrets:
```bash
gh-lockbox list
```

Remember name normalization:
```bash
gh-lockbox recover api-key    # looks for API_KEY
gh-lockbox recover API_KEY    # also looks for API_KEY
```

---

## Development

### Project Structure

```
bin/gh-lockbox              # CLI entry point (850 lines)
lib/lockbox/
  crypto.rb                 # AES-256-GCM encryption (146 lines)
  github.rb                 # GitHub API + locking (471 lines)
  workflow.rb               # Workflow management (235 lines)
  pin.rb                    # Secret input prompts (115 lines)
  util.rb                   # Utilities
templates/
  lockbox-recovery.yml      # Recovery workflow template
test/
  test_crypto.rb            # Crypto tests (19 tests)
  test_helper.rb            # Test utilities
```

### Running Tests

```bash
# Run verification suite
./bin/gh-lockbox verify

# Run unit tests
ruby test/test_crypto.rb
```

### Contributing

This project was built with AI assistance (Claude Code). The architecture and design are human-driven, implementation is AI-assisted.

For bugs or features:
1. Check existing issues: https://github.com/ahoward/gh-lockbox/issues
2. Open a new issue with reproducible example
3. PRs welcome (include tests)

---

## Philosophy

gh-lockbox continues the lineage of [sekrets](https://github.com/ahoward/sekrets) (2013) and [senv](https://github.com/ahoward/senv) (2015):

**Core principles:**
- Secrets should be in version control (encrypted)
- Sharing secrets between developers should be easy
- No cloud services, no complex infrastructure

**What gh-lockbox adds:**
- No key files to manage
- No persistent keys
- CI/CD just works
- Ultra KISS

**KISS security is REAL security.** Complex security systems that nobody uses are less secure than simple systems that everyone uses correctly.

---

## Status

**Current version:** v0.2.1

**What works:**
- ✅ Store/recover/list/remove secrets
- ✅ Git-based recovery (no blob storage race conditions)
- ✅ .env file bidirectional sync
- ✅ dotenvx support with safe append mode
- ✅ Bulk recovery (all secrets as JSON)
- ✅ Distributed locking (concurrent recovery protection)
- ✅ Automated test suite
- ✅ Zero dependencies (stdlib only)

**Known limitations:**
- Single repo only (no cross-repo secret sharing)
- Recovery takes 10-30 seconds (GitHub Actions startup time)
- Requires git push rights (necessary for recovery workflow)

**Roadmap:**
- Multi-repo support
- Team secrets with role-based access
- See [PROPOSAL-GIST-RECOVERY.md](PROPOSAL-GIST-RECOVERY.md) for detailed plans

---

## License

MIT

---

## Credits

Built by [@ahoward](https://github.com/ahoward) with AI assistance (Claude Code).

Standing on the shoulders of giants:
- [sekrets](https://github.com/ahoward/sekrets) - The original encrypted config tool (2013)
- [senv](https://github.com/ahoward/senv) - Encrypted environment variables (2015)
- [pbj](https://github.com/ahoward/pbj) - Universal clipboard, inspiration for this project

Born at [dojo4](https://classic.dojo4.com/) where these ideas were first explored.

Mostly written by robots. Slightly guided by humans.

---

**Your secrets, locked tight. GitHub Actions does the work. No keys to lose.**

_Rolled at [nickel5](https://nickel5.com/). Built with Claude Code._
