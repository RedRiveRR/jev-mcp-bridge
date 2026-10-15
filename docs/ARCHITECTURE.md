# Architecture

## Components

- `src/index.mjs`: MCP stdio server, input validation, OpenCode Zen request handling, retry/error mapping, and tool registration.
- `scripts/test-api.mjs`: opt-in live API smoke test.
- `install.ps1`: Windows installer that validates Node.js/Claude Code, tests Jev access, installs the bridge under the user profile, persists `OPENCODE_API_KEY` in the Windows user environment, and registers a user-scoped MCP server.

## Request flow

1. Claude Code calls `jev_assess` or `jev_code_triage` over MCP stdio.
2. The bridge validates request fields and limits input sizes.
3. It sends only the supplied state and typed questions to `https://opencode.ai/zen/v1/systemone` using the fixed `jev-1.13-free` model.
4. It returns structured `answers` and `usage` fields to Claude Code.

## Safety boundaries

- The bridge does not read the current repository or run tests on its own.
- `jev_code_triage` assesses only the change and test summaries provided by its caller.
- No paid model fallback is configured.
- The API key is read from `OPENCODE_API_KEY`; it must not be committed or included in request state.
- Jev's structured outputs are decision-support signals, not authoritative security findings.
- MCP protocol messages use stdout; diagnostic logs must not be added to stdout.

## Known limitations

- OpenCode Zen controls model availability and free-use limits.
- A successful HTTP/MCP response does not guarantee a correct or calibrated assessment.
- The installer stores the key in the Windows user environment. This is convenient but is not a dedicated secrets vault.
