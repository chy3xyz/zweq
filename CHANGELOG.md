# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **就绪探针每次都泄漏一整页用户行**：`/api/v1/health/ready` 的探针用 `listUsers(1, 1, …)` 探库，却用 `ctx.allocator`（连接 arena，`free` 是 no-op）释放结果——行与切片实由 `UserStore` 的进程 gpa 分配，而健康检查在生产是按秒调用的，属稳态泄漏。已改为 `UserStore.freeList`。**这处是新加的分配器归属 lint 抓到的**（见 `### Added`）。
- **77 处 `catch {}` 吞错分诊**：A 类 27 处（资源清理 / 事务回滚 / 定时兜底——语义上确实无可挽回且错误另有通道）补注释说明为何可吞；B 类 49 处（业务写入、状态变更、外部调用被静默吞掉）补 `std.log.err`/`warn` 带上下文，**控制流与 best-effort 语义不变**。钱相关的几处值得点名：余额支付成功后的 `markPaid`、支付成功后的分佣与积分入账、取消/退款/超时的库存回滚、成团后的 `markPaid`，以及分销佣金第二笔 `total_commission` 累加（同一函数第一步是 `try`、第二步却把 `Save` 吞掉——账目半成功且静默漂移）。
- **3 处 `catch unreachable`**（`rate_limit.zig` 的两个 middleware 构造、`main.zig` 的 `OrderPaidBus` 堆分配）改为 `catch @panic("<上下文>: out of memory")`：ReleaseFast 下 `unreachable` 是 UB，OOM 至少该留一句可读的报错（zigmodu 0.15.41 对它自己同类 8 处做了同样处理）。
- **`Session` 的混合所有权**：`session.deinit(allocator)` 用一个分配器释放两种来源（`row` 归 store、`token` 归安全模块签发方）——今天恰好同为进程 gpa 所以不崩，注入一旦分歧就是非法释放。改为 `UserService.freeSession(&session)` 按各自拥有者释放，`Session.deinit` 删除（auth ×2、admin CLI、测试共 4 处调用点同步）。同类脆弱点一并收敛：`shop/handlers/content.zig` 的 C-token 签发/验签产物改用 `sec.module.allocator`，`vote/api.zig` 的鉴权用户行改用 `user_svc.store.allocator`。
- **分配器不匹配导致的静默泄漏（约 30 处）**：`ctx.allocator` 是**连接 fiber 的 arena**（zigmodu 源码注释原话："Zig 0.17 arena free is a no-op"），而各 store/service 的 `dup*` 用**进程 gpa** 分配行与字符串——用 arena 去释放进程 gpa 的对象，`free` 直接退化成空操作，整块内存再也不回来。这是本轮真库冒烟实测出来的：CSV 导出每次请求泄漏整页（用户 11 行、审计 121 行），每次登录泄漏一份密码哈希，一次全流程停机共 **631 条 `leaked`**。已把约 30 处释放改回**拥有者分配器**（store/service 自己的 `allocator`，或复用 `freeList` 这类既有辅助），并修掉 `AiService.resolveProvider` 的所有权结构问题——它把选中行从列表里拷出来，却让列表与调用方两侧都去释放同一行（过去两侧都是 arena，所以既不崩也完全不释放），现在选中行显式从列表释放中排除、所有权转移给调用方。修完跑同一套冒烟：**停机泄漏 631 条 → 0**。
  - 这类不匹配**单元测试抓不到**：测试里 `ctx.allocator` 与 store 分配器同为 `std.testing.allocator`，两侧同源。判断方法只能查被释放对象的**生产者**用的是哪个分配器（生产者把 allocator 当形参时 = 谁传谁拥有）。
- **上传内容判定只信客户端声明（存储型 XSS 口子）**：`validMime` 比较的是客户端自己写的 `Content-Type`，`说明.png` + `image/png` 里装 HTML/SVG 能直接通过（同源存储型 XSS 的经典形态）。现接入 zigmodu v0.15.46 `http.UploadGuard`，按**字节**嗅探魔数并 fail-closed 拒绝 SVG/HTML 主动内容（策略导出为 `file.service.upload_policy`，生产与测试共用同一份以防漂移）。实测：伪装成 PNG 的 HTML 被 400 拒绝（新增文案「文件内容不允许（SVG/HTML 等主动内容）」），真实 PNG / PDF / docx / gzip / txt 全部正常——刻意**不**要求扩展名与内容一致（`.docx`/`.xlsx`/`.jar` 内容本就是 ZIP、`.heic`/`.rar` 无魔数，开对齐会把正常上传判死）。
- **钱的正确性（并发竞态/事务）**：支付回调 `markOrderPaid` 改条件更新（`WHERE status='pending'`），重复回调幂等不再重复入账；`completeRecharge` 两写包进同一事务；积分兑换 `decrementStock` 改原子 increment+`RawArgs` 守卫防超卖，`redeem` 三写改补偿流（失败按相反顺序回补）；店铺 `markPaid`/`cancelOrder`/`auditRefund` 幂等+事务化（条件更新 affected 语义：已终态幂等、归属不符 NotFound），消除重复分佣/双回滚库存/重复审核；秒杀 `rush` 落单失败回补库存；`setDefaultAddress` 两写改单语句 CASE 翻转消除双默认。
- **越领/超发**：任务 `claimNext` 检查 affected（多 worker 不再重复执行）；`member_card.adjustPoints` 两次 increment 合并单条+`points >= ?` 下限守卫；拼团 `joinGroupon` 下单前满员拦截。
- **越权（IDOR）**：购物车/地址写操作 WHERE 加 openid 归属；`pickupOrder` 加 tenant；C 端 6 处 store 查询补 tenant 过滤（秒杀活动/积分商品/投票/地址快照/拼团/下单商品归属）。
- **静默失败**：邮件任务 SMTP 失败走既有重试链路（不再记成功丢信）；分销台账/清理 job/cleanup 全部补 `log.err`；27 个 api.zig 约 100 处 `@errorName` 内部错误名不再泄漏给用户。
- **前端**：业务错误（400/404/500）的中文 msg 现在真正展示给用户（client.ts 非 2xx envelope 解包，此前只显示 axios 英文兜底）；Points 页三 modal 共享提交状态串错（拆为独立 signal）；envelope 泛型 helper 上移到 `client.ts`（约 30 个模块 -463 行样板）。
- **停机 panic**：`defer server_handle.join()` 与停机段的显式 join 必然各 join 一次；POSIX 下 join 过的 `pthread_t` 立即失效，二次 join 以 `ESRCH` 撞上 `std.Thread.join` 内的 `.SRCH => unreachable`，**每次 SIGINT/SIGTERM 都 panic**（并吞掉了后续的模块停机与分配器报告）。改用 `server_joined` 标志互斥，保留 defer 兜底（提前 return 的错误路径仍不泄漏线程）。
- **停机泄漏**：上面那个 panic 一直掩盖着一条泄漏——`OrderPaidBus` 按进程生命周期堆分配且从未释放（debug 分配器每次停机报 2 条 `leaked`，共约 288 B）。现在在「在途请求已排空、模块停机尚未开始」的时刻 `deinit` + `destroy` 并置空引用。不能挪到服务层释放：`defer app.deinit()`（模块停机）注册得比总线创建早，晚注册的 defer 会先于模块停机执行、留下悬垂指针；且测试传的是栈上 `&bus`，无条件释放会砸掉测试。

