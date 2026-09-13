# Security Policy

## Supported versions

Only the latest release receives security fixes.

| Version | Supported |
| ------- | --------- |
| 1.2.x   | Yes       |
| < 1.2   | No        |

## Reporting a vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Use GitHub private vulnerability reporting instead:
[Report a vulnerability](https://github.com/jangisaac-dev/apple-vision-ocr-cli/security/advisories/new)

If that form is unavailable, open an issue that only asks for a private contact, without any vulnerability details.

Include:

- the affected version (`apple-vision-ocr --version`) and macOS version;
- steps to reproduce, with a sample PDF if possible;
- the impact you expect.

The maintainer will respond as soon as possible. Once a fix is released, the report will be credited unless you ask otherwise.

## Scope notes

VOCR runs locally. PDFs are processed on the machine with Apple Vision and are not uploaded anywhere. The release app is ad-hoc signed and not notarized, and the installer removes the quarantine attribute from the installed copy; verify the SHA-256 file published with each release before installing.
