#!/bin/sh
# detection patterns shared by the git hooks, harness hooks, ci job and cli,
# so every layer agrees on what counts as an agent crediting itself.
#
# three families, deliberately kept apart:
#   ident   -> git author/committer strings, codeowners entries
#   msg     -> commit messages, tag messages, pr/issue bodies (blunt rules)
#   content -> tracked file contents (context-aware rules)
#
# blunt rules are safe in messages: nobody legitimately writes a co-authored-by
# trailer for a language model. file contents need context, otherwise a
# dependency named "openai" or the word "cursor" in an editor would trip it.

# --- identities ------------------------------------------------------------

# unambiguous, matched anywhere inside "name <email>"
NCH_IDENT_STRONG='claude|anthropic|openai|chatgpt|codex|copilot|windsurf|codeium|cognition-?labs|aider|opencode|roo-?code|augment-?code|ampcode|qodo|codiumai|tabnine|sweep-?ai|openhands|all-?hands|swe-?agent|blackbox-?ai|google-labs-jules|jules\.google|gemini-?(cli|code)|trae-?ai|kilo-?code|factory-?droid|zencoder|v0\.dev|bolt\.new|lovable\.dev|replit-?agent|smol-?developer|gpt-?engineer|autogpt|metagpt|codebuff|mentat-?bot|sourcegraph|cursor[ ._-]?(agent|bot)|@cursor\.(com|sh)|devin[ ._-]?(ai|agent|bot)|@devin\.ai|amp[ ._-]?(agent|bot)|cline[ ._-]?(agent|bot)'

# ambiguous alone: real people are called jules and devin, and "amp" and
# "cursor" are ordinary words. only counted when the identity also looks
# machine-shaped, see NCH_IDENT_ROBOT
NCH_IDENT_WEAK='gemini|jules|devin|cursor|goose|amp|cline|junie|droid|gpt|llm'

NCH_IDENT_ROBOT='\[bot\]|(^|[^a-z0-9])(ai|a\.i\.|agent|assistant|bot|automation|machine)([^a-z0-9]|$)'

# release and dependency bots are not an agent crediting itself, so the
# generic \[bot\] rule skips them
NCH_IDENT_ALLOWED_BOTS='dependabot|renovate|github-actions|pre-commit-ci|semantic-release|greenkeeper|imgbot|allcontributors|snyk-bot|mergify|netlify|vercel'

# --- commit, tag and pr message rules --------------------------------------

# trailer keys whose only purpose is crediting a tool or linking a session
NCH_MSG_BAD_TRAILER='^[[:space:]]*(generated[ _-]?(by|with)|assisted[ _-]?by|ai[ _-]?assisted|ai[ _-]?generated|(claude|codex|cursor|devin|amp|opencode|agent|chat|tool|copilot|gemini|aider)[ _-]?(session|thread|task|run|url|link|id)|session[ _-]?(url|link|id)?|thread[ _-]?url|x-(codex|claude|cursor)-[a-z-]+)[[:space:]]*:'

NCH_MSG_COAUTHOR='^[[:space:]]*co[ _-]?(authored|committed|developed)[ _-]?by[[:space:]]*:'

NCH_MSG_CREDIT='(generated|created|authored|written|produced|built|made|drafted|implemented|committed)[[:space:]]+(with|by|using|via)[[:space:]]+[^[:alnum:]]*(claude|anthropic|chatgpt|openai|codex|copilot|cursor|windsurf|gemini|devin|aider|amp|opencode|cline|junie|an?[[:space:]]+(ai|llm|language[[:space:]]model|coding[[:space:]]agent)|ai[[:space:]]+(assistance|help|agent))|(powered|assisted)[[:space:]]+by[[:space:]]+[^[:alnum:]]*(claude|chatgpt|copilot|cursor|codex|gemini|devin|an?[[:space:]]+ai)|with[[:space:]]+(help|assistance)[[:space:]]+from[[:space:]]+[^[:alnum:]]*(claude|chatgpt|copilot|cursor|codex|gemini|devin|an?[[:space:]]+ai)|\[claude[[:space:]]code\]|claude[[:space:]]code[[:space:]]*(session|generated)'

