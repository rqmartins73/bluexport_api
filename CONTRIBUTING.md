# Contributing to bluexport_api

First off, thank you for considering contributing to bluexport_api! It's people like you that make this tool better for everyone working with IBM Cloud PowerVS.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Style Guidelines](#style-guidelines)
  - [Bash Style Guide](#bash-style-guide)
  - [Commit Messages](#commit-messages)
- [Testing](#testing)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to ricardo.martins@bluechip.pt.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (sanitized logs, command output)
- **Describe the behavior you observed** and what you expected
- **Include your environment details**:
  - OS version
  - Bash version (`bash --version`)
  - jq version (`jq --version`)
  - IBM Cloud PowerVS region
  - Script version

**Template for Bug Reports:**

```markdown
## Description
[Clear description of the bug]

## Steps to Reproduce
1. Run command: `./bluexport_api.sh ...`
2. Observe error: ...

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Environment
- OS: [e.g., RHEL 8.5, IBM i 7.5]
- Bash: [version]
- jq: [version]
- Script version: [version]

## Logs
[Sanitized relevant log excerpts]
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear and descriptive title**
- **Provide a detailed description** of the suggested enhancement
- **Explain why this enhancement would be useful** to most users
- **List any alternative solutions** you've considered

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our style guidelines
3. **Test your changes** thoroughly
4. **Update documentation** if needed
5. **Ensure your code follows** the existing patterns
6. **Write clear commit messages**
7. **Submit a pull request**

**Pull Request Process:**

1. Update the README.md with details of changes if applicable
2. Update the CHANGELOG.md following the existing format
3. Ensure all sensitive information is removed (API keys, IPs, etc.)
4. The PR will be merged once you have approval from a maintainer

## Development Setup

### Prerequisites

```bash
# Required tools
bash --version  # 5.x or higher
jq --version    # 1.7 or higher
curl --version  # Any recent version

# IBM Cloud access
# - Valid IBM Cloud API key
# - PowerVS workspace access
```

### Local Development

1. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/bluexport_api.git
   cd bluexport_api
   ```

2. **Create a test configuration:**
   ```bash
   # Use a separate config for testing
   ./bluexscrt_config_api.sh -createconfig
   # Save as bluexscrt_test.json
   ```

3. **Test your changes:**
   ```bash
   # Always test with non-production resources
   ./bluexport_api.sh -chscrt ~/bluexscrt_test.json
   ./bluexport_api.sh -v  # Verify version
   ```

## Style Guidelines

### Bash Style Guide

Follow these conventions to maintain code consistency:

**General:**
- Use tabs for indentation (existing codebase standard)
- Maximum line length: 120 characters
- Use meaningful variable names
- Add comments for complex logic

**Variables:**
```bash
# Use lowercase with underscores for local variables
local my_variable="value"

# Use UPPERCASE for constants and environment variables
readonly API_ENDPOINT="https://api.example.com"

# Quote all variable expansions
echo "${my_variable}"
```

**Functions:**
```bash
# Function names: lowercase with underscores
# Add description comments
function my_function() {
    local param1="$1"
    local param2="$2"
    
    # Function logic here
    echo "Result"
}
```

**Error Handling:**
```bash
# Always check command success
if ! command_that_might_fail; then
    echo "Error: Command failed" >&2
    return 1
fi

# Use meaningful error messages
if [[ ! -f "$config_file" ]]; then
    echo "Error: Configuration file not found: ${config_file}" >&2
    exit 1
fi
```

**API Calls:**
```bash
# Store responses for error checking
response=$(curl -s -X GET "${api_url}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json")

# Check for errors
if [[ $? -ne 0 ]]; then
    echo "Error: API call failed" >&2
    return 1
fi
```

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(snapshots): add support for snapshot scheduling

Add ability to schedule automatic snapshots with cron-like syntax.
Includes validation and error handling for invalid schedules.

Closes #123

---

fix(grs): handle rate limiting in GRS operations

Add exponential backoff when API returns 429 status.
Prevents script failures during high-frequency operations.

Fixes #456

---

docs(readme): update installation instructions

Clarify prerequisites and add troubleshooting section.
```

## Testing

### Manual Testing Checklist

Before submitting a PR, test the following:

- [ ] Script runs without syntax errors (`bash -n bluexport_api.sh`)
- [ ] Help output is correct (`./bluexport_api.sh -h`)
- [ ] Version output is correct (`./bluexport_api.sh -v`)
- [ ] Configuration file validation works
- [ ] Error messages are clear and helpful
- [ ] Logs are written correctly
- [ ] No sensitive data in output or logs

### Test in Safe Environment

**Always test with:**
- Non-production workspaces
- Test VSIs that can be safely modified
- Separate configuration files
- Verbose logging enabled

**Never test with:**
- Production systems
- Critical workspaces
- Shared credentials
- Real customer data

### Sanitizing Logs

When sharing logs or examples:

```bash
# Remove sensitive information
sed -i 's/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}/REDACTED-UUID/g' log.txt
sed -i 's/"apikey":"[^"]*"/"apikey":"REDACTED"/g' log.txt
sed -i 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/XXX.XXX.XXX.XXX/g' log.txt
```

## Questions?

Feel free to:
- Open an issue for questions
- Contact the maintainer: ricardo.martins@bluechip.pt
- Check existing issues and discussions

## Recognition

Contributors will be recognized in:
- The project README
- Release notes
- GitHub contributors page

Thank you for contributing to bluexport_api! 🚀