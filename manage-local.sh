#!/bin/bash

# Local management script for Podman deployment
# This script provides management commands for the locally deployed Flask app

set -euo pipefail

# Configuration
APP_NAME="flask-web-local"
IMAGE_NAME="localhost/flask-web"
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

# Check container status
status() {
    echo "Container Status"
    echo "=================="
    
    if podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        echo "🟢 Container is running"
        podman ps --filter "name=${APP_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        echo ""
        echo "🌐 Application URLs:"
        echo "   Home:     http://localhost:${HOST_PORT}"
        echo "   Health:   http://localhost:${HOST_PORT}/healthz"
        echo "   Debug:    http://localhost:${HOST_PORT}/debug"
        echo "   Actuator: http://localhost:${HOST_PORT}/actuator"
        
    elif podman ps -a --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        echo "🔴 Container exists but is not running"
        podman ps -a --filter "name=${APP_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "⚪ Container does not exist"
        echo "Run './deploy-local.sh' to deploy the application"
    fi
}

# Show logs
logs() {
    if podman ps -a --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        if [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]]; then
            log_info "Following logs for $APP_NAME (Ctrl+C to stop)..."
            podman logs -f "$APP_NAME"
        else
            log_info "Showing logs for $APP_NAME..."
            podman logs "$APP_NAME"
        fi
    else
        log_error "Container $APP_NAME does not exist"
        exit 1
    fi
}

# Start container
start() {
    if podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_warning "Container $APP_NAME is already running"
        return 0
    fi
    
    if podman ps -a --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_info "Starting container $APP_NAME..."
        podman start "$APP_NAME"
        log_success "Container started"
    else
        log_error "Container $APP_NAME does not exist. Run './deploy-local.sh' first."
        exit 1
    fi
}

# Stop container
stop() {
    if podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_info "Stopping container $APP_NAME..."
        podman stop "$APP_NAME"
        log_success "Container stopped"
    else
        log_warning "Container $APP_NAME is not running"
    fi
}

# Restart container
restart() {
    log_info "Restarting container $APP_NAME..."
    stop
    sleep 2
    start
    log_success "Container restarted"
}

# Remove container and optionally images
remove() {
    local remove_images=false
    
    if [[ "${1:-}" == "--images" ]]; then
        remove_images=true
    fi
    
    # Stop container if running
    if podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_info "Stopping container $APP_NAME..."
        podman stop "$APP_NAME"
    fi
    
    # Remove container
    if podman ps -a --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_info "Removing container $APP_NAME..."
        podman rm "$APP_NAME"
        log_success "Container removed"
    fi
    
    # Remove images if requested
    if [ "$remove_images" = true ]; then
        log_info "Removing images..."
        podman images --format "{{.Repository}}:{{.Tag}}" | grep "^${IMAGE_NAME}:" | while read -r image; do
            log_info "Removing image: $image"
            podman rmi "$image" || true
        done
        log_success "Images removed"
    fi
    
    # Remove network if no other containers are using it
    if podman network exists "$NETWORK_NAME" 2>/dev/null; then
        local network_containers
        network_containers=$(podman network inspect "$NETWORK_NAME" --format "{{len .Containers}}" 2>/dev/null || echo "0")
        if [ "$network_containers" -eq 0 ]; then
            log_info "Removing unused network: $NETWORK_NAME"
            podman network rm "$NETWORK_NAME"
            log_success "Network removed"
        fi
    fi
}

# Execute command in container
exec_cmd() {
    if ! podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_error "Container $APP_NAME is not running"
        exit 1
    fi
    
    if [[ $# -eq 0 ]]; then
        log_info "Opening interactive shell in container..."
        podman exec -it "$APP_NAME" /bin/bash
    else
        log_info "Executing command in container: $*"
        podman exec -it "$APP_NAME" "$@"
    fi
}

# Test application endpoints
test() {
    if ! podman ps --format "{{.Names}}" | grep -q "^${APP_NAME}$"; then
        log_error "Container $APP_NAME is not running"
        exit 1
    fi
    
    log_info "Testing application endpoints..."
    
    echo ""
    echo "🧪 Endpoint Tests"
    echo "================"
    
    # Test home page
    echo -n "🏠 Home page: "
    if response=$(curl -s "http://localhost:${HOST_PORT}/" 2>/dev/null); then
        echo "SUCCESS: $response"
    else
        echo "ERROR: Failed to connect"
    fi
    
    # Test health check
    echo -n "Health check: "
    if health=$(curl -s "http://localhost:${HOST_PORT}/healthz" 2>/dev/null); then
        if echo "$health" | grep -q "ok"; then
            echo "SUCCESS: Healthy"
        else
            echo "WARNING: Response: $health"
        fi
    else
        echo "ERROR: Failed to connect"
    fi
    
    # Test debug endpoint
    echo -n "Debug info: "
    if curl -s "http://localhost:${HOST_PORT}/debug" >/dev/null 2>&1; then
        echo "SUCCESS: Available"
    else
        echo "ERROR: Not available"
    fi
    
    # Test actuator endpoints
    echo -n "Actuator info: "
    if curl -s "http://localhost:${HOST_PORT}/actuator/info" >/dev/null 2>&1; then
        echo "SUCCESS: Available"
    else
        echo "ERROR: Not available"
    fi
    
    echo -n "Actuator metrics: "
    if curl -s "http://localhost:${HOST_PORT}/actuator/metrics" >/dev/null 2>&1; then
        echo "SUCCESS: Available"
    else
        echo "ERROR: Not available"
    fi
    
    echo ""
}

# Show help
help() {
    echo "🛠️  Flask Local Management Script"
    echo "================================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show container status and URLs"
    echo "  logs [-f|--follow]  Show container logs (optionally follow)"
    echo "  start               Start the container"
    echo "  stop                Stop the container"
    echo "  restart             Restart the container"
    echo "  remove [--images]   Remove container (and optionally images)"
    echo "  exec [command]      Execute command in container (or open shell)"
    echo "  test                Test application endpoints"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status           # Check if app is running"
    echo "  $0 logs -f          # Follow application logs"
    echo "  $0 restart          # Restart the application"
    echo "  $0 exec python      # Open Python shell in container"
    echo "  $0 remove --images  # Remove everything"
    echo ""
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        help
        exit 0
    fi
    
    case "${1:-}" in
        status|st)
            status
            ;;
        logs|log)
            shift
            logs "$@"
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            restart
            ;;
        remove|rm)
            shift
            remove "$@"
            ;;
        exec|sh)
            shift
            exec_cmd "$@"
            ;;
        test)
            test
            ;;
        help|--help|-h)
            help
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
