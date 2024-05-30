const std = @import("std");
const log = std.log.scoped(.m349wm);
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const free = std.c.free;
const zInit = std.mem.zeroInit;

const builtin = @import("builtin");

const c = @import("c.zig");
const Client = struct {
    window: c.xcb_window_t,
};

const violet = 0x9f00ff;
const dark_violet = 0x390099;
const border_width = 3;

const allocator = c_allocator;

var clients: struct {
    mapped: std.ArrayList(Client),
    unmapped: std.ArrayList(Client),
    current: ?c.xcb_window_t = null,
} = undefined;

var default_screen_num: c_int = undefined;
var connection: *c.xcb_connection_t = undefined;

fn setCurrentClient(window: ?c.xcb_window_t) void {
    const con = connection;
    defer _ = c.xcb_flush(con);
    if (clients.current) |cur| {
        const value_mask = c.XCB_CW_BORDER_PIXEL;
        const value_list = zInit(c.xcb_change_window_attributes_value_list_t, .{
            .border_pixel = dark_violet,
        });
        _ = c.xcb_change_window_attributes_aux(
            con,
            cur,
            value_mask,
            &value_list,
        );
    }
    clients.current = if (window) |win| blk: {
        const value_mask = c.XCB_CW_BORDER_PIXEL;
        const value_list = zInit(c.xcb_change_window_attributes_value_list_t, .{
            .border_pixel = violet,
        });
        _ = c.xcb_change_window_attributes_aux(
            con,
            win,
            value_mask,
            &value_list,
        );
        break :blk win;
    } else null;
}

