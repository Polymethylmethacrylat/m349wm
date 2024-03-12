const std = @import("std");
const c = @import("../c.zig");
const wm = @import("../wm.zig");
const root = @import("root");
const KeyMap = wm.KeyMap;

const Self = @This();

/// treat active caps as a pressed down shift
caps_eqls_shift: bool = true,
/// explicitly state numlock modifier as its own modifier
num_lock_explicit: bool = false,
key_mappings: []const KeyMap,
