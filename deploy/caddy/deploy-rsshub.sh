#!/usr/bin/env bash
set -euo pipefail

RSSHUB_DIR="${RSSHUB_DIR:-/home/RSSHub}"
RSSHUB_BRANCH="${RSSHUB_BRANCH:-sherry/dev}"
RSSHUB_LOCK_FILE="${RSSHUB_LOCK_FILE:-/tmp/rsshub-deploy.lock}"
RSSHUB_GIT_SSH_KEY="${RSSHUB_GIT_SSH_KEY:-/var/lib/caddy/id_ed25519}"
RSSHUB_BUILD_NODE_OPTIONS="${RSSHUB_BUILD_NODE_OPTIONS:---max-old-space-size=512}"

if [ -f "$RSSHUB_GIT_SSH_KEY" ]; then
    export GIT_SSH_COMMAND="ssh -i $RSSHUB_GIT_SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi

if command -v pnpm >/dev/null 2>&1; then
    pnpmCommand=(pnpm)
elif command -v corepack >/dev/null 2>&1; then
    pnpmCommand=(corepack pnpm)
else
    echo "Neither pnpm nor corepack is available. Install Node.js 22.20+ or 24 with corepack enabled."
    exit 1
fi

exec 9>"$RSSHUB_LOCK_FILE"
if ! flock -n 9; then
    echo "Another RSSHub deployment is already running."
    exit 0
fi

cd "$RSSHUB_DIR"

current_branch="$(git branch --show-current)"
if [ "$current_branch" != "$RSSHUB_BRANCH" ]; then
    echo "Refusing to deploy branch '$RSSHUB_BRANCH' while checkout is on '$current_branch'."
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Refusing to deploy with a dirty working tree."
    git status --short
    exit 1
fi

git fetch origin "$RSSHUB_BRANCH"
git merge --ff-only FETCH_HEAD

PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 "${pnpmCommand[@]}" install --frozen-lockfile
NODE_OPTIONS="$RSSHUB_BUILD_NODE_OPTIONS" RSSHUB_ROUTE_ALLOWLIST_CONFIG=config/personal-route-allowlist.json "${pnpmCommand[@]}" build:routes

sudo -n systemctl restart rsshub
systemctl is-active --quiet rsshub

echo "RSSHub deployed successfully."
