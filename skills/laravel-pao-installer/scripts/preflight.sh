#!/usr/bin/env bash
#
# preflight.sh — verify a project can install laravel/pao (1.x).
#
# Usage: bash preflight.sh [project-root]   (defaults to CWD)
#
# Emits a human-readable report, then a final line:
#   PREFLIGHT_OK    — safe to `composer require laravel/pao --dev`
#   PREFLIGHT_FAIL  — one or more hard requirements violated (see reasons)
#
# Checks (PAO 1.x composer.json):
#   - PHP >= 8.3            (require.php = "^8.3")
#   - laravel/framework     >= 12.0.0   (conflict: <12.0.0)
#   - phpunit/phpunit       12.5.23–12.x or 13.1.7–13.x
#   - pestphp/pest          4.6.3–5.x
#   - nunomaduro/collision  >= 8.9.3
#
# Pure bash + grep/sed — no PHP, jq, or composer required to run.

set -u

ROOT="${1:-$(pwd)}"
COMPOSER_JSON="$ROOT/composer.json"
COMPOSER_LOCK="$ROOT/composer.lock"

FAILS=()
WARNS=()

note()  { printf '  - %s\n' "$1"; }
fail()  { FAILS+=("$1"); }
warn()  { WARNS+=("$1"); }

# ---- semver helpers -------------------------------------------------------

# Normalize "v1.2.3", "1.2.3-dev", "1.2" -> "1 2 3" (space separated, padded).
ver_parts() {
  local v="$1"
  v="${v#v}"
  v="${v%%[-+]*}"          # strip prerelease/build metadata
  v="${v%%.x}"             # 8.x -> 8
  local IFS=.
  read -r a b c <<<"$v"
  printf '%s %s %s' "${a:-0}" "${b:-0}" "${c:-0}"
}

# ver_ge A B  -> return 0 if A >= B
ver_ge() {
  read -r a1 a2 a3 <<<"$(ver_parts "$1")"
  read -r b1 b2 b3 <<<"$(ver_parts "$2")"
  (( a1 != b1 )) && { (( a1 > b1 )); return; }
  (( a2 != b2 )) && { (( a2 > b2 )); return; }
  (( a3 >= b3 ))
}

# ver_lt A B  -> return 0 if A < B
ver_lt() { ! ver_ge "$1" "$2"; }

# Extract the first concrete minimum version token from a composer constraint
# string. Handles ^8.3, >=12.0.0, ~4.6.3, 5.0.0|^6, "12.5.23 || ^13.1".
min_version() {
  # grab first NN[.NN[.NN]] occurrence
  grep -oE '[0-9]+(\.[0-9]+){0,2}' <<<"$1" | head -n1
}

# Read a package's version constraint from composer.json require/require-dev.
# Echoes the raw constraint, or empty string if package not present.
pkg_constraint() {
  local pkg="$1"
  # match  "vendor/pkg": "constraint"
  grep -oE "\"${pkg//\//\\/}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$COMPOSER_JSON" 2>/dev/null \
    | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/'
}

# Read a package's locked version from composer.lock (more reliable than the
# constraint when available).
pkg_locked() {
  local pkg="$1"
  [ -f "$COMPOSER_LOCK" ] || return 0
  # crude but effective: find the "name": "pkg" object and the nearest "version"
  grep -A3 "\"name\": \"${pkg}\"" "$COMPOSER_LOCK" 2>/dev/null \
    | grep -oE '"version": "[^"]+"' | head -n1 | sed -E 's/.*"version": "([^"]+)".*/\1/'
}

# Resolve the effective version to test: prefer lock, fall back to constraint min.
effective_version() {
  local pkg="$1" v
  v="$(pkg_locked "$pkg")"
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  local c; c="$(pkg_constraint "$pkg")"
  [ -n "$c" ] && min_version "$c"
}

# ---- start ----------------------------------------------------------------

echo "PAO preflight — target: $ROOT"
echo

if [ ! -f "$COMPOSER_JSON" ]; then
  echo "No composer.json found at: $COMPOSER_JSON"
  echo "Cannot install a Composer package without a composer.json."
  echo
  echo "PREFLIGHT_FAIL"
  exit 1
fi

# 1. PHP version --------------------------------------------------------------
# Prefer the actually-running PHP, fall back to composer.json require.php.
PHP_RUNTIME=""
if command -v php >/dev/null 2>&1; then
  PHP_RUNTIME="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null)"
fi

PHP_CONSTRAINT="$(pkg_constraint 'php')"
PHP_CONSTRAINT_MIN=""
[ -n "$PHP_CONSTRAINT" ] && PHP_CONSTRAINT_MIN="$(min_version "$PHP_CONSTRAINT")"

