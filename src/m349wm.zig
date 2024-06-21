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

const violet = 0x9F_00_FF;
const dark_violet = 0x39_00_99;
const border_width = 3;
const terminal = .{"st"};

const shift_super = c.XCB_MOD_MASK_SHIFT | c.XCB_MOD_MASK_4;

const keymap = .{
    // keysym, keybutmask, fn, arg
    //.{ c.XK_t, c.XCB_MOD_MASK_4, print, .{ "Hello, World!", .{} } },
    .{ c.XK_j, c.XCB_MOD_MASK_4, Clients.focusNext, .{&clients} },
    .{ c.XK_k, c.XCB_MOD_MASK_4, Clients.focusPrevious, .{&clients} },
    .{ c.XK_Return, c.XCB_MOD_MASK_4, Clients.focusTop, .{&clients} },
    .{ c.XK_Return, shift_super, spawn, .{&terminal} },
};

fn spawn(args: []const []const u8) void {
    var proc = std.process.Child.init(args, c_allocator);
    proc.spawn() catch {};
}

const Clients = struct {
    const Self = @This();

    mapped: std.ArrayList(c.xcb_window_t),
    unmapped: std.ArrayList(c.xcb_window_t),
    current: ?c.xcb_window_t = null,

    pub fn arrange(self: *const Self) void {
        const screen: *const c.xcb_screen_t = c.xcb_aux_get_screen(connection, default_screen_num);
        const mapped = self.mapped.items.len;
        if (mapped == 0) return;

        const master: struct { width: u16, count: usize } = .{
            .width = if (mapped > 1) (screen.width_in_pixels * 2) / 3 else screen.width_in_pixels,
            .count = mapped / 3 + 1,
        };
        const stack: @TypeOf(master) = .{
            .width = screen.width_in_pixels - master.width,
            .count = mapped - master.count,
        };

        defer assert(0 < c.xcb_flush(connection));
        const value_mask =
            c.XCB_CONFIG_WINDOW_X |
            c.XCB_CONFIG_WINDOW_Y |
            c.XCB_CONFIG_WINDOW_WIDTH |
            c.XCB_CONFIG_WINDOW_HEIGHT |
            c.XCB_CONFIG_WINDOW_STACK_MODE;

        if (master.count > 0) {
            const width = master.width / master.count;

            for (self.mapped.items[0..master.count], 0..) |client, i| {
                const window: c.xcb_window_t = client;
                const pos_adj, const width_adj = if (i != 0)
                    .{ master.width % master.count, 0 }
                else
                    .{ 0, master.width % master.count };

                const value_list = zInit(c.xcb_configure_window_value_list_t, .{
                    .x = @as(i32, @intCast(width * i + pos_adj)),
                    .y = 0,
                    .width = @as(u32, @intCast(width - border_width * 2 + width_adj)),
                    .height = screen.height_in_pixels - border_width * 2,
                    .stack_mode = c.XCB_STACK_MODE_BELOW,
                });

                const cookie = c.xcb_configure_window_aux(
                    connection,
                    window,
                    value_mask,
                    &value_list,
                );

                log.debug(
                    \\ configuring window `{}`. sequence: {x}
                , .{ window, cookie.sequence });
            }
        }
        if (stack.count > 0) {
            const height = screen.height_in_pixels / stack.count;

            for (self.mapped.items[master.count..], 0..) |window, i| {
                const pos_adj, const height_adj = if (i != 0)
                    .{ screen.height_in_pixels % stack.count, 0 }
                else
                    .{ 0, screen.height_in_pixels % stack.count };

                const value_list = zInit(c.xcb_configure_window_value_list_t, .{
                    .x = master.width,
                    .y = @as(i32, @intCast(
                        height * i + pos_adj,
                    )),
                    .height = @as(u32, @intCast(
                        height - border_width * 2 + height_adj,
                    )),
                    .width = stack.width - border_width * 2,
                    .stack_mode = c.XCB_STACK_MODE_BELOW,
                });

                const cookie = c.xcb_configure_window_aux(
                    connection,
                    window,
                    value_mask,
                    &value_list,
                );

                log.debug(
                    \\ configuring window `{}`. sequence: {x}
                , .{ window, cookie.sequence });
            }
        }
    }

    /// assumes window is in self.unmapped
    pub fn remove(self: *Self, window: c.xcb_window_t) void {
        const index = std.mem.indexOfScalar(
            c.xcb_window_t,
            self.unmapped.items,
            window,
        ) orelse unreachable;
        _ = self.unmapped.swapRemove(index);
    }

    /// assumes window is in self.unmapped
    pub fn map(self: *Self, window: c.xcb_window_t) !void {
        const index = std.mem.indexOfScalar(
            c.xcb_window_t,
            self.unmapped.items,
            window,
        ) orelse unreachable;
        _ = self.unmapped.swapRemove(index);
        try self.mapped.insert(0, window);

        _ = c.xcb_map_window(connection, window);
        _ = c.xcb_flush(connection);
    }

    /// assumes window is in self.mapped
    pub fn unmap(self: *Self, window: c.xcb_window_t) !void {
        const index = std.mem.indexOfScalar(
            c.xcb_window_t,
            self.mapped.items,
            window,
        ) orelse unreachable;

        _ = clients.mapped.orderedRemove(index);
        try clients.unmapped.append(window);

        _ = c.xcb_unmap_window(connection, window);
        _ = c.xcb_flush(connection);

        if (std.meta.eql(self.current, window)) self.focus(null);
    }

    pub fn focusTop(self: *Self) void {
        if (self.mapped.items.len > 0)
            self.focus(self.mapped.items[0])
        else
            self.focus(null);
    }

    pub fn focusNext(self: *Self) void {
        if (self.current == null) return self.focusTop();

        const index = init: {
            var index = std.mem.indexOfScalar(
                c.xcb_window_t,
                self.mapped.items,
                self.current.?,
            ) orelse unreachable;
            index = (index + 1) % self.mapped.items.len;
            break :init index;
        };

        self.focus(self.mapped.items[index]);
    }

    pub fn focusPrevious(self: *Self) void {
        if (self.current == null) return self.focusTop();

        const index = init: {
            var index = std.mem.indexOfScalar(
                c.xcb_window_t,
                self.mapped.items,
                self.current.?,
            ) orelse unreachable;
            index -%= 1;
            break :init @min(index, self.mapped.items.len - 1);
        };

        self.focus(self.mapped.items[index]);
    }

    /// assumes window is in self.mapped
    pub fn focus(self: *Self, window: ?c.xcb_window_t) void {
        defer _ = c.xcb_flush(connection);

        if (self.current) |cur| {
            const value_mask = c.XCB_CW_BORDER_PIXEL;
            const value_list = zInit(c.xcb_change_window_attributes_value_list_t, .{
                .border_pixel = dark_violet,
            });
            _ = c.xcb_change_window_attributes_aux(
                connection,
                cur,
                value_mask,
                &value_list,
            );
        }

        self.current = if (window) |win| blk: {
            const value_mask = c.XCB_CW_BORDER_PIXEL;
            const value_list = zInit(c.xcb_change_window_attributes_value_list_t, .{
                .border_pixel = violet,
            });
            _ = c.xcb_change_window_attributes_aux(
                connection,
                win,
                value_mask,
                &value_list,
            );
            break :blk win;
        } else null;

        _ = c.xcb_set_input_focus(
            connection,
            c.XCB_INPUT_FOCUS_PARENT,
            window orelse c.xcb_aux_get_screen(connection, default_screen_num).*.root,
            c.XCB_CURRENT_TIME,
        );
    }

    pub fn init(allocator: Allocator) !Self {
        return .{
            .mapped = std.ArrayList(c.xcb_window_t).init(allocator),
            .unmapped = std.ArrayList(c.xcb_window_t).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mapped.deinit();
        self.unmapped.deinit();
        self.current = null;
    }
};

var clients: Clients = undefined;

var default_screen_num: c_int = undefined;
var connection: *c.xcb_connection_t = undefined;
var keysyms: *c.xcb_key_symbols_t = undefined;

fn handleError(err: *const c.xcb_generic_error_t) void {
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

fn handleKeyInput(event: *c.xcb_key_press_event_t) void {
    const keysym = c.xcb_key_press_lookup_keysym(keysyms, event, 0);

    inline for (keymap) |mapping| {
        blk: {
            if (keysym != mapping[0]) break :blk;
            if (event.state & ~c.XCB_MOD_MASK_LOCK != mapping[1] and
                mapping[1] != c.XCB_MOD_MASK_ANY) break :blk;
            _ = @call(.auto, mapping[2], mapping[3]);
        }
    }
}

fn handleCreateNotify(event: *const c.xcb_create_notify_event_t) !void {
    log.debug(
        \\handling create notify request. window: {}
    , .{event.window});

    try clients.unmapped.append(event.window);

    {
        const value_mask: u16 = c.XCB_CONFIG_WINDOW_BORDER_WIDTH;
        const value_list = zInit(c.xcb_configure_window_value_list_t, .{
            .border_width = border_width,
        });
        const cookie = c.xcb_configure_window_aux(
            connection,
            event.window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ configuring window `{}`. sequence: {x}
        , .{ event.window, cookie.sequence });
        assert(c.xcb_request_check(connection, cookie) == null);
    }
    {
        const value_mask: u16 = c.XCB_CW_BORDER_PIXEL | c.XCB_CW_BORDER_PIXMAP;
        const value_list = std.mem.zeroInit(c.xcb_change_window_attributes_value_list_t, .{
            .border_pixel = dark_violet,
            .border_pixmap = c.XCB_PIXMAP_NONE,
        });
        const cookie = c.xcb_change_window_attributes_aux(
            connection,
            event.window,
            value_mask,
            &value_list,
        );
        log.debug(
            \\ changing window attributes. window:`{}`; sequence: {x}
        , .{ event.window, cookie.sequence });
        assert(c.xcb_request_check(connection, cookie) == null);
    }
}

fn handleDestroyNotify(event: *const c.xcb_destroy_notify_event_t) void {
    clients.remove(event.window);

    log.debug(
        \\handling destroy notify. window: {}
    , .{event.window});
}

fn handleUnmapNotify(event: *const c.xcb_unmap_notify_event_t) !void {
    try clients.unmap(event.window);
    log.debug(
        \\handling unmap notify. window: {}
    , .{event.window});
    clients.arrange();
}

fn handleMapRequest(event: *const c.xcb_map_request_event_t) !void {
    clients.focus(null);
    try clients.map(event.window);
    log.debug(
        \\handling map request. window: {}, parent: {}
    , .{ event.window, event.parent });

    clients.arrange();
    clients.focus(event.window);
}

fn handleMappingNotify(event: *c.xcb_mapping_notify_event_t) void {
    _ = c.xcb_refresh_keyboard_mapping(keysyms, event);
    dropKeyGrabs();
    registerKeyGrabs();
}

fn registerKeyGrabs() void {
    inline for (keymap) |mapping| {
        _ = c.xcb_grab_key(
            connection,
            0,
            c.xcb_aux_get_screen(connection, default_screen_num).*.root,
            mapping[1],
            c.xcb_key_symbols_get_keycode(keysyms, mapping[0]).*,
            c.XCB_GRAB_MODE_ASYNC,
            c.XCB_GRAB_MODE_ASYNC,
        );
        _ = c.xcb_grab_key(
            connection,
            0,
            c.xcb_aux_get_screen(connection, default_screen_num).*.root,
            mapping[1] | c.XCB_MOD_MASK_LOCK,
            c.xcb_key_symbols_get_keycode(keysyms, mapping[0]).*,
            c.XCB_GRAB_MODE_ASYNC,
            c.XCB_GRAB_MODE_ASYNC,
        );
    }
    _ = c.xcb_flush(connection);
}

fn dropKeyGrabs() void {
    _ = c.xcb_ungrab_key(
        connection,
        c.XCB_GRAB_ANY,
        c.xcb_aux_get_screen(connection, default_screen_num).*.root,
        c.XCB_MOD_MASK_ANY,
    );
    _ = c.xcb_flush(connection);
}

fn eventLoop() !void {
    const con = connection;
    while (@as(?*c.xcb_generic_event_t, c.xcb_wait_for_event(con))) |event| {
        defer free(event);
        switch (c.XCB_EVENT_RESPONSE_TYPE(event)) {
            0 => handleError(@ptrCast(event)),
            c.XCB_KEY_PRESS => handleKeyInput(@ptrCast(event)),
            c.XCB_CREATE_NOTIFY => try handleCreateNotify(@ptrCast(event)),
            c.XCB_DESTROY_NOTIFY => handleDestroyNotify(@ptrCast(event)),
            c.XCB_UNMAP_NOTIFY => try handleUnmapNotify(@ptrCast(event)),
            c.XCB_MAP_REQUEST => try handleMapRequest(@ptrCast(event)),
            c.XCB_MAPPING_NOTIFY => handleMappingNotify(@ptrCast(event)),
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

fn registerEvents() void {
    const screen: *c.xcb_screen_t = c.xcb_aux_get_screen(connection, default_screen_num);

    const value_mask = c.XCB_CW_EVENT_MASK;
    const value_list = std.mem.zeroInit(c.xcb_change_window_attributes_value_list_t, .{
        .event_mask = c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
            c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
            c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
            c.XCB_EVENT_MASK_RESIZE_REDIRECT,
    });
    const cookie = c.xcb_change_window_attributes_aux_checked(
        connection,
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
    assert(c.xcb_flush(connection) > 0);

    const err = c.xcb_request_check(connection, cookie) orelse return;
    defer free(err);
    std.log.err(
        \\unable to register for desired events of root window
    , .{});
    handleError(@ptrCast(err));
    std.process.exit(0);
}

fn setupConnection() !*c.xcb_connection_t {
    const con = c.xcb_connect(null, &default_screen_num) orelse unreachable;

    const connection_error = c.xcb_connection_has_error(con);
    switch (connection_error) {
        0 => return con,
        c.XCB_CONN_ERROR => {
            log.err(
                \\xcb connection errors because of socket, pipe and other stream errors. 
            , .{});
        },
        c.XCB_CONN_CLOSED_PARSE_ERR => {
            log.err(
                \\Connection closed, error during parsing display string.
            , .{});
            log.info(
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
        },
        c.XCB_CONN_CLOSED_INVALID_SCREEN => {
            log.err(
                \\Connection closed because the server does not have a screen matching the display.
            , .{});
            log.info(
                \\Hint: is `$DISPLAY` set correctly?
            , .{});
        },
        else => unreachable,
    }

    return error.ConnectionError;
}

pub fn main() !void {
    log.info(
        \\trying to connect to X server...
    , .{});

    connection = setupConnection() catch return;
    defer c.xcb_disconnect(connection);

    log.debug(
        \\connected successfully. Desired screen is: {}
    , .{default_screen_num});

    registerEvents();

    clients = try Clients.init(c_allocator);
    defer clients.deinit();

    {
        keysyms = c.xcb_key_symbols_alloc(connection) orelse unreachable;
        errdefer c.xcb_key_symbols_free(keysyms);
        registerKeyGrabs();
    }
    defer {
        c.xcb_key_symbols_free(keysyms);
        dropKeyGrabs();
    }

    try eventLoop();
}
