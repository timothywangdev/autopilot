# SavantAlpha Constitution

## Core Principles

### I. Single Language Stack

TypeScript/Node.js 20+ for the entire codebase. No polyglot complexity. Mongoose for MongoDB ODM. Strong typing throughout with Zod runtime validation for external data (LLM output, API responses). **Yarn** is the package manager for the entire project — never use npm.

### II. Content Non-Persistence (with RAG Exception)

Newsletter content is held in memory only during processing, then discarded. The database stores only factual metadata (author, ticker, date, URL), our classification (sentiment, conviction, category), and a brief context_snippet (LLM-generated justification, not quotes). SavantAlpha tracks performance, not redistributes content.

**RAG Exception (amended v1.3.0)**: For semantic search and knowledge extraction, the system MAY persist:
- Article text chunks (≤512 tokens each) in the `articleChunks` collection, paired with vector embeddings for retrieval
- Full article text in `processedContents.articleText` for re-extraction and RAG context

This content is used exclusively for internal AI analysis (framework extraction, thesis drift detection, research briefs) and is never exposed to end users as readable content. The web dashboard displays only LLM-synthesized summaries with three-tier citations, not raw newsletter text. Access to stored article text is restricted to the pipeline and CLI — the Next.js API never returns raw article content.

### III. Sequential Pipeline with Error Isolation

Single orchestrator runs pipeline steps sequentially: Fetch -> Parse -> Extract -> Store -> Positions -> Price -> Stats. Per-item error isolation: one bad email does not block the entire run. Steps 5-7 are non-critical - failures are logged but don't abort the pipeline. Circuit breaker after 5 consecutive failures.

### IV. Idempotency Everywhere

Every operation is repeatable without side effects:

- Cross-source dedup via `processedContents.slug` (canonical post slug)
- Same article ingested via email or archive is recognized as one item
- Signal dedup via unique compound index `{ authorId, ticker, postUrl }`
- Position resolution via `positionId: null` check + partial unique index
- Duplicate key errors (MongoDB 11000) are caught and logged, not thrown

### V. Shared Cloud Database

MongoDB Atlas (M0 free tier for MVP) shared by both local pipeline and cloud Next.js app. Both connect to the same Atlas instance - no sync mechanism needed. Connection string stored in `.env` locally, AWS SSM Parameter Store (SecureString) in production.

### VI. Dual LLM Backend

Primary: Claude Code CLI (local invocation, zero marginal cost). Fallback: z.ai GLM-5 API (for unattended backfill or when Claude Code unavailable). Both outputs validated with identical Zod schemas. Prompt version and model ID recorded on every signal for audit trail.

### VII. Observability First

Structured JSON logging with Pino (redacts secrets). Every pipeline run creates a `pipeline_runs` record with counts, errors, and status. Dead-man's switch: alert if no successful run in 26 hours. Health check CLI command for diagnostics.

### VIII. Skills-First for Frontend

Before implementing any Next.js, React, or web UI code, consult the skills in `.claude/skills/`:

- `vercel-composition-patterns` - Component composition, server/client boundaries
- `vercel-react-best-practices` - React patterns, hooks, state management
- `web-design-guidelines` - UI/UX patterns, accessibility, responsive design

These skills define the canonical patterns for frontend work. Deviate only with documented justification.

## Technology Constraints

| Component | Technology | Non-Negotiable |
| --------- | ---------- | -------------- |
| Runtime | Node.js 20+ / TypeScript 5.x | Yes |
| Package manager | Yarn | Yes |
| Database | MongoDB Atlas + Mongoose | Yes |
| Email API | Gmail API (googleapis) | Yes |
| Browser automation | Patchright (for public archives only) | Yes |
| HTML parsing | Cheerio + Turndown | Yes |
| Validation | Zod | Yes |
| Logging | Pino | Yes |
| CLI | Commander | Yes |
| Web frontend | Next.js | Yes |

## Security Requirements

1. **Read-only Gmail scope** - `gmail.readonly` only, never modify/send
2. **No secrets in code** - All credentials in `.env` (gitignored) or SSM
3. **Token rotation** - 90-day refresh token rotation policy
4. **Pre-commit scanning** - Lefthook hook to detect leaked secrets
5. **Network whitelist** - Atlas accessible only from dev IP and App Runner CIDR
6. **Minimal DB privileges** - `readWrite` role scoped to `savantalpha` database only
7. **Third-party data awareness** - Content transmitted to Anthropic/z.ai for extraction; review their data processing terms

## Development Workflow

### Pipeline Modes

| Mode | Purpose |
| ---- | ------- |
| `daily_ingest` | Scheduled run: fetch new content, full pipeline |
| `backfill_email` | Historical import of saved emails |
| `backfill_public` | Scrape public archive posts |
| `price_backfill` | Backfill entry/exit prices and compute returns |
| `stats_refresh` | Recompute author stats from closed positions |
| `position_resolve` | Re-resolve unlinked thesis signals + stale close |

### Error Recovery

- **Auth errors**: Re-run `savantalpha auth`, pipeline aborts
- **Network errors**: Exponential backoff (3 attempts), skip on failure
- **LLM errors**: Retry once, then skip article
- **Parse errors**: Log and continue to next item
- **Rate limits**: Wait 60s, retry; abort batch if persistent

### Migration Strategy

MongoDB is schema-flexible. Mongoose schema changes apply automatically. For index changes or data transformations, use versioned migration scripts in `scripts/migrate-*.ts`. Every document has a `schemaVersion` field for clean migration paths.

## Governance

1. **Constitution supersedes all other practices** - When in doubt, refer here
2. **Prompt versioning mandatory** - Never modify extraction prompt without incrementing version
3. **Signal provenance required** - Every signal records `promptVersion`, `modelId`, `pipelineRunId`
4. **Position integrity** - Transactions for all position lifecycle changes
5. **Content boundary** - Raw article text may be stored for RAG/semantic search (Principle II RAG Exception) but is never exposed via web API. `contextSnippet` remains the only user-facing content field
6. **Skills compliance for frontend** - Always check `.claude/skills/` before writing React/Next.js code; follow Vercel and web patterns defined there

**Version**: 1.3.0 | **Ratified**: 2026-03-03 | **Last Amended**: 2026-03-11
