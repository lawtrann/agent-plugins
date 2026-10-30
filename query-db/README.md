# query-db

Connect to a Cloud SQL PostgreSQL database through cloud-sql-proxy with IAM auth, using named targets from a local config

## Install

```
/plugin install query-db --marketplace lawtrann/agent-plugins
```

If you already added the marketplace, run `/plugin install query-db@agent-plugins`.

## Usage

The `query-db` skill connects to a Cloud SQL PostgreSQL database through `cloud-sql-proxy` with IAM auth, then proves the connection with `SELECT current_user, current_database()`. Version 0.1.x only connects. It runs no other queries.

Ask in your own words, for example "check that I can connect to the staging database", or run `/query-db:query-db staging`.

### Prerequisites

- `cloud-sql-proxy` (v2), `psql` and `pg_isready` on `PATH`.
- `gcloud auth login` with an account that has an IAM database user on the instance and the Cloud SQL Client role.

### Targets

A target is a name for a connection. The skill reads targets from two files. They are outside every repo, so connection details are never committed:

| File | Read in |
| --- | --- |
| `~/.config/query-db/<repo>/targets` | the repo `<repo>` only (the directory name of its main worktree; all worktrees share it). Read first. |
| `~/.config/query-db/targets` | every repo |

One target per line, `#` for comments:

```
# name     connection (project:region:instance)   local port   database
staging    my-project:my-region:my-instance         15500        app
```

When no target fits, the skill asks you for the connection name, a free local port and the database. After a successful test, it offers to save them as a target. It writes a file only if you say yes. You can also edit the files by hand.

The skill leaves the proxy running. It reuses a proxy that already listens on the target's port.
