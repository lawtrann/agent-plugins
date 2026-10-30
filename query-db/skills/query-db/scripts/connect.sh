#!/usr/bin/env bash
#
# connect.sh — named Cloud SQL targets from a local config, and a connection test.
#
#   ${CLAUDE_SKILL_DIR}/scripts/connect.sh list <PROJECT_DIR>
#   ${CLAUDE_SKILL_DIR}/scripts/connect.sh test <PROJECT_DIR> <TARGET>
#   ${CLAUDE_SKILL_DIR}/scripts/connect.sh test <PROJECT_DIR> <project:region:instance> <PORT> [DB]
#   ${CLAUDE_SKILL_DIR}/scripts/connect.sh save <PROJECT_DIR> <TARGET> <project:region:instance> <PORT> <DB> [repo|shared]
#
# Targets live outside every repo, one per line: <name> <project:region:instance> <port> <db>
#   ~/.config/query-db/<repo>/targets   for the repo at <PROJECT_DIR> (read first)
#   ~/.config/query-db/targets          for every repo
# <repo> is the directory name of the main worktree, so all worktrees of a repo share one file.
#
# test starts or reuses the proxy (proxy-up.sh), then runs SELECT current_user, current_database().
# Success prints two lines:  ready localhost:<PORT> (...)  and  <user>|<db>
# Exit codes: 1 proxy or psql failed, 2 missing tool or bad argument, 3 unknown target, 4 no database given.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/query-db"

usage() {
  sed -n '5,8p' "$0" | sed 's/^#   //' >&2
  exit 2
}

repo_name() {
  local common
  if common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    basename "$(dirname "$common")"
  else
    basename "$1"
  fi
}

# The config files to read, most specific first.
config_files() {
  echo "$CONFIG/$(repo_name "$1")/targets"
  echo "$CONFIG/targets"
}

# targets <project-dir>: "<name> <conn> <port> <db> <file>" per target; a repo target hides a shared one of the same name.
targets() {
  local file
  config_files "$1" | while read -r file; do
    [ -f "$file" ] || continue
    awk -v f="$file" '!/^[[:space:]]*(#|$)/ && NF >= 3 { print $1, $2, $3, (NF >= 4 ? $4 : "-"), f }' "$file"
  done | awk '!seen[$1]++'
}

valid_conn() { [[ "$1" =~ ^[a-z0-9.:-]+:[a-z0-9-]+:[a-z0-9-]+$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{4,5}$ ]]; }

cmd="${1:-}"
[ $# -ge 2 ] || usage
project="$2"
[ -d "$project" ] || { echo "no such directory: $project" >&2; exit 2; }

case "$cmd" in
  list)
    echo "config files (first match wins):"
    config_files "$project" | while read -r file; do
      if [ -f "$file" ]; then echo "  $file"; else echo "  $file (missing)"; fi
    done
    found="$(targets "$project")"
    if [ -z "$found" ]; then
      echo "no targets"
    else
      echo "targets (name connection port db):"
      awk '{ print "  " $1, $2, $3, $4 }' <<<"$found"
    fi
    ;;

  test)
    if [ $# -eq 3 ]; then
      line="$(targets "$project" | awk -v n="$3" '$1 == n')"
      if [ -z "$line" ]; then
        echo "no target '$3' in: $(config_files "$project" | tr '\n' ' ')" >&2
        exit 3
      fi
      read -r _ conn port db _ <<<"$line"
    elif [ $# -ge 4 ]; then
      conn="$3" port="$4" db="${5:--}"
    else
      usage
    fi
    valid_conn "$conn" || { echo "bad connection name '$conn' (want project:region:instance)" >&2; exit 2; }
    valid_port "$port" || { echo "bad port '$port'" >&2; exit 2; }

    for bin in cloud-sql-proxy psql pg_isready gcloud; do
      command -v "$bin" >/dev/null || { echo "$bin not found in PATH" >&2; exit 2; }
    done
    account="$(gcloud config get-value account 2>/dev/null)"
    [ -n "$account" ] || { echo "no gcloud account. Run: gcloud auth login" >&2; exit 2; }
    # An IAM database user is the account email; a service account drops ".gserviceaccount.com".
    user="${account%.gserviceaccount.com}"

    "$HERE/proxy-up.sh" "$port" "$conn"
    dsn="host=localhost port=$port user=$user sslmode=disable"
    if [ "$db" = "-" ]; then
      echo "no database given. Databases on this instance:" >&2
      psql "$dsn dbname=postgres" -Atc "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1" >&2 || exit 1
      exit 4
    fi
    psql "$dsn dbname=$db" -Atc "SELECT current_user, current_database()" || exit 1
    ;;

  save)
    [ $# -ge 6 ] || usage
    name="$3" conn="$4" port="$5" db="$6" scope="${7:-repo}"
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "bad target name '$name' (kebab-case)" >&2; exit 2; }
    valid_conn "$conn" || { echo "bad connection name '$conn' (want project:region:instance)" >&2; exit 2; }
    valid_port "$port" || { echo "bad port '$port'" >&2; exit 2; }
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "bad database name '$db'" >&2; exit 2; }
    case "$scope" in
      repo) file="$CONFIG/$(repo_name "$project")/targets" ;;
      shared) file="$CONFIG/targets" ;;
      *) usage ;;
    esac
    mkdir -p "$(dirname "$file")"
    touch "$file"
    # Replace a target of the same name, keep everything else.
    awk -v n="$name" '$1 != n' "$file" >"$file.tmp"
    echo "$name $conn $port $db" >>"$file.tmp"
    mv "$file.tmp" "$file"
    echo "saved $name in $file"
    ;;

  *) usage ;;
esac
