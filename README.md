# no-claude-help

Keeps coding agents off the byline.

No `Co-Authored-By: Claude`. No robot-emoji `Generated with ...` footers. No
session URLs in commit messages or pull requests. No agent in `AUTHORS`,
`CONTRIBUTORS`, `CODEOWNERS` or a `package.json` author field. Every commit
authored and committed by the human, and nobody else.

It is a Claude Code plugin, but the enforcement is not. The rule lives in git
hooks and a CI job, so it holds for Codex, Cursor, Copilot, Gemini, Devin,
Aider, a colleague on another machine, or a plain terminal — whatever touches
the repository next.

## Why hooks and not instructions

An instruction in `CLAUDE.md` is a request. An agent that forgets it, a
different agent that never read it, or a cloud runner with its own defaults
will still sign your commits. This plugin writes the rule where git enforces
it, then repeats it as instructions for good measure.

Four layers, each one catching what the previous one missed:

| Layer | Catches | Works without |
| :--- | :--- | :--- |
| Claude Code hooks | The attempt, before the tool call runs | — |
| Git hooks | Any commit or push on this machine | Claude Code |
| CI workflow | Commits pushed from anywhere else | Local hooks |
| Instruction files | Reminds every harness that reads them | Nothing |

## Install

### As a Claude Code plugin

```
/plugin marketplace add wrxck/no-claude-help
/plugin install no-claude-help@no-claude-help
```

It then loads the policy at session start, blocks the offending tool calls, and
installs the git hooks into each repository you open, so the rule outlives the
session.

### As plain git tooling, any harness

```sh
git clone https://github.com/wrxck/no-claude-help ~/.no-claude-help
~/.no-claude-help/install.sh --global
```

`--global` sets `core.hooksPath`, which covers every repository on the machine.
It chains into whatever hooks were already configured, so husky, lefthook and a
pre-existing global hooks directory keep working.

Per repository instead:

```sh
nch install                 # git hooks only
nch install --all           # hooks, instruction files for every harness, and CI
nch install --ci            # the GitHub Actions backstop, committed to the repo
```

## What gets rejected

```
$ git commit -m "fix the parser

Co-Authored-By: Claude <noreply@anthropic.com>"

no-claude-help: refusing to write this commit
  commit message:3
    co-authorship trailer credits an agent
    > Co-Authored-By: Claude <noreply@anthropic.com>

  the change is the human author's work, do not credit the tool
  fix the message or the file and try again
```

Rejected everywhere: attribution trailers, `Generated with ...` footers, robot
attribution footers, agent session and thread URLs, an agent as commit author or
committer, `--author` and `GIT_AUTHOR_*` overrides, an agent added to a
contributors, owners or maintainers file, an agent in a copyright line or a
manifest author field, and acknowledgement lines crediting a tool.

Accepted, deliberately: `Co-authored-by:` a real colleague, a dependency called
`@anthropic-ai/sdk` or `openai`, the word `cursor` in ordinary code, prose that
mentions an AI product without claiming it wrote the change, and any line
carrying an `nch-allow` marker.

The identity rules also pin the author. Once installed, commits must carry the
configured `Name <email>`, so an agent cannot quietly swap it for its own or for
somebody else's.

## Commands

```sh
nch doctor                     # what is protecting this repository
nch scan                       # staged, unstaged and unpushed work
nch scan --range main..HEAD    # a branch, the way CI checks it
nch scan --all                 # every commit and every tracked file
nch clean <message-file>       # strip attribution lines in place
nch identity show              # who commits are being authored as
nch identity set "Name <email>"
nch rules --all                # write the policy into every harness's file
nch policy                     # print the policy text
nch uninstall [--global]
```

## Configuration

Per repository with `git config`, or globally with `git config --global`:

| Key | Default | Effect |
| :--- | :--- | :--- |
| `nch.author.name`, `nch.author.email` | from `user.*` at install | The only identity commits may carry |
| `nch.enforceIdentity` | `true` | Set `false` to check for agent identities only, not an exact match |
| `nch.strict` | `false` | Also reject generic `[bot]` identities. Release and dependency bots stay allowed |
| `nch.autoclean` | `false` | Strip attribution from the message instead of rejecting the commit |
| `nch.extraIdentityPattern` | unset | Extra case-insensitive regex of identities to reject |

Environment: `NCH_DISABLE=1` bypasses every check for one command, `NCH_STRICT=1`
forces strict mode, `NO_COLOR=1` gives plain output.

The plugin surfaces the same settings through `/plugin` configuration: commit
identity, whether to install git hooks automatically (default yes), and strict
mode (default no).

Claude Code renders every plugin option as a text field, whatever type the
manifest declares, so the two on/off options are `y`/`n` questions you type the
answer to. Leaving a field empty keeps its default, so you can skip the dialog
entirely. `Enter` moves to the next field; `Enter` on **Save configuration**
saves.

## Instruction files

`nch rules` writes the policy into `AGENTS.md` and `CLAUDE.md`, and updates
`GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/`,
`.windsurfrules`, `.clinerules`, `.rules` and `.junie/guidelines.md` when they
exist. `nch rules --all` creates all of them. The text sits between
`<!-- no-claude-help:start -->` markers, so re-running updates in place instead
of duplicating.

## Fixing history that already carries attribution

```sh
nch scan --all                                        # find it
git rebase -i <base> --exec 'git commit --amend --no-edit'
nch scan --range <base>..HEAD                         # confirm
```

With `nch.autoclean` enabled, the rebase strips the offending lines from each
message as it rewrites. This changes every commit SHA in the range, so agree it
with anyone else working on the branch first.

## Requirements

POSIX `sh`, `git`, `awk`, `grep`, `sed`. No runtime, no packages. The Claude
Code hook scripts additionally use `jq` or `python3` to read the event JSON;
either is enough.

## Tests

```sh
sh tests/run.sh
```

42 cases against real git repositories: every rule, every accepted case, hook
chaining, inherited `core.hooksPath`, the `--no-verify` backstop, and uninstall.

## Licence

MIT
