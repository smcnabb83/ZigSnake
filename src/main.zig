const std = @import("std");
const SDL = @import("sdl2");
const settings = @import("./settings.zig");

// zero is actually a meaningful value in the GameStateData.snake array, so
// we are using max usize as the empty value. if the fielf array length is ever
// usize + 1, this breaks.
const snake_empty = std.math.maxInt(usize);

const FieldState = enum { empty, snake, apple };
const Direction = enum { up, down, left, right };
const GameState = enum { playing, over, quit, paused };
const Input = enum { left, right, up, down, paused, select, cancel, any, none };

const PrintStringToTextureReturn = struct { texture: SDL.Texture, size: SDL.Size };

const Pos = struct {
    x: i32,
    y: i32,
};

const RenderData = struct {
    start_render_x: i32,
    start_render_y: i32,
    render_chunk_size_x: i32,
    render_chunk_size_y: i32,
    render_size: i32,
};

const GameStateData = struct {
    snake_dir: Direction,
    snake_last_moved_dir: Direction,
    snake_head_idx: usize,
    input: Input,
    state: GameState,
    score: i32,
    next_step_time: u32,
    field: []FieldState,
    snake: []usize,
    fn advanceSnake(self: *GameStateData, grow_snake: bool, new_head: usize) void {
        var end_index: usize = 0;
        for (0..self.snake.len - 1) |idx| {
            if (!grow_snake) {
                self.snake[idx] = self.snake[idx + 1];
            }
            if (self.snake[idx] == snake_empty) {
                end_index = idx;
                break;
            }
        }
        self.snake[end_index] = new_head;
        self.snake_head_idx = end_index;
    }
    fn snakeHeadPos(self: *GameStateData) Pos {
        var snakeHeadIdx = self.snake[self.snake_head_idx];
        return Pos{ .x = getXFromIndex(snakeHeadIdx), .y = getYFromIndex(snakeHeadIdx) };
    }
};

fn getXFromIndex(index: usize) i32 {
    return @intCast(index % settings.field_width);
}

fn getYFromIndex(index: usize) i32 {
    var idx: i32 = @intCast(index);
    return @divFloor(idx, settings.field_width);
}

fn getIndexFromXY(x: i32, y: i32) usize {
    return @intCast(y * settings.field_width + x);
}

fn updateAndRenderGameOver(input: Input, renderer: *SDL.Renderer, render_data: RenderData, text_size: SDL.Size, texture: *SDL.Texture) !GameState {
    try renderer.setColor(settings.background_color);
    try renderer.clear();
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rect.width = text_size.width;
    rect.height = text_size.height;
    rect.x = render_data.start_render_x + @divFloor((render_data.render_size - rect.width), 2);
    rect.y = render_data.start_render_y + @divFloor((render_data.render_size - rect.height), 2);
    try renderer.copy(texture.*, rect, null);
    renderer.present();
    if (input != Input.none) {
        return GameState.quit;
    }
    return GameState.over;
}

fn updateAndRenderPaused(input: Input, renderer: *SDL.Renderer, render_data: RenderData, text_size: SDL.Size, texture: *SDL.Texture) !GameState {
    try renderer.setColor(settings.background_color);
    try renderer.clear();
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rect.width = text_size.width;
    rect.height = text_size.height;
    rect.x = render_data.start_render_x + @divFloor((render_data.render_size - rect.width), 2);
    rect.y = render_data.start_render_y + @divFloor((render_data.render_size - rect.height), 2);
    try renderer.copy(texture.*, rect, null);
    renderer.present();
    if (input == Input.paused) {
        return GameState.playing;
    }
    return GameState.paused;
}

