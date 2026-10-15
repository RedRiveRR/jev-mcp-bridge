# Architecture

## Components

- `src/index.mjs`: MCP stdio server, shared input validation, Jev and Cloudflare Clef-Flash request handling, error mapping, and tool registration.
- `scripts/test-api.mjs` and `scripts/test-clef-api.mjs`: opt-in live API smoke tests for each provider.
- `configure-clef.ps1`: securely prompts for Cloudflare account settings, tests access, then persists user environment variables.
- `update-installed-mcp.ps1`: updates the already registered user-scoped MCP implementation without re-registering it.
- `install.ps1`: Windows installer that validates Node.js/Claude Code, tests Jev access, installs the bridge under the user profile, persists `OPENCODE_API_KEY` in the Windows user environment, and registers a user-scoped MCP server.

## Request flow

1. Claude Code calls one of the provider-specific assessment/triage tools over MCP stdio.
2. The bridge validates request fields and limits input sizes.
3. Jev tools call `https://opencode.ai/zen/v1/systemone` using the fixed `jev-1.13-free` model; Clef tools call the Cloudflare Workers AI endpoint for `@cf/cloudflare/clef-flash`.
4. The bridge returns structured `answers` and available usage metadata to Claude Code. Each tool uses only its named provider; there is no automatic provider or paid-model fallback.

## Safety boundaries

- The bridge does not read the current repository or run tests on its own.
- `jev_code_triage` assesses only the change and test summaries provided by its caller.
- No paid model fallback is configured.
- Jev credentials are read from `OPENCODE_API_KEY`; Cloudflare credentials are read from `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. They must never be committed or included in request state.
- Jev's structured outputs are decision-support signals, not authoritative security findings.
- MCP protocol messages use stdout; diagnostic logs must not be added to stdout.

## Known limitations

- OpenCode Zen controls Jev availability/free-use limits. Cloudflare Workers AI has a 10,000 Neuron/day free allocation; usage beyond it fails on Free plan but can be billed on Workers Paid.
- A successful HTTP/MCP response does not guarantee a correct or calibrated assessment.
- The installer stores the key in the Windows user environment. This is convenient but is not a dedicated secrets vault.
