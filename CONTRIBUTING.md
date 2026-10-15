# Contributing

Thanks for helping improve Jev MCP Bridge.

## Development setup

- Windows with PowerShell is the primary supported install target.
- Node.js 20 or newer and npm are required.
- Claude Code CLI is required to test registration end-to-end.
- An OpenCode Zen key with access to `jev-1.13-free` is needed only for live API checks.

Install dependencies and run the local checks:

```powershell
npm install
npm run check
```

For a live API smoke test, set `OPENCODE_API_KEY` in your local user environment and run:

```powershell
npm run test:api
```

The live smoke test spends a small amount of Jev Free quota. Do not run it in CI.

## Pull requests

- Describe the problem and the proposed behavior change.
- Include verification steps and test output.
- Keep API keys, `.env` files, user paths, generated logs, and private source summaries out of commits.
- Do not introduce a paid-model fallback or transmit entire repositories by default.
- Do not claim Jev's decision is proof of correctness or a substitute for code review and tests.
- Update README/docs when tool inputs, installation, behavior, or limitations change.

## Security and privacy

Never include a real API key in a pull request, test fixture, log, screenshot, or issue. Use dummy placeholders only. Report possible vulnerabilities privately to the repository owner rather than posting secrets or exploit details in a public issue.
