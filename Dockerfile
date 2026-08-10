# zweq — 单二进制全栈（Zig 后端 + SolidJS SPA）
#
# 构建上下文需包含 zig_ws 与 zigmodu_ws（build.zig.zon 用 ../../zig_ws 相对路径）：
#   docker build -f zweq/Dockerfile -t zweq .
# 或从仓库布局根构建。生产更佳做法：vendor 依赖后改为自包含构建。

# ── 前端：SolidJS → web/dist ──────────────────────────────────────
FROM node:22-alpine AS frontend
WORKDIR /app
COPY web/package.json web/package-lock.json* ./
RUN npm install
COPY web/ .
RUN npm run build

# ── 后端：Zig 0.17 ────────────────────────────────────────────────
FROM ziglang/zig:0.17.0 AS backend
WORKDIR /build
# 保留兄弟布局：zweq 在 /build/zigmodu_ws/zweq，依赖在 /build/zig_ws
COPY zig_ws /build/zig_ws
COPY zigmodu_ws /build/zigmodu_ws
WORKDIR /build/zigmodu_ws/zweq
RUN zig build -Doptimize=ReleaseFast

# ── 运行镜像 ──────────────────────────────────────────────────────
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=backend /build/zigmodu_ws/zweq/zig-out/bin/zweq /usr/local/bin/zweq
COPY --from=backend /build/zigmodu_ws/zweq/zig-out/bin/zweq-admin /usr/local/bin/zweq-admin
COPY --from=frontend /app/dist /app/web/dist
ENV ZWEQ_DB_DRIVER=sqlite \
    ZWEQ_SQLITE_PATH=/data/zweq.db \
    ZWEQ_STATIC_DIR=/app/web/dist \
    ZWEQ_HTTP_PORT=8000
VOLUME ["/data"]
EXPOSE 8000
CMD ["/usr/local/bin/zweq"]
