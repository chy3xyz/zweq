//! Shared zent schema graph for the whole application.
//!
//! Every module registers its schemas here so a single `StoreEnv` can
//! migrate the full schema and expose one type-safe client to all stores
//! (zigmodu + zent best practice: one client, schema-as-code in one place).

const zent = @import("zent");

const user_model = @import("modules/user/model.zig");
const task_model = @import("modules/task/model.zig");
const file_model = @import("modules/file/model.zig");
const notify_model = @import("modules/notify/model.zig");
const tenant_model = @import("modules/tenant/model.zig");
const audit_model = @import("modules/audit/model.zig");
const mail_template_model = @import("modules/mail_template/model.zig");
const ai_model = @import("modules/ai/model.zig");
const account_model = @import("modules/account/model.zig");
const permission_model = @import("modules/permission/model.zig");
const setting_model = @import("modules/setting/model.zig");
const rule_model = @import("modules/rule/model.zig");
const member_model = @import("modules/member/model.zig");
const message_model = @import("modules/message/model.zig");
const app_module_model = @import("modules/module/model.zig");
const payment_model = @import("modules/payment/model.zig");
const cloud_model = @import("modules/cloud/model.zig");
const material_model = @import("modules/material/model.zig");

// zent's `buildGraph` comptime edge-resolution has a per-call branch quota;
// keeping the graph small avoids it, so the app schema and each domain
// cluster are built as small graphs and their types merged.
const graph = zent.codegen.graph.buildGraph(&.{
    tenant_model.Tenant,
    user_model.User,
    user_model.PasswordToken,
    user_model.EmailVerification,
    task_model.Task,
    file_model.File,
    notify_model.Notification,
    audit_model.AuditLog,
});
const template_graph = zent.codegen.graph.buildGraph(&.{mail_template_model.EmailTemplate});
const ai_graph = zent.codegen.graph.buildGraph(&.{
    ai_model.AiProvider,
    ai_model.AiSession,
    ai_model.AiMessage,
    ai_model.AiApproval,
    ai_model.AiRun,
});
const account_graph = zent.codegen.graph.buildGraph(&.{
    account_model.Account,
    account_model.AccountWechat,
});
const permission_graph = zent.codegen.graph.buildGraph(&.{
    permission_model.Role,
    permission_model.Permission,
    permission_model.UserRole,
});
const setting_graph = zent.codegen.graph.buildGraph(&.{setting_model.SiteSetting});
const rule_graph = zent.codegen.graph.buildGraph(&.{
    rule_model.Rule,
    rule_model.RuleKeyword,
    rule_model.RuleReply,
});
const member_graph = zent.codegen.graph.buildGraph(&.{member_model.Fan});
const message_graph = zent.codegen.graph.buildGraph(&.{message_model.MessageLog});
const app_module_graph = zent.codegen.graph.buildGraph(&.{
    app_module_model.AppModule,
    app_module_model.ModuleBinding,
});
const payment_graph = zent.codegen.graph.buildGraph(&.{
    payment_model.Wallet,
    payment_model.RechargeOrder,
    payment_model.Withdraw,
});
const cloud_graph = zent.codegen.graph.buildGraph(&.{
    cloud_model.License,
    cloud_model.MarketPackage,
});
const material_graph = zent.codegen.graph.buildGraph(&.{
    material_model.MaterialNews,
    material_model.MaterialFile,
});

pub const infos = graph.types ++
    template_graph.types ++
    ai_graph.types ++
    account_graph.types ++
    permission_graph.types ++
    setting_graph.types ++
    rule_graph.types ++
    member_graph.types ++
    message_graph.types ++
    app_module_graph.types ++
    payment_graph.types ++
    cloud_graph.types ++
    material_graph.types;
pub const Client = zent.codegen.client.Client(infos);
