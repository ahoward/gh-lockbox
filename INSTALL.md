# Installation Guide

## Prerequisites

Before installing gh-lockbox, ensure you have:

1. **GitHub CLI (`gh`)** - [Install gh](https://cli.github.com/)
   ```bash
   # macOS
   brew install gh

   # Linux
   # See: https://github.com/cli/cli/blob/trunk/docs/install_linux.md

   # Windows
   # See: https://github.com/cli/cli#windows
   ```

2. **Ruby 2.7+** - Usually pre-installed on macOS/Linux
   ```bash
   ruby --version  # Should be 2.7 or higher
   ```

3. **Git repository with GitHub Actions enabled**
   - Your repository must be on GitHub
   - GitHub Actions must be enabled (default for public repos)

4. **GitHub authentication**
   ```bash
   gh auth login
   gh auth status
   ```

## Test Before Installing (Recommended!)

Try gh-lockbox without installing first:

```bash
# Clone the repository
git clone https://github.com/ahoward/gh-lockbox.git
cd gh-lockbox

# Run automated verification tests
./bin/gh-lockbox verify

# Test shows 8 steps:
# ✓ GitHub CLI authenticated
# ✓ Secret storage working
# ✓ Workflow creation working
# ✓ Encryption/decryption working
# ✓ Security validation passing
# ✓ Cleanup working

# If all tests pass, proceed with installation!
```

**Why test first?**
- Validates your environment is compatible
- Catches configuration issues early
- Builds confidence before installation
- Takes only ~10 seconds

## Installation Methods

### Method 1: Install as gh Extension (Recommended)

Once published to GitHub, install directly:

```bash
gh extension install ahoward/gh-lockbox
```

### Method 2: Install from Source (Development)

For development or testing:

```bash
# Clone the repository
git clone https://github.com/ahoward/gh-lockbox.git
cd gh-lockbox

# Install as local gh extension
gh extension install .

# Verify installation
gh lockbox version
```

### Method 3: Manual Installation

If you prefer manual setup:

```bash
# Clone the repository
git clone https://github.com/ahoward/gh-lockbox.git

# Add to PATH
export PATH="/path/to/gh-lockbox/bin:$PATH"

# Or create a symlink
ln -s /path/to/gh-lockbox/bin/gh-lockbox /usr/local/bin/gh-lockbox

# Verify
gh-lockbox version
```

## Verify Installation

After installation, verify everything works:

```bash
# Check version
gh lockbox version

# Check help
gh lockbox help

# Test gh CLI is working
gh auth status
```

## Post-Installation Setup

No additional setup required! You can start using gh-lockbox immediately:

```bash
cd /path/to/your/github/repo
gh lockbox store test-secret
```

## Upgrading

### For gh Extension Installation

```bash
gh extension upgrade lockbox
```

### For Source Installation

```bash
cd gh-lockbox
git pull origin main
```

## Uninstallation

### For gh Extension Installation

```bash
gh extension remove lockbox
```

### For Manual Installation

```bash
# Remove from PATH
# (edit your .bashrc, .zshrc, etc.)

# Or remove symlink
rm /usr/local/bin/gh-lockbox

# Delete cloned repository
rm -rf /path/to/gh-lockbox
```

## Troubleshooting

### "gh: command not found"

Install GitHub CLI first:
```bash
# macOS
brew install gh

# See https://cli.github.com/ for other platforms
```

### "ruby: command not found"

Install Ruby:
```bash
# macOS (usually pre-installed)
brew install ruby

# Linux
sudo apt-get install ruby  # Debian/Ubuntu
sudo yum install ruby      # RHEL/CentOS
```

### "Not in a GitHub repository"

Make sure you're in a git repository connected to GitHub:
```bash
git remote -v  # Should show github.com URL
gh repo view   # Should show repository info
```

### "GitHub CLI not authenticated"

Authenticate with GitHub:
```bash
gh auth login
# Follow the prompts
```

### Permission errors

Make sure the executable has correct permissions:
```bash
chmod +x bin/gh-lockbox
```

### Ruby gem dependencies

gh-lockbox only uses Ruby standard library, no gems needed!

## Platform-Specific Notes

### macOS

- Ruby is pre-installed on most macOS versions
- Use Homebrew for installing gh CLI
- Works with both Intel and Apple Silicon

### Linux

- May need to install Ruby separately
- Follow gh CLI installation for your distro
- Tested on Ubuntu 20.04+, Debian 11+

### Windows

- Requires WSL (Windows Subsystem for Linux)
- Install Ruby and gh CLI in WSL
- Not tested on native Windows (PowerShell)

## Next Steps

Once installed, check out:

- [README.md](README.md) - Quick start guide
- [USAGE.md](USAGE.md) - Detailed usage instructions
- [EXAMPLES.md](EXAMPLES.md) - Common use cases

## Support

Having installation issues?

1. Check [GitHub Issues](https://github.com/ahoward/gh-lockbox/issues)
2. Open a new issue with:
   - Your OS and version
   - Ruby version (`ruby --version`)
   - gh CLI version (`gh --version`)
   - Error messages or logs