### Added
- **工程卫生批次（5 项）**：
  - **`zig build lint-fmt`**（CI 同步）：`zig fmt --check src`，先一次性把 9 个不达标文件 format 干净。
  - **CORS 生产 fail-closed**：`ZWEQ_CORS_ORIGINS` 未显式设置且驱动为 PostgreSQL（与 JWT 同一"生产"判据）→ 拒绝启动，报错逐条点名缺失的环境变量。此前默认 `"*"` 在生产同样放行任意来源。
  - **`/metrics` 补两块**：连接池 `zweq_db_pool_total/in_use/available/waiters`（gauge）+ `zweq_db_pool_exhausted_total`（counter，zent v0.53 `ConnPool.stats()`，经 `StoreEnv.poolStats()` 快照 + 函数指针注入，SQLite 也走池故两种驱动都导出）；限流拒绝 `zweq_rate_limit_rejections_total`（counter，per-IP 超限 / per-openid 超限与无身份拒绝 / fail-closed 三条 429 路径共用一个进程级原子，多实例由 Prometheus `sum()` 聚合）。实测：25 次登录打爆 20/分限流 → 计数恰好 5。
  - **出站 URL 治理（SSRF 基线）**：新增 `src/http/url_guard.zig`（scheme 必须 http(s)、host 非空、按字面拒绝 localhost/127./10./192.168./169.254./172.16-31./::1，并剥离 userinfo 防 `user@127.0.0.1` 绕过；注释写明局限——不做 DNS 解析，域名解析到内网防不住），接入三个管理员配置的出站地址写入口：AI provider `endpoint`（create+update）、shop webhook 创建、`zweq-cloud` 市场包 `download_url`（独立构建根，内联同款副本）。新增测试覆盖合法/拒绝/172.15-32 边界。
  - **Dockerfile 自包含化**：旧版要求构建上下文带兄弟目录 `zig_ws`（依赖改 git pin 后单仓库构建直接失败），且 `ziglang/zig:0.17.0` 镜像并不存在。重写为：node:22-alpine（`npm ci`）→ alpine:3.21 + git + DB dev 包 + 官方 dev tarball `0.17.0-dev.1970+67f39b551`（与本地/CI 一致，TARGETARCH 映射 amd64/arm64）→ strip → alpine 运行层（musl 与链接库 ABI 匹配）。**实测构建成功，最终镜像 27.6 MB**，`/health/live` 冒烟通过；`docker-compose.yml` 对齐（context 指仓库自身、`ZWEQ_JWT_SECRET`/`ZWEQ_CORS_ORIGINS` 必填插值、健康检查），新增 `.dockerignore`（上下文 2.65 MB）。
- **两道防回归门禁**（把上一轮手工发现的问题固化成机器检查）：
  - **`zig build lint-alloc`**（`scripts/check_alloc_owner.py`）：静态拦「用请求 arena 释放长期分配器对象」。这类缺陷**单元测试原理上抓不到**——测试里 `ctx.allocator` 与 store 分配器同为 `std.testing.allocator`，两侧同源、不匹配不可见；判据只能是静态追被释放对象的**生产者**用哪个分配器。对上一轮修复前的代码树实测报出 **24 处**，当前树 **0 处**；门禁首次接线时又抓出就绪探针那处（见 `### Fixed`）。
  - **CI 新增 `e2e` job**：`scripts/run_e2e.sh` 起真库 + 真服务跑管理员与 C 端两套 e2e，**停机后扫日志断言「无泄漏、无 panic」**，并断言 SIGTERM 后 20 秒内退出。这是本轮之前靠人工做的冒烟流程的固化（当时正是它发现了 631 条泄漏）。
  - **登记豁免（必须随上游修复删除）**：该门禁目前豁免一处**已确认的 zigmodu ≤ v0.15.47 上游泄漏**——`SecurityModule.base64UrlDecode`/`base64Decode` 在 `decoder.decode` 失败时不释放已分配的缓冲（无效 token 的 header/payload 段触发；修法是每函数两行 `errdefer`，归 zigmodu 仓库）。升级到带修复的 zigmodu 发布版后，`scripts/run_e2e.sh` 里那段豁免必须删掉。
- **安全**：fan 经济接口（领券/抽奖/兑换/秒杀/提现/开卡/签到/投票）per-openid 限流（10/5/3 次每分档）+ fail-open/closed 统一策略；`shop_invite_record` 加 `UNIQUE(tenant_id, invitee_openid)`，`bindInvite` 改 `SaveIgnore` 幂等；checkin/member_account/distributor/vote_record 补唯一索引（并发撞键映射为已签/已开卡/已加盟/已投票）；`draw_record` 加 `draw_day` 列（不落唯一索引——daily_limit 可配 >1）。
- **可观测性**：`/metrics` 新增 `zweq_tasks_processed_total`/`zweq_tasks_failed_total`；Dispatcher tick/scheduled/单任务耗时日志。
- **OpenAPI**：fan 公共 API + payment 共 34 路由补参数注解（45 个参数进 openapi.json），模块顶部 doc comment 承载中文契约（summary/body 结构受 zigmodu `RouteMeta` 字段限制，待库扩展）。
- CI 前端 job（`npm run typecheck` + `vitest`）。
- **SQL 驱动按需编译/链接**（`zig build -Ddb=`，默认 `sqlite,postgres`；可 `all|sqlite|postgres|mysql` 逗号列表）：本仓库驱动面 = SQLite（开发/测试/默认运行时）+ PostgreSQL（生产），**MySQL 从不使用，不再编译进二进制**。实测 `otool -L zig-out/bin/zweq`：仅 `libpq` + `libsqlite3`，`mysql/mariadb` 引用 **0**。三处落地：
  - `build.zig`：新增 `-Ddb` 选项（`db_link.parseDb`），并**透传给 zigmodu 依赖**（它自身默认 `-Ddb=all`，不透传只会收窄我方链接、zigmodu 模块仍链接全套）。
  - `zweq-cloud/build.zig`：修正一处**隐性依赖**——它本就说 `sqlite_only`，但 libpq 实际是靠「搭 zigmodu 默认 all 的便车」链接进来的；现显式声明 `sqlite+postgres` 并同步透传 `.db="sqlite,postgres"`（透传成 `sqlite` 曾导致 22 个 `PQ*` 未定义符号，证明便车确实存在过）。
  - `Dockerfile`：构建层去掉 `mariadb-connector-c-dev`、运行层去掉 `mariadb-connector-c`、`/usr/include/mariadb` 软链 hack 删除（它只服务于 zent 的 mysql 头文件发现）。
  - 机制说明：zent 无 `-Ddb` 选项（sqlite 恒编译、pg/mysql 按构建机头文件自动发现），但缺头文件本就能编译（懒分析），且**链接**只发生在我们 `db_link.link` 的驱动集合上——所以收窄链接即收窄产物，与 zent 的发现逻辑无关。部署侧收益：运行镜像少一个动态库依赖与攻击面；CI/构建机少一个 dev 包要求。
  - **Docker 实测（alpine 全量构建 + 冒烟）**：`zweq` musl 二进制 16.8 MB，`ldd` 仅 `libpq/libsqlite3/libssl/libcrypto/musl`，**无 libmysqlclient**；`/health/live` 冒烟通过。顺带修 `db_link.zig` 的 linux lib 目录硬编码（debian multiarch 路径在 alpine 不存在会产生 "unable to open library directory" 告警）：改为存在才传。
  - **排查插曲（下轮避坑）**：alpine 构建日志里出现过 `compile exe … fast native failure` + `-isystem conflicts with -I` 的片段，实为 **BuildKit 在客户端断开/取消后重放的上一步骤残留日志**，伴随 macOS Docker Desktop 守护进程不稳定（rpc EOF）出现——当前树两次独立全量构建均为 `10/10 steps succeeded`，该片段非真实失败。`-isystem conflicts with -I` 告警本体来自 zwechat 回退 `-I/usr/include`（openssl 探测）与 pg 的 `-isystem /usr/include/postgresql` 嵌套，**非致命**，归上游（zwechat/zhttp），已如实登记。

