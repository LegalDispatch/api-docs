# Error Handling

> How errors are structured in the LegalDispatch API.

## Error Envelope

Every error response uses the same flat JSON structure:

```json
{
  "code": "ENTITY_NOT_FOUND",
  "message": "Document not found",
  "request_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

| Field        | Type   | Required | Description                                                 |
| ------------ | ------ | -------- | ----------------------------------------------------------- |
| `code`       | string | Yes      | Machine-readable code in `SCREAMING_SNAKE_CASE`             |
| `message`    | string | Yes      | Human-readable description                                  |
| `request_id` | string | Yes      | Correlation ID for tracing (from `X-Correlation-ID` header) |
| `details`    | object | No       | Field-level errors for validation failures                  |

## Validation Errors

When a request fails validation, the `details` field contains field-to-message mappings:

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "details": {
    "email": "Email is required",
    "partner_id": "Must be a valid UUID"
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

## Error Codes by Status

### 400 Bad Request

| Code                 | Meaning                                        |
| -------------------- | ---------------------------------------------- |
| `VALIDATION_ERROR`   | Field validation failed — check `details`      |
| `INVALID_REQUEST`    | Malformed JSON or wrong content type           |
| `DUPLICATE_{ENTITY}` | Uniqueness violation (e.g., `DUPLICATE_EMAIL`) |

### 401 Unauthorized

| Code           | Meaning                                           |
| -------------- | ------------------------------------------------- |
| `UNAUTHORIZED` | Missing, expired, or invalid JWT / internal token |

### 403 Forbidden

| Code             | Meaning                                              |
| ---------------- | ---------------------------------------------------- |
| `FORBIDDEN`      | Authenticated but lacks required permission          |
| `ACCESS_DENIED`  | Resource-level access control denial                 |
| `ACCOUNT_LOCKED` | Account locked due to too many failed login attempts |

### 404 Not Found

| Code                 | Meaning                                                         |
| -------------------- | --------------------------------------------------------------- |
| `{ENTITY}_NOT_FOUND` | Entity not found (e.g., `USER_NOT_FOUND`, `DOCUMENT_NOT_FOUND`) |

### 409 Conflict

| Code                | Meaning                                          |
| ------------------- | ------------------------------------------------ |
| `{ENTITY}_CONFLICT` | State conflict (e.g., `SESSION_ALREADY_REVOKED`) |

### 413 Payload Too Large

| Code             | Meaning                           |
| ---------------- | --------------------------------- |
| `FILE_TOO_LARGE` | Upload exceeds maximum size limit |

### 415 Unsupported Media Type

| Code                    | Meaning                       |
| ----------------------- | ----------------------------- |
| `UNSUPPORTED_FILE_TYPE` | File type not in allowed list |

### 422 Unprocessable Entity

| Code                   | Meaning                                              |
| ---------------------- | ---------------------------------------------------- |
| `UNPROCESSABLE_ENTITY` | Valid request, but business logic prevents operation |
| `TEMPLATE_NOT_FOUND`   | Required template missing for PDF generation         |

### 429 Too Many Requests

| Code           | Meaning                           |
| -------------- | --------------------------------- |
| `RATE_LIMITED` | Rate limit exceeded — retry later |

### 500 Internal Server Error

| Code             | Meaning                   |
| ---------------- | ------------------------- |
| `INTERNAL_ERROR` | Unexpected server failure |

### 503 Service Unavailable

| Code                  | Meaning                              |
| --------------------- | ------------------------------------ |
| `SERVICE_UNAVAILABLE` | Dependency down (database, external) |

## Correlation ID

Every request should include an `X-Correlation-ID` header. This value is:

- Echoed back in the response `X-Correlation-ID` header
- Included as `request_id` in all error responses
- Used for distributed tracing across services

If omitted, the server generates a UUID automatically.

```bash
curl -X GET /api/v1/users/me \
  -H "Authorization: Bearer <token>" \
  -H "X-Correlation-ID: my-request-123"
```

## Client Best Practices

1. **Switch on `code`, not `message`** — the message is human-readable and may change.
2. **Check `details` on 400s** — display field-level errors to the user.
3. **Log `request_id`** — include it in support requests for fast tracing.
4. **Handle 401 gracefully** — refresh the token or redirect to login.
5. **Respect 429** — back off and retry after the `Retry-After` header duration.
