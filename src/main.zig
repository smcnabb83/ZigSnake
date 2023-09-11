const std = @import("std");
const SDL = @import("sdl2");
const settings = @import("./constants.zig");

const Pos = struct {
    x: i32,
    y: i32,
};

const FieldState = enum { empty, snake, apple };
const Direction = enum { up, down, left, right };
const GameState = enum { start, playing, over, quit, paused };
const Input = enum { left, right, up, down, paused, select, cancel, any, none };

const PrintStringToTextureReturn = struct { texture: SDL.Texture, size: SDL.Size };

const GameStateData = struct {
    snake_dir: Direction,
    snake_last_moved_dir: Direction,
    snake_head_idx: usize,
    input: Input,
    state: GameState,
    score: i32,
    nextStepTime: u32,
    field: []FieldState,
    snake: []usize,
    fn AdvanceSnake(self: *GameStateData, growSnake: bool, newHead: usize) void {
        var endIdx: usize = 0;
        for (0..self.snake.len - 1) |idx| {
            if (!growSnake) {
                self.snake[idx] = self.snake[idx + 1];
            }
            if (self.snake[idx] == std.math.maxInt(usize)) {
                endIdx = idx;
                break;
            }
        }
        self.snake[endIdx] = newHead;
        self.snake_head_idx = endIdx;
    }
    fn SnakeHeadPos(self: *GameStateData) Pos {
        var snakeHeadIdx = self.snake[self.snake_head_idx];
        return Pos{ .x = getXFromIndex(snakeHeadIdx), .y = getYFromIndex(snakeHeadIdx) };
    }
};

const RenderData = struct {
    startRenderX: i32,
    startRenderY: i32,
    renderChunkSizeX: i32,
    renderChunkSizeY: i32,
    renderSize: i32,
};

fn getXFromIndex(index: usize) i32 {
    return @intCast(index % settings.play_area_x);
}

fn getYFromIndex(index: usize) i32 {
    var idx: i32 = @intCast(index);
    return @divFloor(idx, settings.play_area_x);
}

fn getIndexFromXY(x: i32, y: i32) usize {
    return @intCast(y * settings.play_area_x + x);
}

fn updateAndRenderGameOver(input: Input, renderer: *SDL.Renderer, renderData: RenderData, textSize: SDL.Size, texture: *SDL.Texture) !GameState {
    try renderer.setColor(settings.background_color);
    try renderer.clear();
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rect.width = textSize.width;
    rect.height = textSize.height;
    rect.x = renderData.startRenderX + @divFloor((renderData.renderSize - rect.width), 2);
    rect.y = renderData.startRenderY + @divFloor((renderData.renderSize - rect.height), 2);
    try renderer.copy(texture.*, rect, null);
    renderer.present();
    if (input != Input.none) {
        return GameState.quit;
    }
    return GameState.over;
}

fn updateAndRenderPaused(input: Input, renderer: *SDL.Renderer, renderData: RenderData, textSize: SDL.Size, texture: *SDL.Texture) !GameState {
    try renderer.setColor(settings.background_color);
    try renderer.clear();
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rect.width = textSize.width;
    rect.height = textSize.height;
    rect.x = renderData.startRenderX + @divFloor((renderData.renderSize - rect.width), 2);
    rect.y = renderData.startRenderY + @divFloor((renderData.renderSize - rect.height), 2);
    try renderer.copy(texture.*, rect, null);
    renderer.present();
    if (input == Input.paused) {
        return GameState.playing;
    }
    return GameState.paused;
}

