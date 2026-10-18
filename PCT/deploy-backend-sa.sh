root@applictionvm2:~# cat deploy-backend-sa.sh
#!/bin/bash

set -Eeuo pipefail

BUILD_NUMBER="${1:-}"

APP_DIR="/root/backend/PCTS2.0-Backend"
COMPOSE_DIR="$APP_DIR/docker"
DEPLOY_DIR="/root/deployments"

# ==============================
# Docker Images
# ==============================
IDENTITY_IMAGE="pcts2/identityservice:${BUILD_NUMBER}"
MASTER_IMAGE="pcts2/master:${BUILD_NUMBER}"
DHS_IMAGE="pcts2/dhs:${BUILD_NUMBER}"
MEDICAL_IMAGE="pcts2/medical:${BUILD_NUMBER}"
JANAADHAAR_IMAGE="pcts2/janaadhaar:${BUILD_NUMBER}"

# ==============================
# Docker Artifacts
# ==============================
IDENTITY_TAR="$DEPLOY_DIR/identityservice-${BUILD_NUMBER}.tar"
MASTER_TAR="$DEPLOY_DIR/master-${BUILD_NUMBER}.tar"
DHS_TAR="$DEPLOY_DIR/dhs-${BUILD_NUMBER}.tar"
MEDICAL_TAR="$DEPLOY_DIR/medical-${BUILD_NUMBER}.tar"
JANAADHAAR_TAR="$DEPLOY_DIR/janaadhaar-${BUILD_NUMBER}.tar"

echo "========================================"
echo "PCTS2 Backend Deployment"
echo "Build: ${BUILD_NUMBER:-NOT PROVIDED}"
echo "========================================"

# ==============================
# Validate Build Number
# ==============================
if [ -z "$BUILD_NUMBER" ]; then
    echo "ERROR: Build number is required."
    echo "Usage: $0 <BUILD_NUMBER>"
    exit 1
fi

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid build number: $BUILD_NUMBER"
    exit 1
fi

# ==============================
# Validate Directories
# ==============================
if [ ! -d "$COMPOSE_DIR" ]; then
    echo "ERROR: Compose directory not found: $COMPOSE_DIR"
    exit 1
fi

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "ERROR: Deployment directory not found: $DEPLOY_DIR"
    exit 1
fi

# ==============================
# Validate All Artifacts
# Do this before changing containers
# ==============================
for ARTIFACT in \
    "$IDENTITY_TAR" \
    "$MASTER_TAR" \
    "$DHS_TAR" \
    "$MEDICAL_TAR" \
    "$JANAADHAAR_TAR"; do

    if [ ! -s "$ARTIFACT" ]; then
        echo "ERROR: Artifact missing or empty: $ARTIFACT"
        exit 1
    fi

    echo "Artifact verified: $ARTIFACT"
done

cd "$COMPOSE_DIR"

# ==============================
# Validate Docker Compose
# ==============================
echo
echo "Validating Docker Compose configuration..."

IMAGE_TAG="$BUILD_NUMBER" docker compose config --quiet

# ==============================
# Load Docker Images
# ==============================
echo
echo "Loading Identity image..."
docker load -i "$IDENTITY_TAR"

echo
echo "Loading Master image..."
docker load -i "$MASTER_TAR"

echo
echo "Loading DHS image..."
docker load -i "$DHS_TAR"

echo
echo "Loading Medical image..."
docker load -i "$MEDICAL_TAR"

echo
echo "Loading JanAadhaar image..."
docker load -i "$JANAADHAAR_TAR"

# ==============================
# Verify Docker Images
# ==============================
echo
echo "Verifying all five Docker images..."

for IMAGE in \
    "$IDENTITY_IMAGE" \
    "$MASTER_IMAGE" \
    "$DHS_IMAGE" \
    "$MEDICAL_IMAGE" \
    "$JANAADHAAR_IMAGE"; do

    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "ERROR: Required image not found: $IMAGE"
        exit 1
    fi

    echo "Verified: $IMAGE"
done

# ==============================
# Verify Compose Services
# ==============================
echo
echo "Checking required Compose services..."

SERVICES="$(IMAGE_TAG="$BUILD_NUMBER" docker compose config --services)"

for SERVICE in \
    identityservice \
    master \
    dhs \
    medical \
    janaadhaar \
    backend-gateway; do

    if ! grep -Fxq "$SERVICE" <<< "$SERVICES"; then
        echo "ERROR: Compose service not found: $SERVICE"
        echo "Available services:"
        printf '%s\n' "$SERVICES"
        exit 1
    fi
done

echo
echo "All five services and the gateway are configured."

# ==============================
# Deploy All Services
# ==============================
echo
echo "Starting all five microservices and gateway..."

# Do not run docker compose down.
# Existing containers are not deliberately stopped first.
IMAGE_TAG="$BUILD_NUMBER" docker compose up -d \
    identityservice \
    master \
    dhs \
    medical \
    janaadhaar \
    backend-gateway

# ==============================
# Wait for Initialization
# ==============================
echo
echo "Waiting for containers to initialize..."
sleep 5

# ==============================
# Container Status
# ==============================
echo
echo "========================================"
echo "Container Status"
echo "========================================"

docker ps --format \
    'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

# ==============================
# Deployed Container Details
# ==============================
echo
echo "========================================"
echo "Deployed Microservices"
echo "========================================"

for CONTAINER in \
    pcts-identityservice \
    pcts-master \
    pcts-dhs \
    pcts-medical \
    pcts-janaadhaar; do

    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker inspect "$CONTAINER" \
            --format '{{.Name}}: {{.Config.Image}} | Status: {{.State.Status}}'
    else
        echo "WARNING: Container not found: $CONTAINER"
    fi
done

# ==============================
# Recent Logs
# ==============================
echo
echo "========================================"
echo "Recent DHS Logs"
echo "========================================"
docker logs --tail 50 pcts-dhs || true

echo
echo "========================================"
echo "Recent Identity Logs"
echo "========================================"
docker logs --tail 20 pcts-identityservice || true

echo
echo "========================================"
echo "Recent Master Logs"
echo "========================================"
docker logs --tail 20 pcts-master || true

echo
echo "========================================"
echo "Recent Medical Logs"
echo "========================================"
docker logs --tail 30 pcts-medical || true

echo
echo "========================================"
echo "Recent JanAadhaar Logs"
echo "========================================"
docker logs --tail 30 pcts-janaadhaar || true

# ==============================
# Deployment Complete
# ==============================
echo
echo "========================================"
echo "Deployment command completed"
echo "Build: ${BUILD_NUMBER}"
echo "Services: Identity, Master, DHS, Medical, JanAadhaar"
echo "========================================"