fn updateAndRenderGame(time: u32, state: *GameStateData, rand: *std.rand.Xoshiro256, render_data: RenderData, renderer: *SDL.Renderer) !GameState {
    var grow_snake = false;
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    switch (state.input) {
        .paused => return GameState.paused,
        .cancel => return GameState.over,
        .up => if (state.snake_last_moved_dir != Direction.down) {
            state.snake_dir = Direction.up;
        },
        .left => if (state.snake_last_moved_dir != Direction.right) {
            state.snake_dir = Direction.left;
        },
        .down => if (state.snake_last_moved_dir != Direction.up) {
            state.snake_dir = Direction.down;
        },
        .right => if (state.snake_last_moved_dir != Direction.left) {
            state.snake_dir = Direction.right;
        },
        else => {},
    }

    if (time >= state.next_step_time) {
        state.next_step_time = time + settings.step_time;
        //  move snake head
        var head_pos = state.snakeHeadPos();
        switch (state.snake_dir) {
            .up => head_pos.y -= 1,
            .down => head_pos.y += 1,
            .left => head_pos.x -= 1,
            .right => head_pos.x += 1,
        }
        if (head_pos.x < 0 or head_pos.x > settings.field_width - 1 or head_pos.y < 0 or head_pos.y > settings.field_height - 1) {
            return GameState.over;
        }

        //  check collision
        var snake_start_idx = getIndexFromXY(head_pos.x, head_pos.y);
        switch (state.field[snake_start_idx]) {
            FieldState.snake => return GameState.over,
            FieldState.apple => {
                grow_snake = true;
                state.score += 1;
                var rand_index: usize = rand.random().intRangeAtMost(usize, 0, settings.play_area_size - 1);
                while (state.field[rand_index] != FieldState.empty) {
                    rand_index = rand.random().intRangeAtMost(usize, 0, settings.play_area_size - 1);
                }
                state.field[rand_index] = FieldState.apple;
            },
            else => {},
        }
        var snake_tail_idx: usize = state.snake[0];
        // update snake in field
        state.field[snake_start_idx] = FieldState.snake;
        state.field[snake_tail_idx] = FieldState.empty;
        // update the in memory representation of the snake
        state.advanceSnake(grow_snake, snake_start_idx);
        state.snake_last_moved_dir = state.snake_dir;
    }

    //  Render

    rect.width = render_data.render_chunk_size_x;
    rect.height = render_data.render_chunk_size_y;

    try renderer.setColor(settings.border_color);
    try renderer.clear();
    for (state.field, 0..) |value, idx| {
        var index: usize = idx;
        rect.x = getXFromIndex(index) * render_data.render_chunk_size_x + render_data.start_render_x;
        rect.y = getYFromIndex(index) * render_data.render_chunk_size_y + render_data.start_render_y;
        if (value == FieldState.snake) {
            try renderer.setColor(settings.snake_color);
        } else if (value == FieldState.apple) {
            try renderer.setColor(settings.apple_color);
        } else {
            try renderer.setColor(settings.background_color);
        }
        try renderer.fillRect(rect);
    }

    renderer.present();
    return GameState.playing;
}

fn generateRenderData(data: *RenderData, window: *SDL.Window) void {
    var size = window.getSize();
    data.render_size = @min(size.width, size.height);
    data.start_render_x = @divFloor((size.width - data.render_size), 2);
    data.start_render_y = @divFloor((size.height - data.render_size), 2);
    data.render_chunk_size_x = @divFloor(data.render_size, settings.field_width);
    data.render_chunk_size_y = @divFloor(data.render_size, settings.field_height);
}

fn printAllocStringToTexture(allocator: std.mem.Allocator, renderer: SDL.Renderer, comptime str: []const u8, font: SDL.ttf.Font, args: anytype) !PrintStringToTextureReturn {
    var string_slice = try std.fmt.allocPrintZ(allocator, str, args);
    var size = try font.sizeText(string_slice);
    defer std.heap.page_allocator.free(string_slice);
    var sfc = try font.renderTextSolid(string_slice, settings.font_color);
    defer sfc.destroy();
    var texture = try SDL.createTextureFromSurface(renderer, sfc);
    return PrintStringToTextureReturn{ .texture = texture, .size = size };
}