### Changed
- 依赖升级（主站 + `zweq-cloud` 同步）：zigmodu **v0.34.0 → v0.35.0**（清 `.zig-cache` 重建，零代码改动编译通过；上游 UPGRADING 自标「没有公开 API 被删」）。逐条核对结论：
  - **唯一行为变化（对我们无感）**：`ws_write_timeout_ms = 0` 由「无界」改成「继承 `response_write_timeout_ms`」（默认 30 s）——本仓库 src 与 zweq-cloud 均零 WebSocket/SSE/streaming 使用（grep 零命中），不设置即新默认，无需改动。
  - **纯免费收益**：服务端每条写路径接上写预算（H1 缓冲/chunked/SSE/H2/Server WS 推送，`response_write_timeout_ms` 默认 30 s，`0`=旧行为）+ 写失败粘住契约（空 flush 不再假成功）+ 裸写去 SIGPIPE（`writeFull/writevAll` 改 `MSG_NOSIGNAL`，RST 对端不再能杀进程）；H2 响应体 > `max_pending_bytes`（4 MiB）不再被拒（6 MiB 曾 `RST_STREAM(ENHANCE_YOUR_CALM)`、16 MiB `INTERNAL_ERROR`，「同一路由 H1 正常 H2 报错」的差异消失）；H2 新流窗口按对端 `SETTINGS_INITIAL_WINDOW_SIZE` 起（RFC 9113 §6.5.2，修 64 KiB 卡顿）；WS 路由关停洞（静默对端拖住 `stop()`）修掉 + stuck-callback 看门狗；validation 链搬新家 `validation/FieldValidation.zig`（`Validator.zig` 只剩别名，弃用拼写不早于 1.0 删，零影响）。
  - 验证：`zig build` + 三门禁 + **96/96 测试**（`zig build test` 首跑出现已知 macOS 假 flake「failed command 无输出」，同种子 `0x813e1257` 手动复跑 96/96 全过，非确定性、与升级无关）+ `zweq-cloud` build/test + e2e 两套件 15/15 + 停机泄漏严格门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zigmodu **v0.33.2 → v0.34.0**（跨 0.33.3/0.33.4/0.33.5；清 `.zig-cache` 重建）。**本版有真 Breaking（上游自标"破坏性：否"的那几节之外，UPGRADING §v0.33.4 单独列了 2 处编译错）**，命中我们 1 处：
  - **`SecurityModule.verifyPassword` / `PasswordEncoder.matches` 返回 `PasswordError!bool`**（0.33.4，把"存储哈希不可解码 / 解码 OOM"从"答成口令不匹配（401）"改为如实报错——失败登录计数不再说谎；顺带修掉"32 字节摘要+1 字节垃圾"前缀比较可判真的真漏洞）。适配：新增 `verifyPasswordChecked` 助手（user/service.zig）——`OutOfMemory` 与 `MalformedStoredHash` 记日志后上抛（按上游口径 → API 层 500），`false` 仍由各调用点映射成本地 invalid 错误；四个声明式错误集（`LoginError`/`ResetTokenError`/`VerificationError`/`ChangePasswordError`）扩员，auth/api.zig 四个穷尽 switch 补 500 分支（故意走"编译错→补分支"的响亮路径）。**修一条被新语义照出的假测试**：`user_test` 的 changePassword 用例此前把字面量 `"hash"` 当存储密码（旧代码畸形哈希→false；新代码→`MalformedStoredHash`），改用 `hashPassword` 造真实哈希，并补"改密后新口令可登录"的闭环断言。
  - **其余 Breaking 逐项 grep 零命中**：`Cursor.next` 错误联合（不用 sqlx 游标）、`csrf()` 需 user_data（无手工调用）、`attachIdentityBestEffort` 变 `!void`（走常规 jwtAuth 接线）、`RedisCluster.init(allocator, io)`（不用）、无类型 `EventBus(T).subscribe` 变 `!void`（我们用 `TypedEventBus`，本就 `!void` 且已 `catch`）、`AgentAuditLog.owned` 字段（不用）。
  - **行为变化（对我们无感或纯收益）**：认证中间件"我们这侧失败"由 401 改 500（正是我们上一批自己在 handler 层做的事，框架现在原生对齐）；HEAD 不再带 body / Content-Length 只写一遍（H1+H2）；H2 转发 handler 响应头（Set-Cookie 不再静默丢）；同进程两 Server 的全局状态按实例隔离（我们单 Server）；Prometheus `create*` 首次抓取后 `error.Frozen`、重名 `error.DuplicateName`、Summary 三个死字段删除——**我们自定义指标是手写文本追加在 HttpMetricsCollector 输出后，从不调 `create*`，零影响**；Redis 不可达抛错不再答假值（我们用 redis 限流后端的话会看见错误而非静默放行——正是想要的）；sqlite `readSQLiteValue` 的 OOM 不再伪装成 SQL NULL（正中我们的 sqlite 驱动面）；metrics 渲染 UAF、WS 帧缺 flush/双关 fd、Lru/Pool 取消丢资源等一批框架内部修复纯免费。
  - 验证：`zig build` + 三门禁 + **96/96 测试**（中途真红 1 条：changePassword 假测试，已修；其余 `failed command` 为已知 macOS 假 flake，同种子手动 96/96）+ `zweq-cloud` build/test + e2e 两套件 + 停机泄漏严格门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zigmodu **v0.33.1 → v0.33.2**（清 `.zig-cache` 重建，零代码改动编译通过；上游自标「破坏性：否」）。逐条核对结论：
  - **全部是框架内部修复，对我们纯免费收益**：① `Lru.deinit` 无锁 teardown 竞态（持锁者正改 map/list 时竞败方带病拆）改 `lockUncancelable` 等待；② `Pool.release` 取消时丢连接（`lock` 被取消即返回，连接不回池不销毁、池永久少一槽）同样改 `lockUncancelable`；③ **h2 响应 content-type 大小写敏感查找真正修好**（v0.33.1 声称修了实际没修，本版用 `headerLookup(ctx.response_headers, …)` 修实，并有 h2 全链路 dispatch E2E 钉住）；④ OOM 注入扫描（`checkAllAllocationFailures`）抓出两个真缺陷——`Hpack.decode` OOM 泄漏名字副本、**Huffman 字面量名字的非-OOM use-after-free**（h2 路径，块表达式 defer 在 `break :blk` 时提前 free）；⑤ 上游解释了我们并行跑时偶发的 `TwoPhaseCommit`/`sqlite prepared statement` 失败：两个用例写死 `/tmp` 固定路径互相拆台，已改按 pid 唯一（与我们的 96/96 假 flake 是同族现象的不同实例，我们的 flake 属 macOS 工具链，仍旧观察）。
  - **语义澄清不涉及我们**：`ConnPool.active` 上游判定"不是 bug"（数的是池拥有数而非在飞数，容量闸门依赖此语义）；`ConnPool.reconnect` 是死代码。
  - 验证：`zig build` + 三门禁 + **96/96 测试**（`zig build test` 首跑再现已知 macOS 假 flake「failed command 无输出」，同种子 `0x71d22ce` 手动复跑 96/96 全过）+ `zweq-cloud` build/test + e2e 两套件 15/15 + 停机泄漏严格门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zent **v0.74.2 → v0.78.0**、zwechat **v0.4.5 → v0.5.1**（清 `.zig-cache` 重建，零业务代码改动编译通过）。逐项核对结论：
  - **zent v0.76 按选项收窄 translate-c 驱动绑定（采用）**：新增 `sqlite`/`pg`/`mysql` 构建选项（默认"头文件在就全翻译"，每个驱动冷缓存 ~30s/~590MB）。两个 build.zig 把我们的驱动面传给 zent：主站 `-Ddb` 解析结果直挂（**postgres 的选项名是 `pg`**，照抄 changelog 示例的 `postgres` 会编译报错）；`zweq-cloud` 显式 `sqlite+pg`、`mysql=false`。从此不链接的驱动连翻译都不做。
  - **zent v0.78 BREAKING 均未命中**：① 七个单值聚合（`Sum`/`Avg`/`Max`/`Min`/`SumOrZero`/`AggregateOne`/`AggregateText`）对带 `GROUP BY` 的查询改报 `error.GroupByNotSupported`——本仓库仅两处聚合（`ai/persistence.zig` 的 `quotaForUser` ×2 `SumOrZero`、`shop/trade_store.zig` 的 `sumPaidAmount` `AggregateText`），**均纯 `Where` 过滤、无分组**，语义不变；② `SaveOne`/`ExecOne`/`ForceExecOne` 无计数时由 `NotFound` 改报 `RowsAffectedUnknown`——全仓零这三个 API 的调用。免费收益顺带认领：分组 `Count()` 改答组数、8+3 处 OOM 路径泄漏修复、junction 表名撞实体名 fail-closed、grouped 聚合误答第一组这类"答错数据"修复。`zent.runtime.log.setSink`（v0.77）与 `AllOwned()`（v0.78）新能力可用，本轮未采用。
  - **zwechat v0.5.0 BREAKING：移除 zhttp 依赖，mTLS 改 `-Dmtls` 可选（默认关）**。我们仍提供支付 v2 退款/转账管理端点（配了 `cert_p12` 的商户走 mTLS），故两个 build.zig 显式传 `.mtls = true` 保持行为——v0.5 的实现是**运行时 `std.DynLib` dlopen OpenSSL**（可用 `ZWECHAT_SSL_LIB`/`ZWECHAT_CRYPTO_LIB` 指绝对路径），构建期零头文件、零 linkSystemLibrary，成本仅模块 `link_libc`（本就已开）；若用默认 `-Dmtls=false`，v2 端点会在运行时返回 `MtlsNotEnabled`——不能静默接受。`otool -L` 实证：产物仍只链 `libpq`+`libsqlite3`，无 `libssl/libcrypto`（按需 dlopen）。**上一批登记的 alpine 构建告警（zwechat openssl 探测回退 `-I/usr/include` 与 pg `-isystem` 嵌套）随 zhttp 移除自然消失**，登记关闭。
  - **zwechat 免费收益认领**：`util/uri.queryEscape` 堆越界修复（fuzz 发现的内存安全缺陷，影响所有 query 转义出口）、PKCS#12 PBKDF2 迭代上限（DoS 面，v2 mTLS 解析商户证书走这条）、cache TTL 改 `Clock.boot`（合盖休眠后不再用过期 access_token——我们的 `Memory` token 缓存正中此场景）、响应体默认 16 MiB 上限（`ResponseTooLarge`；素材同步是 JSON 列表、媒体下载走自带 100 MiB 限额的专用路径，均无行为变化）、重定向改走 std 原生（错误名兼容）。v0.5.1 的 `Memcache.timeout_reader` 类型变化、`SpinMutex`→`std.Io.Mutex` 字段类型变化、`default_io` 私有化均不命中（不触碰对应字段/不用 memcache）。
  - **逐项 grep 零使用确认**：zhttp（src 零 import，仅一处注释提及）、`SaveOne`/`ExecOne`、zent 分组聚合、zwechat memcache/redis。
  - 验证：`zig build`（47s 冷本地缓存）+ 三门禁 + **96/96 测试**（`zig build test` 首跑又出现已知 macOS 假 flake「failed command 无输出」，同种子 `0x432c4fd9` 手动复跑 96/96 全过，非确定性、与升级无关）+ `zweq-cloud` build/test + e2e 两套件 15/15 + 停机泄漏严格门禁 + `otool -L` 驱动面复核。
