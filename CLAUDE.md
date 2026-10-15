# Repository instructions for Claude Code

- Read `README.md`, `docs/ARCHITECTURE.md`, and `ROADMAP.md` before material changes.
- Preserve the fixed `jev-1.13-free` model and never add automatic paid-model fallback.
- Never commit secrets, `.env` files, API keys, authorization headers, or local user paths.
- Do not send the whole repository to Jev; only pass minimum necessary summaries.
- For meaningful alternatives, consult the configured Jev MCP tool when available, then independently evaluate evidence and constraints. Disclose when Jev was unavailable.
- Do not call live Jev endpoints in ordinary CI or unit tests; live calls consume free quota.
- Keep MCP protocol output off stdout except for MCP JSON-RPC messages.
- Run `npm run check` and relevant tests before finalizing code changes.
- Never represent Jev output as proof of a vulnerability, code correctness, or test execution.
