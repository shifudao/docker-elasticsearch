# docker-elasticsearch

师傅到项目使用的 Elasticsearch 镜像，预装 [IK 中文分词器](https://github.com/medcl/elasticsearch-analysis-ik)。

- **Elasticsearch** `2.1.2`
- **IK Analysis 插件** `1.7.0`（已为 2.1.2 做编译修改）

镜像同步发布于 [Docker Hub](https://hub.docker.com/r/shifudao/elasticsearch)、[GHCR](https://github.com/shifudao/docker-elasticsearch/pkgs/container/elasticsearch) 与 [Quay.io](https://quay.io/repository/shifudao/elasticsearch)，三者内容一致（同一多架构 manifest），拉取时任选其一。

## 多架构

镜像同时发布 `linux/amd64` 与 `linux/arm64`（镜像约 176 MB，拉取时自动匹配宿主架构）。

官方 [`elasticsearch:2.1.2`](https://hub.docker.com/_/elasticsearch) 发布于 2015 年，早于 Docker 多架构 manifest，仅有 `amd64` 单一架构镜像；社区 [`arm64v8/elasticsearch`](https://hub.docker.com/r/arm64v8/elasticsearch) 最低版本为 `8.x`，也不覆盖 ES 2.x。由于 Elasticsearch 发行包为**纯 Java**（无原生二进制），本镜像改用多架构基础镜像 [`azul-zulu:8-jre-headless-alpine`](https://hub.docker.com/_/azul-zulu)（alpine + headless JRE，体积小）从官方 tar.gz 自行组装。已实测在 `musl libc` 下双架构均可正常运行。

## 快速开始

```bash
docker run -d --name es \
  -p 9200:9200 -p 9300:9300 \
  shifudao/elasticsearch:2.1.2
```

验证服务：

```bash
curl http://localhost:9200/
```

验证 IK 分词：

```bash
curl -sX POST 'http://localhost:9200/_analyze?pretty' \
  -H 'Content-Type: application/json' \
  -d '{"analyzer":"ik_smart","text":"师傅到中文分词测试"}'
```

## 数据持久化

ES 数据目录为 `/usr/share/elasticsearch/data`，使用命名卷持久化：

```bash
docker run -d --name es \
  -p 9200:9200 -p 9300:9300 \
  -v es-data:/usr/share/elasticsearch/data \
  shifudao/elasticsearch:2.1.2
```

## 配置

### 通过环境变量

ES 2.x 支持以环境变量覆盖设置（变量名对应 `elasticsearch.yml` 的配置项，`.` 与 `_` 等价）：

```bash
docker run -d --name es \
  -p 9200:9200 \
  -e ES_HEAP_SIZE=2g \
  -e cluster.name=my-cluster \
  -e discovery.zen.minimum_master_nodes=1 \
  -v es-data:/usr/share/elasticsearch/data \
  shifudao/elasticsearch:2.1.2
```

### 挂载配置文件

将自定义 `elasticsearch.yml` 挂载覆盖默认配置：

```bash
docker run -d --name es \
  -p 9200:9200 \
  -v es-data:/usr/share/elasticsearch/data \
  -v "$PWD/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro" \
  shifudao/elasticsearch:2.1.2
```

## Docker Compose

`compose.yaml`：

```yaml
services:
  elasticsearch:
    image: shifudao/elasticsearch:2.1.2
    container_name: es
    ports:
      - "9200:9200"
      - "9300:9300"
    environment:
      ES_HEAP_SIZE: 2g
      cluster.name: my-cluster
    volumes:
      - es-data:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
    restart: unless-stopped

volumes:
  es-data:
```

启动：

```bash
docker compose up -d
```

## 健康检查与依赖编排

ES 2.x 启动偏慢（首次需建索引、加载 IK 插件、完成主节点选举），下游服务若在 ES 就绪前启动会连接失败。利用 Compose 的 `healthcheck` 配合 `depends_on.condition: service_healthy`，可让依赖容器等到 ES 真正就绪后再启动。

`compose.yaml`：

```yaml
services:
  elasticsearch:
    image: shifudao/elasticsearch:2.1.2
    container_name: es
    ports:
      - "9200:9200"
      - "9300:9300"
    environment:
      ES_HEAP_SIZE: 2g
    volumes:
      - es-data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=2s"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  app:
    image: your-app-image        # 替换为实际应用镜像
    depends_on:
      elasticsearch:
        condition: service_healthy   # ES 进入 healthy 状态后才启动 app
    restart: unless-stopped

volumes:
  es-data:
```

说明：

- **`wait_for_status=yellow`**：ES 在 2s（`timeout=2s`）内达到 yellow/green 才返回 200，否则返回 408，wget 随即非零退出、本次检查计为失败。相比单纯判断端口可达，它能识别“进程活着但集群 `status: red`”的中间态，避免下游误连。
- **`start_period: 60s`**：启动后 60s 内的失败不计入 unhealthy 判定，专为 ES 2.x + IK 的慢启动预留。数据量大或机器较慢时应适当调大。
- **`timeout: 5s`**（需大于 URL 内的 `timeout=2s`）：给单次检查留余量。
- 若只判断端口存活、不关心集群状态，可去掉 `?wait_for_status=yellow&timeout=2s` 查询参数。
- `depends_on.condition` 另有 `service_started`（默认，仅等容器启动）与 `service_completed_successfully`（等 init 容器成功退出）两个取值。

## IK 分词器

镜像预装 IK 插件，提供两种分词模式：

| analyzer      | 说明             |
| ------------- | ---------------- |
| `ik_smart`    | 粗粒度，适合检索 |
| `ik_max_word` | 细粒度，适合索引 |

### 自定义词典

IK 词典位于容器内 `/usr/share/elasticsearch/plugins/elasticsearch-analysis/config/ik/`。挂载自定义词典（如 `mydict.dic`）到 `custom/` 目录：

```yaml
volumes:
  - ./mydict.dic:/usr/share/elasticsearch/plugins/elasticsearch-analysis-ik/config/ik/custom/mydict.dic:ro
```

> 注意：ES 2.x + IK 1.7.0 不支持词典热更新，新增/修改词典需重启容器。

## 暴露端口

| 端口   | 用途                    |
| ------ | ----------------------- |
| `9200` | HTTP / REST API         |
| `9300` | 节点间通信（transport） |

## 本地构建

当前架构：

```bash
docker build -t shifudao/elasticsearch:2.1.2 .
```

多架构（需 [buildx](https://docs.docker.com/build/buildx/) 与 QEMU）：

```bash
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t shifudao/elasticsearch:2.1.2 --push .
```

构建参数：

| 参数                    | 默认值  | 说明               |
| ----------------------- | ------- | ------------------ |
| `ELASTICSEARCH_VERSION` | `2.1.2` | Elasticsearch 版本 |

## 目录说明

```
.
├── Dockerfile                              # 多架构构建定义
├── docker-entrypoint.sh                    # 入口脚本（复刻官方镜像）
├── config/
│   ├── elasticsearch.yml                   # 默认配置（network.host: 0.0.0.0）
│   └── logging.yml                         # 日志配置
├── elasticsearch-analysis-ik-1.7.0.tar.xz  # IK 插件（已编译修改）
```
