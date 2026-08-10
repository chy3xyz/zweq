# Security Policy

zweq handles credentials, wallet balances and WeChat callback endpoints — security
is taken seriously. If you believe you have found a security vulnerability, please
report it responsibly.

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.** Please email
the maintainers directly (address listed in the repository profile / latest release)
or use the GitHub "Report a vulnerability" private advisory flow
(Security → Advisories → New draft security advisory).

Please include:

- A description of the vulnerability and its impact
- The affected version / commit
- Steps to reproduce (or a minimal proof of concept)
- Any suggested fix, if you have one

We aim to acknowledge reports within **3 business days** and to ship a fix as soon
as a verified reproduction is available. We will credit researchers (if requested)
once a fix is released.

## Scope

In scope:

- Authentication / authorization bypass (including multi-tenant row isolation)
- WeChat callback signature / AES verification bypass
- WeChat Pay v3 notify verification, idempotency, or fund-flow manipulation
- Secret handling (JWT secret, AI master key, SMTP credentials)
- Injection (SQL, header, path traversal on uploads)
- DoS on public endpoints (auth rate limiting, `/metrics`, `/wx/{token}`)

Out of scope (please follow responsible disclosure to the relevant party):

- Vulnerabilities in third-party dependencies (zigmodu, zent, zwechat, zhttp,
  Node.js ecosystem)
- Issues requiring physical access or already-known misconfiguration

## Security model highlights

- **Secrets fail closed**: production requires explicit `ZWEQ_JWT_SECRET` and
  `ZWEQ_AI_KEY_SECRET`; missing config rejects rather than degrades.
- **Multi-tenancy**: physical `app_id` column isolation; tenant rides in the JWT
  `aud` claim; admin checks hit the database, not just the JWT.
- **Pay v3 notify**: verified against the WeChat platform certificate
  (RSA-SHA256) and decrypted with AES-256-GCM; credit is idempotent.
- **Callback endpoints**: WeChat signature verification + AES safe mode supported.
- **At-rest encryption**: AI provider keys encrypted with AES-256-GCM.
- **Credential versioning**: password change revokes previously issued JWTs.

## Supported versions

| Version | Supported |
| --- | --- |
| latest `main` | ✅ |
| latest release tag | ✅ |
| older releases | ❌ — upgrade to the latest release |

## Disclosure

Once fixed, we will publish a security advisory and tag the affected version
ranges. If you reported the issue, you may choose to be credited in the advisory.
