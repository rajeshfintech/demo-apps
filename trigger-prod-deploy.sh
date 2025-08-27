#!/bin/bash

# Script to trigger production deployment with manual approval
# Only uses approved workflows for production safety
set -euo pipefail

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed. Please install jq first."
    echo "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) is required but not installed."
    echo "Install from: https://cli.github.com/"
    exit 1
fi

# Check GitHub CLI authentication
if ! gh auth status &> /dev/null; then
    echo "ERROR: GitHub CLI is not authenticated."
    echo "Run: gh auth login"
    exit 1
fi

COMMIT_SHA="${1:-$(git rev-parse HEAD)}"
SHORT_HASH=$(git rev-parse --short "$COMMIT_SHA")
REPO="rajeshfintech/demo-apps"

echo "Production Deployment"
echo "Repository: $REPO"
echo "Commit SHA: $COMMIT_SHA"
echo "Short hash: $SHORT_HASH"
echo ""

echo "Production deployment requires manual approval for safety."
echo ""
echo "Available options:"
echo "1) Manual approval workflow (recommended - requires human approval)"
echo "2) Promote existing image (also requires manual approval for production)"
echo ""
read -p "Select option (1 or 2): " -n 1 -r
echo

case $REPLY in
    1)
        echo ""
        echo "Triggering manual approval workflow..."
        
        # Check if the commit has a corresponding container image
        echo "Checking if container image exists for commit $COMMIT_SHA..."
        IMAGE_TAG="sha-$COMMIT_SHA"
        IMAGE_NAME="ghcr.io/rajeshfintech/flask-web:$IMAGE_TAG"

        # Use GitHub CLI to trigger the workflow
        gh workflow run "CD • Production (manual approval)" \
          --repo "$REPO" \
          --field commit_sha="$COMMIT_SHA"

        echo ""
        echo "Manual approval workflow triggered!"
        echo ""
        echo "Next steps:"
        echo "1. Go to: https://github.com/$REPO/actions"
        echo "2. Find the 'CD • Production (manual approval)' workflow run"
        echo "3. The workflow will create an approval issue"
        echo "4. Approve the deployment in the issue"
        echo "5. The deployment will proceed to production"
        ;;
    2)
        echo ""
        echo "Promoting existing image with approval..."
        echo "Finding available commits..."
        
        # Function to get recent commits from git history
        get_recent_commits() {
            echo "Getting recent commits from git history..." >&2
            
            # Get last 20 commits from current branch and main
            {
                git log --oneline -20 --format="%H %s" 2>/dev/null || true
                git log --oneline -20 --format="%H %s" origin/main 2>/dev/null || true
            } | sort -u | head -20
        }
        
        # Function to get commits from GitHub releases
        get_release_commits() {
            echo "Getting commits from GitHub releases..." >&2
            gh api "/repos/$REPO/releases" --jq '.[].tag_name' 2>/dev/null | head -10 | while read -r tag; do
                if [ -n "$tag" ]; then
                    commit=$(gh api "/repos/$REPO/git/refs/tags/$tag" --jq '.object.sha' 2>/dev/null || echo "")
                    if [ -n "$commit" ]; then
                        echo "$commit Release: $tag"
                    fi
                fi
            done
        }
        
        echo "Collecting available commits..."
        temp_file=$(mktemp)
        
        # Try multiple sources for commits
        {
            get_recent_commits
            get_release_commits
        } > "$temp_file" 2>/dev/null
        
        # Parse and deduplicate commits
        available_commits=$(cat "$temp_file" | cut -d' ' -f1 | sort -u | head -15)
        
        if [ -z "$available_commits" ]; then
            echo "ERROR: Could not find recent commits."
            echo "You can manually enter a commit hash, or use current commit."
            echo ""
            echo "Options:"
            echo "1) Use current commit ($SHORT_HASH)"
            echo "2) Enter commit hash manually"
            echo ""
            read -p "Select option (1 or 2): " -n 1 -r
            echo
            
            case $REPLY in
                1)
                    selected_commit="$COMMIT_SHA"
                    echo "Using current commit: $SHORT_HASH"
                    ;;
                2)
                    echo ""
                    while true; do
                        read -p "Enter commit hash (full or short): " manual_commit
                        if [ -n "$manual_commit" ]; then
                            # Try to resolve short hash to full hash
                            if full_commit=$(git rev-parse "$manual_commit" 2>/dev/null); then
                                selected_commit="$full_commit"
                                echo "Using commit: $(echo "$selected_commit" | cut -c1-8)"
                                break
                            else
                                echo "ERROR: Invalid commit hash. Please try again."
                            fi
                        else
                            echo "ERROR: Please enter a commit hash."
                        fi
                    done
                    ;;
                *)
                    echo "ERROR: Invalid option. Using current commit."
                    selected_commit="$COMMIT_SHA"
                    ;;
            esac
        else
            echo ""
            echo "Available commits (most recent first):"
            echo ""
            
            # Create numbered list
            commit_array=()
            i=1
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    commit=$(echo "$line" | cut -d' ' -f1)
                    message=$(echo "$line" | cut -d' ' -f2- || echo "")
                    
                    if [ -n "$commit" ]; then
                        commit_array+=("$commit")
                        short_commit=$(echo "$commit" | cut -c1-8)
                        
                        if [ -n "$message" ]; then
                            echo "$i) $short_commit - $message"
                        else
                            echo "$i) $short_commit"
                        fi
                        ((i++))
                    fi
                fi
            done < "$temp_file"
            
            echo ""
            echo "0) Use current commit ($SHORT_HASH)"
            echo "99) Enter commit hash manually"
            echo ""
            
            # Get user selection
            while true; do
                read -p "Select commit (0-$((${#commit_array[@]})), or 99 for manual): " selection
                
                if [[ "$selection" =~ ^[0-9]+$ ]]; then
                    if [ "$selection" -eq 0 ]; then
                        selected_commit="$COMMIT_SHA"
                        echo "Selected current commit: $SHORT_HASH"
                        break
                    elif [ "$selection" -eq 99 ]; then
                        echo ""
                        while true; do
                            read -p "Enter commit hash (full or short): " manual_commit
                            if [ -n "$manual_commit" ]; then
                                if full_commit=$(git rev-parse "$manual_commit" 2>/dev/null); then
                                    selected_commit="$full_commit"
                                    echo "Using commit: $(echo "$selected_commit" | cut -c1-8)"
                                    break 2
                                else
                                    echo "ERROR: Invalid commit hash. Please try again."
                                fi
                            else
                                echo "ERROR: Please enter a commit hash."
                            fi
                        done
                    elif [ "$selection" -ge 1 ] && [ "$selection" -le "${#commit_array[@]}" ]; then
                        selected_commit="${commit_array[$((selection-1))]}"
                        selected_short=$(echo "$selected_commit" | cut -c1-8)
                        echo "Selected commit: $selected_short"
                        break
                    else
                        echo "ERROR: Invalid selection. Please choose 0-$((${#commit_array[@]})) or 99"
                    fi
                else
                    echo "ERROR: Please enter a number."
                fi
            done
        fi
        
        # Ensure we always have a selected commit
        if [ -z "${selected_commit:-}" ]; then
            selected_commit="$COMMIT_SHA"
        fi
        
        rm -f "$temp_file"
        
        echo ""
        echo "Promoting image for commit: $(echo "$selected_commit" | cut -c1-8)"
        
        # Use manual approval workflow with selected commit
        gh workflow run "CD • Production (manual approval)" \
          --repo "$REPO" \
          --field commit_sha="$selected_commit"

        echo ""
        echo "Production approval workflow triggered for image promotion!"
        echo ""
        echo "Next steps:"
        echo "1. Go to: https://github.com/$REPO/actions"
        echo "2. Find the 'CD • Production (manual approval)' workflow run"
        echo "3. The workflow will create an approval issue"
        echo "4. Approve the deployment in the issue"
        echo "5. The selected image will be deployed to production"
        ;;
    *)
        echo "ERROR: Invalid option. Exiting."
        exit 1
        ;;
esac

echo ""
if [ "$REPLY" = "2" ] && [ -n "${selected_commit:-}" ]; then
    echo "Selected image: ghcr.io/rajeshfintech/flask-web:sha-$(echo "$selected_commit" | cut -c1-8)"
else
    echo "Expected image: ghcr.io/rajeshfintech/flask-web:sha-$COMMIT_SHA"
fi
echo "Monitor at: https://github.com/$REPO/actions"
