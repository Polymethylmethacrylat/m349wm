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

pub const Client = struct {
    const Self = @This();

    parent: c.xcb_window_t,
    window: c.xcb_window_t,
    x: i16,
    y: i16,
    width: u16,
    height: u16,
    border_width: u16,
    override_redirect: bool,
    mapped: bool,
};

pub const KeyState = enum {
    released,
    pressed,
    releasing,
    pressing,
};

pub const KeyMap = struct {
    key: c.xcb_keysym_t,
    mod: c.xcb_mod_mask_t,
    key_state: KeyState,
    action: Action,
};

