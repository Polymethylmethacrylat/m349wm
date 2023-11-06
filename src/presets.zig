const c = @import("c.zig");
const Config = @import("Config.zig");
const wm = @import("m349wm.zig");
const wm_actions = @import("wm_actions.zig");

pub const default: Config = .{
    .key_mappings = &[_]Config.KeyMap{
        .{
            .key = c.XK_q,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .release,
            .action = blk: {
                var exit = wm_actions.Exit{};
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_h,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm_actions.Move{ .direction = .west };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_j,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm_actions.Move{ .direction = .south };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_k,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm_actions.Move{ .direction = .north };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_l,
            .mod = c.XCB_MOD_MASK_4,
            .key_action = .press,
            .action = blk: {
                var exit = wm_actions.Move{ .direction = .east };
                break :blk exit.action();
            },
        },
    },
};

