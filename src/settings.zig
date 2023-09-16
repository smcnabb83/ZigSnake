const SDL = @import("sdl2");
const std = @import("std");
pub const field_width: i32 = 25;
pub const field_height: i32 = 25;
pub const step_time: u32 = 150;
pub const border_color: SDL.Color = SDL.Color{ .r = 0, .g = 0, .b = 100, .a = 255 };
pub const snake_color: SDL.Color = SDL.Color{ .r = 0, .g = 200, .b = 0, .a = 255 };
pub const apple_color: SDL.Color = SDL.Color{ .r = 200, .g = 0, .b = 0, .a = 255 };
pub const background_color: SDL.Color = SDL.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const font_color: SDL.Color = SDL.Color{ .r = 0, .g = 255, .b = 255, .a = 255 };
pub const play_area_size = field_width * field_height;
pub const RandGen = std.rand.DefaultPrng;