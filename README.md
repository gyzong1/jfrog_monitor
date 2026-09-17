# JF Monitor 部署指南

JF Monitor 安装与升级说明。支持 **linux/amd64** 与 **linux/arm64**。

安装包通常为：

```text
jf-monitor-1.0.0-release.tar.gz    # 完整安装包（含 Server 镜像、Agent 二进制、脚本与配置）
```

---

## 架构概览

```text
┌─────────────────────────────┐     抓取 metrics / REST
│  JF Monitor Server (Docker) │ ◄──────────────────── Artifactory 节点
│  :8080  浏览器打开即用        │
└─────────────────────────────┘
         ▲
         │ 可选：每节点部署 Agent (:9105)
┌────────┴────────┐
│  jf-agent 二进制   │  采集 TCP / 请求日志 / 主机资源
└─────────────────┘
```

## 前置条件


| 组件     | 要求                                                   |
| ------ | ---------------------------------------------------- |
| Server | Docker 20.10+、docker compose v2+                     |
| Agent  | Linux（amd64 或 arm64），Artifactory 日志目录访问权限            |
| 网络     | Server 能访问各 Artifactory 节点；Agent 端口 9105 对 Server 可达 |


---



## 一、首次部署 Server



### 1. 解压安装包

```bash
# 解压后目录 jf-monitor-1.0.0-release/
tar xzf jf-monitor-1.0.0-release.tar.gz
mv jf-monitor-1.0.0-release jf-monitor
cd jf-monitor

# 或安装到指定路径
# tar xzf jf-monitor-1.0.0-release.tar.gz -C /opt
# mv /opt/jf-monitor-1.0.0-release /opt/jf-monitor
# cd /opt/jf-monitor
```

> 将 `1.0.0` 替换为实际版本号。查看包内版本：`cat VERSION`



### 2. 启动服务

**离线环境（推荐，包内已含镜像）：**

```bash
./start.sh
```

`start.sh` 会按本机架构自动加载 `images/` 下对应镜像（`*-linux-amd64.tar.gz` 或 `*-linux-arm64.tar.gz`）并启动容器。

**在线环境（从 Registry 拉镜像）：**

```bash
export JF_MONITOR_IMAGE=your-registry/jf-monitor:1.0.0
docker compose pull
./start.sh
```



### 3. 打开 Web 界面

```bash
# 浏览器访问（将 <server-ip> 换为实际 IP）
http://<server-ip>:8080
```



### 4. 停止 / 查看版本

```bash
./stop.sh          # 停止
./version.sh       # 查看当前版本与运行状态
```

---



## 二、配置 Artifactory（启动后在 UI 完成）

1. 浏览器进入 **设置 → Artifactory 集群**
2. **添加集群**，再在集群下 **添加节点**：填写 **URL**、**Token**、可选 **Agent 地址**（`http://<node-ip>:9105`）
3. 顶栏先选集群，再选「全部节点」（集群级指标）或某个节点（节点级指标）
4. 保存后下一轮采集即生效，**无需重启**

也可直接编辑 `config/config.yaml`；`config/` 挂载在宿主机持久化目录，修改会持久保存。

---



## 三、部署 Node Agent（可选）

在每个 Artifactory 节点上，使用安装包中的 `agent/` 目录（或单独拷贝该目录）。  
部署 Agent 前，请先完成下方 **Artifactory 侧前置配置**，再启动 Agent。

### 1. Artifactory 侧前置配置



#### （1）开启 metrics

编辑 Artifactory `system.yaml`：

```bash
vim $ARTIFACTORY_HOME/var/etc/system.yaml
```

添加（或合并）以下内容：

```yaml
artifactory:
    metrics:
        enabled: true
access:
    metrics:
        enabled: true
event:
    metrics:
        enabled: true
integration:
    metrics:
        enabled: true
observability:
    metrics:
        enabled: true
```

保存后 **重启 Artifactory** 使配置生效。

#### （2）开启 S3 connection debug 日志

编辑 Artifactory `logback.xml`：

```bash
vim $ARTIFACTORY_HOME/var/etc/artifactory/logback.xml
```

在**倒数第二行**（`</configuration>` 上一行）添加：

