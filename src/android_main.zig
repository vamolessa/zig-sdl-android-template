const std = @import("std");
const main = @import("main.zig");

export fn SDL_main() void {
    main.main() catch |err| std.debug.panic("something went wrong {}", .{err});
}
