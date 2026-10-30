---
name: query-db
description: "Connect to a Cloud SQL PostgreSQL database through cloud-sql-proxy with IAM auth, using named targets from a local config. Use when the user asks to connect to, or check the connection to, a Cloud SQL database or a named database target such as 'staging'. Not for installing tools, for writing SQL without a connection, or for other database engines."
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/*)
---

# query-db

Connect to a Cloud SQL PostgreSQL database and prove the connection with one query.
Connection details come from a local config outside every repo. Never write them into a repo or into this plugin.

## Step 1: find the target

    ${CLAUDE_SKILL_DIR}/scripts/connect.sh list "${CLAUDE_PROJECT_DIR}"

The output lists the config files it reads and one line per target: name, connection name, port, database.
- Use the target that the user named. If exactly one target fits the request, use it. If several fit, ask with AskUserQuestion.
- No targets, or none fits: go to Step 3.

## Step 2: connect

    ${CLAUDE_SKILL_DIR}/scripts/connect.sh test "${CLAUDE_PROJECT_DIR}" <TARGET>

The script checks the tools (cloud-sql-proxy, psql, pg_isready, gcloud) and the gcloud account. It then starts the proxy or reuses one, and runs `SELECT current_user, current_database()`.

**Success criterion**: two lines.

    ready localhost:<PORT> (reused | started pid N)
    <account>|<database>

Report the account and the database. Leave the proxy running.

On failure, the exit code tells you what to do:
- 2: a missing tool, no gcloud account or a bad argument. Tell the user what is missing, then stop.
- 3: the target is unknown. Go to Step 3.
- 4: the target has no database. The script lists the databases on the instance. Ask the user which one to use. Do not guess. Then run Step 3's ad hoc test with that database.
- 1: the proxy or psql failed. Show the last lines of the output and check Gotchas.

## Step 3: no target

Ask with one AskUserQuestion call, with one question for each value:
- the connection name, `project:region:instance`;
- a free local port;
- the database (optional).

Then test with those values:

    ${CLAUDE_SKILL_DIR}/scripts/connect.sh test "${CLAUDE_PROJECT_DIR}" <project:region:instance> <PORT> [DB]

When the test passes, offer to save the values as a target. Save only if the user says yes:

    ${CLAUDE_SKILL_DIR}/scripts/connect.sh save "${CLAUDE_PROJECT_DIR}" <TARGET> <project:region:instance> <PORT> <DB> [repo|shared]

`repo` (the default) writes `~/.config/query-db/<repo>/targets`, which is read only in this repo. `shared` writes `~/.config/query-db/targets`, which every repo reads.

# Gotchas

- When a refused connection on `(::1)` is printed next to the `127.0.0.1` line, ignore it. It is noise. Read the `127.0.0.1` line.
- Do not `pkill` cloud-sql-proxy. Another session can be using the same proxy. Stop a proxy only when the user asks: `${CLAUDE_SKILL_DIR}/scripts/proxy-down.sh <PORT>`.
- `Connection refused` on a port that worked minutes ago means that the proxy stopped. Run Step 2 again.
- If the permission prompt blocks a script, do not try other forms of the command. Ask the user to run the same command with the `!` prefix.
- An IAM or authentication error means that the gcloud account has no IAM database user on that instance, or no Cloud SQL Client role. Tell the user, then stop.
