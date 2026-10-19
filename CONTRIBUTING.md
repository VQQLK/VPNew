# Contributing to MyVPN

Thank you for your interest in contributing to MyVPN! This document provides guidelines and information for contributors.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Create a new issue with:
   - Clear title describing the bug
   - Steps to reproduce
   - Expected vs actual behavior
   - Platform and version information
   - Logs (if available)

### Suggesting Features

1. Check existing feature requests
2. Create a new issue with:
   - Clear title and description
   - Use case and benefits
   - Implementation suggestions (optional)

### Code Contributions

1. Fork the repository
2. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes
4. Test thoroughly
5. Commit with clear messages:
   ```bash
   git commit -m "feat: add new feature description"
   ```
6. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
7. Create a Pull Request

## Development Setup

### Prerequisites

- **Server**: Bash, curl, openssl
- **Android**: Android Studio, JDK 17, Android SDK 34
- **iOS**: Xcode 15+, Apple Developer Program
- **macOS**: Xcode 15+, Homebrew
- **Windows**: .NET 8 SDK, Visual Studio 2022

### Building

```bash
# Android
cd AC_MyVPN_android_20260612
./gradlew assembleDebug

# Windows
cd AC_MyVPN_windows_20260612/src
dotnet build

# macOS
cd AC_MyVPN_macos_20260612
xcodebuild -scheme MyVPN

# Server (no build needed)
chmod +x AC_MyVPN_server_20260612/setup_xray.sh
```

## Code Style

### Kotlin (Android)

- Follow Kotlin coding conventions
- Use meaningful variable names
- Add KDoc comments for public functions
- Keep functions focused and short

### Swift (iOS/macOS)

- Follow Swift style guide
- Use proper naming conventions
- Add documentation comments
- Handle errors properly

### C# (Windows)

- Follow Microsoft coding conventions
- Use proper naming conventions
- Add XML documentation comments
- Handle exceptions appropriately

### Bash (Server)

- Use shellcheck for linting
- Add comments for complex logic
- Handle errors with `set -e`
- Use proper quoting

## Testing

### Manual Testing

1. **Server**: Test installation on clean Ubuntu system
2. **Android**: Test on Android 8.0+ devices
3. **iOS**: Test on iOS 16+ devices
4. **macOS**: Test on macOS 13+ systems
5. **Windows**: Test on Windows 10+ systems

### Test Cases

- [ ] Server installation completes successfully
- [ ] Client connects to server
- [ ] VPN tunnel establishes correctly
- [ ] DNS queries go through tunnel
- [ ] Kill switch activates on disconnect
- [ ] Configuration import works
- [ ] UI updates correctly

## Security

### Reporting Security Issues

**DO NOT** report security vulnerabilities through public GitHub issues.

Instead, please report them via email to [security@yourdomain.com](mailto:security@yourdomain.com).

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Security Guidelines

- Never commit sensitive data (keys, passwords, tokens)
- Use environment variables for secrets
- Validate all user inputs
- Follow secure coding practices
- Review code for vulnerabilities before submitting

## Pull Request Guidelines

### Before Submitting

1. **Code Review**: Self-review your changes
2. **Testing**: Test on all applicable platforms
3. **Documentation**: Update documentation if needed
4. **Changelog**: Add entry to CHANGELOG.md

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tested on Android
- [ ] Tested on iOS
- [ ] Tested on macOS
- [ ] Tested on Windows
- [ ] Tested on Server

## Checklist
- [ ] Code follows project style
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No sensitive data committed
```

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Code of Conduct

### Our Pledge

We pledge to make participation in our project a harassment-free experience for everyone.

### Our Standards

Examples of behavior that contributes to creating a positive environment:

- Using welcoming and inclusive language
- Being respectful of differing viewpoints and experiences
- Gracefully accepting constructive criticism
- Focusing on what is best for the community

### Enforcement

Project maintainers are responsible for clarifying the standards of acceptable behavior and will take appropriate and fair corrective action in response to any instances of unacceptable behavior.

## Questions?

If you have questions about contributing, please open an issue or contact the maintainers.
