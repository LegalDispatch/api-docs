# Authentication

> How to obtain, use, and manage JWT tokens in the LegalDispatch API.

## Overview

LegalDispatch uses **JWT Bearer tokens** for all authenticated API requests. Tokens are issued by the authentication-service and signed with RS256 (RSA 2048-bit).

| Token Type    | Format             | TTL       | Storage                  |
| ------------- | ------------------ | --------- | ------------------------ |
| Access token  | JWT (RS256)        | 15 min    | Client-side only         |
| Refresh token | Opaque (`rt_...`)  | 30 days   | SHA-256 hash in database |
| API key       | `ldk_{env}_{48ch}` | No expiry | SHA-256 hash in database |

## Login Flow

### Single-Partner Login

```bash
curl -X POST /api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "your-password"
  }'
```

**Response** (single partner):

```json
{
  "step": "complete",
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "rt_a1b2c3d4...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

### Multi-Partner Login

If the user belongs to multiple partners, the first response requires partner selection:

```json
{
  "step": "select_partner",
  "session_token": "temp-session-token",
  "available_partners": [
    { "partner_id": "uuid-1", "partner_name": "Acme Corp" },
    { "partner_id": "uuid-2", "partner_name": "Beta LLC" }
  ]
}
```

Complete login by selecting a partner (session token expires in 5 minutes):

```bash
curl -X POST /api/v1/auth/login/select-partner \
  -H "Content-Type: application/json" \
  -d '{
    "session_token": "temp-session-token",
    "partner_id": "uuid-1"
  }'
```

## Using the Token

Pass the access token in the `Authorization` header on every request:

```
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
```

### JWT Claims

The access token contains these claims:

| Claim         | Type     | Description                                       |
| ------------- | -------- | ------------------------------------------------- |
| `sub`         | string   | User ID (UUID)                                    |
| `user_id`     | string   | User ID (UUID)                                    |
| `partner_id`  | string   | Partner context (UUID)                            |
| `role`        | string   | User role (e.g., `dispatcher`, `super_admin`)     |
| `permissions` | string[] | Permission strings (e.g., `sop.create_on_behalf`) |
| `session_id`  | string   | Session ID for revocation tracking                |
| `iss`         | string   | `legaldispatch-auth`                              |
| `aud`         | string   | `legaldispatch-api`                               |
| `exp`         | number   | Expiry timestamp (15 min from issue)              |

## Token Refresh

Access tokens expire after 15 minutes. Refresh before expiry to maintain the session:

```bash
curl -X POST /api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{ "refresh_token": "rt_a1b2c3d4..." }'
```

**Response:**

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "rt_new_token...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**Important:** Each refresh token is single-use. The response contains a **new** refresh token — store it and discard the old one. Reusing a spent refresh token triggers theft detection and revokes the entire token family.

## Logout

### Single Device

```bash
curl -X POST /api/v1/auth/logout \
  -H "Content-Type: application/json" \
  -d '{ "refresh_token": "rt_a1b2c3d4..." }'
```

### All Devices

```bash
curl -X POST /api/v1/auth/logout-all \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{ "password": "your-password" }'
```

## Password Management

### Change Password (Authenticated)

```bash
curl -X POST /api/v1/auth/password/change \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "current_password": "old-password",
    "new_password": "new-password",
    "invalidate_other_sessions": true
  }'
```

### Reset Password (Unauthenticated)

1. Request a reset link (always returns 200 to prevent email enumeration):

```bash
curl -X POST /api/v1/auth/password/reset-request \
  -H "Content-Type: application/json" \
  -d '{ "email": "user@example.com" }'
```

2. Complete the reset with the token from the email:

```bash
curl -X POST /api/v1/auth/password/reset \
  -H "Content-Type: application/json" \
  -d '{ "token": "reset-token", "new_password": "new-password" }'
```

**Password requirements:** 12+ characters, uppercase, lowercase, digit, special character. Last 5 passwords cannot be reused.

## Session Management

List active sessions:

```bash
curl -X GET /api/v1/auth/sessions \
  -H "Authorization: Bearer <access_token>"
```

Revoke a specific session:

```bash
curl -X DELETE /api/v1/auth/sessions/{sessionId} \
  -H "Authorization: Bearer <access_token>"
```

## API Keys

API keys provide long-lived authentication for programmatic access.

### Create

```bash
curl -X POST /api/v1/auth/api-keys \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "CI Pipeline",
    "environment": "live",
    "permissions": ["sop.create_on_behalf"],
    "ip_allowlist": ["203.0.113.0/24"]
  }'
```

The full key is returned **once** — store it securely.

### List

```bash
curl -X GET /api/v1/auth/api-keys \
  -H "Authorization: Bearer <access_token>"
```

Returns key prefixes only (never the full key).

### Revoke

```bash
curl -X DELETE /api/v1/auth/api-keys/{keyId} \
  -H "Authorization: Bearer <access_token>"
```

### Rotate

```bash
curl -X POST /api/v1/auth/api-keys/{keyId}/rotate \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{ "grace_period_hours": 24 }'
```

During the grace period, both old and new keys are valid.

## JWKS (Public Key Verification)

Services can verify JWT signatures using the public JWKS endpoint:

```
GET /api/v1/auth/.well-known/jwks.json
```

This endpoint is public (no authentication required) and returns `Cache-Control: public, max-age=3600`. Keys rotate every 90 days with a 24-hour overlap period.

## Common Errors

| Code               | Status | Meaning                                    |
| ------------------ | ------ | ------------------------------------------ |
| `UNAUTHORIZED`     | 401    | Missing, expired, or invalid token         |
| `FORBIDDEN`        | 403    | Valid token but insufficient permissions   |
| `ACCOUNT_LOCKED`   | 403    | Too many failed login attempts             |
| `VALIDATION_ERROR` | 400    | Invalid request body (see `details` field) |