# the robot glyph only counts on a credit-ish line, built from bytes so the
# source file stays free of emoji
NCH_MSG_ROBOT_LINE=$(printf '\360\237\244\226')
NCH_MSG_ROBOT_CONTEXT='generat|creat|assist|author|claude|codex|copilot|cursor|gemini|devin|aider|agent|ai'

# known agent permalinks, plus a generic rule for session-shaped urls from
# vendors not listed here. the generic rule stays inside a url on purpose:
# matching bare identifiers would flag ordinary names like task_completed
NCH_MSG_SESSION_URL='claude\.(ai|com)/(code|chat|share|session)|console\.anthropic\.com/|chatgpt\.com/(codex|c|share|g|s)/|chat\.openai\.com/|cursor\.(com|sh|so)/(agent|background|bc)|app\.devin\.ai/|devin\.ai/sessions?/|jules\.google\.com/|copilot-workspace\.githubnext\.com|github\.com/copilot/(s|c)/|ampcode\.com/(threads?|t)/|opencode\.ai/s/|factory\.ai/(session|run)|codeium\.com/(session|chat)/|windsurf\.com/(session|cascade)/|https?://[^[:space:]]*(sessions?|threads?|conversations?|tasks?|chats?)[/_=][A-Za-z0-9_-]*[0-9]'

# --- file content rules ----------------------------------------------------

# paths that exist purely to record attribution
NCH_PATH_ATTRIBUTION='(^|/)(AUTHORS|CONTRIBUTORS|MAINTAINERS|OWNERS|CODEOWNERS|CREDITS|humans\.txt|\.mailmap|\.all-contributorsrc)([.-][A-Za-z0-9]+)?$'

# package manifests: an identity here only offends inside an author,
# contributor or maintainer field, never in a dependency name
NCH_PATH_MANIFEST='(^|/)(package\.json|package-lock\.json|pyproject\.toml|setup\.py|setup\.cfg|Cargo\.toml|composer\.json|pubspec\.yaml|mix\.exs|Chart\.yaml|Gemfile|.*\.gemspec|.*\.podspec|.*\.nuspec|.*\.csproj|.*\.cabal|bower\.json|.*\.opam)$'

NCH_PATH_LICENSE='(^|/)(LICEN[CS]E|COPYING|NOTICE)([.-][A-Za-z0-9]+)?$'

# words that turn a mention into a credit
NCH_CONTENT_ATTRIB_KEY='author|contributor|maintainer|copyright|credit|acknowledge?ment|owner|created[ _-]?by|written[ _-]?by|developed[ _-]?by|built[ _-]?by|made[ _-]?by|thanks[ _-]?to|team|holder'

# the shape of a person entry
NCH_CONTENT_PERSON='<[^@<>[:space:]]+@[^@<>[:space:]]+>|\(https?://[^)]*\)[[:space:]]*$|^[[:space:]]*[-*][[:space:]]*@[A-Za-z0-9_-]+'

NCH_CONTENT_COPYRIGHT='copyright|\(c\)|spdx-filecopyrighttext'

# per-line opt out
NCH_ALLOW_MARKER='nch-allow'

# marker file letting this repository hold the patterns above without
# flagging itself
NCH_SELF_MARKER='.no-claude-help-source'

# awk processes escape sequences in -v assignments, which turns \(c\) into a
# capture group and \. into "any character". reading through ENVIRON instead
# passes every pattern to the regex engine exactly as written here.
export NCH_IDENT_STRONG NCH_IDENT_WEAK NCH_IDENT_ROBOT NCH_IDENT_ALLOWED_BOTS \
	NCH_MSG_BAD_TRAILER NCH_MSG_COAUTHOR NCH_MSG_CREDIT NCH_MSG_ROBOT_LINE \
	NCH_MSG_ROBOT_CONTEXT NCH_MSG_SESSION_URL NCH_PATH_ATTRIBUTION \
	NCH_PATH_MANIFEST NCH_PATH_LICENSE NCH_CONTENT_ATTRIB_KEY \
	NCH_CONTENT_PERSON NCH_CONTENT_COPYRIGHT NCH_ALLOW_MARKER NCH_SELF_MARKER
