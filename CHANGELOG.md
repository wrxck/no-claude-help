# Changelog

## 1.0.1

- Drop the `hooks` field from `plugin.json`. Claude Code loads
  `hooks/hooks.json` automatically, so naming it in the manifest registered the
  same file twice and the plugin failed to load its hooks.

## 1.0.0

First release.

- Git hooks for `pre-commit`, `prepare-commit-msg`, `commit-msg` and `pre-push`,
  installable per repository or machine-wide via `core.hooksPath`, chaining into
  any hooks already configured.
- Identity enforcement: rejects agent identities as author or committer, and
  pins commits to one configured `Name <email>`.
- Message rules: attribution trailers, generated-with footers, robot attribution
  footers, and agent session URLs.
- Content rules: agents added to contributors, owners and maintainers files,
  copyright lines, package manifest author fields, and acknowledgement sections,
  with context so dependency names and ordinary words are not flagged.
- Claude Code plugin layer: policy loaded at session start, `PreToolUse` denials
  for commits, tags, pull requests, author overrides and hook tampering, and a
  `Stop` check over unpushed work.
- GitHub Actions workflow as the backstop for commits made elsewhere.
- `nch rules` writes the policy into `AGENTS.md`, `CLAUDE.md` and the other
  harness instruction files.
