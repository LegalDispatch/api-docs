# Rate Limiting

> How the LegalDispatch API enforces rate limits.

## Overview

Rate limiting is enforced at the API gateway using Redis-backed token bucket counters. Two tiers apply to every request — IP-based and user-based. If either limit is exceeded, the request is rejected with `429 Too Many Requests`.

## Rate Limit Tiers

| Tier | Scope                  | Requests/Minute | Burst |
| ---- | ---------------------- | --------------- | ----- |
| IP   | Per source IP          | 100             | 20    |
| User | Per authenticated user | 300             | 50    |

- **Unauthenticated requests** are limited by the IP tier only.
- **Authenticated requests** are checked against both tiers. The user tier limit is higher to allow normal application usage.

## Response Headers

Every response includes rate limit headers:

| Header                  | Description                              |
| ----------------------- | ---------------------------------------- |
| `X-RateLimit-Limit`     | Maximum requests allowed per window      |
| `X-RateLimit-Remaining` | Requests remaining in the current window |
| `X-RateLimit-Reset`     | Seconds until the current window resets  |

When a limit is exceeded:

| Header        | Description                     |
| ------------- | ------------------------------- |
| `Retry-After` | Seconds to wait before retrying |

## 429 Response

```json
{
  "code": "RATE_LIMITED",
  "message": "Rate limit exceeded",
  "request_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

## Client Best Practices

1. **Monitor `X-RateLimit-Remaining`** — reduce request frequency when it drops low.
2. **Respect `Retry-After`** — wait the indicated number of seconds before retrying.
3. **Use exponential backoff** — if you receive repeated 429s, increase the delay between retries.
4. **Batch where possible** — prefer fetching lists over making many individual requests.
5. **Cache aggressively** — reduce redundant calls for data that changes infrequently.

## API Key Rate Limits

API keys can have custom rate limit overrides configured per key or per partner. When an API key has a `rate_limit_override`, those limits apply instead of the default user tier.
