# Security Model

## Overview

gh-lockbox uses split-key encryption to protect secrets stored in GitHub. The security model is designed to balance convenience with security for secret recovery across devices.

## Split-Key Security

### Key Derivation

```
User's PIN (4+ chars) + Static Padding (28 bytes) = 32-byte AES Key
```

- **PIN Component**: User-provided, typically 4 digits (13.3 bits entropy)
- **Static Padding**: Hardcoded in the application (224 bits entropy)
- **Total Entropy**: 237 bits effective entropy

### Encryption Details

- **Algorithm**: AES-256-GCM
- **Mode**: Galois/Counter Mode (authenticated encryption)
- **Key Size**: 256 bits (32 bytes)
- **IV**: Randomly generated per encryption (96 bits)
- **Authentication**: Built-in auth tag via GCM mode

### Security Properties

✅ **Protected Against:**
- Workflow log exposure (only encrypted blobs visible)
- GitHub Secrets API read access (PIN still required for decryption)
- Partial compromise (need both PIN and static padding)
- Fork/clone attacks (secrets not in repository)
- Tampering (GCM authentication detects modifications)

❌ **NOT Protected Against:**
- Compromised GitHub account (attacker can read secrets)
- Compromised local machine during PIN entry
- Keyloggers capturing PIN
- Malicious workflow modifications
- Social engineering for PIN
- Brute force of 4-digit PIN (10,000 combinations)

## Static Padding

The static padding is a **permanent** part of the security model:

```ruby
STATIC_PADDING = [
  0x7a, 0x3f, 0x8c, 0x91, 0x2e, 0x5d, 0xb4, 0x67,
  0xc1, 0x4e, 0x9f, 0x23, 0x76, 0xad, 0x3c, 0x88,
  0x5b, 0xe2, 0x19, 0x6c, 0xf5, 0x42, 0xb8, 0x7d,
  0x31, 0xa6, 0x4f, 0xd9
].pack('C*').freeze
```

**⚠️ WARNING**: This padding must NEVER be changed. Changing it will make all existing encrypted secrets unrecoverable.

## Threat Model

### Trust Assumptions

You must trust:
1. **GitHub**: To properly secure GitHub Secrets
2. **GitHub Actions**: To execute workflows without exfiltration
3. **This tool**: The encryption implementation is correct
4. **Your device**: Where you enter the PIN is not compromised

### Attack Scenarios

#### Scenario 1: Workflow Logs Leaked
**Attack**: Workflow logs are exposed publicly
**Defense**: Logs only contain encrypted blobs, useless without PIN

#### Scenario 2: GitHub Account Compromised
**Attack**: Attacker gains access to your GitHub account
**Impact**: Attacker can read GitHub Secrets (encrypted value + PIN)
**Risk**: High - attacker has both components needed for decryption
**Mitigation**: Use strong GitHub authentication, enable 2FA

#### Scenario 3: Repository Forked
**Attack**: Attacker forks your repository
**Defense**: Secrets are not in repository, only workflows

#### Scenario 4: PIN Guessed
**Attack**: Brute force 4-digit PIN (10,000 attempts)
**Defense**: Limited - 4 digits are weak, use longer PINs
**Mitigation**: Use 6+ digit PINs or alphanumeric PINs

#### Scenario 5: Malicious Workflow
**Attack**: Someone modifies workflow to exfiltrate secrets
**Defense**: Workflow changes are visible in git history
**Mitigation**: Review workflow changes, enable branch protection

## Best Practices

### PIN Strength

- ✅ **Recommended**: 6+ digits or alphanumeric (e.g., "pass1234")
- ⚠️ **Acceptable**: 4-5 digits (e.g., "1234")
- ❌ **Avoid**: Common PINs (1234, 0000, 1111)

### Secret Hygiene

1. **Use as Backup**: gh-lockbox is best for recovery, not primary storage
2. **Rotate Regularly**: Change secrets periodically
3. **Delete Old Runs**: Clean up workflow runs after recovery
4. **Limit Secrets**: Only store secrets you need to recover across devices

### Repository Security

1. **Enable Branch Protection**: Require reviews for workflow changes
2. **Review Workflow Changes**: Carefully examine any modifications
3. **Restrict Write Access**: Limit who can modify workflows
4. **Enable Audit Logs**: Monitor access to secrets

### Recovery Security

1. **Delete Runs**: After recovery, delete the workflow run
2. **Private Recovery**: Recover secrets on trusted devices only
3. **Secure Output**: Don't leave recovered secrets in shell history
4. **Re-encrypt**: If PIN is compromised, store with new PIN

## Limitations

### Known Limitations

1. **PIN Strength**: 4-digit PINs are weak (~13 bits entropy)
2. **GitHub Trust**: Must trust GitHub to secure secrets
3. **No HSM**: Keys not stored in hardware security modules
4. **No MFA**: No multi-factor authentication for recovery
5. **No Key Rotation**: Static padding cannot be rotated

### Not Suitable For

- **Highly sensitive secrets** (use hardware security keys)
- **Compliance requirements** (PCI, HIPAA, etc.)
- **Zero-trust environments** (too many trust assumptions)
- **Production secrets** (use proper secret management)

### Suitable For

- **Personal encryption keys** (ssh keys, GPG keys)
- **Development API tokens**
- **Non-production credentials**
- **Convenience over maximum security**
- **Cross-device secret recovery**

## Comparison to Alternatives

| Solution | Security | Convenience | Use Case |
|----------|----------|-------------|----------|
| gh-lockbox | Medium | High | Personal recovery |
| Hardware keys (YubiKey) | High | Low | Maximum security |
| Password managers | High | Medium | Daily usage |
| Encrypted files | Medium | Low | Backups |
| GitHub Secrets (plain) | Medium | Medium | CI/CD |

## Disclosure Policy

If you discover a security vulnerability in gh-lockbox, please:

1. **DO NOT** open a public issue
2. Email the maintainer: [security contact]
3. Include details: description, impact, reproduction
4. Allow time for fix before public disclosure

We will:
- Acknowledge within 48 hours
- Provide fix timeline within 7 days
- Credit you in release notes (if desired)
- Notify users of critical issues

## Version History

### v0.1.0 (MVP)
- Initial implementation
- AES-256-GCM encryption
- Split-key with 4+ digit PIN
- GitHub Actions recovery

---

**Last Updated**: 2025-11-07
**Version**: 0.1.0
