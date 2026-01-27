# Fix: Remove Hardcoded Google OAuth Credentials

## Problem
GitHub push protection is blocking push because Google OAuth credentials (clientId + clientSecret) are hardcoded in:
- `packages/core/src/auth/google-oauth.ts` (lines 80-81, 105-107)
- `packages/core/src/settings/defaults.ts` (lines 103-104)

The secrets were introduced in commit `1d97378` ("Add Google Gemini provider with API key and OAuth authentication").

## Solution
Move Google OAuth client credentials to `~/.tron/auth.json` (which is gitignored and user-specific), similar to how API keys and OAuth tokens are already stored.

## Files to Modify

### 1. `packages/core/src/auth/types.ts`
Extend `ProviderAuth` or add Google-specific type to include:
```typescript
interface GoogleProviderAuth extends ProviderAuth {
  clientId?: string;
  clientSecret?: string;
  endpoint?: 'cloud-code-assist' | 'antigravity';
  projectId?: string;
}
```

### 2. `packages/core/src/auth/google-oauth.ts`
- Remove hardcoded `clientId` and `clientSecret` from `CLOUD_CODE_ASSIST_CONFIG` and `ANTIGRAVITY_CONFIG`
- Modify `getGoogleOAuthSettings()` to load clientId/clientSecret from auth.json
- Add a setup/initialization function that saves default credentials to auth.json on first use
- Keep the endpoint URLs and scopes hardcoded (those aren't secrets)

### 3. `packages/core/src/settings/defaults.ts`
- Remove `clientId` and `clientSecret` from `api.google` section
- Keep other non-secret Google settings (URLs, scopes, etc.)

### 4. Git History Rewrite
After code changes are made:
```bash
# Interactive rebase to edit the offending commit
git rebase -i 1d97378^

# Mark 1d97378 as "edit", then amend it with the fixed files
# Continue rebase to replay remaining commits
```

## Implementation Steps

1. **Update types.ts** - Add Google-specific auth fields
2. **Update google-oauth.ts** - Load credentials from auth.json, provide defaults on first OAuth flow
3. **Update defaults.ts** - Remove clientId/clientSecret
4. **Test the changes** - Ensure Google OAuth flow still works
5. **Rewrite git history** - Remove secrets from commit 1d97378
6. **Verify push** - Confirm GitHub accepts the push

## Verification
1. Run `bun run build` - Ensure no compile errors
2. Run `bun run test` - Ensure no test failures
3. Test Google OAuth flow manually (if possible)
4. Run `git push` - Confirm GitHub accepts the push

## Notes
- The credentials are technically "public" (from Gemini CLI), but GitHub scanner still flags them
- Moving to auth.json keeps the zero-config experience (defaults written on first use)
- This follows the existing pattern for API keys in auth.json
