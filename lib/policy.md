## Attribution policy (enforced)

The human running this session is the sole author of every change. You are a
tool they used, like an editor or a compiler. Tools do not sign their work.

**Never do any of the following:**

1. **Never add a co-authorship trailer.** No `Co-Authored-By:`,
   `Co-Committed-By:` or `Assisted-By:` line naming an AI tool, model, vendor
   or agent, in any commit message, tag message, pull request or issue.
2. **Never link a session.** No `claude.ai/code/...`, `Claude-Session:`,
   `chatgpt.com/codex/...`, `cursor.com/agents/...`, `app.devin.ai/...`,
   `jules.google.com/...`, `ampcode.com/threads/...` or any other agent
   conversation, task or thread URL. Not in commits, not in PR bodies, not in
   code comments, not in changelogs.
3. **Never add a generated-with footer.** No "Generated with Claude Code",
   "Created with ...", "Powered by ...", "Written by an AI", robot-emoji
   footers, or any equivalent credit line.
4. **Never commit as yourself.** The commit author *and* committer must be the
   human's configured git identity. Never pass `--author`, never set
   `GIT_AUTHOR_*` or `GIT_COMMITTER_*`, and never change `user.name` or
   `user.email` to a tool, model or bot identity.
5. **Never list yourself as a contributor or maintainer.** Do not add an AI
   tool, model or vendor to `AUTHORS`, `CONTRIBUTORS`, `MAINTAINERS`,
   `CODEOWNERS`, `.mailmap`, `humans.txt`, a copyright or licence line, or to
   the `author`, `contributors` or `maintainers` fields of `package.json`,
   `pyproject.toml`, `Cargo.toml`, `composer.json` or any other manifest.
6. **Never credit yourself in prose.** No "built with", "with help from" or
   acknowledgements entries naming an AI tool in READMEs, docs, changelogs,
   release notes or PR descriptions.

**Do instead:** write the commit message as the human would — describe what
changed and why, and stop. A commit message ends at its last substantive line.

This policy is enforced mechanically by git hooks and CI, so a violation fails
the commit or the build rather than reaching the repository. Do not attempt to
work around it: do not use `--no-verify`, do not disable or edit the hooks, do
not set `NCH_DISABLE`, and do not amend history to reintroduce attribution. If
a check fires, correct the message or the file and try again.

Discussing this policy, or writing tests and documentation about it, is fine.
The rule is about crediting the tool for real work, not about the words.
