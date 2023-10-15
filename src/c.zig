pub usingnamespace @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xcb_keysyms.h");
    {
        @cDefine("XK_MISCELLANY", {});
        defer @cUndef("XK_MISCELLANY");
        @cDefine("XK_LATIN1", {});
        defer @cUndef("XK_LATIN1");
        @cInclude("X11/keysymdef.h");
    }
});

pub usingnamespace @import("std").c;
