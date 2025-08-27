# Flask App

- Minimal Flask app with actuator-like monitoring endpoints
- CI builds/pushes image once per commit, run unit test and then **deploys to dev**
- On success, creates a GitHub Release with the image digest
- On merge to `main`, deploys to staging via GitHub Actions
- Prod deploys go through manual approval process via GitHub Actions
- Manual `promote.yml` workflow re-tags the same digest to staging/prod (no rebuild)
- Used github container registry to store images
- Used AWS EKS to deploy the app to a kubernetes cluster, with separate namespaces for dev/staging/prod

## Local Development with Podman

### Prerequisites

- [Podman](https://podman.io/getting-started/installation) installed
- Git repository cloned locally
- Port 8080 available on your machine

### Quick Start

```bash
# Deploy the application locally
./deploy-local.sh

# Check application status
./manage-local.sh status

# View application logs
./manage-local.sh logs

# Test all endpoints
./manage-local.sh test

# Container lifecycle
./manage-local.sh start      # Start container
./manage-local.sh stop       # Stop container
./manage-local.sh restart    # Restart container

# Test endpoints
./manage-local.sh test

# Cleanup
./manage-local.sh remove            # Remove container
./manage-local.sh remove --images   # Remove container and images
```

### Application URLs

Once deployed locally, the application will be available at:

| Endpoint | URL | Description |
|----------|-----|-------------|
| **Home** | http://localhost:8080 | Main application page with commit info |
| **Health Check** | http://localhost:8080/healthz | Kubernetes-style health check |
| **Debug Info** | http://localhost:8080/debug | Debug information and environment details |
| **Actuator** | http://localhost:8080/actuator | List of available actuator endpoints |
| **App Info** | http://localhost:8080/actuator/info | Application metadata and build info |
| **Health** | http://localhost:8080/actuator/health | Detailed health check with system metrics |
| **Metrics** | http://localhost:8080/actuator/metrics | System metrics (CPU, memory, disk) |
| **Environment** | http://localhost:8080/actuator/env | Environment variables (filtered) |

### Local Development Workflow

1. **Make code changes**
2. **Rebuild and deploy**:
   ```bash
   ./deploy-local.sh --clean
   ```
3. **Test your changes**:
   ```bash
   ./manage-local.sh test
   curl http://localhost:8080
   ```
4. **View logs for debugging**:
   ```bash
   ./manage-local.sh logs -f
   ```
5. **Clean up when done**:
   ```bash
   ./manage-local.sh remove --images
   ```

### Troubleshooting

#### Container won't start
```bash
# Check container logs
./manage-local.sh logs

# Check if port 8080 is in use
lsof -i :8080

# Remove and rebuild
./manage-local.sh remove --images
./deploy-local.sh --clean
```

#### Application not responding
```bash
# Check container status
./manage-local.sh status

# Test endpoints
./manage-local.sh test

# Restart container
./manage-local.sh restart
```

#### Clean slate restart
```bash
# Remove everything and start fresh
./manage-local.sh remove --images
./deploy-local.sh --clean --test
```

## Rollback & Recovery

### Quick Rollback Scripts

#### `rollback.sh` - Rollback Tool

```bash
# Interactive rollback with deployment history
./rollback.sh prod --interactive

# Direct rollback to specific commit
./rollback.sh staging abc1234567890abcdef

# Show deployment history
./rollback.sh prod --history

# Show available images
./rollback.sh staging --images

# Production rollback via deployment workflow (with approval)
./rollback.sh prod abc12345 --deployment
```

**Features:**
- **Deployment History** - Shows recent successful deployments
- **Image Validation** - Verifies target images exist
- **Multiple Methods** - Promote workflow (default) or deployment workflows
- **Safety Checks** - Confirmation prompts and validation
- **Progress Monitoring** - Direct links to workflow runs

**Emergency Use:**
- **Fast Rollback** - Uses promote workflow (safe image re-tagging)
- **Auto-Detection** - Finds last 2 deployments automatically
- **One Command** - Minimal interaction required
- **Safe Method** - Uses promote workflow instead of bypassing approvals

### Rollback Methods

#### 1. **Promote Workflow** (Recommended)
- **Safe** - Re-tags existing images without rebuilding
- **Fast** - No build time, just image promotion
- **Reliable** - Uses proven image artifacts
- **Traceable** - Clear audit trail

#### 2. **Deployment Workflow**
- **Full Process** - Goes through complete deployment pipeline
- **Approval Gates** - Maintains production safety (for prod)
- **Comprehensive** - Includes all validation steps
- **Slower** - Takes longer due to full process

#### 3. **Emergency Method**
- **Fast** - Uses promote workflow for speed
- **Automated** - Minimal manual intervention
- **Targeted** - Rolls back to immediate previous version
- **Safe** - Uses image re-tagging instead of bypassing approvals

### Rollback Scenarios

#### **Scenario 1: Planned Rollback**
```bash
# Interactive selection with history
./rollback.sh prod --interactive

# 1. Shows deployment history
# 2. Shows available images  
# 3. Allows commit selection
# 4. Confirms before execution
# 5. Uses safe promote method
```

#### **Scenario 2: Quick Rollback to Known Commit**
```bash
# Direct rollback to specific commit
./rollback.sh prod abc1234567890abcdef

# Fast rollback using promote workflow
# Validates image exists before proceeding
```


### Prerequisites

- **GitHub CLI** (`gh`) installed and authenticated
- **skopeo** (optional, for image validation)
- **Appropriate permissions** to trigger workflows

### Rollback Safety

#### **Built-in Safety Features:**
- **Image Validation** - Verifies target images exist
- **Deployment History** - Shows context before rollback
- **Confirmation Prompts** - Prevents accidental rollbacks
- **Progress Monitoring** - Links to track rollback status
- **Environment Isolation** - Cannot cross-contaminate environments

#### **Best Practices:**
1. **Use Interactive Mode** for planned rollbacks
2. **Validate in Lower Environments** first when possible
3. **Monitor Application** after rollback completion
4. **Document Rollback Reason** for future reference
5. **Plan Forward Fix** rather than staying on old version

### Troubleshooting Rollbacks

#### **Common Issues:**

**Image Not Found:**
```bash
# Check available images
./rollback.sh prod --images

# Verify image exists in registry
skopeo inspect docker://ghcr.io/owner/flask-web:sha-abc12345
```

**Workflow Fails:**
```bash
# Check workflow status
gh run list --repo owner/repo --limit 5

# View specific run logs
gh run view RUN_ID --log
```

**Rollback Doesn't Take Effect:**
```bash
# Check Kubernetes deployment status
kubectl get deployments -n prod
kubectl describe deployment flask-web -n prod

# Check pod status
kubectl get pods -n prod
kubectl logs -l app=flask-web -n prod
```

## Production Deployment

### Deployment Methods

1. **Manual Approval** (Recommended and Required for production):
   ```bash
   ./trigger-prod-deploy.sh
   # Select option 1 for manual approval
   ```

**Security Note**: 

All production deployments require manual approval for safety.

### Adding New Features

1. Make changes to the Flask application
2. Test locally with `./deploy-local.sh --clean --test`
3. Commit and push changes
4. CI/CD will automatically build and deploy to dev
5. Merge to main for staging deployment
6. Use production deployment scripts for prod

## Monitoring

The application includes comprehensive monitoring capabilities:

- **Health checks** for Kubernetes liveness/readiness probes
- **Metrics collection** for system monitoring
- **Build metadata** for deployment tracking
- **Environment detection** for multi-environment deployments
- **Debug endpoints** for troubleshooting


## Todo
- Add smoke test script

## Improvements 

### Separate CD from CI 

### Use ArgoCD 
- Can do rollback
- Use argocd rollouts, can rollback based on error rates/metrics 
- Focus on CD 
- 

# Create preview endpoints from branches/commit
- Can do preview urls with argoCD
- Deploy as new app and generate preview endpoints
- Easy to clean up the environment once done
