const std = @import("std");
const sdl = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "");
    @cInclude("SDL.h");
});

const SCREEN_WIDTH = 480;
const SCREEN_HEIGHT = 640;

pub fn main() anyerror!void {
    sdl.SDL_Log("================================================ SDL MAIN!");

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_EVENTS) != 0) {
        std.debug.panic("could not initialize SDL", .{});
    }
    defer sdl.SDL_Quit();

    var window = sdl.SDL_CreateWindow(
        "My Game",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        0,
    ) orelse std.debug.panic("could not create window", .{});
    defer sdl.SDL_DestroyWindow(window);

    var windowSurface = sdl.SDL_GetWindowSurface(window);
    if (sdl.SDL_FillRect(windowSurface, null, sdl.SDL_MapRGB(windowSurface.*.format, 0xaa, 0xaa, 0xaa)) < 0) {
        std.debug.panic("could not fill rect", .{});
    }

    sdl.SDL_Log("before load");
    var rw = sdl.SDL_RWFromFile("images/gato.bmp", "rb");
    var imageSurface = sdl.SDL_LoadBMP_RW(rw, @boolToInt(true)) orelse {
        sdl.SDL_Log("could not load image");
    };
    defer sdl.SDL_FreeSurface(imageSurface);

    main_loop: while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :main_loop,
                sdl.SDL_MOUSEBUTTONDOWN => {
                    sdl.SDL_Log("mouse down");
                },
                sdl.SDL_MOUSEBUTTONUP => {
                    sdl.SDL_Log("mouse up");
                },
                else => {},
            }
        }

        var destRect = sdl.SDL_Rect{
            .x = 10,
            .y = 10,
            .w = 0,
            .h = 0,
        };
        if (sdl.SDL_BlitSurface(imageSurface, null, windowSurface, &destRect) < 0) {
            std.debug.panic("could not blit image", .{});
        }

        if (sdl.SDL_UpdateWindowSurface(window) < 0) {
            std.debug.panic("could not update window surface", .{});
        }
    }
}

