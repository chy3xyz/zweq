//! Shared zent schema graph for zweq-cloud（license + market）。

const zent = @import("zent");
const license_model = @import("modules/license/model.zig");
const market_model = @import("modules/market/model.zig");

const license_graph = zent.codegen.graph.buildGraph(&.{license_model.License});
const market_graph = zent.codegen.graph.buildGraph(&.{market_model.MarketPackage});

pub const infos = license_graph.types ++ market_graph.types;
pub const Client = zent.codegen.client.Client(infos);
