const std = @import("std");
const c = @import("c.zig");

const Self = @This();

conn: *c.xcb_connection_t,
screen: *c.xcb_screen_t,

pub fn init() !Self {
    var self: Self = undefined;

    // never returns null
    self.conn = c.xcb_connect(null, null).?;
    errdefer c.xcb_disconnect(self.conn);
    if (c.xcb_connection_has_error(self.conn) != 0)
        return error.ConnectionError;

    self.screen = @ptrCast(c.xcb_setup_roots_iterator(c.xcb_get_setup(self.conn)).data);

    return self;
}

pub fn deinit(self: Self) void {
    c.xcb_disconnect(self.conn);
}
