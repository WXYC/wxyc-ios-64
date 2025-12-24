#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <tag-name> <new-commit-ish> [remote]" >&2
  exit 1
fi

tag="$1"
commit="$2"
remote="${3:-origin}"

# Ensure we're in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# Ensure the commit exists
if ! git rev-parse --verify "$commit" >/dev/null 2>&1; then
  echo "Error: commit '$commit' not found." >&2
  exit 1
fi

echo "Retagging '$tag' to point at '$commit' on remote '$remote'..."
echo

# Delete local tag if it exists
if git show-ref --tags --quiet --verify "refs/tags/$tag"; then
  echo "Deleting local tag '$tag'..."
  git tag -d "$tag"
else
  echo "Local tag '$tag' does not exist, skipping local delete."
fi

# Delete remote tag if it exists
if git ls-remote --tags "$remote" "refs/tags/$tag" | grep -q .; then
  echo "Deleting remote tag '$tag' from '$remote'..."
  # Either of these is fine; this one is explicit:
  git push "$remote" ":refs/tags/$tag"
else
  echo "Remote tag '$tag' does not exist on '$remote', skipping remote delete."
fi

# Create the new tag at the desired commit (lightweight tag)
echo "Creating new tag '$tag' at '$commit'..."
git tag "$tag" "$commit"

# Push the updated tag
echo "Pushing tag '$tag' to '$remote'..."
git push "$remote" "$tag"

echo
echo "Done. Tag '$tag' now points to '$commit' locally and on '$remote'."