```xml
<appender name="connectionpool" class="ch.qos.logback.core.rolling.RollingFileAppender">
  <File>${log.dir}/artifactory-connectionpool.log</File>
  <rollingPolicy class="org.jfrog.common.logging.logback.rolling.FixedWindowWithDateRollingPolicy">
    <FileNamePattern>${log.dir.archived}/artifactory-connectionpool.%i.log.gz</FileNamePattern>
    <maxIndex>10</maxIndex>
  </rollingPolicy>
  <triggeringPolicy class="ch.qos.logback.core.rolling.SizeBasedTriggeringPolicy">
    <MaxFileSize>25MB</MaxFileSize>
  </triggeringPolicy>
  <encoder class="ch.qos.logback.core.encoder.LayoutWrappingEncoder">
    <layout class="org.jfrog.common.logging.logback.layout.BackTracePatternLayout">
      <pattern>%date{yyyy-MM-ddTHH:mm:ss.SSS, UTC}Z [jfrt ] [%-5p] [%-16X{uber-trace-id}] [%-30.30(%c{3}:%L)] [%-20.20thread] - %m%n</pattern>
    </layout>
  </encoder>
</appender>
<logger name="org.apache.http.impl.conn.PoolingHttpClientConnectionManager" additivity="false">
  <level value="Debug"/>
  <appender-ref ref="connectionpool"/>
</logger>
```

此项**无需重启** Artifactory。

### 2. Agent 配置

```bash
cd jf-monitor/agent                 # 或至拷贝后的 agent 目录
cp agent.yaml.example agent.yaml
```

确认 `agent.yaml` 中日志路径与 Artifactory 实际路径一致（默认示例）：

```yaml
requests:
  log_file: /var/opt/jfrog/artifactory/log/artifactory-request.log

access_log:
  log_file: /var/opt/jfrog/artifactory/log/artifactory-access.log

s3:
  log_file: /var/opt/jfrog/artifactory/log/artifactory-connectionpool.log
```

若本机 `$ARTIFACTORY_HOME` 或日志目录不同，请按实际路径修改。

### 3. 启动 / 停止

```bash
./start.sh          # 启动
./stop.sh           # 停止
```



### 4. 在 Server 侧关联 Agent

在 Server **设置 → Artifactory 集群** 中，为对应节点填写：

```text
agent_url: http://<node-ip>:9105
```



### Agent 说明


| 文件                         | 适用架构    |
| -------------------------- | ------- |
| `bin/jf-agent-linux-amd64` | x86_64  |
| `bin/jf-agent-linux-arm64` | aarch64 |


健康检查：

```bash
curl -s http://127.0.0.1:9105/health
curl -s http://127.0.0.1:9105/metrics | head
```

---



## 四、版本升级

下载新版本包（如 `jf-monitor-1.2.0-release.tar.gz`）后，在**现有安装目录**执行升级。  
**保留的内容：** `config/`（节点、Dashboard）、`data/`（历史指标）、`agent.yaml`  
**更新的内容：** Server 镜像、Agent 二进制、可选的新版默认 Dashboard

### 1. 升级 Server

```bash
# 解压新版本（解压后如 jf-monitor-1.2.0-release/）
tar xzf jf-monitor-1.2.0-release.tar.gz -C /tmp

# 在现有安装目录执行升级
cd /opt/jf-monitor                  # 现有安装目录 
./update-server.sh --from /tmp/jf-monitor-1.2.0-release
```

**在线 Registry 升级：**

```bash
export JF_MONITOR_IMAGE=your-registry/jf-monitor:1.2.0
./update-server.sh
```



### 2. 升级 Agent（各 Artifactory 节点）

```bash
cd /opt/jf-monitor/agent
./update.sh --from /tmp/jf-monitor-1.2.0-release/agent
```



### 3. 升级说明


| 说明             |                                                    |
| -------------- | -------------------------------------------------- |
| Server 与 Agent | 可独立升级；大版本建议同步升级                                    |
| 回退旧版本          | 解压旧版 tar.gz 后同样使用 `update-server.sh --from <旧版目录>` |
| 查看版本           | 安装目录执行 `./version.sh`                              |


---



## 五、常用配置


