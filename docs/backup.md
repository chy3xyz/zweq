# zweq 生产备份与恢复

> 数据是生产系统的生命线。本文档是部署前必须落地的最小备份策略。

## 1. Postgres（生产主路径）

使用 `scripts/backup.sh`（逻辑备份，`pg_dump -Fc` 自定义格式）：

```bash
./scripts/backup.sh /var/backups/zweq \
  --pg-conninfo "host=db port=5432 dbname=zweq user=zweq"
```

特性：
- 文件名带时间戳（`zweq-pg-20260813-033000.dump`）
- 保留最近 N 份（默认 7，`KEEP=30` 环境变量覆盖）
- `-Fc` 自定义格式：可用 `pg_restore -l` 列出、按对象选择性恢复

**定时**（cron，每日 + 周保留）：

```cron
0 3 * * * /opt/zweq/scripts/backup.sh /var/backups/zweq --pg-conninfo "host=db port=5432 dbname=zweq user=zweq" >> /var/log/zweq-backup.log 2>&1
0 4 * * 0 KEEP=8 /opt/zweq/scripts/backup.sh /var/backups/zweq-weekly --pg-conninfo "host=db port=5432 dbname=zweq user=zweq"
```

**恢复**：

```bash
# 1) 建新库（或先 drop 现有库）
createdb zweq_restore
# 2) 恢复
pg_restore -d zweq_restore /var/backups/zweq/zweq-pg-<ts>.dump
# 3) 验证（行数抽查）
psql -d zweq_restore -c "select count(*) from user;" 2>/dev/null || true
psql -d zweq_restore -c "select count(*) from app_module;"
```

**PITR（时间点恢复）**：若需要恢复到分钟级，须启用 WAL 归档 + 连续归档（`wal_level=replica` + `archive_command`），并配合 basebackup。这是高可用部署（如 Patroni）的范畴，按需启用。

## 2. SQLite（开发/单机）

SQLite 是单文件，直接复制文件即可；但**在线复制可能损坏**（写入中途）。用 `sqlite3` 的 `.backup` API 做安全在线备份：

```bash
sqlite3 zweq.db ".backup '/var/backups/zweq-$(date +%F).db'"
```

或用脚本方式（推荐放到 cron）：

```bash
sqlite3 zweq.db ".backup '/backups/zweq.db'" && mv /backups/zweq.db "/backups/zweq-$(date +%F).db"
```

## 3. 备份验证（演练）

- **恢复演练**：每季度在临时库完整恢复一次并抽查关键表行数（`app_module`、`user`、`wallet`），确保备份可用。
- **备份监控**：脚本成功/失败写入日志；告警「备份目录最新文件 > 48h 未更新」。

## 4. 与备份配套的运维项

- **`ZWEQ_JWT_SECRET` / `ZWEQ_AI_KEY_SECRET`**：独立于数据库，须从 secret 管理（env/K8s Secret/Vault）注入，**不要**只存在数据库备份里。
- **uploads/ 目录**：文件类数据（上传的文件）不在 DB 备份内，需单独备份（rsync/对象存储），并保持与 DB 的挂载点一致。
- **迁移回滚**：zent 的迁移是前向 schema-as-code，无自动回滚。升级前先备份，出错时用 `pg_restore` 恢复到备份点。

## 5. 已知限制：Postgres 单连接（连接池缺失）

`zent` 的 `PostgresDriver` 是**单连接**（`conn: *c.PGconn`，无连接池），所有 DB 操作在同一连接上串行执行：

- 影响：高并发读写下，DB 层成为吞吐瓶颈（请求排队复用单连接）。
- 现状：对中小规模（QPS 数百级）够用；单连接也天然规避了 SQLite/Postgres 的并发写冲突。
- 后续改造方向：zent 增加连接池（多 `PGconn` + 借用/归还），或在 zweq 侧用多 `StoreEnv` 实例做读写分离。**水平扩容的真正瓶颈在 DB 连接，不在应用实例数。**
