# Jev MCP Bridge for Claude Code

A local MCP server that lets Claude Code call OpenCode Zen's **`jev-1.13-free`** structured-decision API. Jev is not a general-purpose coding model: it returns typed answers (`noul`, `choice`, and `score`) to questions about supplied context.

> **Status:** Initial working Windows integration. The API endpoint has been tested interactively by the maintainer, and the installer registered a user-scoped stdio MCP server. The live MCP tools should still be verified in Claude Code on the target machine. Do not interpret a Jev result as a verified finding.

## Features

- `jev_assess`: send a concise context and typed questions to Jev; receive structured `answers` and `usage`.
- `jev_code_triage`: classify a caller-supplied change/diff/test summary by review priority, possible security concern, regression concern, and need for human review.
- Request timeout and bounded retries for HTTP 429/529.
- Actionable handling of authentication, quota, validation, and server errors.
- Fixed model ID `jev-1.13-free`; **no automatic fallback to paid models**.
- No repository scanning or test execution by Jev. It only evaluates information supplied to the tool.
- No API key in source code. The key is read from `OPENCODE_API_KEY`.

## Requirements

- Windows PowerShell (the installer is Windows-specific)
- Node.js 20 or newer with npm
- Claude Code CLI (`claude` command)
- An OpenCode Zen API key with access to Jev Free

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

The server should expose `jev_assess` and `jev_code_triage`. Registration/connection alone does not prove each tool call works; ask Claude Code to invoke both tools and inspect their actual responses.

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

## Run a live API smoke test

After setting `OPENCODE_API_KEY` in the current PowerShell environment, run:

```powershell
npm install
npm run test:api
```

This test sends one small request and consumes Jev Free quota. Do not run it automatically in CI.

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

- OpenCode Zen controls Jev Free availability and usage limits; access and quotas can change.
- Only supplied summaries/questions are sent. Never send credentials, `.env` contents, customer data, or complete private repositories.
- Jev answers are decision-support signals—not proof of a security vulnerability, code correctness, or release readiness.
- The current project has limited automated coverage. Check the repository's CI result and make a real MCP call before relying on an integration change.
- No license is included at this stage. Public visibility does not itself grant others a license to reuse the code.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), and [`ROADMAP.md`](ROADMAP.md) before making larger changes.
