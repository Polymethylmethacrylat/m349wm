const std = @import("std");
const c = @import("c.zig");

const Self = @This();

/// treat active caps as a pressed down shift
caps_eqls_shift: bool = true,
/// explicitly state numlock modifier as its own modifier
num_lock_explicit: bool = false,
key_mappings: []const KeyMap,

pub const KeyMap = struct {
    key: c.xcb_keysym_t,
    mod: c.xcb_mod_mask_t,
    action: KeyAction,
    func: *const fn () anyerror!void,
};

pub const KeyAction = enum {
    press,
    release,
};
