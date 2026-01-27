# Fix: OpenAI Codex OAuth Refresh Token Not Rotated

## Problem Summary

When using `gpt-5.2-codex`, the session fails with error:
```
Token refresh failed: 401 - refresh_token_reused
```

## Root Cause

The Codex provider at `packages/core/src/providers/openai-codex.ts`:
1. Ignores the new `refresh_token` in the OAuth response (line 341)
2. Never persists refreshed tokens to disk
3. OAuth refresh tokens are one-time use, so the old token becomes invalid

## Implementation Plan

### File: `packages/core/src/providers/openai-codex.ts`

**1. Add import for token persistence (near line 24):**
```typescript
import { saveProviderOAuthTokens, type OAuthTokens } from '../auth/unified.js';
```

**2. Fix `refreshTokens()` method (lines 319-346):**

Change return type and extract new refresh token:
```typescript
private async refreshTokens(): Promise<OAuthTokens> {
  // ... existing fetch code ...

  const data = await response.json() as {
    access_token: string;
    refresh_token: string;  // ADD THIS
    expires_in: number;
  };

  const newTokens: OAuthTokens = {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,  // ADD THIS
    expiresAt: Date.now() + data.expires_in * 1000,
  };

  // Persist to disk
  await saveProviderOAuthTokens('openai-codex', newTokens);

  return newTokens;
}
```

**3. Fix `ensureValidTokens()` method (lines 351-357):**

Update refresh token in memory too:
```typescript
private async ensureValidTokens(): Promise<void> {
  if (this.shouldRefreshTokens()) {
    const newTokens = await this.refreshTokens();
    this.config.auth.accessToken = newTokens.accessToken;
    this.config.auth.refreshToken = newTokens.refreshToken;  // ADD THIS
    this.config.auth.expiresAt = newTokens.expiresAt;
  }
}
```

## Important Note

Your current refresh token is already invalid (it was used but the new one wasn't saved). After deploying this fix, you'll need to re-authenticate with OpenAI Codex once to get fresh tokens. The fix will then ensure all future token refreshes are properly persisted.

## Verification

1. Build: `bun run build`
2. Run tests: `bun run test`
3. Re-authenticate with OpenAI Codex (required since current token is invalid)
4. Manual test:
   - Start beta app with `gpt-5.2-codex`
   - Send messages to confirm it works
   - Wait for token to expire (or check `~/.tron/auth.json` for `expiresAt`)
   - Continue using - should auto-refresh without errors
