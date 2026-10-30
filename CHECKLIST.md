# Checklist

Each item is an assumption until it is ticked.
When you verify an item, tick the box. Write the date, the method and the result in "Notes".
If an item is false, fix the process, the template or the README before you continue.

Docs:
[plugins](https://code.claude.com/docs/en/plugins/) ·
[manifest](https://code.claude.com/docs/en/plugins-reference) ·
[loading](https://code.claude.com/docs/en/plugins/loading) ·
[evals](https://code.claude.com/docs/en/plugin-evals) ·
[troubleshooting](https://code.claude.com/docs/en/plugins/troubleshooting) ·
[mise tasks](https://mise.jdx.dev/tasks/)

## A. Once per repo

Verify these items when you set up the repo. Verify them again after you upgrade Claude Code or mise.

- [x] **A1. The marketplace name is not reserved.**
  How: run `claude plugin validate .` at the repo root.
  Notes: 2026-10-31, Claude Code 2.1.314. **False for `claude-plugins`**: error "Marketplace name impersonates an official Anthropic/Claude marketplace". The repo moved to `lawtrann/agent-plugins`, marketplace name `agent-plugins`; validate passes. `--strict` also needs a marketplace `description`, and fails while `plugins` is empty (`check` validates an empty marketplace without `--strict`).
- [x] **A2. `claude plugin validate --strict` also checks `marketplace.json`. This includes the check "entry name == manifest name".**
  How: make the two names different on purpose. Then run validate.
  Notes: 2026-10-31, entry `x` with `source: ./s` and plugin.json `s`. **False**: validate reports only that the README has no install line for `x`. `mise run check` does the name check with jq. (`claude plugin tag` does check that the entry and plugin.json agree.)
- [ ] **A3. `claude plugin validate` runs in CI without login.**
  How: run it in an environment that has no credentials.
  If false: CI needs a secret for the free check step too.
  Notes:
- [x] **A4. The file task `scripts/mise/tasks/plugin/new` becomes `plugin:new`. It takes a parameter through `#USAGE arg "<name>"`.**
  How: run `mise tasks` and `mise run plugin:new --help`.
  Notes: 2026-10-31, mise 2026.10.21. Confirmed by docs and by a spike: `includes = ["scripts/mise/tasks"]` gives `plugin:new`; a `choices` block rejects `--kind bar` ("Invalid choice for option kind"); a missing `required=#true` flag fails; a non-executable `lib.sh` is not listed.
- [ ] **A5. mise installs the pinned `jq` on dev machines and in CI.**
  How: run `mise install` on a clean machine or in CI. (The `claude` CLI is installed separately.)
  Notes:
- [ ] **A6. All team accounts can use mods.**
  Known: mods need Claude Code ≥ 2.1.287 (`require_claude` in `scripts/mise/lib.sh` enforces it), and an organization admin can block mods.
  How: ask a teammate to install a mod.
  If false: write the requirement in the README.
  Notes:
- [x] **A7. A local eval uses the subscription. It does not need an API key.**
  Notes: 2026-10-31. `claude plugin eval` ran a 4-run suite with no `ANTHROPIC_API_KEY` in the environment. The trust prompt appears under `mise run` in a terminal. A yes trusts the whole repository. `--trust-plugin` does not persist.
- [ ] **A9. When you bump `version`, the team gets the new version.**
  The docs say that auto-update is **off by default** for third-party marketplaces.
  How: bump the version and push. Then check if a second machine updates.
  If false: the README tells the team to run `claude plugin update` or to turn on `autoUpdate`.
  Notes:

## B. Each new plugin or release

Note: `--plugin-dir` loads the plugin **in place**. A marketplace added from a local path also loads it in place.
A team install from GitHub **copies the plugin into the cache**.
Thus item B4 fails only in a team-style install (B7).

### All plugins

- [ ] **B1. The plugin name is kebab-case. It is not reserved.** Reserved forms: `claude-*`, `anthropic-*`, `cc-plugin-*`, and `official` next to `claude`. No other plugin in the marketplace has the same name. (`plugin:new` checks the prefixes and duplicates.)
- [ ] **B2. The entry `name` in `marketplace.json` is the same as `name` in `plugin.json`.** (`check` verifies it; see A2.)
- [ ] **B3. `claude plugin validate --strict <name>` shows no errors and no warnings.**
- [ ] **B4. No path or symlink points outside `<name>/`.** Do not use `../`. Do not use a shared tsconfig or lib at the repo root.
  An install copies only the plugin directory.
- [ ] **B5. Each bare name in `dependencies` is a plugin in this marketplace. The version constraints do what you expect.**
  How: read the dependencies docs. Then do a test install.
- [ ] **B6. `claude plugin eval` loads the plugins that this plugin depends on.** This applies only to plugins with `dependencies`.
- [ ] **B7. Do a team-style install.** Add the marketplace from a GitHub branch. Install the plugin. Then look at the Errors tab in `/plugin`.
  Open question: the syntax to add a marketplace from a branch.
- [ ] **B8. For a release, bump `version` in `plugin.json`.** (`plugin:bump`.)

### Skill

- [ ] **B9. The skill eval passes.** The eval checks that the skill triggers at the right time. It also checks that the result is correct. Run it locally at release (`plugin:bump` does).
  Grader syntax, confirmed by the evals docs: "skill fired" is `type: tool_used`, `tool: Skill`, `input_match`; "skill did not fire" adds `min: 0`, `max: 0` and `arm: both` (without `arm: both`, a `tool: Skill` grader is not scored in a two-arm run).

### Mod (TypeScript)

- [x] **B10. The hooks module loads `.ts` files directly.**
  Notes: 2026-10-31. Confirmed by docs (plugin-authoring skill, Claude Code 2.1.314). The template mod passes `claude plugin validate --strict` and `claude plugin test` with no build step.
- [x] **B11. Can a mod import npm packages?**
  Notes: 2026-10-31, spike: a mod with `package.json`, `bun.lock` and `node_modules/ms`. **No.** `claude plugin validate` and `claude plugin test` both refuse it: "a hooks module imports its own files by relative path and "claude-code", nothing else". Bun, `package.json` and lockfiles are therefore not part of the template.
- [x] **B13. `claude plugin test <name>` runs the mod tests outside a session.** The tests import `test`, `expect`, `mock` from `claude-code/testing` and get `$` and `on`. (`check` runs it for every mod.)
  Notes: 2026-10-31. The template test passes under `claude plugin test`.
