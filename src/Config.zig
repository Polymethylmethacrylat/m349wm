const std = @import("std");
const c = @import("c.zig");
const wm = @import("wm_actions.zig");
const XClient = @import("XClient.zig");

const Self = @This();

/// treat active caps as a pressed down shift
caps_eqls_shift: bool = true,
/// explicitly state numlock modifier as its own modifier
num_lock_explicit: bool = false,
key_mappings: []const KeyMap,

pub const KeyMap = struct {
    key: c.xcb_keysym_t,
    mod: c.xcb_mod_mask_t,
    key_action: KeyAction,
    action: wm.Action,
};

pub const Args = union {
    v: void,
    b: bool,
    i: i64,
    u: u64,
    f: f64,
    o: struct{t: type, ptr: *anyopaque},
};

pub const KeyAction = enum {
    press,
    release,
};
