//! Runtime configuration for zweq — read from environment variables.
//! Env var prefix: ZWEQ_.

const std = @import("std");

pub const Config = struct {
    http_port: u16 = 8000,
    /// "sqlite" | "postgres" — which driver to open for the data store.
    db_driver: []const u8 = "sqlite",
    sqlite_path: []const u8 = "zweq.db",
    pg_conninfo: []const u8 = "host=localhost port=5432 dbname=zweq user=postgres password=postgres sslmode=prefer connect_timeout=10",
    /// HMAC key for JWT signing.
    jwt_secret: []const u8 = "dev-secret-change-me",
    /// True when ZWEQ_JWT_SECRET was explicitly set (fail-closed in prod).
    jwt_secret_explicit: bool = false,
    /// Comma-separated IP allow-list for /metrics (empty = all; use in prod).
    metrics_allow_ips: []const u8 = "",
    /// Audit log retention in days (scheduled prune).
    audit_retention_days: i64 = 180,
    /// JWT lifetime in seconds.
    token_expiry_seconds: i64 = 24 * 3600,
    /// Password reset token lifetime in seconds.
    password_token_expiration_seconds: i64 = 3600,
    /// Public base URL used to build absolute links (e.g. reset links).
    /// Points at the SPA (dev server) by default so reset links open the
    /// frontend page, which then calls the API.
    app_host: []const u8 = "http://localhost:3001",
    /// Comma-separated CORS allow-list. "*" allows any origin (dev only);
    /// set e.g. `ZWEQ_CORS_ORIGINS=https://admin.example.com` in prod.
    cors_origins: []const u8 = "*",
    /// Mail transport. Empty host => console/log sink (dev). When set, SMTP
    /// is used (with STARTTLS when `smtp_starttls` is true).
    smtp_host: []const u8 = "",
    smtp_port: u16 = 587,
    smtp_username: []const u8 = "",
    smtp_password: []const u8 = "",
    smtp_from: []const u8 = "zweq@localhost",
    smtp_starttls: bool = true,
    /// Also log every outbound email at info level (useful in dev).
    mail_console: bool = true,
    /// Email verification token lifetime in seconds.
    verification_token_expiration_seconds: i64 = 24 * 3600,
    /// Upload directory (created on startup). Files are served from /files.
    upload_dir: []const u8 = "uploads",
    /// Frontend build output served by the single binary. Empty disables.
    static_dir: []const u8 = "web/dist",
    upload_max_bytes: usize = 10 * 1024 * 1024,
    /// In-memory cache capacity / TTL.
    cache_max_entries: usize = 1024,
    cache_ttl_seconds: u64 = 300,
    /// Background task dispatcher.
    task_workers: usize = 2,
    task_max_attempts: i64 = 3,
    task_retry_interval_seconds: i64 = 60,
    /// Master key used to encrypt AI provider API keys at rest
    /// (ZWEQ_AI_KEY_SECRET). Providers cannot be saved without it.
    ai_key_secret: []const u8 = "",
    /// Max agent runs per user per rolling 24h.
    ai_daily_run_limit: i64 = 100,
    /// 远端 zweq-cloud 服务 base url（如 `http://cloud:8100/api/v1`）。
    /// 空 = 本地模式（授权码/市场走本地 DB）。
    cloud_remote_url: []const u8 = "",

    pub fn fromEnv(environ: *const std.process.Environ.Map) Config {
        var cfg: Config = .{};
        cfg.http_port = parsePort(environ.get("ZWEQ_HTTP_PORT") orelse "8000");
        cfg.db_driver = environ.get("ZWEQ_DB_DRIVER") orelse "sqlite";
        cfg.sqlite_path = environ.get("ZWEQ_SQLITE_PATH") orelse "zweq.db";
        cfg.pg_conninfo = environ.get("ZWEQ_PG_CONNINFO") orelse cfg.pg_conninfo;
        cfg.jwt_secret = environ.get("ZWEQ_JWT_SECRET") orelse "dev-secret-change-me";
        cfg.jwt_secret_explicit = environ.get("ZWEQ_JWT_SECRET") != null;
        cfg.metrics_allow_ips = environ.get("ZWEQ_METRICS_ALLOW_IPS") orelse "";
        cfg.audit_retention_days = parseInt64(environ.get("ZWEQ_AUDIT_RETENTION_DAYS") orelse "180", 180);
        cfg.token_expiry_seconds = parseInt64(environ.get("ZWEQ_TOKEN_EXPIRY") orelse "86400", 86400);
        cfg.password_token_expiration_seconds = parseInt64(environ.get("ZWEQ_PASSWORD_TOKEN_EXPIRATION") orelse "3600", 3600);
        cfg.app_host = environ.get("ZWEQ_APP_HOST") orelse "http://localhost:3001";
        cfg.cors_origins = environ.get("ZWEQ_CORS_ORIGINS") orelse "*";
        cfg.smtp_host = environ.get("ZWEQ_SMTP_HOST") orelse "";
        cfg.smtp_port = parsePort(environ.get("ZWEQ_SMTP_PORT") orelse "587");
        cfg.smtp_username = environ.get("ZWEQ_SMTP_USERNAME") orelse "";
        cfg.smtp_password = environ.get("ZWEQ_SMTP_PASSWORD") orelse "";
        cfg.smtp_from = environ.get("ZWEQ_SMTP_FROM") orelse "zweq@localhost";
        cfg.smtp_starttls = parseBool(environ.get("ZWEQ_SMTP_STARTTLS") orelse "true", true);
        cfg.mail_console = parseBool(environ.get("ZWEQ_MAIL_CONSOLE") orelse "true", true);
        cfg.verification_token_expiration_seconds = parseInt64(environ.get("ZWEQ_VERIFICATION_TOKEN_EXPIRATION") orelse "86400", 86400);
        cfg.upload_dir = environ.get("ZWEQ_UPLOAD_DIR") orelse "uploads";
        cfg.static_dir = environ.get("ZWEQ_STATIC_DIR") orelse "web/dist";
        cfg.upload_max_bytes = parseIntUsize(environ.get("ZWEQ_UPLOAD_MAX_BYTES") orelse "10485760", 10 * 1024 * 1024);
        cfg.cache_max_entries = parseIntUsize(environ.get("ZWEQ_CACHE_MAX_ENTRIES") orelse "1024", 1024);
        cfg.cache_ttl_seconds = @intCast(parseInt64(environ.get("ZWEQ_CACHE_TTL_SECONDS") orelse "300", 300));
        cfg.task_workers = parseIntUsize(environ.get("ZWEQ_TASK_WORKERS") orelse "2", 2);
        cfg.task_max_attempts = parseInt64(environ.get("ZWEQ_TASK_MAX_ATTEMPTS") orelse "3", 3);
        cfg.task_retry_interval_seconds = parseInt64(environ.get("ZWEQ_TASK_RETRY_INTERVAL_SECONDS") orelse "60", 60);
        cfg.ai_key_secret = environ.get("ZWEQ_AI_KEY_SECRET") orelse "";
        cfg.ai_daily_run_limit = parseInt64(environ.get("ZWEQ_AI_DAILY_RUN_LIMIT") orelse "100", 100);
        cfg.cloud_remote_url = environ.get("ZWEQ_CLOUD_REMOTE_URL") orelse "";
        return cfg;
    }
};

fn parsePort(s: []const u8) u16 {
    return std.fmt.parseInt(u16, s, 10) catch 8000;
}

fn parseInt64(s: []const u8, default: i64) i64 {
    return std.fmt.parseInt(i64, s, 10) catch default;
}

fn parseIntUsize(s: []const u8, default: usize) usize {
    return std.fmt.parseInt(usize, s, 10) catch default;
}

fn parseBool(s: []const u8, default: bool) bool {
    if (std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "yes")) return true;
    if (std.mem.eql(u8, s, "0") or std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "no")) return false;
    return default;
}
