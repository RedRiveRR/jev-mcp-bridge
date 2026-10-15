# Security Policy

## Reporting a concern

Do not publish API keys, credentials, exploit details, or private user data in a public issue. Contact the repository owner privately through GitHub to coordinate a report. Do not assume this project has a dedicated security response SLA.

## Handling secrets

- Keep `OPENCODE_API_KEY` in the environment; never commit it.
- Never send API keys, `.env` contents, authentication headers, customer data, or complete private repositories to Jev.
- Treat Jev output as decision support, not as proof that a change is secure or insecure.
- The bridge currently stores no submitted code or API response to disk by design; the API provider's own data handling terms still apply.
