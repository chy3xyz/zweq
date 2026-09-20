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

### Changed
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
