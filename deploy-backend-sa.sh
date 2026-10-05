#!/bin/bash

set -e

BUILD_NUMBER="$1"

APP_DIR="/root/backend/PCTS2.0-Backend"
COMPOSE_DIR="$APP_DIR/docker"
DEPLOY_DIR="/root/deployments"

IDENTITY_IMAGE="pcts2/identityservice:${BUILD_NUMBER}"
MASTER_IMAGE="pcts2/master:${BUILD_NUMBER}"

IDENTITY_TAR="$DEPLOY_DIR/identityservice-${BUILD_NUMBER}.tar"
MASTER_TAR="$DEPLOY_DIR/master-${BUILD_NUMBER}.tar"

echo "========================================"
echo "PCTS2 Backend Deployment"
echo "Build: ${BUILD_NUMBER}"
echo "========================================"

if [ -z "$BUILD_NUMBER" ]; then
    echo "ERROR: Build number is required."
    echo "Usage: $0 <BUILD_NUMBER>"
    exit 1
fi

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid build number: $BUILD_NUMBER"
    exit 1
fi

if [ ! -d "$COMPOSE_DIR" ]; then
    echo "ERROR: Compose directory not found:"
    echo "$COMPOSE_DIR"
    exit 1
fi

if [ ! -f "$IDENTITY_TAR" ]; then
    echo "ERROR: Identity artifact not found:"
    echo "$IDENTITY_TAR"
    exit 1
fi

if [ ! -f "$MASTER_TAR" ]; then
    echo "ERROR: Master artifact not found:"
    echo "$MASTER_TAR"
    exit 1
fi

echo
echo "Loading Identity image..."
docker load -i "$IDENTITY_TAR"

echo
echo "Loading Master image..."
docker load -i "$MASTER_TAR"

echo
echo "Verifying images..."

docker image inspect "$IDENTITY_IMAGE" >/dev/null 2>&1 || {
    echo "ERROR: Identity image not found: $IDENTITY_IMAGE"
    exit 1
}

docker image inspect "$MASTER_IMAGE" >/dev/null 2>&1 || {
    echo "ERROR: Master image not found: $MASTER_IMAGE"
    exit 1
}

echo "Identity image:"
docker image inspect "$IDENTITY_IMAGE" \
    --format '{{.RepoTags}}'

echo "Master image:"
docker image inspect "$MASTER_IMAGE" \
    --format '{{.RepoTags}}'

cd "$COMPOSE_DIR"

echo
echo "Available Docker Compose services:"
docker compose config --services

echo
echo "Stopping existing backend containers..."

docker compose down

echo
echo "Starting Identity + Master + Gateway..."

IMAGE_TAG="$BUILD_NUMBER" docker compose up -d \
    identityservice \
    master \
    backend-gateway

echo
echo "Waiting for services to become healthy..."

for i in {1..30}; do

    IDENTITY_STATUS=$(docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        pcts-identityservice 2>/dev/null || echo "not-found")

    MASTER_STATUS=$(docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        pcts-master 2>/dev/null || echo "not-found")

    echo "Identity: $IDENTITY_STATUS | Master: $MASTER_STATUS"

    if [ "$IDENTITY_STATUS" = "healthy" ] && \
       [ "$MASTER_STATUS" = "healthy" ]; then
        break
    fi

    sleep 2

done

echo
echo "========================================"
echo "Container Status"
echo "========================================"

docker ps --format \
    'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "========================================"
echo "Deployed Images"
echo "========================================"

docker inspect pcts-identityservice \
    --format 'Identity: {{.Config.Image}}'

docker inspect pcts-master \
    --format 'Master: {{.Config.Image}}'

echo
echo "========================================"
echo "Deployment completed"
echo "Build: ${BUILD_NUMBER}"
echo "========================================"
