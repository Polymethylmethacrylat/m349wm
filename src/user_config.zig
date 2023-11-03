const c = @import("c.zig");
const Config = @import("Config.zig");
const XClient = @import("XClient.zig");
const wm = @import("wm_actions.zig");

pub const default: Config = .{
    .key_mappings = &[_]Config.KeyMap{
        .{
            .key = c.XK_q,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .release,
            .action = blk: {
                var exit = wm.Exit{};
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_h,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm.Move{ .direction = .west };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_j,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm.Move{ .direction = .south };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_k,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm.Move{ .direction = .north };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_l,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm.Move{ .direction = .east };
                break :blk exit.action();
            },
        },
    },
};

