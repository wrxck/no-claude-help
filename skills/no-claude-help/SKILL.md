---
name: no-claude-help
description: Attribution policy and tooling. Load when writing a commit message, tag message, pull request or issue body, when touching AUTHORS, CONTRIBUTORS, MAINTAINERS, CODEOWNERS, .mailmap or a package manifest's author fields, when a commit or push is rejected for crediting an agent, or when the user asks to install, audit or repair attribution enforcement in a repository.
---

# no-claude-help

The human running the session is the sole author of every change. This plugin
makes that mechanical rather than aspirational.

## The policy

@../../lib/policy.md

## When a check fires

The git hooks reject the operation and print what they found. Fix the cause,
never the check.

| Rejected at | What to do |
| :--- | :--- |
| `commit-msg` | Rewrite the message without the trailer, footer or session link, then commit again. |
| `pre-commit` | Remove the agent from the contributors, owners, manifest or copyright line you staged. |
| `pre-push` | The offending commit already exists. `git commit --amend` for the tip, or `git rebase -i` for anything older. |
| CI | Same as above, then force-push the corrected branch. |

Never resolve a rejection with `--no-verify`, `NCH_DISABLE=1`, by editing
`.git/hooks`, or by changing `core.hooksPath`. Those are bypasses, not fixes,
and the pre-push hook and CI job will catch the commit anyway.

## Commands

The plugin ships a POSIX shell CLI at `${CLAUDE_PLUGIN_ROOT}/bin/nch`.

```sh
nch doctor                       # which protections are active here
nch scan                         # staged, unstaged and unpushed work
nch scan --range main..HEAD      # a branch, the way CI checks it
nch scan --all                   # every commit and every tracked file
nch scan --file AUTHORS package.json
nch clean .git/COMMIT_EDITMSG    # strip attribution lines in place
nch identity show                # who commits are being authored as
```

Installing enforcement in a repository:

```sh
nch install                      # git hooks for this repository
nch install --global             # every repository on the machine
nch install --rules              # also write the policy into AGENTS.md and CLAUDE.md
nch install --ci                 # also add the GitHub Actions backstop
nch install --all                # hooks, rules for every harness, and CI
```

`nch install --global` is the strongest option: it sets `core.hooksPath`, so
the rule applies to every repository and every tool on the machine, including
other agents and plain terminal use. It chains into each repository's own
hooks, so husky and lefthook keep working.

## Fixing history that already carries attribution

`nch scan --all` finds it. To strip trailers from existing commits, rewrite the
range and keep the original authors:

```sh
git rebase -i <base> --exec 'git commit --amend --no-edit'
```

with the hooks installed, the `prepare-commit-msg` hook strips the offending
lines from each rewritten message. Confirm with `nch scan --range <base>..HEAD`
before force-pushing, and warn the user first: rewriting history changes every
commit SHA in the range.

## What is not a violation

Discussing the policy, writing tests for it, documenting it, or naming an AI
tool in ordinary prose about the tool. A repository may legitimately depend on
`@anthropic-ai/sdk` or contain the word "cursor". The rule is about crediting a
tool for authorship, not about the words themselves.

For a single deliberate exception, put `nch-allow` on the line.
