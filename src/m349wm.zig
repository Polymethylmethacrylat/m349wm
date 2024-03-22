const std = @import("std");
const log = std.log.scoped(.m349wm);
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const free = std.c.free;

const builtin = @import("builtin");

const c = @import("c.zig");
const Client = struct {
    window: c.xcb_window_t,
    mapped: bool = false,
};

const violet = 0x9f00ff;
const dark_violet = 0x390099;
const border_width = 3;

var clients: std.ArrayList(Client) = undefined;
var screen: *const c.xcb_screen_t = undefined;

/// assumes that `clients` is ordered after windows being mapped or not
fn arrangeClients(con: *c.xcb_connection_t) void {
    const mapped: usize = blk: {
        var i: usize = 0;
        while (i < clients.items.len and clients.items[i].mapped) : (i += 1) {}
        break :blk i;
    };
    if (mapped == 0) return;

    const master = .{
        .width = if (mapped > 1) (screen.width_in_pixels * 2) / 3 else screen.width_in_pixels,
        .count = mapped / 3 + 1,
    };
    const stack = .{
        .width = screen.width_in_pixels - master.width,
        .count = mapped - master.count,
    };

    defer assert(c.xcb_flush(con) > 0);
    for (clients.items[0..master.count], 0..) |client, i| {
        const window: c.xcb_window_t = client.window;
        assert(client.mapped);
        const value_mask =
            c.XCB_CONFIG_WINDOW_X |
            c.XCB_CONFIG_WINDOW_Y |
            c.XCB_CONFIG_WINDOW_WIDTH |
            c.XCB_CONFIG_WINDOW_HEIGHT;
        const value_list = std.mem.zeroInit(c.xcb_configure_window_value_list_t, .{
            .x = @as(i32, @intCast(
                (master.width / master.count) * i + if (i != 0)
                    (master.width % master.count)
                else
                    0,
            )),
            .y = 0,
            .width = @as(u32, @intCast(
                master.width / master.count - border_width * 2 +
                    if (i == 0) master.width % master.count else 0,
            )),
            .height = screen.height_in_pixels - border_width * 2,
        });
        const cookie = c.xcb_configure_window_aux(
            con,
            window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ configuring window `{}`. sequence: {x}
        , .{ window, cookie.sequence });
    }
    for (clients.items[master.count..][0..stack.count], 0..) |client, i| {
        const window: c.xcb_window_t = client.window;
        assert(client.mapped);
        const value_mask =
            c.XCB_CONFIG_WINDOW_X |
            c.XCB_CONFIG_WINDOW_Y |
            c.XCB_CONFIG_WINDOW_WIDTH |
            c.XCB_CONFIG_WINDOW_HEIGHT;
        const value_list = std.mem.zeroInit(c.xcb_configure_window_value_list_t, .{
            .x = master.width,
            .y = @as(i32, @intCast(
                (screen.height_in_pixels / stack.count) * i +
                    if (i != 0) (screen.height_in_pixels % stack.count) else 0,
            )),
            .height = @as(u32, @intCast(
                screen.height_in_pixels / stack.count - border_width * 2 +
                    if (i == 0) screen.height_in_pixels % stack.count else 0,
            )),
            .width = stack.width - border_width * 2,
        });
        const cookie = c.xcb_configure_window_aux(
            con,
            window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ configuring window `{}`. sequence: {x}
        , .{ window, cookie.sequence });
    }
}