| 项                   | 配置方式                                                            | 默认         |
| ------------------- | --------------------------------------------------------------- | ---------- |
| Web 端口              | 可选 `.env` 中 `JF_MONITOR_PORT=8080`，或改 `docker-compose.yml` 端口映射 | 8080       |
| Artifactory 集群 / 节点 | **设置页**（推荐）或 `config/config.yaml` 的 `clusters:`                 | 启动后在 UI 配置 |
| 采集间隔                | 设置页或 `config/config.yaml`                                       | 15s        |
| 演示数据                | 设置页关闭，或 `collectors.demo.enabled: false`                        | 默认关闭       |
| 远程镜像                | `.env` 或环境变量 `JF_MONITOR_IMAGE`                                 | 使用包内离线镜像   |


`.env` 为**可选项**，仅在有端口、镜像等高级需求时使用（参考 `.env.example`）。

---



## 六、Prometheus 指标接入（Beta）

在 **设置 → Prometheus Targets** 或 `config/config.yaml` 中添加任意 `/metrics` 端点（如 jmx_exporter、node_exporter），协议与 Prometheus scrape 相同。

---



## 七、故障排查


| 现象                                            | 处理                                                                                                                                                                                                                |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 页面打不开                                         | `docker ps` 确认 `jf-monitor` 容器运行；检查防火墙是否放行 8080                                                                                                                                                                   |
| 只有演示数据                                        | 在设置页添加集群与节点（有效 Token），并关闭演示模式                                                                                                                                                                                     |
| Agent 无数据                                     | 检查 `agent.yaml` 日志路径；确认 Server 能访问节点 `:9105`                                                                                                                                                                      |
| Agent 启动报 `libz.so.1: failed to map segment…` | 多为 `/tmp` 挂了 `noexec`。请用最新 `agent/start.sh`（会把 TMPDIR 指到 `run/tmp`）；或手动：`mkdir -p run/tmp && export TMPDIR=$PWD/run/tmp && ./start.sh`                                                                            |
| Agent 报 `GLIBC_2.38 not found`                | 旧版 Agent 可能出现，使用当前最新版 Agent（CentOS 7+ 可用）                                                                                                                                                                         |
| 架构不匹配                                         | 确认使用对应 `bin/jf-agent-linux-amd64` 或 `linux-arm64`                                                                                                                                                                 |
| 升级后异常                                         | `./version.sh` 核对版本；确认已 `docker load` 新镜像后 `./update-server.sh --from <新版本解压路径>`；必要时 `./stop.sh && ./start.sh`                                                                                                    |
| Xray 页报 `Unexpected token '<'` / HTML 非 JSON  | 多为 **Dashboard 已更新但容器仍是旧镜像**（同 tag 未重新 load）。用包内 `images/jf-monitor-<VERSION>-linux-*.tar.gz` 再执行 `./update-server.sh --from <解压目录>`，或 `curl -sI http://localhost:8080/api/xray/overview` 应返回 JSON 而非 `text/html` |


---



## 目录说明（解压后）

```text
./
  VERSION                  # 当前包版本号
  start.sh / stop.sh       # Server 启停
  update-server.sh         # Server 升级
  version.sh               # 查看版本
  docker-compose.yml
  .env.example             # 可选高级配置
  config/                  # 节点与 Dashboard（持久化）
  data/                    # 时序指标 SQLite（持久化，启动后自动生成）
  images/                  # 离线 Docker 镜像（按架构：*-linux-amd64 / *-linux-arm64）
  agent/                   # Node Agent
    start.sh / stop.sh / update.sh
    agent.yaml.example
    bin/jf-agent-linux-*
  README.md                # 本文档
```



### 数据持久化说明


| 内容        | 安装目录路径                                        | 说明                     |
| --------- | --------------------------------------------- | ---------------------- |
| 配置        | `./config/`                                   | 节点、Dashboard 等         |
| 监控数据      | `./data/metrics.db`                           | SQLite 时序库，跟安装目录一起备份即可 |
| Server 镜像 | `./images/jf-monitor-<版本>-linux-amd64.tar.gz` | x86_64 离线镜像            |
|           | `./images/jf-monitor-<版本>-linux-arm64.tar.gz` | arm64 离线镜像             |


---



## License

MIT