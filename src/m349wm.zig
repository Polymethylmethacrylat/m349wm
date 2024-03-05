const std = @import("std");
const log = std.log.scoped(.m349wm);
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const free = std.c.free;

const builtin = @import("builtin");

const c = @import("c.zig");

const Client = struct {
    const Self = @This();
    connection: *c.xcb_connection_t,
    window: c.xcb_window_t,
    pub fn getAttributes(self: *const Self) ?*c.xcb_get_window_attributes_reply_t {
        const cookie = c.xcb_get_window_attributes(
            self.connection,
            self.window,
        );
        log.debug(
            \\getting attributes of window `{}`. sequence number: {x}
        , .{ self.window, cookie.sequence });
        const reply = c.xcb_get_window_attributes_reply(
            self.connection,
            cookie,
            null,
        );
        return reply;
    }
    pub fn getGeometry(self: *const Self) ?*c.xcb_get_geometry_reply_t {
        const cookie = c.xcb_get_geometry(
            self.connection,
            self.window,
        );
        log.debug(
            \\getting geometry of window `{}`. sequence number: {x}
        , .{ self.window, cookie.sequence });
        const reply = c.xcb_get_geometry_reply(
            self.connection,
            cookie,
            null,
        );
        return reply;
    }
    pub fn listProperties(self: *const Self) ?*c.xcb_list_properties_reply_t {
        const cookie = c.xcb_list_properties(
            self.connection,
            self.window,
        );
        log.debug(
            \\getting property list of window `{}`. sequence number: {x}
        , .{ self.window, cookie.sequence });
        const reply = c.xcb_list_properties_reply(
            self.connection,
            cookie,
            null,
        );
        return reply;
    }
    pub fn getProperty(
        self: *const Self,
        property: c.xcb_atom_t,
        property_type: c.xcb_atom_t,
        long_offset: u32,
        long_length: u32,
    ) ?*c.xcb_get_property_reply_t {
        const cookie = c.xcb_get_property(
            self.connection,
            0,
            self.window,
            property,
            property_type,
            long_offset,
            long_length,
        );
        log.debug(
            \\getting property list of window `{}`. sequence number: {x}
        , .{ self.window, cookie.sequence });
        const reply = c.xcb_get_geometry_reply(
            self.connection,
            cookie,
            null,
        );
        return reply;
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
fn handleCreateNotify() void {}
fn handleDestroyNotify() void {}
fn handleUnmapNotify() void {}
fn handleMapNotify() void {}
fn handleMapRequest(con: *c.xcb_connection_t, ev: *const c.xcb_generic_event_t) !void {
    const event: *const c.xcb_map_request_event_t = @ptrCast(ev);
    log.debug(
        \\handling map request. window: {}, parent: {}
    , .{ event.window, event.parent });

    const map_cookie = c.xcb_map_window(con, event.window);
    log.debug(
        \\mapping window `{}`. sequence id: `{x}`
    , .{ event.window, map_cookie.sequence });

    assert(c.xcb_flush(con) > 0);
}
fn handleReparentNotify() void {}
fn handleConfigureNotify() void {}
fn handleResizeRequest() void {}
fn handleConfigureRequest() !void {}
fn handleCirculateNotify() void {}
fn hanldeCirculateRequest() void {}
fn handlePropertyNotify() void {}
fn handleMappingNotify() void {}
fn hanldeClientMessage() void {}

fn eventLoop(con: *c.xcb_connection_t) !void {
    while (@as(?*c.xcb_generic_event_t, c.xcb_wait_for_event(con))) |event| {
        defer free(event);
        switch (c.XCB_EVENT_RESPONSE_TYPE(event)) {
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

    const screen: *c.xcb_screen_t = c.xcb_aux_get_screen(con, screenp);

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
