#!/bin/bash

# Emergency rollback script for production
# Quick rollback to the last known good deployment

set -euo pipefail

# Configuration
REPO="rajeshfintech/demo-apps"
APP_NAME="flask-web"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Emergency rollback function
emergency_rollback() {
    local environment="${1:-prod}"
    
    echo "EMERGENCY ROLLBACK"
    echo "===================="
    echo ""
    log_warning "This will rollback $environment to the previous successful deployment"
    echo ""
    
    # Get the last 2 successful deployments
    log_info "Finding last successful deployments..."
    
    local workflows=()
    case "$environment" in
        "prod")
            workflows=("CD • Production (manual approval)")
            ;;
        "staging")
            workflows=("CD • Auto Promote & Deploy Staging (on main)")
            ;;
        "dev")
            workflows=("CI • Build Once & Deploy Dev")
            ;;
    esac
    
    local deployments=()
    for workflow in "${workflows[@]}"; do
        while IFS=$'\t' read -r run_number created_at short_sha title; do
            deployments+=("$run_number|$created_at|$short_sha|$title")
        done < <(gh run list \
            --repo "$REPO" \
            --workflow "$workflow" \
            --status success \
            --limit 5 \
            --json conclusion,createdAt,headSha,displayTitle,number \
            --jq '.[] | select(.conclusion == "success") | [.number, .createdAt, .headSha[0:8], .displayTitle] | @tsv')
        
        if [ ${#deployments[@]} -ge 2 ]; then
            break
        fi
    done
    
    if [ ${#deployments[@]} -lt 2 ]; then
        log_error "Cannot find enough deployment history for rollback"
        exit 1
    fi
    
    # Show current and previous deployments
    echo "Recent Deployments:"
    echo "====================="
    
    local current_deployment="${deployments[0]}"
    local previous_deployment="${deployments[1]}"
    
    IFS='|' read -r current_run current_time current_sha current_title <<< "$current_deployment"
    IFS='|' read -r previous_run previous_time previous_sha previous_title <<< "$previous_deployment"
    
    echo "Current:  Run #$current_run  | $current_sha | $current_title"
    echo "Previous: Run #$previous_run | $previous_sha | $previous_title"
    echo ""
    
    # Confirm emergency rollback
    log_warning "EMERGENCY ROLLBACK CONFIRMATION"
    echo "Environment: $environment"
    echo "Rolling back FROM: $current_sha ($current_title)"
    echo "Rolling back TO:   $previous_sha ($previous_title)"
    echo ""
    echo "This will:"
    echo "1. Immediately trigger a rollback workflow"
    echo "2. Deploy the previous version to $environment"
    if [[ "$environment" == "prod" ]]; then
        echo "3. Use the fastest deployment method (test workflow - NO APPROVAL)"
    fi
    echo ""
    
    read -p "PROCEED WITH EMERGENCY ROLLBACK? (type 'ROLLBACK' to confirm): " confirmation
    
    if [[ "$confirmation" != "ROLLBACK" ]]; then
        log_info "Emergency rollback cancelled"
        exit 0
    fi
    
    # For production, require additional confirmation
    if [[ "$environment" == "prod" ]]; then
        echo ""
        log_warning "PRODUCTION EMERGENCY ROLLBACK"
        echo "This will trigger a manual approval workflow for production safety."
        echo ""
        read -p "Confirm production emergency rollback (type 'PROD-EMERGENCY'): " prod_confirmation
        
        if [[ "$prod_confirmation" != "PROD-EMERGENCY" ]]; then
            log_info "Production emergency rollback cancelled"
            exit 0
        fi
    fi
    
    # Get full commit SHA
    local full_commit_sha
    full_commit_sha=$(gh run view "$previous_run" --repo "$REPO" --json headSha --jq '.headSha')
    
    log_info "EXECUTING EMERGENCY ROLLBACK..."
    
    # Use appropriate workflow based on environment
    case "$environment" in
        "prod")
            log_info "Using manual approval workflow for production emergency rollback..."
            gh workflow run "CD • Production (manual approval)" \
                --repo "$REPO" \
                --field commit_sha="$full_commit_sha"
            ;;
        "staging"|"dev")
            log_info "Using promote workflow for rollback..."
            gh workflow run "CD • Promote Image (No Rebuild)" \
                --repo "$REPO" \
                --field commit_sha="$full_commit_sha" \
                --field to_env="$environment"
            ;;
    esac
    
    log_success "EMERGENCY ROLLBACK TRIGGERED!"
    
    # Get workflow URL
    sleep 2
    local run_url
    run_url=$(gh run list --repo "$REPO" --limit 1 --json url --jq '.[0].url')
    
    echo ""
    echo "🔗 Monitor emergency rollback:"
    echo "   $run_url"
    echo ""
    echo "Emergency Rollback Summary:"
    echo "   Environment: $environment"
    echo "   Rolled back to: $previous_sha"
    echo "   Previous deployment: Run #$previous_run"
    if [[ "$environment" == "prod" ]]; then
        echo "   Method: Manual approval workflow (requires human approval)"
        echo ""
        log_warning "Production rollback requires manual approval for safety"
        echo "   1. Check GitHub Actions for the approval issue"
        echo "   2. Approve the rollback in the created issue"
        echo "   3. Monitor the deployment after approval"
    else
        echo "   Method: Promote workflow (safe image re-tagging)"
    fi
    echo ""
    
    log_info "Next steps:"
    echo "   1. Monitor the rollback deployment"
    echo "   2. Verify application is working correctly"
    echo "   3. Investigate the issue that caused the rollback"
    echo "   4. Plan a proper fix and deployment"
}

# Show help
show_help() {
    echo "Emergency Rollback Script"
    echo "============================"
    echo ""
    echo "Usage: $0 [environment]"
    echo ""
    echo "Environments:"
    echo "  prod      Production (default)"
    echo "  staging   Staging"
    echo "  dev       Development"
    echo ""
    echo "Examples:"
    echo "  $0           # Emergency rollback production"
    echo "  $0 prod      # Emergency rollback production"
    echo "  $0 staging   # Emergency rollback staging"
    echo ""
    echo "WARNING: This script is for EMERGENCY situations only!"
    echo ""
    echo "What this script does:"
    echo "  1. Finds the last 2 successful deployments"
    echo "  2. Shows current vs previous deployment"
    echo "  3. Rolls back to the previous deployment"
    echo "  4. Uses promote workflow (safe image re-tagging)"
    echo ""
    echo "For deployment workflows with approval, use: ./rollback.sh --interactive"
    echo ""
}

# Main function
main() {
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is required but not installed"
        echo "Install from: https://cli.github.com/"
        exit 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated. Run 'gh auth login' first."
        exit 1
    fi
    
    local environment="prod"
    
    # Parse arguments
    case "${1:-}" in
        prod|staging|dev)
            environment="$1"
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
        "")
            # Use default (prod)
            ;;
        *)
            log_error "Unknown environment: $1"
            show_help
            exit 1
            ;;
    esac
    
    emergency_rollback "$environment"
}

# Run main function
main "$@"
