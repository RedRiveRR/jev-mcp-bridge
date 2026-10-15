# Jev MCP Bridge for Claude Code

A local MCP server that lets Claude Code call two structured-decision APIs: OpenCode Zen **`jev-1.13-free`** and Cloudflare Workers AI **Clef-Flash**. These are decision models, not general-purpose coding models: they return typed answers (`noul`, `choice`, and `score`) to questions about supplied context.

> **Status:** Initial working Windows integration. The API endpoint has been tested interactively by the maintainer, and the installer registered a user-scoped stdio MCP server. The live MCP tools should still be verified in Claude Code on the target machine. Do not interpret a Jev result as a verified finding.

## Features

- `jev_assess`: send a concise context and typed questions to Jev; receive structured `answers` and `usage`.
- `jev_code_triage`: classify a caller-supplied change/diff/test summary with Jev.
- `clef_assess`: send a concise context and typed questions to Cloudflare Clef-Flash.
- `clef_code_triage`: classify a caller-supplied change/diff/test summary with Clef-Flash.
- Request timeout and bounded retries for HTTP 429/529.
- Actionable handling of authentication, quota, validation, and server errors.
- Fixed model ID `jev-1.13-free`; **no automatic fallback to paid models**.
- No repository scanning or test execution by Jev. It only evaluates information supplied to the tool.
- No API keys in source code. Jev reads `OPENCODE_API_KEY`; Clef reads `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`.
- No automatic fallback between Jev, Clef, or any paid model; each tool calls only its named provider.

## Requirements

- Windows PowerShell (the installer is Windows-specific)
- Node.js 20 or newer with npm
- Claude Code CLI (`claude` command)
- An OpenCode Zen API key with access to Jev Free
- (Optional) Cloudflare account and API token with Account > Workers AI > Read permission for Clef-Flash

## Install on Windows

1. Download/clone this repository.
2. Open PowerShell in the project folder.
3. Run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\install.ps1
   ```

The installer validates Node.js and Claude Code, makes one small Jev Free API request, installs files under `%USERPROFILE%\.claude-mcp\jev-bridge`, installs npm dependencies, stores `OPENCODE_API_KEY` in the current Windows user's environment, and registers `jev-bridge` at Claude Code user scope.

The API key is not printed or written to source files. A Windows user environment variable is convenient, but it is not a dedicated secrets vault. After changing it, restart Claude Code so the process inherits the updated environment.

## Enable Cloudflare Clef-Flash (optional)

Clef-Flash is a structured decision model in the same System One family as Jev. It uses the Cloudflare Workers AI endpoint directly and does not require or use the OpenCode Zen key. Its dedicated MCP tools are `clef_assess` and `clef_code_triage`.

1. In Cloudflare, create an API token with **Account > Workers AI > Read** permission and locate your Account ID.
2. In this repository's PowerShell window, run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\configure-clef.ps1
   ```

3. Enter the Account ID and API token when prompted. The token is hidden while typing. The script makes one small live request and saves the user environment variables only if the request succeeds.
4. Update the existing local MCP installation with:

   ```powershell
   .\update-installed-mcp.ps1
   ```

5. Completely close and reopen Claude Code, then check `/mcp` for `clef_assess` and `clef_code_triage`.

The integration calls `https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/cloudflare/clef-flash` with the System One request shape. Only summaries/questions supplied by the tool are sent.

### Free quota and billing safety

Workers AI currently includes 10,000 Neurons per day at no charge, resetting at 00:00 UTC. On the Workers Free plan, usage beyond that allocation fails rather than continuing; on Workers Paid, usage above the free allocation is billed. This integration does not switch models automatically, but account-level billing still applies, so use a Free-plan account if you require a hard no-overage boundary. Monitor usage in the Cloudflare dashboard. See the [official pricing docs](https://developers.cloudflare.com/workers-ai/platform/pricing/) and [Clef-Flash model docs](https://developers.cloudflare.com/ai/models/@cf/cloudflare/clef-flash/).

## Verify

Close and reopen Claude Code. In Claude Code, run:

```text
/mcp
```

Or check from PowerShell:

```powershell
claude mcp list
claude mcp get jev-bridge --scope user
```

The server should expose `jev_assess` and `jev_code_triage`; after enabling Clef, it should also expose `clef_assess` and `clef_code_triage`. Registration/connection alone does not prove each tool call works; ask Claude Code to invoke the tools and inspect their actual responses.

## Example prompts

### `jev_assess`

Ask Claude Code:

> Call `jev_assess` with a concise change summary as `state` and the following `questions_json`: `{"security_risk":{"type":"noul","instructions":"Does the supplied summary indicate a plausible security risk?"},"priority":{"type":"choice","instructions":"Choose a review priority.","criteria":{"low":"Low impact","medium":"Moderate impact","high":"High impact or security-sensitive"}}}`. Do not send secrets. Show the actual structured answer and token usage.

The `questions_json` input is a JSON-encoded object; each question requires `type` and `instructions`. `choice` questions require a `criteria` object. `score` questions require at least two criteria.

### `jev_code_triage`

Ask Claude Code to use the tool with:
- `change_summary`: a short description of the change
- `files_or_diff_summary`: relevant filenames and a concise diff summary
- `test_results`: tests actually run and their real results, or a clear note that tests were not run

Do not claim Jev inspected files or ran tests. It only receives these summaries.

## Run live API smoke tests

After setting `OPENCODE_API_KEY` in the current PowerShell environment, run:

```powershell
npm install
npm run test:api
```

This test sends one small request and consumes Jev Free quota. Do not run it automatically in CI. After configuring Cloudflare, use `npm run test:clef-api` to send one small Clef-Flash request, which consumes part of the daily Workers AI Neuron allocation.

## Publish this project to your own GitHub account

If Git, Node.js/npm, and [GitHub CLI](https://cli.github.com/) are installed and `gh auth login` is complete, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\publish.ps1
```

The publisher defaults to a **private** repository, pins the current npm dependency versions, runs syntax checks, rejects common secret/credential file patterns, creates an initial Git commit, creates the GitHub repository, and pushes `main`. If you choose public visibility, it asks for an explicit confirmation. No license is included yet; choose a license before public redistribution.

## Uninstall from Claude Code

```powershell
claude mcp remove jev-bridge --scope user
Remove-Item -Recurse -Force "$HOME\.claude-mcp\jev-bridge"
```

To remove the persisted API key from the Windows user environment:

```powershell
[Environment]::SetEnvironmentVariable('OPENCODE_API_KEY', $null, 'User')
Remove-Item Env:OPENCODE_API_KEY -ErrorAction SilentlyContinue
```

## Privacy and limitations

- OpenCode Zen controls Jev Free availability and usage limits; Cloudflare controls Clef-Flash model availability, free Neuron allocation, and billing.
- Only supplied summaries/questions are sent. Never send credentials, `.env` contents, customer data, or complete private repositories.
- Jev answers are decision-support signals—not proof of a security vulnerability, code correctness, or release readiness.
- The current project has limited automated coverage. Check the repository's CI result and make a real MCP call before relying on an integration change.
- No license is included at this stage. Public visibility does not itself grant others a license to reuse the code.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), and [`ROADMAP.md`](ROADMAP.md) before making larger changes.
