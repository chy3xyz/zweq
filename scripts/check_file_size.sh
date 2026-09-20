#!/bin/sh
# 文件体积门禁：src 下任一 .zig 超过行数上限即失败，防止再次长成巨型单体。
# 上限可用环境变量覆盖：ZWEQ_MAX_FILE_LINES=1500 ./scripts/check_file_size.sh
MAX=${ZWEQ_MAX_FILE_LINES:-1800}
status=0
for f in $(find src -name '*.zig' | sort); do
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -gt "$MAX" ]; then
    echo "❌ $f: ${lines} 行（上限 ${MAX}）——请按子域拆分"
    status=1
  fi
done
if [ $status -eq 0 ]; then
  echo "✓ 全部 src/**/*.zig ≤ ${MAX} 行"
fi
exit $status
