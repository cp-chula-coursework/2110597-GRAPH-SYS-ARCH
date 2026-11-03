#!/bin/sh
# make_playground_branch.sh - build the branch the VGA Playground loads.
#
#   scripts/make_playground_branch.sh          # build the branch locally
#   scripts/make_playground_branch.sh --push   # ... and push it to origin
#
# The playground only reads info.yaml from the root of a branch, and source and
# .mem files from src/ beneath it. In this repo the project lives in
# project04_slidepuzzle/, not at the root. So this script makes a commit whose
# root *is* that folder, taken from the committed HEAD, and points the branch
# project04-playground at it. Each run adds one commit on top of the last, so
# a push never needs --force.
#
# Commit your changes first: the branch is built from HEAD, not from the
# working tree.
set -e

BRANCH=project04-playground
PREFIX=project04_slidepuzzle
REPO_URL=https://github.com/cp-chula-coursework/2110597-GRAPH-SYS-ARCH

cd "$(git rev-parse --show-toplevel)"

tree=$(git rev-parse "HEAD:$PREFIX")
src=$(git rev-parse --short HEAD)

if git rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
    if [ "$(git rev-parse "$BRANCH^{tree}")" = "$tree" ]; then
        echo "$BRANCH is already up to date with $src"
        commit=$(git rev-parse "$BRANCH")
    else
        commit=$(git commit-tree "$tree" -p "$BRANCH" -m "Playground build of $PREFIX at $src")
    fi
else
    commit=$(git commit-tree "$tree" -m "Playground build of $PREFIX at $src")
fi
git branch -f "$BRANCH" "$commit"

echo "$BRANCH -> $(git rev-parse --short "$commit"), root = $PREFIX/ at $src:"
git ls-tree --name-only "$BRANCH" info.yaml
git ls-tree --name-only "$BRANCH" src/

if [ "$1" = "--push" ]; then
    git push origin "$BRANCH"
fi

echo
echo "Open in the VGA Playground (once the branch is pushed):"
echo "  https://vga-playground.com/?repo=$REPO_URL&ref=$BRANCH"
