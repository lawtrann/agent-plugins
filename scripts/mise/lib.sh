# Shared helpers for the mise tasks in scripts/mise/tasks/.
# Source this file. It is not executable, so mise does not list it as a task.

ROOT="$(git rev-parse --show-toplevel)"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
TEMPLATES="$ROOT/scripts/mise/templates"
MIN_CLAUDE="2.1.287" # mods need this version
RELEASE_BRANCH="develop" # the only long-lived branch; team installs come from it
CC_TYPES="feat|fix|docs|test|refactor|perf|style|build|ci|chore|revert"
ZERO_SHA="0000000000000000000000000000000000000000" # git's "no commit", e.g. a new branch in pre-push

die() {
  echo "error: $*" >&2
  exit 1
}

# version_ge A B: succeeds when version A >= version B (x.y.z).
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if (x[i] + 0 > y[i] + 0) exit 0
      if (x[i] + 0 < y[i] + 0) exit 1
    }
    exit 0
  }'
}

require_claude() {
  command -v claude >/dev/null || die "claude is not on PATH. Install Claude Code >= $MIN_CLAUDE."
  local v
  v="$(claude --version | awk '{print $1}')"
  version_ge "$v" "$MIN_CLAUDE" || die "Claude Code $v is too old. Mods need >= $MIN_CLAUDE. Run: claude update"
}

# plugin_dirs: one plugin directory per line (relative to ROOT), from marketplace.json.
plugin_dirs() {
  jq -r '.plugins[].source | ltrimstr("./")' "$MARKETPLACE"
}

# plugin_kind <dir>: prints "mod" or "skill"; fails when the kind is both or neither.
plugin_kind() {
  local dir="$1" is_mod=false is_skill=false
  if [ -f "$dir/hooks/hooks.json" ] && jq -e '(.modules // []) | length > 0' "$dir/hooks/hooks.json" >/dev/null; then
    is_mod=true
  fi
  [ -d "$dir/skills" ] && is_skill=true
  if $is_mod && $is_skill; then
    echo "error: $dir is both a mod (hooks/hooks.json declares modules) and a skill plugin (skills/ exists). A plugin has exactly one kind." >&2
    return 1
  elif $is_mod; then
    echo mod
  elif $is_skill; then
    echo skill
  else
    echo "error: $dir is neither a mod (no modules in hooks/hooks.json) nor a skill plugin (no skills/)." >&2
    return 1
  fi
}

# validate_name <name>: fails with the reason when <name> cannot be a new plugin.
validate_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] ||
    die "'$name' is not kebab-case (lowercase letters, digits and single hyphens)."
  case "$name" in
    claude-* | anthropic-* | anthropics-* | cc-plugin-*)
      die "'$name' starts with a reserved prefix (claude-, anthropic-, anthropics-, cc-plugin-)." ;;
    scripts | docs | node_modules)
      die "'$name' is reserved for the repo itself." ;;
  esac
  [ ! -e "$ROOT/$name" ] || die "'$name' already exists at the repo root."
  ! jq -e --arg n "$name" 'any(.plugins[]; .name == $n)' "$MARKETPLACE" >/dev/null ||
    die "'$name' is already an entry in marketplace.json."
}

# plugin_dir <name>: the plugin's directory (relative to ROOT), from marketplace.json. Empty when <name> is not an entry.
# check makes the directory equal to the name, so the release rules below use the directory as the name.
plugin_dir() {
  jq -r --arg n "$1" '.plugins[] | select(.name == $n) | .source | ltrimstr("./")' "$MARKETPLACE"
}

# In the git helpers below, <ref> "" means the index (the staged content).

# plugin_dirs_at <ref>: like plugin_dirs, from marketplace.json at <ref>.
plugin_dirs_at() {
  { git show "$1:.claude-plugin/marketplace.json" 2>/dev/null | jq -r '.plugins[].source | ltrimstr("./")'; } || true
}

# plugin_tree <commit> <dir>: the tree hash of <dir> at <commit>. Empty when <dir> does not exist there.
plugin_tree() {
  git rev-parse -q --verify "$1:$2" 2>/dev/null || true
}

# version_at <ref> <dir>: the version in <dir>/.claude-plugin/plugin.json at <ref>. Empty when there is none.
version_at() {
  { git show "$1:$2/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty'; } || true
}

# manifest_sans_version <ref> <dir>: plugin.json at <ref> without "version", normalized for comparison.
manifest_sans_version() {
  { git show "$1:$2/.claude-plugin/plugin.json" 2>/dev/null | jq -S 'del(.version)'; } || true
}

# semver_gt A B: succeeds when version A > version B.
semver_gt() {
  [ "$1" != "$2" ] && version_ge "$1" "$2"
}

# last_tag <name>: the highest release tag <name>--v<version>. Empty when there is none.
last_tag() {
  git tag -l "$1--v*" --sort=-v:refname | sed -n 1p
}

# lint_subject <subject> <dir>: fails, with the reason, unless <subject> is "type(<dir>)[!]: text".
lint_subject() {
  local re="^($CC_TYPES)\\(([a-z0-9-]+)\\)!?: .+"
  if ! [[ "$1" =~ $re ]]; then
    echo "'$1' is not a Conventional Commit subject: type($2)[!]: text, with type one of ${CC_TYPES//|/, }" >&2
    return 1
  fi
  if [ "${BASH_REMATCH[2]}" != "$2" ]; then
    echo "'$1' has the scope '${BASH_REMATCH[2]}'; it must be the plugin, '$2'" >&2
    return 1
  fi
}

# check_release <base> <new> <dir> <subject> <trailer>: fails, with the reasons, unless going from <base> to <new>
# is a release of <dir>: the subject is "chore(<dir>): release v<version>", the version goes up and is the only
# change in <dir>, and the Verified-Tree trailer is the tree of <dir> at <base> (the tree that plugin:bump verified).
check_release() {
  local base="$1" new="$2" dir="$3" subject="$4" trailer="$5" ver old changed tree why=""
  ver="$(version_at "$new" "$dir")"
  old="$(version_at "$base" "$dir")"
  tree="$(plugin_tree "$base" "$dir")"
  if [ -n "$new" ]; then
    changed="$(git diff --name-only "$base" "$new" -- "$dir")"
  else
    changed="$(git diff --cached --name-only "$base" -- "$dir")"
  fi
  [ "$subject" = "chore($dir): release v$ver" ] ||
    why="$why  the subject must be 'chore($dir): release v$ver'"$'\n'
  { [ -n "$old" ] && semver_gt "$ver" "$old"; } ||
    why="$why  the version must go up from '$old' (it is '$ver')"$'\n'
  { [ "$changed" = "$dir/.claude-plugin/plugin.json" ] &&
    [ "$(manifest_sans_version "$base" "$dir")" = "$(manifest_sans_version "$new" "$dir")" ]; } ||
    why="$why  a release changes only 'version' in $dir/.claude-plugin/plugin.json"$'\n'
  [ -n "$trailer" ] && [ "$trailer" = "$tree" ] ||
    why="$why  the trailer must be 'Verified-Tree: $tree' (it is '$trailer'). Only plugin:bump writes it, after the evals pass"$'\n'
  [ -z "$why" ] && return 0
  printf '%s' "$why" >&2
  return 1
}

# is_release_commit <commit> <dir>: check_release from the parent of <commit> to <commit>.
is_release_commit() {
  check_release "$1^" "$1" "$2" "$(git log -1 --format=%s "$1")" \
    "$(git log -1 --format='%(trailers:key=Verified-Tree,valueonly)' "$1")"
}