fn updateAndRenderGame(time: u32, state: *GameStateData, rand: *std.rand.Xoshiro256, renderData: RenderData, renderer: *SDL.Renderer) !GameState {
    var growSnake = false;
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

    if (time >= state.nextStepTime) {
        state.nextStepTime = time + settings.step_time;
        //  move snake head
        var headPos = state.SnakeHeadPos();
        switch (state.snake_dir) {
            .up => headPos.y -= 1,
            .down => headPos.y += 1,
            .left => headPos.x -= 1,
            .right => headPos.x += 1,
        }
        if (headPos.x < 0 or headPos.x > settings.play_area_x - 1 or headPos.y < 0 or headPos.y > settings.play_area_y - 1) {
            return GameState.over;
        }

        //  check collision
        var snake_start_idx = getIndexFromXY(headPos.x, headPos.y);
        switch (state.field[snake_start_idx]) {
            FieldState.snake => return GameState.over,
            FieldState.apple => {
                growSnake = true;
                state.score += 1;
                var randIndex: usize = rand.random().intRangeAtMost(usize, 0, settings.play_area_size - 1);
                while (state.field[randIndex] != FieldState.empty) {
                    randIndex = rand.random().intRangeAtMost(usize, 0, settings.play_area_size - 1);
                }
                state.field[randIndex] = FieldState.apple;
            },
            else => {},
        }
        state.field[snake_start_idx] = FieldState.snake;
        var snake_tail_idx: usize = @intCast(state.snake[0]);
        state.field[snake_tail_idx] = FieldState.empty;
        state.AdvanceSnake(growSnake, @intCast(snake_start_idx));
        state.snake_last_moved_dir = state.snake_dir;
    }

    //  Render

    rect.width = renderData.renderChunkSizeX;
    rect.height = renderData.renderChunkSizeY;

    try renderer.setColor(settings.border_color);
    try renderer.clear();
    for (state.field, 0..) |value, idx| {
        var index: usize = idx;
        rect.x = getXFromIndex(index) * renderData.renderChunkSizeX + renderData.startRenderX;
        rect.y = getYFromIndex(index) * renderData.renderChunkSizeY + renderData.startRenderY;
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
    data.renderSize = @min(size.width, size.height);
    data.startRenderX = @divFloor((size.width - data.renderSize), 2);
    data.startRenderY = @divFloor((size.height - data.renderSize), 2);
    data.renderChunkSizeX = @divFloor(data.renderSize, settings.play_area_x);
    data.renderChunkSizeY = @divFloor(data.renderSize, settings.play_area_y);
}

fn printAllocStringToTexture(allocator: std.mem.Allocator, renderer: SDL.Renderer, comptime str: []const u8, font: SDL.ttf.Font, args: anytype) !PrintStringToTextureReturn {
    var strSlice = try std.fmt.allocPrintZ(allocator, str, args);
    var size = try font.sizeText(strSlice);
    defer std.heap.page_allocator.free(strSlice);
    var sfc = try font.renderTextSolid(strSlice, settings.font_color);
    defer sfc.destroy();
    var texture = try SDL.createTextureFromSurface(renderer, sfc);
    return PrintStringToTextureReturn{ .texture = texture, .size = size };
}

pub fn main() !void {
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

    var playArea: [settings.play_area_size]FieldState = undefined;
    for (0..playArea.len) |idx| {
        playArea[idx] = FieldState.empty;
    }
    var snake: [settings.play_area_size]usize = undefined;
    for (0..snake.len) |idx| {
        snake[idx] = std.math.maxInt(usize);
    }
    var play_area_center_x = @divFloor(settings.play_area_x, 2);
    var play_area_center_y = @divFloor(settings.play_area_y, 2);
    var snake_index: usize = @intCast(getIndexFromXY(play_area_center_x, play_area_center_y));
    snake[0] = @intCast(snake_index);
    var state = GameStateData{ .score = 0, .field = &playArea, .snake_dir = Direction.up, .snake_last_moved_dir = Direction.up, .snake = &snake, .snake_head_idx = 0, .state = GameState.playing, .nextStepTime = time + settings.step_time, .input = Input.none };

    state.field[snake_index] = FieldState.snake;

    var apple_index =
        getIndexFromXY(
        rand.random().intRangeAtMost(i32, 0, settings.play_area_x - 1),
        rand.random().intRangeAtMost(i32, 0, settings.play_area_y - 1),
    );
    if (apple_index == snake_index) {
        apple_index += 1;
    }
    if (apple_index >= settings.play_area_size) {
        apple_index = 0;
    }
    state.field[apple_index] = FieldState.apple;

    var gameOverTexture: ?SDL.Texture = null;
    var gameOverTextSize: SDL.Size = undefined;
    var renderData = RenderData{ .renderSize = 0, .startRenderX = 0, .startRenderY = 0, .renderChunkSizeX = 0, .renderChunkSizeY = 0 };

    var pauseMessageTextureData = try printAllocStringToTexture(std.heap.page_allocator, renderer, "The game is paused. Press p to resume play", font, .{});

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
        generateRenderData(&renderData, &window);
        state.state = switch (state.state) {
            GameState.playing => try updateAndRenderGame(time, &state, &rand, renderData, &renderer),
            GameState.over => ovr: {
                if (gameOverTexture == null) {
                    var printedTexture = try printAllocStringToTexture(std.heap.page_allocator, renderer, "Game over. Final score: {d} points", font, .{state.score});
                    gameOverTexture = printedTexture.texture;
                    gameOverTextSize = printedTexture.size;
                    state.input = Input.none;
                }
                break :ovr try updateAndRenderGameOver(state.input, &renderer, renderData, gameOverTextSize, &gameOverTexture.?);
            },
            GameState.paused => try updateAndRenderPaused(state.input, &renderer, renderData, pauseMessageTextureData.size, &pauseMessageTextureData.texture),
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
