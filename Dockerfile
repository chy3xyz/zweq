# zweq — 单二进制全栈（Zig 后端 + SolidJS SPA）
#
# 自包含构建：依赖按 build.zig.zon 的 git tag 引用在容器内 fetch（需 git 与网络），
# 构建上下文即本仓库（配合根 .dockerignore 裁剪），不再依赖兄弟目录布局。
#
# Zig 版本说明：0.17.0 正式版已发布，主站/云端/CI/本地统一钉 0.17.0（ziglang.org/download），
# 与 build.zig.zon 的 minimum_zig_version 一致，避免版本漂移导致编译差异。

# ── 前端：SolidJS → web/dist ──────────────────────────────────────
FROM node:22-alpine AS frontend
WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build

# ── 后端：Zig 0.17.0 正式版 ───────────────────────────────────────
# alpine 与运行阶段同基底（musl ABI 一致）；dev 包提供 pq/sqlite3 的头文件
# 与链接库（驱动按需链接：默认 sqlite+postgres，不含 mysql）。
FROM alpine:3.21 AS backend
# TARGETARCH 由 BuildKit 注入（amd64/arm64），映射到 zig 官方 tarball 的命名
ARG TARGETARCH
ARG ZIG_VERSION=0.17.0
RUN apk add --no-cache git postgresql-dev sqlite-dev tar xz \
 && case "${TARGETARCH}" in \
      amd64) ZIG_TUPLE=x86_64-linux ;; \
      arm64) ZIG_TUPLE=aarch64-linux ;; \
      *) echo "不支持的 TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && wget -q "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_TUPLE}-${ZIG_VERSION}.tar.xz" \
 && tar -xJf "zig-${ZIG_TUPLE}-${ZIG_VERSION}.tar.xz" -C /opt \
 && mv "/opt/zig-${ZIG_TUPLE}-${ZIG_VERSION}" /opt/zig \
 && ln -s /opt/zig/zig /usr/local/bin/zig
WORKDIR /src
COPY build.zig build.zig.zon db_link.zig ./
COPY src ./src
COPY scripts ./scripts
# BuildKit cache mount 复用依赖 fetch 与编译缓存（.zig-cache 本地 / ~/.cache/zig 全局）
RUN --mount=type=cache,target=/src/.zig-cache \
    --mount=type=cache,target=/root/.cache/zig \
    zig build -Doptimize=ReleaseSafe --summary all
# 运行镜像不需要调试符号：strip 掉 DWARF/符号表，二进制约 100MB → 30MB 级
RUN apk add --no-cache binutils \
 && strip /src/zig-out/bin/zweq /src/zig-out/bin/zweq-admin

# ── 运行镜像（与构建阶段同 alpine 版本，动态库版本匹配）──────────
FROM alpine:3.21
RUN apk add --no-cache ca-certificates libpq sqlite-libs \
 && addgroup -S zweq && adduser -S -G zweq zweq
WORKDIR /app
COPY --from=backend /src/zig-out/bin/zweq /usr/local/bin/zweq
COPY --from=backend /src/zig-out/bin/zweq-admin /usr/local/bin/zweq-admin
COPY --from=frontend /app/dist /app/web/dist
# 数据目录（sqlite/上传）归非 root 用户；/app 静态资源只读即可
RUN mkdir -p /data && chown -R zweq:zweq /data
ENV ZWEQ_DB_DRIVER=sqlite \
    ZWEQ_SQLITE_PATH=/data/zweq.db \
    ZWEQ_UPLOAD_DIR=/data/uploads \
    ZWEQ_STATIC_DIR=/app/web/dist \
    ZWEQ_HTTP_PORT=8000
VOLUME ["/data"]
EXPOSE 8000
# 非 root 运行：被攻破的进程拿不到容器 root
USER zweq
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8000/health/live || exit 1
CMD ["/usr/local/bin/zweq"]
