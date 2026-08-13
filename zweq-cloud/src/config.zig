//! Runtime configuration for zweq-cloud — read from environment variables.
//! Env var prefix: ZWEQ_CLOUD_.

const std = @import("std");

pub const Config = struct {
    http_port: u16 = 8100,
    db_driver: []const u8 = "sqlite",
    sqlite_path: []const u8 = "zweq-cloud.db",
    pg_conninfo: []const u8 = "host=localhost port=5432 dbname=zweq_cloud user=postgres password=postgres sslmode=prefer connect_timeout=10",
    /// 管理 API 鉴权 token（所有写操作/管理接口需 Bearer 头）。
    admin_token: []const u8 = "change-me",
    /// 市场产物落盘目录（storage_backend=local 时）。
    artifact_dir: []const u8 = "artifacts",
    /// 产物托管后端："local" | "s3"（S3-compatible）。
    storage_backend: []const u8 = "local",
    /// S3-compatible 配置（storage_backend=s3 时）。
    s3_endpoint: []const u8 = "",
    s3_bucket: []const u8 = "",
    s3_region: []const u8 = "us-east-1",
    s3_access_key: []const u8 = "",
    s3_secret_key: []const u8 = "",

    pub fn fromEnv(environ: *const std.process.Environ.Map) Config {
        var cfg: Config = .{};
        cfg.http_port = parseInt(u16, environ.get("ZWEQ_CLOUD_HTTP_PORT") orelse "8100", 8100);
        cfg.db_driver = environ.get("ZWEQ_CLOUD_DB_DRIVER") orelse "sqlite";
        cfg.sqlite_path = environ.get("ZWEQ_CLOUD_SQLITE_PATH") orelse "zweq-cloud.db";
        cfg.pg_conninfo = environ.get("ZWEQ_CLOUD_PG_CONNINFO") orelse cfg.pg_conninfo;
        cfg.admin_token = environ.get("ZWEQ_CLOUD_ADMIN_TOKEN") orelse "change-me";
        cfg.artifact_dir = environ.get("ZWEQ_CLOUD_ARTIFACT_DIR") orelse "artifacts";
        cfg.storage_backend = environ.get("ZWEQ_CLOUD_STORAGE_BACKEND") orelse "local";
        cfg.s3_endpoint = environ.get("ZWEQ_CLOUD_S3_ENDPOINT") orelse "";
        cfg.s3_bucket = environ.get("ZWEQ_CLOUD_S3_BUCKET") orelse "";
        cfg.s3_region = environ.get("ZWEQ_CLOUD_S3_REGION") orelse "us-east-1";
        cfg.s3_access_key = environ.get("ZWEQ_CLOUD_S3_ACCESS_KEY") orelse "";
        cfg.s3_secret_key = environ.get("ZWEQ_CLOUD_S3_SECRET_KEY") orelse "";
        return cfg;
    }
};

fn parseInt(comptime T: type, s: []const u8, default: T) T {
    return std.fmt.parseInt(T, s, 10) catch default;
}