/// assumes that `clients.mapped` is ordered
fn arrangeClients() void {
    const con = connection;
    const screen: *const c.xcb_screen_t = c.xcb_aux_get_screen(con, default_screen_num);
    const mapped = clients.mapped.items.len;
    if (mapped == 0) return;

    const master: struct{ width: u16, count: usize } = .{
        .width = if (mapped > 1) (screen.width_in_pixels * 2) / 3 else screen.width_in_pixels,
        .count = mapped / 3 + 1,
    };
    const stack: @TypeOf(master) = .{
        .width = screen.width_in_pixels - master.width,
        .count = mapped - master.count,
    };

    defer assert(c.xcb_flush(con) > 0);
    const value_mask =
        c.XCB_CONFIG_WINDOW_X |
        c.XCB_CONFIG_WINDOW_Y |
        c.XCB_CONFIG_WINDOW_WIDTH |
        c.XCB_CONFIG_WINDOW_HEIGHT |
        c.XCB_CONFIG_WINDOW_STACK_MODE;
    for (clients.mapped.items[0..master.count], 0..) |client, i| {
        const window: c.xcb_window_t = client.window;
        const value_list = zInit(c.xcb_configure_window_value_list_t, .{
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
            .stack_mode = c.XCB_STACK_MODE_BELOW,
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
    for (clients.mapped.items[master.count..][0..stack.count], 0..) |client, i| {
        const window: c.xcb_window_t = client.window;
        const value_list = zInit(c.xcb_configure_window_value_list_t, .{
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
            .stack_mode = c.XCB_STACK_MODE_BELOW,
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
fn handleCreateNotify(ev: *const c.xcb_generic_event_t) !void {
    const con = connection;
    const event: *const c.xcb_create_notify_event_t = @ptrCast(ev);
    log.debug(
        \\handling create notify request. window: {}
    , .{event.window});
    try clients.unmapped.append(.{ .window = event.window });
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
    for (clients.unmapped.items, 0..) |client, i| {
        if (client.window != event.window) continue;
        _ = clients.unmapped.orderedRemove(i);
        break;
    }
    log.debug(
        \\handling destroy notify request. window: {}
    , .{event.window});
}
fn handleUnmapNotify(ev: *const c.xcb_generic_event_t) !void {
    const event: *const c.xcb_unmap_notify_event_t = @ptrCast(ev);
    for (clients.mapped.items, 0..) |client, i| {
        if (client.window != event.window) continue;
        const tmp: Client = clients.mapped.orderedRemove(i);
        if (clients.current != null and clients.current.? == tmp.window) setCurrentClient(null);
        try clients.unmapped.append(tmp);
        break;
    }
    log.debug(
        \\handling unmap notify. window: {}
    , .{event.window});
    arrangeClients();
}
fn handleMapNotify() void {}
fn handleMapRequest(ev: *const c.xcb_generic_event_t) !void {
    const con = connection;
    const event: *const c.xcb_map_request_event_t = @ptrCast(ev);
    setCurrentClient(null);
    {
        const tmp = for (clients.unmapped.items, 0..) |client, i| {
            if (client.window != event.window) continue;
            break clients.unmapped.swapRemove(i);
        } else unreachable;
        try clients.mapped.insert(0, tmp);
    }
    log.debug(
        \\handling map request. window: {}, parent: {}
    , .{ event.window, event.parent });

    const map_cookie = c.xcb_map_window(con, event.window);
    log.debug(
        \\mapping window `{}`. sequence id: `{x}`
    , .{ event.window, map_cookie.sequence });
    assert(c.xcb_flush(con) > 0);
    arrangeClients();
    setCurrentClient(event.window);
}
fn handleReparentNotify() void {}
fn handleConfigureNotify() void {}
fn handleResizeRequest() void {}
fn handleConfigureRequest() void {}
fn handleCirculateNotify() void {}
fn handleCirculateRequest(ev: *const c.xcb_generic_event_t) void {
    const event: *const c.xcb_circulate_window_request_t = @ptrCast(ev);
    _ = event;

}
fn handlePropertyNotify() void {}
fn handleMappingNotify() void {}
fn handleClientMessage() void {}

fn eventLoop() !void {
    const con = connection;
    while (@as(?*c.xcb_generic_event_t, c.xcb_wait_for_event(con))) |event| {
        defer free(event);
        switch (c.XCB_EVENT_RESPONSE_TYPE(event)) {
            0 => handleError(event),
            c.XCB_CREATE_NOTIFY => try handleCreateNotify(event),
            c.XCB_DESTROY_NOTIFY => handleDestroyNotify(event),
            c.XCB_UNMAP_NOTIFY => try handleUnmapNotify(event),
            c.XCB_MAP_REQUEST => try handleMapRequest(event),
            c.XCB_CIRCULATE_REQUEST => handleCirculateRequest(event),
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
    log.info(
        \\trying to connect to X server...
    , .{});
    connection = c.xcb_connect(null, &default_screen_num) orelse unreachable;
    defer c.xcb_disconnect(connection);

    const con = connection;
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
        else => unreachable,
    }
    log.debug(
        \\connected successfully. Desired screen is: {}
    , .{default_screen_num});

    const screen: *const c.xcb_screen_t = c.xcb_aux_get_screen(con, default_screen_num);
    root_ev: {
        const value_mask = c.XCB_CW_EVENT_MASK;
        const value_list = std.mem.zeroInit(c.xcb_change_window_attributes_value_list_t, .{
            .event_mask = c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
                c.XCB_EVENT_MASK_RESIZE_REDIRECT,
        });
        const cookie = c.xcb_change_window_attributes_aux_checked(
            con,
            screen.root,
            value_mask,
            &value_list,
        );
        log.debug(
            \\trying to register for desired events of root window `{}`, sequence number: `{x}`
        , .{
            screen.root,
            cookie.sequence,
        });
        assert(c.xcb_flush(con) > 0);

        const err = c.xcb_request_check(con, cookie) orelse break :root_ev;
        defer free(err);
        std.log.err(
            \\unable to register for desired events of root window
        , .{});
        handleError(@ptrCast(err));
        return;
    }

    clients = .{
        .mapped = try std.ArrayList(Client).initCapacity(allocator, 64),
        .unmapped = try std.ArrayList(Client).initCapacity(allocator, 64),
    };
    defer {
        clients.mapped.deinit();
        clients.unmapped.deinit();
    }

    try eventLoop();
}
