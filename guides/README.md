# LegalDispatch API — Getting Started

> Quick guide for frontend developers, QA, and external consumers.

## Base URL

| Environment | URL                                     |
| ----------- | --------------------------------------- |
| Production  | `https://api.legaldispatch.dev`         |
| Staging     | `https://api-staging.legaldispatch.dev` |
| Development | `http://localhost:8080`                 |

## Authentication

Most endpoints require a JWT Bearer token. Obtain one by logging in:

```bash
curl -X POST https://api.legaldispatch.dev/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "..."}'
```

Then pass the token in all subsequent requests:

```
Authorization: Bearer <access_token>
```

Tokens expire — use `POST /api/v1/auth/refresh` to rotate before expiry.

## Interactive Docs

Browse the full API at **`https://api.legaldispatch.dev/docs`** — powered by Scalar UI with try-it-out support.

## Guides

- [Authentication](authentication.md) — Token lifecycle, refresh, logout
- [Error Handling](error-handling.md) — Error envelope, common error codes
- [Pagination](pagination.md) — Query parameters and response metadata
- [Rate Limiting](rate-limiting.md) — Tiers, headers, retry behavior
- [Changelog](changelog.md) — API changes across releases
