# Repository Directory Map

> Status: living document — update as the codebase evolves.
> This is a map of the repo **root**. For the deep architecture dive, see
> [ARCHITECTURE.md](ARCHITECTURE.md).

## Legend

- **Build artifacts** — generated during build, never committed; safe to delete.
- **Reference / scaffolding** — local inputs or snapshots, not part of the shipped product.
- **Runtime data** — created by the running server, not source code.

## Top-level directories

| Path | What it is |
| --- | --- |
| `src/` | Zig backend source: `main.zig` (server), `config.zig`, `db.zig` (SQLite/Postgres driver + migrations), `schema.zig` (schema aggregation), `modules/<domain>/` (model → persistence → service → api → module), `services/`, `http/`, `middleware/`, background `jobs.zig` / `scheduled.zig`, admin tooling (`admin_cli.zig`, `admin_nav*`, `permission_*`), and `tests/`. |
| `web/` | Admin console: SolidJS + TypeScript + Rsbuild + Tailwind/DaisyUI SPA under `web/src`. The Zig binary serves compiled `web/dist` in production. |
| `unix/` | **Reference/scaffolding** — the upstream **unibestX** uni-app X template source (git-ignored). The shipped, customized mini-program lives in `mp/`. |
| `mp/` | The shipped uni-app X **mini-program**, customized from the `unix/` template: `.uvue`/`.uts` pages, `uni_modules`, `uniCloud-aliyun`, `pages.json`. |
| `docs/` | Canonical documentation: `ARCHITECTURE.md` (deep dive), `DIRECTORY.md` (this file), `backup.md`, `benchmark-report.md`, `test-report-v0.3.0.md`, and `superpowers/` (specs + plans). |
| `scripts/` | Dev/e2e helpers: backup, file-size check, Python e2e runners, Unix test-data seed. |
| `tools/` | Codegen helpers: `gen_module.py` (scaffolds a new `modules/<domain>` five-file shape). |
| `uploads/` | **Runtime data** — uploaded files directory (contains `market/`), git-ignored. |
| `_dev/` | **Reference/local scaffolding** — WeEngine (微擎) PHP install archive + `weengine_src`, used for local install study. Not part of the project. |
| `_ref/` | **Reference/local scaffolding** — `zenaipa` backend skeleton the project adapts from. Not part of the project. |
| `zweq-cloud/` | Separate Zig cloud service (license codes / app marketplace) with its own `build.zig`, `src/`, `db_link.zig`, and vendored deps. |
| `zig-pkg/` | **Build artifacts** — fetched Zig dependency packages (zigmodu / zent / zwechat / zhttp), pinned by `build.zig.zon`. |
| `zig-out/` | **Build artifacts** — compiled binary output (`zweq`, `zweq-admin`). |
| `.zig-cache/` | **Build artifacts** — Zig build cache. |

## Top-level files

| Path | What it is |
| --- | --- |
| `build.zig` / `build.zig.zon` | Zig build script + dependency manifest (path → git tag pins). |
| `db_link.zig` | Shared DB driver link helpers (build-scripts only, not runtime). |
| `dev.md` | Original design / rewrite plan (微擎 → Zig), kept at root for its internal references. See `docs/` for canonical docs. |
| `CLAUDE.md` | Agent working notes / repo conventions. (Git-ignored.) |
| `README.md` / `README.zh-CN.md` | English and Chinese project overviews + quick start (cross-linked). |
| `CHANGELOG.md` | Release history. |
| `Dockerfile` / `docker-compose.yml` | Container build (multi-stage node → zig → debian) and a Postgres compose file. |
| `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` | Standard repo docs. |
| `zweq.db`, `zweq.db-shm`, `zweq.db-wal` | **Runtime data** — local SQLite database + WAL/SHM sidecars (git-ignored). |

> **Ignored, not shipped:** `_dev/`, `_ref/`, `zig-pkg/`, `zig-out/`, `.zig-cache/`,
> `*.db*`, `uploads/`, `unix/`, `CLAUDE.md` and `dev.md` are git-ignored — they are
> inputs, build artifacts, scaffolds or runtime data, not source to commit.
