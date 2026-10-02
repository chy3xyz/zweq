# zweq-cloud — 独立云服务（授权码 + 应用市场），与 zweq 同架构的单独构建根
#
# 自包含构建：依赖按 build.zig.zon 的 git tag 引用在容器内 fetch（需 git 与网络），
# 构建上下文即本目录（配合本目录 .dockerignore 裁剪），不依赖仓库其他部分。
# 驱动面 = SQLite + PostgreSQL（build.zig 硬编码 sqlite+postgres，无 -Ddb 选项），
# 不含 mysql；运行时可经 ZWEQ_CLOUD_DB_DRIVER 在 sqlite / postgres 间切换。
#
# Zig 版本说明：同主站 Dockerfile —— 0.17.0 尚无稳定发布（ziglang/zig 镜像亦无该
# tag），zent v0.78 的 minimum_zig_version 又要求 0.17.0，因此固定使用与本地/CI
# 一致的官方 dev 构建 0.17.0-dev.1970+67f39b551（ziglang.org/builds），避免版本
# 漂移导致编译差异。

# ── 构建：Zig 0.17.0-dev.1970+67f39b551 ──────────────────────────
# alpine 与运行阶段同基底（musl ABI 一致）；dev 包提供 pq/sqlite3 的头文件
# 与链接库（驱动按需链接：sqlite+postgres，不含 mysql）。
FROM alpine:3.21 AS backend
# TARGETARCH 由 BuildKit 注入（amd64/arm64），映射到 zig 官方 tarball 的命名
ARG TARGETARCH
ARG ZIG_VERSION=0.17.0-dev.1970+67f39b551
RUN apk add --no-cache git postgresql-dev sqlite-dev tar xz \
 && case "${TARGETARCH}" in \
      amd64) ZIG_TUPLE=x86_64-linux ;; \
      arm64) ZIG_TUPLE=aarch64-linux ;; \
      *) echo "不支持的 TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && wget -q "https://ziglang.org/builds/zig-${ZIG_TUPLE}-${ZIG_VERSION}.tar.xz" \
 && tar -xJf "zig-${ZIG_TUPLE}-${ZIG_VERSION}.tar.xz" -C /opt \
 && mv "/opt/zig-${ZIG_TUPLE}-${ZIG_VERSION}" /opt/zig \
 && ln -s /opt/zig/zig /usr/local/bin/zig
WORKDIR /src
COPY build.zig build.zig.zon db_link.zig ./
COPY src ./src
# BuildKit cache mount 复用依赖 fetch 与编译缓存（.zig-cache 本地 / ~/.cache/zig 全局）
RUN --mount=type=cache,target=/src/.zig-cache \
    --mount=type=cache,target=/root/.cache/zig \
    zig build -Doptimize=ReleaseSafe --summary all
# 运行镜像不需要调试符号：strip 掉 DWARF/符号表
RUN apk add --no-cache binutils \
 && strip /src/zig-out/bin/zweq-cloud

# ── 运行镜像（与构建阶段同 alpine 版本，动态库版本匹配）──────────
FROM alpine:3.21
RUN apk add --no-cache ca-certificates libpq sqlite-libs \
 && addgroup -S zweqcloud && adduser -S -G zweqcloud zweqcloud
WORKDIR /app
COPY --from=backend /src/zig-out/bin/zweq-cloud /usr/local/bin/zweq-cloud
# 数据目录（sqlite/市场产物）归非 root 用户；切 postgres 时本目录仅需产物卷
RUN mkdir -p /data && chown -R zweqcloud:zweqcloud /data
ENV ZWEQ_CLOUD_DB_DRIVER=sqlite \
    ZWEQ_CLOUD_SQLITE_PATH=/data/zweq-cloud.db \
    ZWEQ_CLOUD_ARTIFACT_DIR=/data/artifacts \
    ZWEQ_CLOUD_HTTP_PORT=8100
VOLUME ["/data"]
EXPOSE 8100
# 非 root 运行：被攻破的进程拿不到容器 root
USER zweqcloud
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8100/health/live || exit 1
CMD ["/usr/local/bin/zweq-cloud"]
