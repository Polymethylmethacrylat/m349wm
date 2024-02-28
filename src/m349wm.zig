const std = @import("std");
const log = std.log.scoped(.m349wm);
const assert = std.debug.assert;
const free = std.c.free;

const builtin = @import("builtin");

const c = @import("c.zig");
const XcbConnection = c.xcb_connection_t;
const XcbGenericEvent = c.xcb_generic_event_t;

fn handleCreateNotify() void {}
fn handleDestroyNotify() void {}
fn handleUnmapNotify() void {}
fn handleMapNotify() void {}
fn handleMapRequest(con: *XcbConnection, ev: *const XcbGenericEvent) !void {
    const event: *const c.xcb_map_request_event_t = @ptrCast(ev);
    log.debug(
        \\handling map request. window: {}, parent: {}
    , .{ event.window, event.parent });
    //const value_mask = c.XCB_CONFIG_WINDOW_BORDER_WIDTH;
    //const value_list: c.xcb_configure_window_value_list_t = blk: {
    //    var val: c.xcb_configure_window_value_list_t = undefined;
    //    val.border_width = 10;
    //    break :blk undefined;
    //};
    //const configure_cookie = c.xcb_configure_window_aux(con, event.window, value_mask, &value_list);
    //log.debug(
    //    \\configuring window `{}`. sequence id: `{x}`
    //, .{ event.window, configure_cookie.sequence });
    const map_cookie = c.xcb_map_window(con, event.window);
    log.debug(
        \\mapping window `{}`. sequence id: `{x}`
    , .{ event.window, map_cookie.sequence });
    assert(c.xcb_flush(con) > 0);
}
fn handleReparentNotify() void {}
fn handleConfigureNotify() void {}
fn handleResizeRequest() void {}
fn handleConfigureRequest(con: *XcbConnection, ev: *const XcbGenericEvent) !void {
    _ = con;
    const event: *const c.xcb_configure_window_request_t = @ptrCast(ev);
    log.debug(
        \\ignoring configure window request. window: {}, value_mask: {}
    , .{ event.window, event.value_mask });
}
fn handleCirculateNotify() void {}
fn hanldeCirculateRequest() void {}
fn handlePropertyNotify() void {}
fn handleMappingNotify() void {}
fn hanldeClientMessage() void {}

fn eventLoop(con: *XcbConnection) !void {
    while (@as(?*XcbGenericEvent, c.xcb_wait_for_event(con))) |event| {
        defer free(event);
        switch (event.sequence) {
            c.XCB_MAP_REQUEST => try handleMapRequest(con, event),
            c.XCB_CONFIGURE_REQUEST => try handleConfigureRequest(con, event),
            else => {
                log.warn(
                    \\received unknown x event of type `{}` while or after request `{x}`
                , .{
                    event.response_type,
                    event.sequence,
                });
            },
        }
    } else return error.XcbConnError;
}

pub fn main() !void {
    log.debug(
        \\trying to connect to X server...
    , .{});
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
            return;
        },
        c.XCB_CONN_CLOSED_PARSE_ERR => {
            log.err(
                \\Connection closed, error during parsing display string.
            , .{});
            log.info(
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
            return;
        },
        c.XCB_CONN_CLOSED_INVALID_SCREEN => {
            log.err(
                \\Connection closed because the server does not have a screen matching the display.
            , .{});
            log.info(
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
            return;
        },
        else => |errno| {
            log.err("Unknown connection error: {}", .{errno});
            return error.UnknownConnErr;
        },
    }
    log.debug(
        \\connected successfully. Desired screen is: {}
    , .{screenp});

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
            \\trying to register for desired events of root window `{}`, sequence number: `{x}`
        , .{
            screen.root,
            wm_root_ev_req_cookie.sequence,
        });
        assert(c.xcb_flush(con) > 0);
        const err = c.xcb_request_check(con, wm_root_ev_req_cookie) orelse break :root_ev;
        defer free(err);
        switch (err.*.error_code) {
            c.XCB_ACCESS => {
                std.log.err(
                    \\unable to register for desired events of root window
                , .{});
                return;
            },
            else => |errno| {
                log.err(
                    \\unknown error while registering for events of root window: {}
                , .{errno});
                return error.XcbUnknownError;
            },
        }
    }

    try eventLoop(con);
}
