# Changelog

## 1.0.4

- Require the agent name to stand alone before an ordinary source file counts
  as a credit. `CLAUDE_PLUGIN_OPTION_AUTHOR_IDENTITY` and `claudeAuthorName`
  are code, not a byline, and were being flagged. Attribution files, manifests
  and licences are unchanged.
- Honour the `.no-claude-help-source` marker in every content scan, not only in
  the pre-commit hook, so `nch scan` and the CI job agree with it. Message and
  identity rules still apply in a marked repository.

## 1.0.3

- Ask the two on/off plugin options as `y/n` questions, defaulting to yes for
  automatic hook installation and no for strict mode.
- Parse those answers in the plugin's own code rather than relying on Claude
  Code's boolean coercion, which accepts only `1`, `true`, `yes` and `on`, so a
  bare `y` silently read as false.

## 1.0.2

- Spell out the accepted input for the two on/off plugin options. Claude Code
  renders every `userConfig` field as a text box whatever `type` says, so a
  boolean arrives as an empty box with no clue that it wants `true` or `false`.
  The descriptions now say so, and say that an empty field keeps the default.

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
