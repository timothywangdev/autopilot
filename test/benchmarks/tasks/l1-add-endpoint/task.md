# L1: Add Health Check Endpoint

**Difficulty**: L1 (Incremental)
**Estimated LOC**: 50-100
**Files**: 3-5

## Feature Description

Add a `/health` endpoint to the existing Express API that returns system health status including:
- Server uptime
- Memory usage
- Database connection status
- Version info from package.json

## Requirements

1. Create `GET /health` endpoint
2. Return JSON response with:
   - `status`: "healthy" | "degraded" | "unhealthy"
   - `uptime`: seconds since server start
   - `memory`: { heapUsed, heapTotal, rss } in MB
   - `database`: { connected: boolean, latency_ms: number }
   - `version`: from package.json
3. Health check should timeout after 5 seconds
4. Add unit tests for the endpoint
5. Document in README

## Verification

```yaml
verifications:
  - type: TEST
    name: unit-tests-pass
    command: npm test

  - type: API
    name: health-endpoint-responds
    command: curl -s http://localhost:3000/health | jq -e '.status'

  - type: API
    name: health-returns-required-fields
    command: |
      curl -s http://localhost:3000/health | jq -e '
        .uptime and .memory and .database and .version
      '

  - type: CLI
    name: no-typescript-errors
    command: npx tsc --noEmit
```

## Baseline Project

Setup creates a minimal Express + TypeScript project with:
- `src/index.ts` - Express app
- `src/routes/` - Existing routes
- `src/db.ts` - Database connection
- `package.json` - Dependencies
- `tsconfig.json` - TypeScript config