fn handleError(ev: *const c.xcb_generic_event_t) void {
    const err: *const c.xcb_generic_error_t = @ptrCast(ev);
    if (@as(?[*:0]const u8, c.xcb_event_get_error_label(err.error_code))) |label| {
        log.warn(
            \\discarding error `{s}` while or after request `{x}`
        , .{ label, err.sequence });
    } else {
        log.warn(
            \\received unknown x error code `{}` while or after request `{x}`
        , .{
            err.error_code,
            err.sequence,
        });
    }
}
fn handleCreateNotify(con: *c.xcb_connection_t, ev: *const c.xcb_generic_event_t) !void {
    const event: *const c.xcb_create_notify_event_t = @ptrCast(ev);
    log.debug(
        \\handling create notify request. window: {}
    , .{event.window});
    try clients.append(.{ .window = event.window });
    {
        const value_mask: u16 = c.XCB_CONFIG_WINDOW_BORDER_WIDTH;
        const value_list = std.mem.zeroInit(c.xcb_configure_window_value_list_t, .{
            .border_width = border_width,
        });
        const cookie = c.xcb_configure_window_aux(
            con,
            event.window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ configuring window `{}`. sequence: {x}
        , .{ event.window, cookie.sequence });
        assert(c.xcb_request_check(con, cookie) == null);
    }
    {
        const value_mask: u16 = c.XCB_CW_BORDER_PIXEL | c.XCB_CW_BORDER_PIXMAP;
        const value_list = std.mem.zeroInit(c.xcb_change_window_attributes_value_list_t, .{
            .border_pixel = dark_violet,
            .border_pixmap = c.XCB_PIXMAP_NONE,
        });
        const cookie = c.xcb_change_window_attributes_aux(
            con,
            event.window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ changing window attributes. window:`{}`; sequence: {x}
        , .{ event.window, cookie.sequence });
        assert(c.xcb_request_check(con, cookie) == null);
    }
}
fn handleDestroyNotify(ev: *const c.xcb_generic_event_t) void {
    const event: *const c.xcb_destroy_notify_event_t = @ptrCast(ev);
    for (clients.items, 0..) |client, i| {
        if (client.window != event.window) continue;
        _ = clients.orderedRemove(i);
        break;
    }
    log.debug(
        \\handling destroy notify request. window: {}
    , .{event.window});
}
fn handleUnmapNotify(con: *c.xcb_connection_t, ev: *const c.xcb_generic_event_t) !void {
    const event: *const c.xcb_unmap_notify_event_t = @ptrCast(ev);
    for (clients.items, 0..) |client, i| {
        if (client.window != event.window) continue;
        var tmp: Client = clients.orderedRemove(i);
        tmp.mapped = false;
        try clients.append(tmp);
        break;
    }
    log.debug(
        \\handling unmap notify. window: {}
    , .{event.window});
    arrangeClients(con);
}
fn handleMapNotify() void {}
fn handleMapRequest(con: *c.xcb_connection_t, ev: *const c.xcb_generic_event_t) !void {
    const event: *const c.xcb_map_request_event_t = @ptrCast(ev);
    {
        var tmp = for (clients.items, 0..) |client, i| {
            if (client.window != event.window) continue;
            break clients.orderedRemove(i);
        } else unreachable;
        tmp.mapped = true;
        try clients.insert(0, tmp);
    }
    log.debug(
        \\handling map request. window: {}, parent: {}
    , .{ event.window, event.parent });

    const map_cookie = c.xcb_map_window(con, event.window);
    log.debug(
        \\mapping window `{}`. sequence id: `{x}`
    , .{ event.window, map_cookie.sequence });
    assert(c.xcb_flush(con) > 0);
    arrangeClients(con);
}
fn handleReparentNotify() void {}
fn handleConfigureNotify() void {}
fn handleResizeRequest() void {}
fn handleConfigureRequest() void {}
fn handleCirculateNotify() void {}
fn handleCirculateRequest() void {}
fn handlePropertyNotify() void {}
fn handleMappingNotify() void {}
fn handleClientMessage() void {}

fn eventLoop(con: *c.xcb_connection_t) !void {
    while (@as(?*c.xcb_generic_event_t, c.xcb_wait_for_event(con))) |event| {
        defer free(event);
        switch (c.XCB_EVENT_RESPONSE_TYPE(event)) {
            0 => handleError(event),
            c.XCB_CREATE_NOTIFY => try handleCreateNotify(con, event),
            c.XCB_DESTROY_NOTIFY => handleDestroyNotify(event),
            c.XCB_UNMAP_NOTIFY => try handleUnmapNotify(con, event),
            c.XCB_MAP_REQUEST => try handleMapRequest(con, event),
            else => {
                if (@as(?[*:0]const u8, c.xcb_event_get_label(event.response_type))) |label| {
                    log.warn(
                        \\discarding event `{s}` while or after request `{x}`
                    , .{ label, event.sequence });
                } else {
                    log.warn(
                        \\received unknown x event of type `{}` while or after request `{x}`
                    , .{
                        event.response_type,
                        event.sequence,
                    });
                }
            },
        }
    } else return error.XcbConnError;
}

pub fn main() !void {
    const allocator = c_allocator;
    clients = try @TypeOf(clients).initCapacity(allocator, 64);
    defer clients.deinit();

    log.info(
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

    screen = c.xcb_aux_get_screen(con, screenp);

    root_ev: {
        const value_mask = c.XCB_CW_EVENT_MASK;
        const value_list = std.mem.zeroInit(c.xcb_change_window_attributes_value_list_t, .{
            .event_mask = c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
                c.XCB_EVENT_MASK_RESIZE_REDIRECT,
        });

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