- 依赖升级（主站 + `zweq-cloud` 同步）：zigmodu **v0.32.0 → v0.33.1**（改回 git tag pin：`?ref=v0.33.1#6fca2d6`，`rm -rf .zig-cache` 重建；`zig build --verbose` 实测 `-Mzigmodu=zig-pkg/zigmodu-0.33.1-<hash>/src/root.zig`，**单仓库自包含构建恢复**，CI/Docker/Linux 裸机部署不再要求兄弟目录）。
  - **v0.33.0**：零代码改动。实质修复是「Linux 上 `close()` 不唤醒 `accept()`」——本仓库只用 `Server`（早有 `shutdown()` 绕法），不涉及。 **上游 `SecurityModule.base64UrlDecode`/`base64Decode` 泄漏已修**（两处 `errdefer`），因此**删除 `scripts/run_e2e.sh` 的豁免**，停机泄漏门禁恢复严格。新增 `zmodu audit` b23 规则与 `check_alloc_owner.py` 镜像规则同构。
  - **v0.33.1**（并发缺陷清账大版本，全部标破坏性：否）：零代码改动。pub API 面逐面 diff（`root`/`Server`/`CrudService`/`Validator`/`Validation`/`sqlx`/`runtime`）纯新增或仅行号移动。免费收益：DLQ SpinLock、注册表 `nodes_lock`+`snapshotNodes`、`Server.stop()` 唤醒式、`DistributedLock` 弱熵修复。**b24 弱熵源规则扫本仓库 `src/` 零命中**（`std.Io.random`/`std.crypto.random` 均无使用），未做镜像（熵源扫描暂无第二收益点）。
  - **path 依赖往返**：v0.33.0 tag 后两个提交未发布时曾短暂切本地 path（`.path = "../../zig_ws/zigmodu"`）；v0.33.1 发布后 tag 已含全部框架代码——本地检出领先的 `+1` 提交（`19ff13a`）只碰 `tools/zmodu` 脚手架 pin、`src/` 与 tag 逐字节一致——遂按部署方案改回 tag pin。Linux 服务器部署的唯一前提是**构建期可访问一次 GitHub**（依赖缓存在 `~/.cache/zig`，之后离线可重建）；更优做法是直接部署 CI 产物（二进制 / 已自包含的 Dockerfile 镜像），服务器根本不构建。
  - **工具坑（下轮升级避坑）**：① `zig fetch --save=zigmodu <git url>` 在已有 `.path` 条目上会把条目改坏成 `.path = "git+https://…"`（URL 写进 path 键、丢 hash）。正解：zon 里手写 `.url`+`.hash` 条目。② **包 hash 随 `ref` 写法而变**：`?ref=v0.33.1`（tag 名）与 `?ref=6fca2d6…`（裸 SHA）即使最终是同一 commit、tar 内容逐字节一致，也算出**不同 hash**（前者把 tag 对象身份计入）。zon 用哪种 ref 就 fetch 哪种拿 hash——混用会在另一种构建机上 `hash mismatch`（本轮 Docker 实测踩中：本地按 SHA 拿 hash、zon 写 tag ref，容器内构建即失败，已修正为 tag-ref hash，两端验证）。
  - 验证：`zig build` + 三门禁（顺带补了两个文件的历史 fmt 欠账）+ **96/96 测试**（`zig build test` 首跑出现一次已知 macOS 假 flake「95 pass 1 fail」，同种子手动复跑与整跑重测均 96/96 通过，非确定性、与本次升级无关）+ `zweq-cloud` build/test + e2e 两套件 + 停机泄漏严格门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zwechat **v0.4.4 → v0.4.5**（清 `.zig-cache` 重建）。这一版几乎逐条落地了上一轮评估里提的 zwechat 缺口（errcode 详情通道、token 失效自愈、pay/v3 商家转账、媒体下载限额与落盘、`initDefaultClient` 严格模式、API 面快照门禁、`UPGRADING.md`/`OPEN_ITEMS.md`、Redis 连接池、JSON/query 转义收敛、live-probe）。适配结论：
  - **转账端点从"已停用接口"改到新版**：我们手写的 `/v3/transfer/batches`（"商家转账到零钱"）对新商户已不再开放，而管理端 `POST pay/transfer/v3` **是接了线的**——等于这个端点指向停用的 API。现改用 `zwechat.pay.v3.TransferV3`（`/v3/fund-app/mch-transfer/transfer-bills`）。顺带补齐新版语义：① 入参与响应改为"一笔一单"（`out_bill_no`，旧字段名 `out_batch_no` 仍接受）；② 新版要求 `transfer_scene_id` 与场景报备信息（默认以 `remark` 作为"活动名称"报备，可用 `scene_info_*` 覆盖）；③ **HTTP 200 只代表受理**，接口现在把 `state`/`transfer_bill_no`/`package_info` 回给调用方（`WAIT_USER_CONFIRM` 时收款人需在微信确认，`package_info` 供小程序拉起收款页）；④ 上游把"入参不合法"与"接口报错"分开，我们新增 `error.InvalidPayArg` 映射，不再把参数问题报成"转账失败"。
  - **接入 errcode 详情日志**：新增 `src/services/wechat_log.zig`（`beginCall()` / `logApiError()` / `logErrcode()`），在 menu/material/message/member 四个微信服务层的 26 个失败点落地——此前所有失败都塌成"微信接口调用失败"，40001/45009/40003/48001 无从区分。`beginCall()` 是必需的：`lastErrorDetail()` 只反映本线程最近一次失败且成功调用不清槽，不先清就会把**上一次调用的 errcode 挂到当前 label 上**（比没日志更糟）；我们自己解析 errcode 的路径（上游不写详情槽）改用 `logErrcode()` 直打真实值。
  - **修掉两个被这次扫描翻出来的真 bug（同一类）**：`std.json` 默认 `ignore_unknown_fields = false`，而微信响应永远带 `errmsg`/额外字段——① `message.sendBroadcastText` 的结构只有 `{errcode, msg_id}`，**每次群发都落进解码 catch**（群发功能实际不可用）；② `member.listWxTags` 的 tag 对象不认识微信返回的 `count`，**标签列表实际不可用**。四处解析**外部响应**的站点统一改为宽容模式（并给 tag 补上 `count`）；解析我们自己的请求体仍保持严格。
  - **报给上游的覆盖缺口**（不阻塞我们）：`lastErrorDetail()` 只覆盖走 `parseCommonError`/`handleFileResponse` 的路径；`credential.DefaultAccessToken.getAccessToken`、`miniprogram.Auth.code2Session`、`material` 的 errcode 自判都是自己 `parseFromSlice` 后直接抛 `ApiError`，**不写详情槽**——这些点我们只能记到"无 errcode 详情"（`beginCall()` 至少保证了不会谎报）。
  - 不涉及我们：`initDefaultClient` 严格模式（我们所有调用点传的是同一个进程 gpa，构造上即满足）、媒体下载限额（不用 `getMedia`）、`cache/redis` 连接池（不用它的 redis）。
  - 验证：`zig build` + 三门禁 + **96/96 测试** + `zweq-cloud` build/test + e2e 两套件 + 停机泄漏门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zent **v0.72.0 → v0.74.2**（清 `.zig-cache` 重建）。这一版正好落地了上一轮评估里提的三条，且**两条直接命中我们**：
  - **BREAKING `CrudService.get` → `getOwned`**（0.73.0）：owned copy 归**调用方** allocator，而 `deinitRow` 用 client 的——同一个 `Entity` 类型、只有调用点知道哪个对，配错就是非法释放。上游把归属写进了名字，并给出正确释放 `EntityClient.deinitRowWith(allocator, &e)`。本仓库不用 `CrudService`（零调用），**但把这条契约固化进了自己的 lint**：`scripts/check_alloc_owner.py` 新增镜像规则——`deinitRow/deinitRows` 的对象若来自 `getOwned`/`ownedCopy` 即失败（合成用例已验证能抓、当前树 0 处）。
  - **`Sum`/`Avg` 空集改报 `error.EmptyAggregate`**（0.73.0，此前是 `TypeMismatch`——"没有数据"被报成类型错误）。**命中我们的真实缺陷**：`ai/persistence.zig` 的 `quotaForUser` 用 `q.Sum("tokens_in"/"tokens_out")`，窗口内零行（新用户、跨天后的第一次调用）必然报错。已改用 `SumOrZero` 并**补上原先缺失的测试**（空窗口 → 0/0、按 `created_at` 过滤的窗口求和、全量求和）。该函数目前尚无调用方（token 额度口径未接线，线上跑的是 `daily_run_limit` 计数），所以线上没有事故——但它是"一接线就炸"的状态，现在修好并钉住了。
  - **已有表上的列级 `UNIQUE` 开始被强制**（0.73.0）：此前声明内联在 `CREATE TABLE` 里、`ALTER TABLE ADD COLUMN` 带不上，于是老表永远没有该约束——而**没有唯一索引时 `SaveOrUpdateOn` 生成的语句会被直接拒绝**（"ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"），即"schema 说有、运行期每个 upsert 都失败"。现在迁移会补一个 `CREATE UNIQUE INDEX`（方言中立、不重建表），**若历史数据已违约则在 `CREATE UNIQUE INDEX` 上响亮失败并回滚**。本仓库在上上轮正是靠人肉 DDL 才补上这 7 个唯一索引（`zweq.db.bak-unique-index` 就是现场），现在迁移自己会做了。**运维提示**：升级到本版后首次启动会对老库补建唯一索引，历史数据有重复的库会启动失败（这是上游刻意的 fail-closed），需先清重。
  - 其余 0.74.x：EntQL 现在拒绝"当前实体没有的字段"（此前会绑到 junction 上静默答错）、`examples/migrate` 接受 libpq keyword 形式 conninfo、`migrations/` 改为可移植 DDL——都不影响本仓库（不用 EntQL/示例）。
  - 验证：`zig build` + 三门禁 + **96/96 测试** + `zweq-cloud` build/test + e2e 两套件 + 停机泄漏门禁 + **老库升级路径实测**（复制 `zweq.db` 启动 → 6s 就绪、7 个唯一索引完好、`panic 0`/`leaked 0`）。
