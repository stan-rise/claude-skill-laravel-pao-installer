# Claude Code Skill — Laravel PAO Installer

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that
installs [`laravel/pao`](https://github.com/laravel/pao) into a Laravel / PHP
project.

**PAO** (agent-optimized output) replaces the verbose human-readable output of
PHPUnit, Pest, Paratest, PHPStan, Rector, and Laravel Artisan with compact
structured JSON — but **only when an AI agent is detected**. Human terminal
workflows are unchanged. Up to ~99.8% fewer tokens on large test suites.

## What this skill does

1. **Locates** the target project's `composer.json`.
2. **Preflight check** (`scripts/preflight.sh`) — verifies the project meets
   PAO 1.x's hard requirements *before* touching Composer:
   - PHP `^8.3`
   - `laravel/framework` >= 12 (if present)
   - `phpunit/phpunit` 12.5.23–12.x or 13.1.7–13.x (if present)
   - `pestphp/pest` 4.6.3–5.x (if present)
   - `nunomaduro/collision` >= 8.9.3 (if present)
3. **Aborts with a clear, specific message** if any requirement is violated —
   instead of letting `composer require` fail cryptically.
4. **Installs** via the project's Composer entrypoint (host or Docker):
   `composer require laravel/pao --dev`.
5. **Verifies** the package landed in `composer.json` / `composer.lock` and
   reports.

The preflight reads `composer.lock` (authoritative) with a fallback to
`composer.json` constraint minimums. It is pure bash — no PHP, jq, or composer
needed to *run the check*. For projects that run PHP in Docker, run the
preflight inside the project's PHP container for an accurate PHP-runtime read
(the `composer.json` PHP constraint is always checked regardless).

## Install

Copy the skill into your Claude Code skills directory:

```bash
# Personal (all projects)
cp -r skills/laravel-pao-installer ~/.claude/skills/

# Or per-project (committed with the repo)
cp -r skills/laravel-pao-installer <your-project>/.claude/skills/
```

Then in Claude Code:

> install laravel/pao in this project

or trigger explicitly via the skill name.

## Layout

```
skills/laravel-pao-installer/
├── SKILL.md              # skill instructions & procedure
└── scripts/
    └── preflight.sh      # version-compatibility gate
```

## License

MIT — see [LICENSE](LICENSE).
