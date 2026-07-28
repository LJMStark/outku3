# Kirole Prompt Studio

Browser-based workbench for inspecting, editing, compiling, and testing every active Kirole prompt. It runs on Codex Sites with a vinext/Cloudflare Worker build.

## Local development

```bash
npm install
npm run dev
```

Useful checks:

```bash
npx tsc --noEmit
npm run lint
npm test
```

## Runtime configuration

- `OPENROUTER_API_KEY` (or `OPENAI_API_KEY`): server-only OpenRouter credential.
- `OPENAI_MODEL`: primary OpenRouter model, defaulting to `openai/gpt-oss-120b`.
- `RATE_LIMIT_SALT`: optional dedicated salt for short-lived IP hashes. When absent, the server credential is used as the salt.
- D1 binding `DB`: usage counters for the ten-minute per-IP and daily global limits.

Prompt edits and mock inputs are kept in browser `localStorage`. The service does not persist prompt content or model output.
