# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.0.x   | ✅ Yes             |
| 1.0.x   | ❌ No              |

## Reporting a Vulnerability

**DO NOT** report security vulnerabilities through public GitHub issues.

Instead, please report them via email to [security@yourdomain.com](mailto:security@yourdomain.com).

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

Please include the following information in your report:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

## Security Features

### VLESS + XTLS-Reality Protocol

- **Traffic Masking**: VPN traffic is indistinguishable from legitimate HTTPS connections
- **TLS 1.3**: Latest encryption standards
- **X25519 Key Exchange**: Elliptic curve cryptography
- **AES-256-GCM**: Military-grade encryption
- **Chrome Fingerprint**: Mimics legitimate browser traffic

### Client Security

- **DNS Leak Protection**: All DNS queries routed through VPN tunnel
- **Kill Switch**: Automatic disconnect when VPN drops
- **Hardware Keystore** (Android): Keys stored in secure hardware element
- **Keychain Storage** (iOS): Configs encrypted in Keychain
- **allowInsecure: false**: Rejects insecure connections

### Server Security

- **Rate Limiting**: 5 connections/60 seconds per IP
- **Key Rotation**: Automatic key rotation script
- **Log Rotation**: 7-day log retention
- **Systemd Auto-restart**: Automatic service recovery
- **Firewall Rules**: iptables rate limiting

## Security Update Process

1. **Vulnerability Reported**: Security team reviews and validates
2. **Impact Assessment**: Determine severity and affected versions
3. **Fix Development**: Create patch for affected versions
4. **Testing**: Verify fix doesn't break functionality
5. **Release**: Publish security update
6. **Disclosure**: Public disclosure after update is available

## Security Best Practices

### For Users

1. **Keep Software Updated**: Always use the latest version
2. **Verify Downloads**: Check file integrity before installation
3. **Use Strong Credentials**: Choose complex passwords
4. **Enable All Security Features**: DNS leak protection, Kill switch
5. **Monitor Logs**: Regularly check for suspicious activity

### For Administrators

1. **Regular Key Rotation**: Rotate server keys periodically
2. **Monitor Access Logs**: Review access patterns
3. **Update Dependencies**: Keep Xray-core updated
4. **Backup Configurations**: Regular backups of server configs
5. **Network Monitoring**: Monitor for unusual traffic patterns

## Security Checklist

### Pre-Release

- [ ] Code review completed
- [ ] Security audit performed
- [ ] Dependencies updated
- [ ] No hardcoded credentials
- [ ] Input validation implemented
- [ ] Error handling proper
- [ ] Logging appropriate
- [ ] Documentation updated

### Post-Release

- [ ] Security advisories published
- [ ] Users notified of updates
- [ ] Vulnerability database updated
- [ ] Incident response plan reviewed

## Incident Response

### 1. Detection

- Monitor security advisories
- Review user reports
- Analyze traffic patterns

### 2. Containment

- Identify affected systems
- Isolate compromised components
- Preserve evidence

### 3. Eradication

- Remove malicious code
- Patch vulnerabilities
- Update security measures

### 4. Recovery

- Restore from clean backups
- Verify system integrity
- Monitor for recurrence

### 5. Lessons Learned

- Document incident
- Update security procedures
- Share knowledge with community

## Security Contacts

- **Security Team**: security@yourdomain.com
- **PGP Key**: [Link to PGP key]
- **Bug Bounty**: Not available at this time

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Xray-core Security](https://xtls.github.io/)
