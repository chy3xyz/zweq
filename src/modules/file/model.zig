//! zent schema-as-code — uploaded file metadata.
//!
//! File bytes live on the local disk under the configured upload directory;
//! the `File` row keeps name, size, mime type, storage key and uploader.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const File = Schema("File", .{
    .fields = &.{
        field.String("name"),
        field.String("storage_key"),
        field.String("mime").Default("application/octet-stream"),
        field.Int("size_bytes").Default(0),
        field.Int("uploader_id").Default(0),
        field.Int("tenant_id").Default(1),
        field.Int("group_id").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// Image/category group for the file manager. Mirrors the zmcanyin
/// `xdaofood_upload_group` table: a soft namespace users file uploads into.
pub const UploadGroup = Schema("UploadGroup", .{
    .fields = &.{
        field.String("group_name"),
        field.String("group_type").Default("image"),
        field.Int("sort").Default(0),
        field.Int("tenant_id").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