- 依赖升级（主站 + `zweq-cloud` 同步）：zwechat **v0.4.3 → v0.4.4**（清 `.zig-cache` 重建）。核对结论：
  - **编译级一处**：`officialaccount.menu.Button` 的字段由 `type_` 改名为 `@"type"`（Zig 关键字转义）——**上游 Changed 清单里没写这条**，靠编译才发现；改我们 1 处构造点 + 2 处测试断言。
  - **顺带删掉两处已过期的说法**：① 字段改名后 `std.json` 反而能正确解析 JSON 的 `"type"` 键（`@"type"` 的名字就是 `type`），加上全仓解析开了 `ignore_unknown_fields`，`menu.getMenu` 已可用；我们"透传原始 JSON"的理由从"绕反射丢失 bug"改成"前端直接渲染微信原生结构"这个刻意选择（注释已改，接口形状不动）。② `material.addNews` 返回类型从 `![]const u8` 改为 `![]u8`，`@constCast` 多余，已去掉。
  - **语义级（收紧，对我们无行为变化）**：`pay/v3/signer` 新增 `MissingPrivateKey` 守卫——0.4.3 会拿**空私钥**签字，0.4.4 直接报错。生产路径本就有 `InvalidPayConfig` 前置守卫（缺私钥在调用方拦住），所以线上行为不变；但**暴露了一条弱测试**：`v3 refund 报文构造` 原来传空私钥、只断言 header 形状，现在改用真测试私钥断言真签名（并把重复的密钥块收敛到文件作用域一处）。
  - **与我们无关的改动**（逐项 grep 零使用）：`miniprogram/content.checkText` 新增必填参数、`user.OpenidList.openids` → `.data.openid`、`middleware.handleServerMessage` 新增 `expected_app_id`、删除 `work/material.getMediaList`、`openplatform` 授权链路重构；`customerservice.listAccounts` 的返回类型变化不影响我们（同名 `listAccounts` 是本仓库自己的方法）；`util.rsa.rsaSign`/`rsaVerify` 本体未变（本次修的是上游自家 pay v3 签名器/校验器，我们只用原语自行构造与校验签名）。
  - **免费收益**：`util_http.getFollowRedirect`（官方素材下载跟随 302）、`credential` 四个获取器改 singleflight + `cache` 单连接加锁（并发凭据/缓存安全）、openplatform token 链路加锁与 UAF/泄漏修复、全仓 41 个 JSON 解析站点统一 `ignore_unknown_fields`（微信返回的字段名笔误如 `vaild`/`exteranalopenid` 不再炸解析）。
  - API 面差异是**逐个人工比对**过的（对我们消费的 `util/http`、`officialaccount/{menu,material,message}` 抽 `pub fn`/字段差异），不只依赖 changelog。
  - 验证：`zig build` + `lint-size`/`lint-alloc`/`lint-fmt` + **96/96 测试** + `zweq-cloud` build/test + e2e 两套件 + 停机泄漏门禁。
