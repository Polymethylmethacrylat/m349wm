const std = @import("std");
const log = std.log.scoped(.m349wm);
const assert = std.debug.assert;

const c = @import("c.zig");

pub fn main() !void {
    var screenp: c_int = undefined;
    const con = c.xcb_connect(null, &screenp) orelse unreachable;
    defer c.xcb_disconnect(con);
    const con_err = c.xcb_connection_has_error(con);
    log.debug("TODO: improve error handling on connection initialization", .{});
    if (con_err > 0) return error.ConnectionError;

    const screen: c.xcb_screen_t = blk: {
        const setup = c.xcb_get_setup(con);
        assert(c.xcb_setup_roots_length(setup) > screenp);
        var roots_iter = c.xcb_setup_roots_iterator(setup);
        for (0..@intCast(screenp)) |_| c.xcb_screen_next(&roots_iter);
        break :blk roots_iter.data.*;
    };
    _ = screen;
}
