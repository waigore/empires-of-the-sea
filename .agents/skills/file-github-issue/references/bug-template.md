# Bug issue template

**Title:** `[Bug] <short symptom>`

**Labels:** `todo`, `bug`

```markdown
## Summary
<1–2 sentences>

## Platform
<!-- Include this section only when the user stated platform or it is clearly relevant.
     Otherwise omit entirely (assumed all platforms). -->
- OS / build: <desktop Windows | desktop macOS | desktop Linux | Android | iOS>
- How run: <editor | exported build | debug APK | other>
- Version / commit: <git SHA or “main @ <date>” if known>

## Map seed
<!-- Include only when the user provided a seed and it helps repro (layout / generation).
     Otherwise omit entirely. -->
- Seed: <int>

## Steps to reproduce
1. …
2. …

## Expected
<what should happen; cite wiki page/section if known>

## Actual
<what happened>

## Analysis
- Likely locus: <scene/script/area or “unknown”>
- Wiki alignment: <matches rules | conflicts with rules | rules silent>
- Severity: <blocker | major | minor | polish>
- Notes: <repro confidence, related code/PRs>

## Acceptance
- [ ] Expected behavior restored (or clarified via wiki if rules were wrong)
```

Optional (only after user confirms wiki follow-up):

```markdown
## Wiki follow-up
- Pages: <wiki page titles/URLs>
- Change needed: <conflict fix or new rule summary>
```
