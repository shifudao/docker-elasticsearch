#!/usr/bin/env bash
#
# 多架构镜像构建并同步发布到 Docker Hub、GHCR、Quay.io
#
# 参考: ce-compressor-spares-platform/publish_images.sh
#
# 认证 (一次性, podman 按仓库存储凭证, 详见脚本下方说明 / README):
#   podman login docker.io -u <dockerhub-user>
#   podman login ghcr.io  -u <github-user>   # 密码用 PAT, 需 write:packages 权限
#   podman login quay.io  -u <quay-user>
#
# 用法:
#   ./publish_images.sh                  # 发布 Dockerfile 中 ARG 指定的版本
#   VERSION=2.1.2 ./publish_images.sh    # 显式指定版本
#
# 可覆盖的环境变量:
#   IMAGE_NAME    镜像名 (默认 elasticsearch)
#   DOCKERHUB_NS  Docker Hub 命名空间 (默认 shifudao)
#   GHCR_NS       GHCR 命名空间, 必须小写 (默认 shifudao)
#   QUAY_NS       Quay.io 命名空间 (默认 shifudao)
#   PLATFORMS     目标平台 (默认 linux/amd64,linux/arm64)

set -euo pipefail

cd "$(dirname "$0")"

IMAGE_NAME="${IMAGE_NAME:-elasticsearch}"
DOCKERHUB_NS="${DOCKERHUB_NS:-shifudao}"
GHCR_NS="${GHCR_NS:-shifudao}"
QUAY_NS="${QUAY_NS:-shifudao}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# 版本: 优先环境变量, 否则从 Dockerfile 的 ARG 提取, 保证单一数据源
VERSION="${VERSION:-$(grep -oP '^ARG ELASTICSEARCH_VERSION=\K\S+' Dockerfile)}"
if [[ -z ${VERSION:-} ]]; then
  echo "✗ 无法确定版本 (请设置 VERSION 或检查 Dockerfile)" >&2
  exit 1
fi

# 由 semver 生成 tag 列表: 2.1.2 -> 2.1.2 / 2.1 / 2 / latest
generate_tags() {
  local v="$1"
  echo "$v"
  if [[ $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    echo "${BASH_REMATCH[1]}"
  fi
  echo "latest"
}
mapfile -t TAGS < <(generate_tags "$VERSION")

# 三个仓库的全限定名 (不含 tag)
REPOS=(
  "docker.io/${DOCKERHUB_NS}/${IMAGE_NAME}"
  "ghcr.io/${GHCR_NS}/${IMAGE_NAME}"
  "quay.io/${QUAY_NS}/${IMAGE_NAME}"
)

LOCAL="publish-${IMAGE_NAME}:${VERSION}"

echo "版本: ${VERSION}"
echo "tags: ${TAGS[*]}"
echo "平台: ${PLATFORMS}"
echo "仓库:"
printf '  - %s\n' "${REPOS[@]}"
echo

# 构建多架构 manifest 到本地
echo "==> 构建多架构 manifest"
podman manifest rm -f "${LOCAL}" >/dev/null 2>&1 || true
podman manifest create "${LOCAL}" >/dev/null
podman build --pull=always --platform "${PLATFORMS}" --manifest "${LOCAL}" .

# 推送到每个仓库的每个 tag
# 同 registry 的后续 tag 只传 manifest (层按 digest 去重, 不会重传)
for repo in "${REPOS[@]}"; do
  for tag in "${TAGS[@]}"; do
    echo "==> 推送 ${repo}:${tag}"
    podman manifest push "${LOCAL}" "${repo}:${tag}"
  done
done

echo "==> 清理本地 manifest"
podman manifest rm "${LOCAL}" >/dev/null

echo
echo "✓ 发布完成:"
for repo in "${REPOS[@]}"; do
  for tag in "${TAGS[@]}"; do
    echo "  ${repo}:${tag}"
  done
done