- 依赖升级（主站 + `zweq-cloud` 同步）：zent **v0.67.0 → v0.72.0**、zigmodu **v0.15.47 → v0.32.0**（跨 17 个 minor）。改 pin 后清 `.zig-cache` 重建，**零代码改动**编译通过。逐项核对结论：
  - **编译级破坏均未命中**（逐项 grep 核实零使用）：zigmodu `http.Method.fromString` 改返回 `?Method`、WS 路由编译期强制 `.meta.auth = .public`、`PasswordEncoder`/`ApiKeyGenerator`/`kit.random` 增加 `io` 形参（CSPRNG 迁移）、`Runtime.cancelTimer` 拆成 `requestCancelTimer`/`cancelTimerSync`、脚手架生成物相关；本仓库 `AppSecurity.init` 本就传 `io`。
  - **zent v0.70 BREAKING「SQLite 强制外键」（`PRAGMA foreign_keys = ON`）不适用**：本仓库 schema 的 model 一律无边声明（`addEdgeFields`/`edges` 为零）→ 迁移不生成外键约束 → 结构性空转；96/96（SQLite 驱动）实证。
  - **命中的语义级加固（免费收益）**：HTTP 解析硬化（畸形头整条 400、未知方法 501、`Transfer-Encoding` 400——堵 CL/TE 走私面；`fromString` 不再折成 `.GET`）；`permissionGateWith` 的配置从函数级全局改每调用一份 + **空 catalog 由放行改 fail-closed**（本仓库单 server、catalog 在开始 accept 前就绪，无行为回退，纯加固）；CSPRNG 从「毫秒+常量+栈地址」换成 `std.Io.randomSecure`（失败即 `error.EntropyUnavailable`、无回落）——JWT/盐/uuid 的熵问题就此修复；legacy `jwtAuth` 的 secret 被第二个 server 覆盖的竞态修复。
  - **不命中的语义级变更**：数据域 `.dept_custom` 空/坏 `dept_ids` fail-closed（无 dept 体系）；sqlx `tenantClause` 括号修复（走 zent，不用 sqlx ORM）；AI business skills `db.query` 租户边界（未注册该 catalog）；Runtime 监督树/时间轮/池化 worker/Raft（未使用）。
  - **上游泄漏仍未修（豁免保留）**：zigmodu v0.32.0 的 `SecurityModule.base64UrlDecode`/`base64Decode` 仍是无 `errdefer` 的 `try decoder.decode(...)`——无效 token 验签失败仍漏一小块。`scripts/run_e2e.sh` 的豁免继续生效，两行 `errdefer` 的补丁继续待上游发布。
  - 验证：`zig build` + `lint-size`/`lint-alloc`/`lint-fmt` 三门禁 + **96/96 测试** + `zweq-cloud` build/test + e2e 两套件 + 停机泄漏门禁 + 运行时抽查（24 项指标在册、上传守卫拒绝伪装 PNG、停机 `leaked 0`/`panic 0`）。