pub fn main() !void {
    if (settings.play_area_size > snake_empty) {
        @panic("play area size is too large. Please reduce the field_width or field_height");
    }
    try SDL.init(.{ .timer = true, .audio = true, .video = true, .events = true });
    defer SDL.quit();
    try SDL.ttf.init();
    defer SDL.ttf.quit();

    var font = try SDL.ttf.openFont("/usr/share/fonts/truetype/ubuntu/Ubuntu-M.ttf", 24);
    defer font.close();

    var window = try SDL.createWindow(
        "Snake",
        .{ .centered = {} },
        .{ .centered = {} },
        640,
        480,
        .{ .vis = .shown },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    var time: u32 = SDL.getTicks();
    defer renderer.destroy();
    var rand = settings.RandGen.init(@intCast(std.time.timestamp()));
    //  initialize game state

    var play_area: [settings.play_area_size]FieldState = undefined;
    for (0..play_area.len) |idx| {
        play_area[idx] = FieldState.empty;
    }
    var snake: [settings.play_area_size]usize = undefined;
    for (0..snake.len) |idx| {
        snake[idx] = snake_empty;
    }
    var play_area_center_x = settings.field_width / 2;
    var play_area_center_y = settings.field_height / 2;
    var snake_index = getIndexFromXY(play_area_center_x, play_area_center_y);
    snake[0] = snake_index;
    var state = GameStateData{ .score = 0, .field = &play_area, .snake_dir = Direction.up, .snake_last_moved_dir = Direction.up, .snake = &snake, .snake_head_idx = 0, .state = GameState.playing, .next_step_time = time + settings.step_time, .input = Input.none };

    state.field[snake_index] = FieldState.snake;

    var apple_index =
        getIndexFromXY(
        rand.random().intRangeAtMost(i32, 0, settings.field_width - 1),
        rand.random().intRangeAtMost(i32, 0, settings.field_height - 1),
    );
    if (apple_index == snake_index) {
        apple_index += 1;
    }
    if (apple_index >= settings.play_area_size) {
        apple_index = 0;
    }
    state.field[apple_index] = FieldState.apple;

    var game_over_texture: ?SDL.Texture = null;
    var game_over_text_size: SDL.Size = undefined;
    var render_data = RenderData{ .render_size = 0, .start_render_x = 0, .start_render_y = 0, .render_chunk_size_x = 0, .render_chunk_size_y = 0 };

    var pause_message_texture_data = try printAllocStringToTexture(std.heap.page_allocator, renderer, "The game is paused. Press p to resume play", font, .{});

    mainLoop: while (true) {
        //  input
        state.input = Input.none;
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_down => |key| {
                    state.input = switch (key.scancode) {
                        .q => Input.cancel,
                        .w, .up => Input.up,
                        .a, .left => Input.left,
                        .s, .down => Input.down,
                        .d, .right => Input.right,
                        .p => Input.paused,
                        else => Input.any,
                    };
                },
                else => {},
            }
        }

        //  update
        time = SDL.getTicks();
        generateRenderData(&render_data, &window);
        state.state = switch (state.state) {
            GameState.playing => try updateAndRenderGame(time, &state, &rand, render_data, &renderer),
            GameState.over => ovr: {
                if (game_over_texture == null) {
                    var printed_texture = try printAllocStringToTexture(std.heap.page_allocator, renderer, "Game over. Final score: {d} points", font, .{state.score});
                    game_over_texture = printed_texture.texture;
                    game_over_text_size = printed_texture.size;
                    state.input = Input.none;
                }
                break :ovr try updateAndRenderGameOver(state.input, &renderer, render_data, game_over_text_size, &game_over_texture.?);
            },
            GameState.paused => try updateAndRenderPaused(state.input, &renderer, render_data, pause_message_texture_data.size, &pause_message_texture_data.texture),
            else => break :mainLoop,
        };
    }
}

test "expect getXFromIndex to get correct X" {
    try std.testing.expect(getXFromIndex(33) == 3);
}

test "expect getYFromIndex to get correct Y" {
    try std.testing.expect(getYFromIndex(33) == 1);
}
