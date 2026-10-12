#!/usr/bin/env bash
# Brings the current branch (feinarbyte/main) up to date:
#   1. merges upstream mealie-next
#   2. merges every branch listed in branches.txt
#   3. joins the Alembic history and updates migrations.lock
#
# Used by .github/workflows/fork-build.yml, and by hand to resolve a conflict:
#   git switch feinarbyte/main && git pull
#   .github/fork/sync.sh        # stops at the conflict
#   ...resolve, git commit...
#   .github/fork/sync.sh        # run again until it finishes
#   git push
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/mealie-recipes/mealie.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-mealie-next}"
ORIGIN="${ORIGIN:-origin}"

cd "$(git rev-parse --show-toplevel)"
fork_dir=".github/fork"

if [ -n "$(git status --porcelain)" ]; then
  echo "::error::working tree is not clean, commit or stash first" >&2
  exit 1
fi

merge() {
  local label="$1" ref="$2"
  echo "--- merging $label"
  if ! git merge --no-edit -m "Merge $label into $(git branch --show-current)" "$ref"; then
    echo "::error::merge conflict while merging $label" >&2
    git diff --name-only --diff-filter=U >&2 || true
    echo "Resolve it locally: see the header of $fork_dir/sync.sh" >&2
    exit 1
  fi
}

git fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
upstream_sha="$(git rev-parse FETCH_HEAD)"
merge "upstream $UPSTREAM_BRANCH" "$upstream_sha"

# Read the list before merging, the feature branches do not carry it.
branches="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$fork_dir/branches.txt" | grep -v '^$' || true)"
for branch in $branches; do
  git fetch --no-tags "$ORIGIN" "$branch"
  merge "$branch" "$(git rev-parse FETCH_HEAD)"
done

python3 "$fork_dir/migrations.py" sync

git add -A mealie/alembic/versions "$fork_dir/migrations.lock"
if ! git diff --cached --quiet; then
  git commit -m "chore(fork): update alembic merge and migration lock"
fi

echo "--- done: $(git rev-parse --short HEAD) (upstream ${upstream_sha:0:9})"