- **参数命名对齐上游约定**：11 处 `ctx.param(` → `ctx.pathParam(`（zigmodu v0.15.38 起的显式别名，上游 DO/DON'T"取参数用对名字"，消除"路径参数 vs 任意参数"误读），覆盖 payment/module/message/cloud/mail_template/setting 六个 api.zig。
- **文件体积门禁上限 1200 → 1800 行**（`scripts/check_file_size.sh`，仍可用 `ZWEQ_MAX_FILE_LINES` 覆盖；CI step 名同步）。改动起因：上一条的吞错留痕让 `shop/service.zig` 从 1175 涨到 1198 行，直接顶住旧上限。**1800 是天花板不是目标**——`shop/service.zig` 仍建议按子域拆分（该文件当前 1198 行，且以下单/支付/退款/取消金路径为主，拆分须只搬运正文、语义零变更）。
- 依赖升级（主站 + `zweq-cloud` 同步）：zent **v0.45.0 → v0.67.0**（22 个 minor）、zigmodu **v0.15.44 → v0.15.47**。按上游 `CHANGELOG` / zent `docs/UPGRADING.md` 逐条核对后的结论：
  - **采用**：`RateLimiterRegistry.initWithCapacity(…, max_keys)`——registry 的键来自 IP / openid（攻击者可轮换），默认 `max_keys = 0` 即无上限，是框架文档点名的内存增长向量；三个 registry（auth/shop/fan）统一上限 `registry_max_keys = 8192`，并在主循环里每 5 分钟 `retain` 回收空闲桶（正常流量下桶数远低于上界，不被 LRU 淘汰掉活跃客户端）。另接入 `http.UploadGuard`（见 `### Fixed`）。
  - **编译级 BREAKING 不适用**：zent v0.54 `CrudService.create(entity, tenant_id)` 双参（本仓库不用 `CrudService`）；v0.59/0.56 `driver.Error` 新增 `ParamCountMismatch`/`PoolWaitTimeout`（无对驱动错误集的穷尽 `switch`）；v0.67 `SaveError` 新增 `MissingLastInsertId`（同上；且本仓库 `Save` 目标均为自增主键）。
  - **语义级变更不适用**：v0.66 空 `dept_ids` 由「放行全表」改为拒绝（本仓库无数据域/dept 过滤）；无谓词 `BulkDelete` 报 `error.NoPredicate`（无 `BulkDelete` 调用）；v0.67 软删重复删除返回 0 → `ExecOne` 抛 `NotFound`（schema 里**没有** `deleted_at`，全仓零软删）；MySQL 专属三项（`String`/`Enum` 落 `VARCHAR(255)`、批量改逐行、`rows_affected` sentinel）不涉及本仓库驱动（SQLite 开发 / PostgreSQL 生产）。
  - **升级陷阱（zigmodu 0.15.47 自己记的两条，均已核对）**：① **不要用 `deinitRow` 释放 arena 拥有的 owned copy**——它的分配器是 client 的（进程 gpa），而 owned copy 的字符串归调用方 arena，混用即 `free of invalid memory` 打死进程；本仓库 177 处 `deinitRow/deinitRows` 已逐点审计，全部作用于驱动扫描出的实体（`Save()` / `Query().First()` / `Query().All()` / `crud.first`），无一处是 owned copy。② **改 pin 后必须 `rm -rf .zig-cache`**，否则增量缓存会沿用旧 fetch 依赖，"编译通过"是假的（本轮已按此清缓存重建，拿到了真实的编译结果）。
  - **免费收益**（驱动/框架侧修复，无需改代码）：SQLite 不再把失败查询当短页/空页、不再上报"上一条语句"的行数（`ai_run` 类单行读取曾可能因此报 `NotFound`）；PostgreSQL 命令标签解析不再 `catch 0`；`RateLimiter`/`RateLimiterRegistry`/`SlidingWindowRateLimiter` 补同步且 Registry 改存指针（原来按值存，`getOrCreate` 返回的指针指向会失效的副本）；`AccessLog`/`HttpMetrics` 热路径自旋锁改为会 `yield`；Redis 客户端四件套（`pool_size <= 1` 的单流分支不加锁等）；`ProblemDetails.toJson` 补 JSON 转义。
  - **登记待决（未动手）**：老库上有 18 列 nullability drift（`ai_run.tool_errors`/`model`/`steps`/`tool_calls`、`ai_message.reasoning_content`、`coupon.status`、`fan.points`、`file.group_id`、`market_package.checksum`、`material_news.media_id` 等）——库里可空、schema 声明 NOT NULL，是历史上 `ALTER TABLE ADD COLUMN` 的产物。方向是"库比 schema 宽松"（**不**破坏读，zent 的 `read_breaking_only` 门禁刻意不拦），只在 debug 级提示；收敛需要显式开启 `migrateSchema` 的 nullability converge（会对表做 ALTER），本轮未开，留给单独决定（重建开发库亦可消除）。
- 依赖升级（主站 + `zweq-cloud` 同步）：zent **v0.37.0 → v0.45.0**、zigmodu **v0.15.37 → v0.15.44**（8 + 7 个 minor）。逐条核对上游 `CHANGELOG` 与 zent `docs/UPGRADING.md` 后的结论：
  - **采用（唯一需要动代码的一条）**：zent v0.40 的一行式实体释放。177 处手写 `zent.codegen.deinitEntity(infos, XInfo, &e, self.allocator)` 与 27 处 `defer { for (rows.items) |*e| deinitEntity(…); rows.deinit(); }` 释放循环迁移为 `client.<实体>.deinitRow(&e)` / `deinitRows(&rows)`（33 个文件）。调用方不再需要持有 graph 与分配器；`deinitRows` 会重置列表使其可复用（等价于原 `rows.deinit()`），反复调用是 no-op 而非二次释放。
  - **BREAKING 不适用**：zent v0.38 把 `queryTargets`/`queryTargetsByValue` 改为 fail-closed（旧「仅软删」语义改名为 `*Unscoped`）——本仓库无 `queryTargets`/`QueryEdge` 用法，无迁移步骤。
  - **不适用**：zent v0.39 `zent.scope`（裸 SQL 的读契约）——本仓库没有命中 graph 表的手写 SQL（仅谓词内 `sql.RawArgs` 参数化，走 Builder 路径自带契约；`cloud` 的动态表预览查的是运行时创建的表，不在 graph 内）；v0.43 不再接受 `[N]u8` 数组值（`setFieldValue`）——编译通过即证明无此用法；v0.39 `<col>Contains` 命名澄清——本仓库搜索一直用 `ContainsEscaped`，`Contains`（等值匹配、不补 `%`）从未被误用；v0.45 空更新报 `error.NoFieldsToUpdate`、纯边写补主键自赋值——本仓库无纯边写更新路径。
  - **新能力已可用、本轮未采用（留作单独变更）**：zigmodu v0.15.41 `Auth.optional`（公开但可个性化路由）、v0.15.38 `ctx.multipart` / `ctx.bindForm` / `ctx.bindQuery` / 静态文件服务、v0.15.39 `Params` 多值容器（`get()` 仍返回最后一次出现的值，故无破坏）。fan C 端路由目前是 catalog `.public` + handler 内 `requireFanOpenid`（fan token 与后台 token 同密钥、角色/受众不同），改 `.optional` 只省一次重复验签却要重审 platform gate 与 `tokenVersionGuard` 交互，收益不匹配风险，故不动。
