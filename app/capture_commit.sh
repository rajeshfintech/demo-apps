#!/bin/bash
# Script to capture Git commit hash during Docker build

# Get the current commit hash
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# Write to commit.txt file
echo "${COMMIT_HASH:0:8}" > /app/commit.txt

echo "Captured commit hash: ${COMMIT_HASH:0:8}"
