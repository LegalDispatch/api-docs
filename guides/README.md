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

Tokens expire after 15 minutes — use `POST /api/v1/auth/refresh` to rotate before expiry.

## Correlation ID

Include `X-Correlation-ID` in every request for distributed tracing. The API echoes it back and includes it as `request_id` in error responses.

```
X-Correlation-ID: my-request-123
```

## JSON Format

All request and response bodies use **`snake_case`** field names. All responses have `Content-Type: application/json`.

## Interactive Docs

Browse the full API at **`https://api.legaldispatch.dev/docs`** — powered by Scalar UI with try-it-out support.

## Guides

- [Authentication](authentication.md) — Token lifecycle, JWT claims, refresh, logout, API keys
- [Error Handling](error-handling.md) — Error envelope shape, all error codes by HTTP status
- [Pagination](pagination.md) — Query parameters and response metadata
- [Rate Limiting](rate-limiting.md) — IP and user tiers, headers, retry behavior
- [Changelog](changelog.md) — API changes across releases
