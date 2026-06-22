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

# curl 仅用于下载 ES, 属构建依赖: 装入虚拟包, 下载解压后连同依赖一并删除, 不进入最终镜像
RUN apk add --no-cache --virtual .build-deps curl \
    && curl -fsSL "https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz" \
        | tar xzf - -C /usr/share/ \
    && mv "/usr/share/elasticsearch-${ELASTICSEARCH_VERSION}" "${ES_HOME}" \
    && mkdir -p "${ES_HOME}/data" "${ES_HOME}/logs" "${ES_HOME}/plugins" "${ES_HOME}/config/scripts" \
    && apk del .build-deps

# 复刻官方镜像配置与入口脚本
COPY config/ "${ES_HOME}/config/"
COPY docker-entrypoint.sh /

# IK 分词器插件 (1.7.0, 已为 2.1.2 编译修改; ADD 自动解压本地 tar.xz)
ADD elasticsearch-analysis-ik-1.7.0.tar.xz "${ES_HOME}/plugins/elasticsearch-analysis-ik/"

# 运行依赖: su-exec (容器内降权) + tini (PID 1 信号/僵尸进程处理); 同时创建运行用户
RUN apk add --no-cache su-exec tini \
    && addgroup -S elasticsearch \
    && adduser -S -D -H -G elasticsearch -s /bin/false elasticsearch

# 权限: 入口脚本可执行, 运行时目录归 elasticsearch 用户
RUN chmod +x /docker-entrypoint.sh \
    && chown -R elasticsearch:elasticsearch \
        "${ES_HOME}/data" "${ES_HOME}/logs" "${ES_HOME}/plugins" "${ES_HOME}/config"

WORKDIR ${ES_HOME}

VOLUME ${ES_HOME}/data

EXPOSE 9200 9300

# tini 作为 PID 1 (-g 信号转发至整个进程组), 由其拉起 entrypoint 脚本
ENTRYPOINT ["/sbin/tini", "-g", "--", "/docker-entrypoint.sh"]
CMD ["elasticsearch"]
