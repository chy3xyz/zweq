//! Response envelope dialect — pins every request to the RuoYi shape.
//!
//! Without this, `ctx.ok` / `ctx.okValue` / `ctx.paginated` fall back to the
//! ZigModu default envelope, which disagrees with the paged responses that
//! already pass `.ruoyi` explicitly. Setting the dialect globally unifies
//! success, paged, fail and unauth responses so the SolidJS SPA can read a
//! single envelope shape.

const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub fn ruoyiEnvelope() http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                ctx.setEnvelope(http.EnvelopeDialect.ruoyi);
                try next(ctx);
            }
        }.handle,
    };
}