# The composer.json require.php constraint is authoritative for the project
# regardless of which PHP runs this script — many projects run Composer/PHP
# inside Docker, so the host `php` binary may not be the project's PHP.
# Check the constraint independently, then the runtime as an extra signal.
if [ -n "$PHP_CONSTRAINT_MIN" ]; then
  note "PHP constraint in composer.json: $PHP_CONSTRAINT (min $PHP_CONSTRAINT_MIN)"
  if ver_lt "$PHP_CONSTRAINT_MIN" "8.3.0"; then
    fail "composer.json requires PHP $PHP_CONSTRAINT — PAO requires PHP ^8.3. Bump the project's PHP requirement to ^8.3 first."
  fi
fi

if [ -n "$PHP_RUNTIME" ]; then
  note "PHP runtime detected: $PHP_RUNTIME"
  if ver_lt "$PHP_RUNTIME" "8.3.0"; then
    fail "PHP runtime is $PHP_RUNTIME — PAO requires PHP ^8.3 (>= 8.3.0). If your project runs PHP in Docker, run this script inside the project's PHP container for an accurate result."
  fi
fi

if [ -z "$PHP_CONSTRAINT_MIN" ] && [ -z "$PHP_RUNTIME" ]; then
  warn "Could not determine PHP version (no php binary, no require.php). PAO needs PHP ^8.3 — verify manually."
fi

# 2. laravel/framework --------------------------------------------------------
LARAVEL_V="$(effective_version 'laravel/framework')"
if [ -n "$LARAVEL_V" ]; then
  note "laravel/framework: $LARAVEL_V"
  if ver_lt "$LARAVEL_V" "12.0.0"; then
    fail "laravel/framework $LARAVEL_V — PAO conflicts with laravel/framework <12.0.0. Upgrade Laravel to 12+ first."
  fi
else
  note "laravel/framework: not present (non-Laravel project — OK, PAO supports vanilla PHP)."
fi

# 3. phpunit/phpunit ----------------------------------------------------------
PHPUNIT_V="$(effective_version 'phpunit/phpunit')"
if [ -n "$PHPUNIT_V" ]; then
  note "phpunit/phpunit: $PHPUNIT_V"
  # allowed: >=12.5.23 <13.0.0  OR  >=13.1.7 <14.0.0
  ok_pu=1
  if ver_ge "$PHPUNIT_V" "12.5.23" && ver_lt "$PHPUNIT_V" "13.0.0"; then ok_pu=0; fi
  if ver_ge "$PHPUNIT_V" "13.1.7" && ver_lt "$PHPUNIT_V" "14.0.0"; then ok_pu=0; fi
  if [ "$ok_pu" -ne 0 ]; then
    fail "phpunit/phpunit $PHPUNIT_V — PAO requires PHPUnit >=12.5.23 (<13.0.0) or >=13.1.7 (<14.0.0)."
  fi
else
  note "phpunit/phpunit: not present (OK if using Pest or no PHPUnit)."
fi

# 4. pestphp/pest -------------------------------------------------------------
PEST_V="$(effective_version 'pestphp/pest')"
if [ -n "$PEST_V" ]; then
  note "pestphp/pest: $PEST_V"
  # allowed: >=4.6.3 <6.0.0
  if ! { ver_ge "$PEST_V" "4.6.3" && ver_lt "$PEST_V" "6.0.0"; }; then
    fail "pestphp/pest $PEST_V — PAO requires Pest >=4.6.3 and <6.0.0."
  fi
else
  note "pestphp/pest: not present (OK if using PHPUnit or no Pest)."
fi

# 5. nunomaduro/collision -----------------------------------------------------
COLLISION_V="$(effective_version 'nunomaduro/collision')"
if [ -n "$COLLISION_V" ]; then
  note "nunomaduro/collision: $COLLISION_V"
  if ver_lt "$COLLISION_V" "8.9.3"; then
    fail "nunomaduro/collision $COLLISION_V — PAO conflicts with collision <8.9.3. Upgrade collision to >=8.9.3 first."
  fi
else
  note "nunomaduro/collision: not present (OK)."
fi

# ---- verdict ----------------------------------------------------------------

echo
if [ "${#WARNS[@]}" -gt 0 ]; then
  echo "Warnings:"
  for w in "${WARNS[@]}"; do note "$w"; done
  echo
fi

if [ "${#FAILS[@]}" -gt 0 ]; then
  echo "Blocking issues — PAO 1.x cannot be installed on this project as-is:"
  for f in "${FAILS[@]}"; do note "$f"; done
  echo
  echo "PREFLIGHT_FAIL"
  exit 1
fi

echo "All hard requirements satisfied."
echo "PREFLIGHT_OK"
exit 0
