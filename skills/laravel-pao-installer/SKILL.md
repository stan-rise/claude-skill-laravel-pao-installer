---
name: laravel-pao-installer
description: >-
  Install laravel/pao (agent-optimized output for PHP testing tools) into a
  Laravel / PHP project. PAO replaces verbose PHPUnit / Pest / Paratest /
  PHPStan / Rector / Artisan output with compact JSON when an AI agent is
  detected. Use when the user asks to "install pao", "add laravel/pao",
  "set up agent-optimized test output", "make test output smaller for the
  agent", or "/install-pao". Detects PHP/Laravel version incompatibilities
  and aborts with a clear message before touching composer.
---

# Laravel PAO Installer

Installs [`laravel/pao`](https://github.com/laravel/pao) — agent-optimized
output for PHP testing tools. Zero runtime config: once required, PAO
auto-discovers its Laravel service provider and Pest plugin via Composer.
It only activates when an AI agent (Claude Code, Cursor, Devin, Gemini CLI,
etc.) is detected, so human terminal workflows are unchanged.

## Hard requirements (PAO 1.x)

PAO declares these constraints in its `composer.json`:

| Requirement | Constraint |
|-------------|-----------|
| PHP         | `^8.3` |
| laravel/framework (if present) | `>=12.0.0` (conflicts with `<12.0.0`) |
| phpunit/phpunit (if present) | `>=12.5.23 <13.0.0` or `>=13.1.7 <14.0.0` |
| pestphp/pest (if present) | `>=4.6.3 <6.0.0` |
| nunomaduro/collision (if present) | `>=8.9.3` |

If the target project violates any of these, `composer require` will fail.
**Always run the preflight check first and abort with a clear explanation
rather than letting composer error out cryptically.**

## Procedure

### 1. Locate the project root

Find the directory containing `composer.json`. Confirm with the user if
ambiguous (monorepo / multiple composer projects).

### 2. Run the preflight check

Run the bundled script from the project root:

```bash
bash <skill-dir>/scripts/preflight.sh <project-root>
```

It inspects `composer.json` (and the running PHP version if available) and
prints either `PREFLIGHT_OK` or `PREFLIGHT_FAIL` with the specific reasons.

- If it prints `PREFLIGHT_FAIL`: **stop**. Report each failing reason to the
  user verbatim, explain that PAO 1.x cannot be installed on this project as-is,
  and suggest the concrete upgrade(s) needed (e.g. "bump PHP to 8.3+",
  "upgrade Laravel to 12+"). Do **not** run `composer require`.
- If it prints `PREFLIGHT_OK`: continue.

### 3. Install

Use the project's normal PHP/Composer entrypoint. Many projects run Composer
inside Docker — check `Makefile` / `docker-compose.yml` for a wrapper before
falling back to host `composer`.

```bash
composer require laravel/pao --dev
```

If the project runs Composer in a container (e.g. a `make composer`
target or `docker exec <php-container> composer ...`), use that instead of
host `composer`. Ask the user which entrypoint to use if unclear.

### 4. Verify

- Confirm `laravel/pao` appears in `composer.json` under `require-dev`.
- Confirm it is present in `composer.lock`.
- For Laravel: `Laravel\Pao\Laravel\ServiceProvider` is auto-discovered — no
  manual registration needed. Don't add it to `config/app.php` or
  `bootstrap/providers.php`.
- Optional sanity check: run the project's test command once. With an AI
  agent detected, output should be compact JSON
  (`{"tool":"phpunit","result":"passed",...}`).

### 5. Report

Summarize: what was installed, the resolved version, and that no config is
required. If preflight failed, summarize the blockers and the upgrade path
instead.

## Notes

- PAO is `--dev` only. Never add it to production `require`.
- Do not edit PAO's own files or scaffold config — it is intentionally
  zero-config.
- If `composer require` fails despite a passing preflight (e.g. a transitive
  conflict), surface composer's actual error to the user rather than forcing
  `-W` / `--ignore-platform-reqs` without asking.
- Default branch of `laravel/pao` is `1.x`; the Packagist package is
  `laravel/pao`.
