#!/bin/bash

# Script to trigger production deployment with manual CLI approval
set -euo pipefail

COMMIT_SHA="${1:-$(git rev-parse HEAD)}"
REPO="rajeshfintech/demo-apps"

echo "🚀 Triggering production deployment with manual approval..."
echo "Repository: $REPO"
echo "Commit SHA: $COMMIT_SHA"
echo ""

echo "⚠️  PRODUCTION DEPLOYMENT APPROVAL REQUIRED"
echo "This will deploy to the production environment."
echo ""
read -p "Type 'approved' to proceed with deployment: " APPROVAL

if [ "$APPROVAL" != "approved" ]; then
    echo "❌ Deployment cancelled. You entered: '$APPROVAL'"
    echo "✅ To approve, you must type exactly: 'approved'"
    exit 1
fi

echo ""
echo "🔧 Triggering workflow via GitHub CLI..."
gh workflow run "prod-manual.yml" \
  --repo "$REPO" \
  --field commit_sha="$COMMIT_SHA" \
  --field approved="approved"

echo ""
echo "✅ Production deployment workflow triggered with approval!"
echo ""
echo "📋 Monitor progress at:"
echo "https://github.com/$REPO/actions"
echo ""
echo "🔍 Expected image: ghcr.io/rajeshfintech/flask-web:sha-$COMMIT_SHA"
