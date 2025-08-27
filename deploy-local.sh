#!/bin/bash

# Local deployment script using Podman
# This script builds and runs the Flask application locally

set -euo pipefail

# Configuration
APP_NAME="flask-web-local"
IMAGE_NAME="localhost/flask-web"
CONTAINER_PORT=8080
HOST_PORT=8080
NETWORK_NAME="flask-network"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
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

# Check if podman is installed
check_podman() {
    if ! command -v podman &> /dev/null; then
        log_error "Podman is not installed. Please install Podman first."
        echo "Visit: https://podman.io/getting-started/installation"
        exit 1
    fi
    log_success "Podman is installed: $(podman --version)"
}

# Get Git commit information
get_git_info() {
    GIT_COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    GIT_SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log_info "Git commit: $GIT_SHORT_HASH ($GIT_BRANCH)"
}

# Clean up existing containers and images
cleanup() {
    log_info "Cleaning up existing containers and images..."
    
    # Stop and remove container if it exists
    if podman ps -a --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_info "Stopping existing container: $APP_NAME"
        podman stop "$APP_NAME" || true
        podman rm "$APP_NAME" || true
    fi
    
    # Remove existing image if requested
    if [[ "${1:-}" == "--clean" ]]; then
        if podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}:"; then
            log_info "Removing existing images"
            podman rmi "${IMAGE_NAME}:latest" || true
            podman rmi "${IMAGE_NAME}:${GIT_SHORT_HASH}" || true
        fi
    fi
}

# Build the container image
build_image() {
    log_info "Building container image..."
    
    podman build \
        --build-arg GIT_COMMIT_HASH="$GIT_COMMIT_HASH" \
        --build-arg BUILD_TIME="$BUILD_TIME" \
        --build-arg GIT_BRANCH="$GIT_BRANCH" \
        -t "${IMAGE_NAME}:latest" \
        -t "${IMAGE_NAME}:${GIT_SHORT_HASH}" \
        .
    
    log_success "Image built successfully: ${IMAGE_NAME}:${GIT_SHORT_HASH}"
}

# Create network if it doesn't exist
create_network() {
    if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
        log_info "Creating network: $NETWORK_NAME"
        podman network create "$NETWORK_NAME"
        log_success "Network created: $NETWORK_NAME"
    else
        log_info "Network already exists: $NETWORK_NAME"
    fi
}

# Run the container
run_container() {
    log_info "Starting container..."
    
    podman run -d \
        --name "$APP_NAME" \
        --network "$NETWORK_NAME" \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -e ENVIRONMENT=local \
        -e GIT_COMMIT_HASH="$GIT_COMMIT_HASH" \
        -e BUILD_TIME="$BUILD_TIME" \
        -e GIT_BRANCH="$GIT_BRANCH" \
        "${IMAGE_NAME}:latest"
    
    log_success "Container started: $APP_NAME"
}

# Wait for the application to be ready
wait_for_app() {
    log_info "Waiting for application to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:${HOST_PORT}/healthz" > /dev/null 2>&1; then
            log_success "Application is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log_error "Application failed to start within ${max_attempts} seconds"
    return 1
}

# Show application information
show_info() {
    echo ""
    echo "Flask Application Deployed Locally"
    echo "======================================"
    echo "Application URL: http://localhost:${HOST_PORT}"
    echo "Health Check:    http://localhost:${HOST_PORT}/healthz"
    echo "Debug Info:      http://localhost:${HOST_PORT}/debug"
    echo "Actuator Info:   http://localhost:${HOST_PORT}/actuator/info"
    echo "Metrics:         http://localhost:${HOST_PORT}/actuator/metrics"
    echo ""
    echo "Build Information"
    echo "===================="
    echo "Commit Hash:     $GIT_SHORT_HASH"
    echo "Branch:          $GIT_BRANCH"
    echo "Build Time:      $BUILD_TIME"
    echo "Image:           ${IMAGE_NAME}:${GIT_SHORT_HASH}"
    echo "Container:       $APP_NAME"
    echo ""
    echo "Management Commands"
    echo "======================"
    echo "View logs:       podman logs $APP_NAME"
    echo "Follow logs:     podman logs -f $APP_NAME"
    echo "Restart:         podman restart $APP_NAME"
    echo "Stop:            podman stop $APP_NAME"
    echo "Remove:          podman rm $APP_NAME"
    echo ""
}

# Test the application
test_app() {
    log_info "Testing application endpoints..."
    
    echo ""
    echo "🧪 Testing Endpoints"
    echo "==================="
    
    # Test home page
    echo -n "🏠 Home page: "
    if response=$(curl -s "http://localhost:${HOST_PORT}/"); then
        echo "SUCCESS: $response"
    else
        echo "ERROR: Failed"
    fi
    
    # Test health check
    echo -n "🏥 Health check: "
    if curl -s "http://localhost:${HOST_PORT}/healthz" | grep -q "ok"; then
        echo "SUCCESS: Healthy"
    else
        echo "ERROR: Unhealthy"
    fi
    
    # Test actuator info
    echo -n "Actuator info: "
    if curl -s "http://localhost:${HOST_PORT}/actuator/info" | grep -q "app"; then
        echo "SUCCESS: Available"
    else
        echo "ERROR: Not available"
    fi
    
    echo ""
}

# Main function
main() {
    echo "Flask Local Deployment Script"
    echo "================================="
    echo ""
    
    # Parse arguments
    CLEAN_BUILD=false
    RUN_TESTS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --test)
                RUN_TESTS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --clean    Remove existing images before building"
                echo "  --test     Run tests after deployment"
                echo "  --help     Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                 # Build and deploy"
                echo "  $0 --clean        # Clean build and deploy"
                echo "  $0 --clean --test # Clean build, deploy, and test"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_podman
    get_git_info
    
    if [ "$CLEAN_BUILD" = true ]; then
        cleanup --clean
    else
        cleanup
    fi
    
    build_image
    create_network
    run_container
    
    if wait_for_app; then
        show_info
        
        if [ "$RUN_TESTS" = true ]; then
            test_app
        fi
        
        log_success "Deployment completed successfully!"
    else
        log_error "Deployment failed!"
        log_info "Check container logs: podman logs $APP_NAME"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
