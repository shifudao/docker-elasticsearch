# Elasticsearch 2.1.2 + IK Analysis Plugin 1.7.0 (multi-arch: amd64/arm64)
#
# 背景: 官方 elasticsearch:2.1.2 与社区 arm64v8/elasticsearch (最低 8.x) 均无 ES 2.x 的 arm64 镜像;
#       ES 发行包为纯 Java, 故改用多架构基础镜像 azul-zulu:8-jre-headless-alpine 从官方 tar.gz 自行组装。
#       (azul-zulu 未同步至 AWS public ECR, 故直接使用 Docker Hub 地址)
#
# 多架构构建 (需 buildx + QEMU):
#   docker buildx build --platform linux/amd64,linux/arm64 -t shifudao/elasticsearch-ik:2.1.2 --push .

FROM docker.io/library/azul-zulu:8-jre-headless-alpine

LABEL org.opencontainers.image.authors="冯宇<yu.feng@shifudao.com>"

ARG ELASTICSEARCH_VERSION=2.1.2

ENV ELASTICSEARCH_VERSION=${ELASTICSEARCH_VERSION} \
    ES_HOME=/usr/share/elasticsearch \
    PATH=/usr/share/elasticsearch/bin:${PATH}

# 单层 RUN 完成所有构建期操作 (用户创建 / 依赖安装 / 下载解压 / 目录初始化 / 构建依赖清理):
#   - 先创建运行用户, 后续 COPY --chown / ADD --chown 即可就地设定属主, 无需独立 chown 层;
#   - curl 装入虚拟包, 下载解压 ES 后连同依赖一并删除, 不进入最终镜像;
#   - data/logs/plugins/config 为 mkdir 出的空目录, 此处 chown 开销≈0 (非空文件改属主才会重复占层)。
RUN addgroup -S elasticsearch \
    && adduser -S -D -H -G elasticsearch -s /bin/false elasticsearch \
    && apk add --no-cache su-exec tini \
    && apk add --no-cache --virtual .build-deps curl \
    && curl -fsSL "https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz" \
        | tar xzf - -C /usr/share/ \
    && mv "/usr/share/elasticsearch-${ELASTICSEARCH_VERSION}" "${ES_HOME}" \
    && mkdir -p "${ES_HOME}/data" "${ES_HOME}/logs" "${ES_HOME}/plugins" "${ES_HOME}/config/scripts" \
    && chown -R elasticsearch:elasticsearch "${ES_HOME}/data" "${ES_HOME}/logs" "${ES_HOME}/plugins" "${ES_HOME}/config" \
    && apk del .build-deps

# 复刻官方镜像配置: COPY --chown 复制时即设定属主, 省去后续 chown 层 (避免文件在层间重复存储)。
COPY --chown=elasticsearch:elasticsearch config/ "${ES_HOME}/config/"

# 入口脚本: COPY --chmod 复制时设可执行位, 省去独立 chmod 层; 保持 root 属主 (tini 以 root 拉起, 经 su-exec 降权)。
COPY --chmod=0755 docker-entrypoint.sh /docker-entrypoint.sh

# IK 分词器插件 (1.7.0, 已为 2.1.2 编译修改):
#   ADD 自动解压本地 tar.xz; --chown 直接归 elasticsearch, 消除原本的递归 chown 层
#   (否则 ~9.4MB 解压内容会在 ADD 层与 chown 层各存一份, 显著膨胀镜像)。
ADD --chown=elasticsearch:elasticsearch elasticsearch-analysis-ik-1.7.0.tar.xz "${ES_HOME}/plugins/elasticsearch-analysis-ik/"

WORKDIR ${ES_HOME}

VOLUME ${ES_HOME}/data

EXPOSE 9200 9300

# tini 作为 PID 1 (-g 信号转发至整个进程组), 由其拉起 entrypoint 脚本
ENTRYPOINT ["/sbin/tini", "-g", "--", "/docker-entrypoint.sh"]
CMD ["elasticsearch"]
