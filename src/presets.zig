const c = @import("c.zig");
const root = @import("root");
const wm = @import("wm.zig");
const actions = @import("wm.zig").actions;
const Config = @import("wm.zig").Config;

pub const default: Config = .{
    .key_mappings = &[_]wm.KeyMap{
        .{
            .key = c.XK_q,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .releasing,
            .action = blk: {
                var exit = actions.Exit{};
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_h,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = blk: {
                var exit = actions.Move{ .direction = .west };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_j,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = blk: {
                var exit = actions.Move{ .direction = .south };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_k,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = blk: {
                var exit = actions.Move{ .direction = .north };
                break :blk exit.action();
            },
        },
        .{
            .key = c.XK_l,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = blk: {
                var exit = actions.Move{ .direction = .east };
                break :blk exit.action();
            },
        },
    },
};

