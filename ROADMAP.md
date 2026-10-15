# Roadmap

This is a proposed backlog, not a promise or a claim that these features are implemented.

## Reliability and tests

- Add unit tests for question validation, retry behavior, and response parsing using mocked HTTP responses.
- Add a separate integration-test command that requires an explicit opt-in and a configured API key.
- Pin dependencies with a committed lockfile and automate dependency/security updates.
- Improve diagnostics while guaranteeing that authorization headers and request secrets never appear in logs.

## MCP capabilities

- Consider configurable timeout/retry limits, with conservative defaults.
- Consider optional prompt templates for architecture comparison, implementation trade-offs, and release triage.
- Document Jev question types and expected response shapes with sanitized examples.
- Add cross-platform setup instructions if macOS/Linux support is desired.

## Distribution

- Decide on a project license before public redistribution.
- Consider tagged releases and a documented upgrade/uninstall flow.
