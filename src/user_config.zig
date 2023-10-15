const c = @import("c.zig");
const Config = @import("Config.zig");

pub const default: Config = .{
    .key_mappings = &[_]Config.KeyMap{
        .{
            .key = c.XK_q,
            .mod = c.XCB_MOD_MASK_4,
            .action = .release,
            .func = haltAndCatchFire,
        },
    },
};

fn haltAndCatchFire() noreturn {
    unreachable;
}
