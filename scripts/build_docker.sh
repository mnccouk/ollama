#!/bin/sh

set -eu

. $(dirname $0)/env.sh

# Set PUSH to a non-empty string to trigger push instead of load
PUSH=${PUSH:-""}

# docker buildx --load uses the "docker" exporter, which cannot load multi-arch
# manifest lists. env.sh defaults PLATFORM to "linux/arm64,linux/amd64".
docker_load_platform() {
    case "$(uname -m)" in
        x86_64) echo linux/amd64 ;;
        aarch64|arm64) echo linux/arm64 ;;
        *) echo linux/amd64 ;;
    esac
}

if [ -z "${PUSH}" ] ; then
    echo "Building ${FINAL_IMAGE_REPO}:$VERSION locally.  set PUSH=1 to push"
    LOAD_OR_PUSH="--load"
    if echo "$PLATFORM" | grep "," >/dev/null 2>&1; then
        DOCKER_PLATFORM="${DOCKER_LOAD_PLATFORM:-$(docker_load_platform)}"
        echo "Note: local --load is single-platform only; using --platform=${DOCKER_PLATFORM} (was ${PLATFORM}). Set DOCKER_LOAD_PLATFORM to override." >&2
    else
        DOCKER_PLATFORM="${PLATFORM}"
    fi
else
    echo "Will be pushing ${FINAL_IMAGE_REPO}:$VERSION"
    LOAD_OR_PUSH="--push"
    DOCKER_PLATFORM="${PLATFORM}"
fi

# Optional: skip CUDA/Vulkan/MLX runner builds (much faster on AMD-only machines).
# Examples: OLLAMA_DOCKER_TARGET=ollama-amd64-rocm  or  ollama-amd64-rocm-polaris
BUILD_TARGET_OPT=""
if [ -n "${OLLAMA_DOCKER_TARGET:-}" ]; then
    BUILD_TARGET_OPT="--target ${OLLAMA_DOCKER_TARGET}"
    echo "Docker build target: ${OLLAMA_DOCKER_TARGET}" >&2
fi

docker buildx build \
    ${LOAD_OR_PUSH} \
    ${BUILD_TARGET_OPT} \
    --platform=${DOCKER_PLATFORM} \
    ${OLLAMA_COMMON_BUILD_ARGS} \
    -f Dockerfile \
    -t ${FINAL_IMAGE_REPO}:$VERSION \
    .

if echo $PLATFORM | grep "amd64" > /dev/null; then
    case "${OLLAMA_DOCKER_TARGET:-}" in
        ollama-amd64-rocm|ollama-amd64-rocm-polaris)
            echo "Skipping :${VERSION}-rocm build (main image is already ROCm-only for this target)." >&2
            ;;
        *)
            docker buildx build \
                ${LOAD_OR_PUSH} \
                ${BUILD_TARGET_OPT} \
                --platform=linux/amd64 \
                ${OLLAMA_COMMON_BUILD_ARGS} \
                --build-arg FLAVOR=rocm \
                -f Dockerfile \
                -t ${FINAL_IMAGE_REPO}:$VERSION-rocm \
                .
            ;;
    esac
fi