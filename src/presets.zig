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
            .action = (actions.Exit{}).action(),
        },
        .{
            .key = c.XK_h,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = (actions.Move{ .direction = .west }).action(),
        },
        .{
            .key = c.XK_j,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = (actions.Move{ .direction = .south }).action(),
        },
        .{
            .key = c.XK_k,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = (actions.Move{ .direction = .north }).action(),
        },
        .{
            .key = c.XK_l,
            .mod = c.XCB_MOD_MASK_4,
            .key_state = .pressed,
            .action = (actions.Move{ .direction = .east }).action(),
        },
    },
};

