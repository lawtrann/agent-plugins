# Shared helpers for the mise tasks in scripts/mise/tasks/.
# Source this file. It is not executable, so mise does not list it as a task.

ROOT="$(git rev-parse --show-toplevel)"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
TEMPLATES="$ROOT/scripts/mise/templates"
MIN_CLAUDE="2.1.287" # mods need this version

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
