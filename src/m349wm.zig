const std = @import("std");
const log = std.log.scoped(.m349wm);
const assert = std.debug.assert;
const free = std.c.free;

const c = @import("c.zig");

pub fn main() !void {
    var screenp: c_int = undefined;
    const con = c.xcb_connect(null, &screenp) orelse unreachable;
    defer c.xcb_disconnect(con);
    const con_err = c.xcb_connection_has_error(con);
    switch (con_err) {
        0 => {},
        c.XCB_CONN_ERROR => {
            log.err(
                \\xcb connection errors because of socket, pipe and other stream errors. 
            , .{});
            return error.ConnError;
        },
        c.XCB_CONN_CLOSED_PARSE_ERR => {
            log.err(
                \\Connection closed, error during parsing display string. 
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
            return error.ConnClosedParseErr;
        },
        c.XCB_CONN_CLOSED_INVALID_SCREEN => {
            log.err(
                \\Connection closed because the server does not have a screen matching the display.
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
            return error.ConnClosedInvalidScreen;
        },
        else => |errno| {
            log.err("Unknown connection error: {}", .{errno});
            return error.UnknownConnErr;
        },
    }

    const screen: c.xcb_screen_t = blk: {
        // gets desired screen
        const setup = c.xcb_get_setup(con);
        assert(c.xcb_setup_roots_length(setup) > screenp);
        var roots_iter = c.xcb_setup_roots_iterator(setup);
        for (0..@intCast(screenp)) |_| c.xcb_screen_next(&roots_iter);
        break :blk roots_iter.data.*;
    };

    root_ev: {
        const value_mask = c.XCB_CW_EVENT_MASK;
        const value_list = blk: {
            var vl: c.xcb_change_window_attributes_value_list_t = undefined;
            vl.event_mask = c.XCB_EVENT_MASK_STRUCTURE_NOTIFY;
            vl.event_mask |= c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY;
            vl.event_mask |= c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT;
            vl.event_mask |= c.XCB_EVENT_MASK_RESIZE_REDIRECT;
            break :blk vl;
        };

        const wm_root_ev_req_cookie = c.xcb_change_window_attributes_aux_checked(
            con,
            screen.root,
            value_mask,
            &value_list,
        );
        log.debug(
            \\trying to register for desired events of root window `{}`
        , .{screen.root});
        assert(c.xcb_flush(con) > 0);
        const err = c.xcb_request_check(con, wm_root_ev_req_cookie) orelse break :root_ev;
        defer free(err);
        switch (err.*.error_code) {
            c.XCB_ACCESS => {
                std.log.err(
                    \\unable to register for desired events of root window
                , .{});
            },
            else => |errno| {
                log.err(
                    \\unknown error while registering for events of root window: {}
                , .{errno});
            },
        }
    }
}
