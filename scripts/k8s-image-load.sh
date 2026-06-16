#!/bin/bash

# Uso:
# ./k8s-image-load.sh <image-name> <tag> <dockerfile-path>

set -e

IMAGE_NAME=$1
TAG=$2
DOCKERFILE_PATH=$3

if [ -z "$IMAGE_NAME" ] || [ -z "$TAG" ]; then
  echo "Uso: $0 <image-name> <tag> <dockerfile-path>"
  exit 1
fi

FULL_IMAGE="${IMAGE_NAME}:${TAG}"
TAR_FILE="${IMAGE_NAME}-${TAG}.tar"

echo "🔍 Verificando si la imagen Docker existe localmente..."

if docker image inspect "$FULL_IMAGE" > /dev/null 2>&1; then
    echo "✅ Imagen ya existe localmente: $FULL_IMAGE"
    echo "⏭️  Saltando build..."
else
    echo "🔨 Imagen no existe. Construyendo..."
    docker build -t $FULL_IMAGE $DOCKERFILE_PATH
fi

echo "💾 Exportando imagen a tar..."
docker save $FULL_IMAGE -o $TAR_FILE

echo "📦 Importando en Kubernetes (containerd)..."
sudo ctr -n=k8s.io images import $TAR_FILE

echo "🧹 Limpiando archivo temporal..."
rm -f $TAR_FILE

echo "🔍 Verificando imagen en containerd..."
sudo ctr -n=k8s.io images ls | grep $IMAGE_NAME || true

echo ""
echo "🚀 Listo para Kubernetes"
echo "   image: $FULL_IMAGE"
echo "   imagePullPolicy: Never"