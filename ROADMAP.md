# Roadmap

## Next

- Add provider-neutral decision output summaries and optional cross-provider comparison.
- Add deterministic unit tests for validation, error mapping, and response normalization without live API calls.
- Test live MCP calls for Jev and Clef-Flash on Windows/Claude Code.
- Add structured logging to stderr only, with all credentials and request bodies excluded.
- Add a configurable hard call budget/circuit breaker for each provider.

## Later

- Add further System One-compatible decision models behind explicit provider-specific tools.
- Add benchmark fixtures to compare decision agreement and calibration across providers.
- Add image-input support for Clef after tests and documented size limits.
