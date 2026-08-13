#!/usr/bin/env bash
# zweq 生产备份脚本（Postgres）
#
# 用法：
#   ./scripts/backup.sh <backup_dir> [--pg-conninfo "host=... dbname=zweq user=..."]
#
# 说明：
#   - 使用 pg_dump 逻辑备份（-Fc 自定义格式，可用 pg_restore 选择性恢复）。
#   - 备份文件名带时间戳；保留最近 N 份（默认 7，可用 --keep 覆盖）。
#   - 建议配合 cron 每日执行：0 3 * * * /path/to/scripts/backup.sh /var/backups/zweq
#   - 恢复：pg_restore -d zweq <backup_file>（先 DROP 目标库或建新库）。
#
# SQLite 场景：直接复制 zweq.db 文件即可（或用 sqlite3 .backup 做在线备份）：
#   sqlite3 zweq.db ".backup '/backups/zweq-$(date +%F).db'"

set -euo pipefail

BACKUP_DIR="${1:?usage: backup.sh <backup_dir> [--pg-conninfo ...]}"
shift || true

KEEP="${KEEP:-7}"
PG_CONNINFO="${PG_CONNINFO:-host=localhost port=5432 dbname=zweq user=postgres}"

while [ $# -gt 0 ]; do
  case "$1" in
    --pg-conninfo) PG_CONNINFO="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$BACKUP_DIR"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/zweq-pg-$TS.dump"

echo "== 备份 Postgres → $OUT"
pg_dump -Fc --no-owner --no-privileges "$PG_CONNINFO" -f "$OUT"

# 清理过期备份
ls -1t "$BACKUP_DIR"/zweq-pg-*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
echo "== 完成（保留最近 $KEEP 份）"
echo "恢复示例: pg_restore -d zweq $OUT"
