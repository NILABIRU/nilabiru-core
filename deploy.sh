#!/bin/bash

set -e

cleanup() {
  echo "=== Running Cleanup ==="
  docker image prune -f
}
trap cleanup EXIT

echo "=== Validate Docker Compose ==="
docker compose config --quiet

echo "=== Run Deploy Script ==="
docker compose up -d --remove-orphans --build

echo "Deployment berhasil!"
