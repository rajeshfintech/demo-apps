from flask import Flask, jsonify
import subprocess
import os
import sys
import platform
from datetime import datetime

def get_git_commit_hash():
    """Get the current Git commit hash"""
    # First try to get from environment variable (set during build)
    commit_hash = os.getenv('GIT_COMMIT_HASH')
    if commit_hash and commit_hash != 'unknown':
        return commit_hash[:8]  # Return short hash
    
    # Try to read from a commit file (if created during build)
    try:
        commit_file = os.path.join(os.path.dirname(__file__), 'commit.txt')
        if os.path.exists(commit_file):
            with open(commit_file, 'r') as f:
                content = f.read().strip()
                if content and content != 'unknown':
                    return content[:8]
    except Exception as e:
        print(f"Error reading commit file: {e}")
    
    # Try Git command (for local development)
    try:
        # Try from the app directory first
        result = subprocess.run(['git', 'rev-parse', 'HEAD'], 
                              capture_output=True, text=True, cwd=os.path.dirname(__file__))
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()[:8]
        
        # Try from parent directory
        parent_dir = os.path.dirname(os.path.dirname(__file__))
        result = subprocess.run(['git', 'rev-parse', 'HEAD'], 
                              capture_output=True, text=True, cwd=parent_dir)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()[:8]
            
    except Exception as e:
        print(f"Error running git command: {e}")
    
    return "unknown"

def get_kubernetes_namespace():
    """Get the Kubernetes namespace from the pod's service account"""
    try:
        # Try to read namespace from the service account token mount
        namespace_file = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
        if os.path.exists(namespace_file):
            with open(namespace_file, 'r') as f:
                return f.read().strip()
    except Exception:
        pass
    
    # Fallback to environment variable or default
    return os.getenv('KUBERNETES_NAMESPACE', os.getenv('ENVIRONMENT', 'development'))

def create_app():
    app = Flask(__name__)
    
    # Try to import and initialize Flask Actuator (optional)
    try:
        from .actuator import FlaskActuator
        actuator = FlaskActuator(app)
        print("Flask Actuator initialized successfully")
    except ImportError as e:
        print(f"Flask Actuator not available: {e}")
        # Continue without actuator
        pass

    @app.route("/healthz")
    def healthz():
        """Kubernetes-style health check"""
        return jsonify(status="ok"), 200

    @app.route("/debug")
    def debug():
        """Debug endpoint to troubleshoot commit hash issues"""
        debug_info = {
            "git_commit_hash_env": os.getenv('GIT_COMMIT_HASH', 'Not set'),
            "build_time_env": os.getenv('BUILD_TIME', 'Not set'),
            "git_branch_env": os.getenv('GIT_BRANCH', 'Not set'),
            "environment": get_kubernetes_namespace(),
            "current_directory": os.getcwd(),
            "app_directory": os.path.dirname(__file__),
            "commit_file_exists": os.path.exists(os.path.join(os.path.dirname(__file__), 'commit.txt')),
            "git_directory_exists": os.path.exists(os.path.join(os.path.dirname(__file__), '.git')),
            "parent_git_exists": os.path.exists(os.path.join(os.path.dirname(os.path.dirname(__file__)), '.git')),
            "computed_commit_hash": get_git_commit_hash()
        }
        
        # Try to read commit file content
        try:
            commit_file = os.path.join(os.path.dirname(__file__), 'commit.txt')
            if os.path.exists(commit_file):
                with open(commit_file, 'r') as f:
                    debug_info["commit_file_content"] = f.read().strip()
        except Exception as e:
            debug_info["commit_file_error"] = str(e)
        
        return jsonify(debug_info), 200

    @app.route("/")
    def home():
        commit_hash = get_git_commit_hash()
        environment = get_kubernetes_namespace()
        
        # Debug information
        print(f"Debug - Commit hash: {commit_hash}")
        print(f"Debug - Environment: {environment}")
        print(f"Debug - GIT_COMMIT_HASH env var: {os.getenv('GIT_COMMIT_HASH', 'Not set')}")
        
        message = f"Hello from Flask! | Environment: {environment} | Commit: {commit_hash}"
        return message, 200

    return app

if __name__ == "__main__":
    app = create_app()
    app.run(host="0.0.0.0", port=8080)
