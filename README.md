# agent-plugins

A Claude Code plugin marketplace for the team. Each plugin is a directory at the repo root.

Install a plugin:

```
/plugin install <plugin> --marketplace lawtrann/agent-plugins
```

## Prerequisites (plugin authors)

- [mise](https://mise.jdx.dev). It installs the pinned `jq`.
- Claude Code ≥ 2.1.287 (mods need it). Check with `claude --version`; upgrade with `claude update`. An organization admin can block mods for your account.
- In a fresh clone:

  ```sh
  mise trust
  mise install
  mise generate git-pre-commit --write --task "check --staged"
  ```

  The last line installs the pre-commit hook. Git does not version hooks, so each clone needs it once.

## Tasks

| Task | What it does |
| --- | --- |
| `mise run plugin:new <name> --kind skill\|mod [--description <text>]` | Copies a template to `./<name>/`, adds the entry to `marketplace.json`, then runs `check <name>`. |
| `mise run check [plugin] [--staged]` | `claude plugin validate --strict` on the marketplace and on each selected plugin; checks entry name = `plugin.json` name = directory; checks the plugin kind; runs `claude plugin test` for a mod. |
| `mise run plugin:bump <plugin> patch\|minor\|major` | Needs a clean tree. Runs `claude plugin eval` (report stays local), then increments `version` in `plugin.json`. It does not run `check` and does not commit. |
| `mise run plugin:tag <plugin>` | Asks for confirmation, then runs `claude plugin tag --dry-run` and `claude plugin tag --push`. Refuses a dirty tree or an existing tag. |

The pre-commit hook is the only place that runs `check` automatically. It checks only the plugins that have staged files (the marketplace is always validated).

## One plugin, one kind

- **skill**: contains exactly one skill, `skills/<name>/SKILL.md`, with the same name as the plugin. It is invoked as `/<name>:<name>`. It has two eval cases from the start: `evals/triggers-on-request/` (the skill must fire) and `evals/ignores-unrelated/` (it must not). Replace their `TODO` prompts before the first release, or `plugin:bump` stops at the evals.
- **mod**: a TypeScript hooks module, `hooks/register.ts`, listed in `hooks/hooks.json` under `modules`. The engine loads `.ts` directly, so there is no build step. A hooks module can import only its own files (by relative path) and `claude-code`: no npm packages. Tests are `tests/*.test.ts`, run by `claude plugin test`.

A plugin never mixes the two. To combine them, list the other plugin under `dependencies` in `plugin.json`.

`version` lives only in `plugin.json`. Marketplace entries have no `version`.

## Dev loop

```sh
claude --plugin-dir <name>
```

This loads `./<name>/` in place, for that session only. For a mod, `/plugin` shows `1 mod active · <name>`.

## Release

```sh
mise run plugin:bump <plugin> patch      # evals, then version bump
git commit -am "chore(<plugin>): v<x.y.z>"   # the hook runs check
mise run plugin:tag <plugin>             # tag <plugin>--v<x.y.z> and push it
```

Push the branch as well, so the tagged commit is on GitHub.

Run `plugin:bump` and `plugin:tag` in a terminal. The first `claude plugin eval` asks you to trust the plugin directory; a yes trusts the whole repository. `plugin:tag` asks for confirmation. Without a terminal, both stop.

See [CHECKLIST.md](CHECKLIST.md) for what is verified and what is still an assumption.
