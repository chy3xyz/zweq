# zweq 可观测性与最小告警

> `/metrics` 暴露的指标已足够支撑最小告警面。本文给出 5 条 Prometheus
> 表达式与处置建议，覆盖「进程活着 / 请求健康 / 延迟 / 数据库 / 后台任务」
> 五个维度。指标名以 `zweq_` 前缀为准，直接照抄即可。

抓取配置建议：`/metrics` 默认公开，生产用 `ZWEQ_METRICS_ALLOW_IPS` 限制到
监控网段；Prometheus 侧给 zweq 实例配一个 job（下文记为 `job="zweq"`）。

## 指标速览

| 指标 | 类型 | 含义 |
| --- | --- | --- |
| `zweq_http_requests_total` | counter | 请求总数 |
| `zweq_http_requests_5xx{class="5xx"}` | counter 语义 | 5xx 累计数（2xx/3xx/4xx 同族） |
| `zweq_http_request_duration_seconds_bucket{le=...}` | histogram | 请求耗时直方图（桶：0.005–10s） |
| `zweq_http_request_duration_seconds_sum` / `_count` | histogram | 耗时总和 / 样本数 |
| `zweq_db_pool_waiters` | gauge | 等连接的阻塞 Borrower 数 |
| `zweq_db_pool_exhausted_total` | counter | 连接池耗尽放弃数 |
| `zweq_tasks_failed_total` | counter 语义 | 后台任务失败累计（处理成功为 `zweq_tasks_processed_total`） |
| `zweq_rate_limit_rejections_total` | counter | 限流 429 拒绝累计 |
| `zweq_uptime_seconds` | gauge | 进程运行时长 |

注：`up` 不是应用导出的，是 Prometheus 抓取健康状态自带的指标。

## 最小告警集（5 条）

### 1. 实例存活

```promql
up{job="zweq"} == 0
```

**处置**：进程/容器挂了或主机网络不通。先看 `zweq_uptime_seconds`（刚重启
说明是崩溃后被拉活，去日志找 panic）与最近部署记录；持续挂则检查主机
资源（内存 OOM、磁盘满）与编排层事件。

### 2. 5xx 比例突增

```promql
sum(increase(zweq_http_requests_5xx[5m])) / sum(increase(zweq_http_requests_total[5m])) > 0.05
```

**处置**：5 分钟内 5xx 占比超 5%。按 `class` 标签拆 4xx/5xx 排除客户端
因素；翻服务日志中的 panic/`error` 段，重点看最近变更的模块与上游
（数据库、微信 API、AI provider）依赖是否抖动。

### 3. P95 延迟劣化

```promql
histogram_quantile(0.95, sum(rate(zweq_http_request_duration_seconds_bucket[5m])) by (le)) > 0.5
```

**处置**：P95 超 500ms（阈值按业务调整）。先用同一表达式按实例拆分定位
慢节点；结合 `zweq_db_pool_waiters`（慢查询拖住连接）与 `zweq_http_request_duration_seconds_max`
（偶发尖刺还是整体劣化）判断方向。

### 4. 数据库连接池告急

```promql
zweq_db_pool_waiters > 0
```

**处置**：已有请求在排队等连接，是池耗尽的前兆。查慢查询/长事务
（Postgres `pg_stat_activity`），确认是否有热点接口放大借用；短期可重启
实例止血，中期调大池上限或优化 SQL。`zweq_db_pool_exhausted_total`
持续增长说明已有请求因超时拿不到连接而失败，优先级更高。

### 5. 后台任务失败

```promql
increase(zweq_tasks_failed_total[10m]) > 0
```

**处置**：任务分发器在 10 分钟内有失败任务（重试后仍失败的计入）。按任务
日志定位失败类型：数据库约束/外呼失败/超时分别走不同修复路径；若同时
观察到 `zweq_rate_limit_rejections_total` 上涨，先排除上游被限流导致的
连带失败。

## 备注

- 直方图桶覆盖 0.005s–10s；超过 10s 的请求只体现在 `le="+Inf"` 桶与
  `_count` 的差值里，慢任务请结合任务日志看。
- `zweq_tasks_*` 两个指标仅在任务分发器绑定时导出（正常启动都会绑定）。
- 告警阈值是最小可用的起点，上线后按一周基线再收紧。
