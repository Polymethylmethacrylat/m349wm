const std = @import("std");
const c = @import("c.zig");

pub const actions = @import("wm/actions.zig");
pub const Config = @import("wm/Config.zig");

pub const Action = struct {
    const Self = @This();
    ptr: *anyopaque,
    func: *const fn (*anyopaque) anyerror!void,
    pub fn execute(self: Self) !void {
        return self.func(self.ptr);
    }
};

pub const KeyMap = struct {
    key: c.xcb_keysym_t,
    mod: c.xcb_mod_mask_t,
    key_action: KeyAction,
    action: Action,
};

pub const KeyAction = enum {
    press,
    release,
};