- 依赖升级（零 breaking，代码零改动即适配）：zent **v0.34.0 → v0.37.0**（主站 + `zweq-cloud`；`zig build` / `zig build test` 93/93 全绿，真实库启动迁移通过）。新能力可用：连接池 `max_wait_ms` 真正阻塞等待（默认 0 = 旧语义）、嵌套预加载每层一次查询（消 N+1）、`StorageKey` 字段↔列名映射、`BulkInsert` 按参数上限分片、`In/NotIn/IsNull/HasPrefix/ContainsFold` 等类型化谓词、边写入（`AddEdgeIDs`/`SetEdgeIDs`/`ClearEdge`）、outbox 认领式派发、迁移默认加锁 + checksum 校验。本项目未用 outbox/BulkInsert/预加载，`UPGRADING` §10 的 outbox 迁移与 `createAllTables` 签名变更均不适用。
- 依赖升级（零 breaking，代码零改动即适配）：zigmodu **v0.15.35 → v0.15.37**（`zweq-cloud` 同步从 v0.15.24 直升）。
- RBAC 闭环：`RolePermission` 关联表 + `collectPermissionCodes`（user.admin / 角色 code / module:action）；`GET /auth/me` 返回 `permissions`；角色权限 API `GET|POST|DELETE /roles/{id}/permissions`；前端菜单按 `canAccessAdmin` 隐藏。
- 小程序商城 C 端登录：`wx.login` → `miniprogram/login`（公开）→ `shop/auth/login` fan JWT；`shopSession` store 替换 `DEMO_OPENID`。
- CI 增加 `zig build lint-size` 门禁。
- 权限目录种子（`permission_catalog` + `permission_seed`）：启动时写入全部 `module:action` 权限码，founder/admin 全绑，operator 默认只读。
- 管理后台「角色权限」页（`/roles`）：角色 CRUD、权限码管理、角色授权勾选、用户绑角色。
- 侧栏菜单细粒度映射（`navItems.ts` + `PermissionGate`）；后端路由 `admin` 改为 `{module}:read|write`。

### Changed
- 依赖升级（零 breaking，代码零改动即适配）：zent **v0.33.0 → v0.34.0**（主站 + `zweq-cloud`；清 `.zig-cache` 后 `zig build` / `zig build test` 全绿）。新能力可用：`sql.RawArgs`、聚合助手（`SumOrZero`/`Aggregate*`）、`SaveOrUpdateOnWith`、`ForUpdateWith`、`sql_scan.queryAll`/`queryOne`。
- 依赖升级（零 breaking，代码零改动即适配）：zigmodu **v0.15.34 → v0.15.35**、zent **v0.32.2 → v0.33.0**（`zig build` + `zig build test` 全绿）。
- 巨型文件按子域拆分（正文逐字搬运，语义零变更；全部源文件 ≤ 1200 行，新增 `zig build lint-size` 门禁）：
  - `src/tests.zig`（3962 行）→ `src/tests/` 共 10 个按域测试文件 + `common.zig` 夹具，原文件保留为聚合入口。
  - `shop/persistence.zig`（1839 行）→ 门面（91 行，`persist.XxxRow` / `ShopStore.init` 引用面不变；方法调用迁移为 `store.<catalog|trade|marketing|content>.xxx`）+ `rows.zig` + 4 个子域 store。
  - `shop/api.zig`（1922 行）→ 门面（~360 行：路由表/注册函数/init）+ `handlers/{catalog,trade,marketing,content}.zig` 混入式处理器 + `api_dto.zig` 统一 DTO 与映射器。适配本版 Zig 已移除的 `usingnamespace`：跨片段宿主成员经 `ApiT.` 前缀调用。
- **修正**：上一条依赖升级在本机 `.zig-cache` 陈旧解析图下验证过一次，实际编译的仍是旧版。已清除缓存重验：构建与全量测试均在 **zent v0.32.1 + zigmodu v0.15.32** 真实通过（92/92），升级结论不变、代码无需改动。
- 依赖升级（纯新增/修复版本，零 breaking）：zigmodu **v0.15.22 → v0.15.32**、zent **v0.29.4 → v0.32.1**。获得：zent Interceptor 运行时查询拦截、`field.Decimal` 精确金额列、`SaveOrUpdateOn`/`SaveIgnore` upsert、PreparedCache 字节级 key 防碰撞；zigmodu 读写分离（`Client.withReplica`）、HTTP header 上限（431 DoS 防护）、OTLP/Vault HTTPS。
- 依赖切换到 git tag 引用并升级：zigmodu **v0.15.22**、zent **v0.29.4**、zwechat **v0.2.0**（内部 httpz → zhttp v0.6.0）。
- 适配 zent v0.29.4 破坏性变更：`Query.Sum` 返回类型 `i64 → f64`（AI 配额聚合改用 `@intFromFloat`）。
- 适配 zigmodu v0.15.22 线程安全修复：`/metrics` 渲染改用 `HttpMetricsCollector.snapshot()`（原先裸读共享字段存在数据竞争）。

## [0.1.0] - 2026-08-06

### Added — 微信运营全链路
- **账号管理** `account`：公众号 / 小程序 CRUD + `account_wechat` 微信配置（secret 脱敏返回）。
- **模块注册表** `module`：模块 CRUD + 账号↔模块绑定。
- **RBAC** `permission`：role / permission / user_role。
- **粉丝** `member`：fan（openid / unionid）同步与管理。
- **关键词回复** `rule`：rule / rule_keyword / rule_reply。
- **素材** `material`：图文 news + 图片 / 语音 / 视频素材。
- **消息引擎** `message`：`GET/POST /wx/{token}` 签名校验、echostr 握手、明文 / AES 解析、关键词匹配、文本 / 图文被动回复（安全模式 AES 加密回包）。
- **支付** `payment`：充值订单 / 钱包 / 提现，channel=mock。
- **站点设置** `setting`：KV 存储，管理员写入。
- **云服务** `cloud`：授权码 + 应用市场。
- **H5 BFF** `app_bff`：移动端薄层。
- 管理后台（SolidJS）页面：账号、自动回复、粉丝、充值支付、模块、云服务、消息日志、素材库。

### Added — 平台底座（复用 zenaipa 并加固）
- 认证：注册 / 登录 / 邮箱验证 / 忘记重置，JWT + Argon2id，登录限流与防枚举。
- 后台任务队列（持久化 + 重试退避）、文件上传、通知收件箱、可配置邮件模板。
- 审计日志（actor / action / keyword 筛选）、概览面板、健康检查、Prometheus `/metrics`、`x-trace-id`。
- 多租户：物理 `app_id` 行隔离，租户随 JWT `aud` claim，跨租户管理筛选。

### Added — 生产化
- **微信支付 v3**：`prepay` 真实 JSAPI 统一下单（`zwechat.pay.v3.signer`），`POST /api/v1/pay/v3/notify` 平台证书验签 + AES-256-GCM 解密 + 幂等入账。
- **AI Provider**：OpenAI 兼容端点，密钥 AES-GCM 加密落库（`ZWEQ_AI_KEY_SECRET`）。
- **静态托管**：单二进制服务 SolidJS SPA（`ZWEQ_STATIC_DIR`）。
- **Docker**：Dockerfile + docker-compose（postgres + zweq）。
- **Postgres 模式**：`ZWEQ_DB_DRIVER=postgres` + `ZWEQ_PG_CONNINFO`，启动自动迁移。

### Security
- JWT 凭据版本化：改密吊销旧令牌。
- 生产 fail-closed：显式 `ZWEQ_JWT_SECRET` / `ZWEQ_AI_KEY_SECRET` 必需。
- 审计日志保留期清理（`ZWEQ_AUDIT_RETENTION_DAYS`）。
- `/metrics` IP 白名单（`ZWEQ_METRICS_ALLOW_IPS`）。
- 优雅停机（SIGINT / SIGTERM）。

[0.1.0]: https://github.com/chy3xyz/zweq/releases/tag/v0.1.0
