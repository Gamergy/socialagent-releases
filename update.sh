#!/usr/bin/env bash
# SocialAgent update / rollback. Deliberate + reversible: pins an exact version,
# saves the previous one, and recreates the stack. NOT an auto-update.
#
#   ./update.sh latest    # update to the newest published version
#   ./update.sh 0.2.0     # update to an exact version
#   ./update.sh rollback  # revert to the previously-running version
#
# "latest" reads the public version manifest (VERSION_MANIFEST_URL in .env) —
# the same source the in-app "update available" banner uses.
# Run from the folder that holds docker-compose.client.yml and .env.
set -euo pipefail
COMPOSE="docker-compose.client.yml"
ENV_FILE=".env"
[ -f "$COMPOSE" ]  || { echo "Run this from the folder with $COMPOSE"; exit 1; }
[ -f "$ENV_FILE" ] || { echo "No .env found — copy .env.client.example to .env first."; exit 1; }

# Tolerates a missing key (no set -e death) and a UTF-8 BOM on line 1 (a .env
# touched by Windows tools); .env is ASCII so the byte strip is safe.
get()    { tr -d '\357\273\277' < "$ENV_FILE" | grep -E "^$1=" | head -1 | cut -d= -f2- || :; }
set_kv() { if grep -qE "^$1=" "$ENV_FILE"; then sed -i.bak -E "s|^$1=.*|$1=$2|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"; else echo "$1=$2" >> "$ENV_FILE"; fi; }

cur="$(get SOCIALAGENT_VERSION)"
arg="${1:-}"
if [ "$arg" = "latest" ]; then
  url="$(get VERSION_MANIFEST_URL)"
  [ -n "$url" ] || { echo "VERSION_MANIFEST_URL is not set in .env — run ./update.sh <version> instead."; exit 1; }
  latest="$(curl -fsSL "$url" | tr -d ' \t\r\n' | sed -n 's/.*"latest":"\([^"]*\)".*/\1/p')" || latest=""
  [ -n "$latest" ] || { echo "Couldn't read the latest version from $url — check your internet connection."; exit 1; }
  if [ "$latest" = "$cur" ]; then echo "Already up to date ($cur)."; exit 0; fi
  echo "Newest published version: $latest"
  arg="$latest"
fi
case "$arg" in
  rollback)
    target="$(get SOCIALAGENT_PREV_VERSION)"
    [ -n "$target" ] || { echo "No previous version recorded — nothing to roll back to."; exit 1; }
    echo "Rolling back: ${cur:-unset} -> $target";;
  "")
    echo "Usage: ./update.sh <version> | rollback"
    echo "Currently running: ${cur:-unset}"; exit 1;;
  *)
    target="$arg"
    echo "Updating: ${cur:-unset} -> $target";;
esac

# Record the version we're leaving so rollback works (skip when rolling back).
if [ "$arg" != "rollback" ] && [ -n "$cur" ]; then set_kv SOCIALAGENT_PREV_VERSION "$cur"; fi
set_kv SOCIALAGENT_VERSION "$target"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE" pull
docker compose --env-file "$ENV_FILE" -f "$COMPOSE" up -d
echo "Now running $target.  Roll back any time with: ./update.sh rollback"
