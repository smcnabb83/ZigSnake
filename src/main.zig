const std = @import("std");
const SDL = @import("sdl2");

const play_area_x: i32 = 30;
const play_area_y: i32 = 30;

const Pos = struct {
    x: i32,
    y: i32,
};

const RandGen = std.rand.DefaultPrng;
const Direction = enum { up, down, left, right };
const GameState = enum { start, playing, over, quit };
const Input = enum { left, right, up, down, select, cancel, any };

const GameStateData = struct {
    snake_dir: Direction,
    snake_last_moved_dir: Direction,
    snake_head_idx: usize,
    state: GameState,
    score: i32,
    nextStepTime: u32,
    field: [play_area_x * play_area_y]i32,
    snake: [play_area_x * play_area_y]i32,
    fn AdvanceSnake(self: *GameStateData, growSnake: bool, newHead: i32) void {
        var endIdx: usize = 0;
        for (0..play_area_x * play_area_y) |idx| {
            if (!growSnake) {
                self.snake[idx] = self.snake[idx + 1];
            }
            if (self.snake[idx] == -1) {
                endIdx = idx;
                break;
            }
        }
        self.snake[endIdx] = newHead;
        self.snake_head_idx = endIdx;
    }
    fn SnakeHeadPos(self: *GameStateData) Pos {
        var snakeHeadIdx: usize = @intCast(self.snake[self.snake_head_idx]);
        return Pos{ .x = getXFromIndex(snakeHeadIdx), .y = getYFromIndex(snakeHeadIdx) };
    }
};

fn getXFromIndex(index: usize) i32 {
    return @intCast(index % play_area_x);
}

fn getYFromIndex(index: usize) i32 {
    var idx: i32 = @intCast(index);
    return @divFloor(idx, play_area_x);
}

fn getIndexFromXY(x: i32, y: i32) usize {
    return @intCast(y * play_area_x + x);
}

fn updateAndRenderGameOver(input: ?Input, renderer: *SDL.Renderer, state: *GameStateData, font: SDL.ttf.Font, startRenderX: i32, startRenderY: i32, renderSize: i32) !GameState {
    try renderer.setColorRGB(0, 0, 0);
    try renderer.clear();
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var messageSlice = try std.fmt.allocPrintZ(std.heap.page_allocator, "Game over. Final score: {d} points", .{state.score});
    defer std.heap.page_allocator.free(messageSlice);
    var fontColor = SDL.Color{ .r = 255, .b = 255, .g = 255, .a = 255 };
    var gameOverMessageSurface = try font.renderTextSolid(messageSlice, fontColor);
    var textSize = try font.sizeText(messageSlice);
    rect.x = startRenderX + @divFloor((renderSize - textSize.width), 2);
    rect.y = startRenderY + @divFloor((renderSize - textSize.height), 2);
    rect.width = textSize.width;
    rect.height = textSize.height;
    var gameOverMessageTexture = try SDL.createTextureFromSurface(renderer.*, gameOverMessageSurface);
    try renderer.copy(gameOverMessageTexture, rect, null);
    renderer.present();
    if (input != null) {
        return GameState.quit;
    }
    return GameState.over;
}

fn updateAndRenderGame(time: u32, input: ?Input, state: *GameStateData, stepTime: u32, rand: *std.rand.Xoshiro256, renderSize: i32, startRenderX: i32, startRenderY: i32, renderer: *SDL.Renderer) !GameState {
    var growSnake = false;
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    if (input != null) {
        switch (input.?) {
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
    }

    if (time >= state.nextStepTime) {
        state.nextStepTime = time + stepTime;
        //  move snake head
        var headPos = state.SnakeHeadPos();
        switch (state.snake_dir) {
            .up => headPos.y -= 1,
            .down => headPos.y += 1,
            .left => headPos.x -= 1,
            .right => headPos.x += 1,
        }
        if (headPos.x < 0 or headPos.x > play_area_x - 1 or headPos.y < 0 or headPos.y > play_area_y - 1) {
            return GameState.over;
        }

        //  check collision
        var snake_start_idx = getIndexFromXY(headPos.x, headPos.y);
        switch (state.field[snake_start_idx]) {
            1 => return GameState.over,
            2 => {
                growSnake = true;
                state.score += 1;
                var randIndex: usize = rand.random().intRangeAtMost(usize, 0, 900);
                while (state.field[randIndex] != 0) {
                    randIndex = rand.random().intRangeAtMost(usize, 0, 900);
                }
                state.field[randIndex] = 2;
            },
            else => {},
        }
        state.field[snake_start_idx] = 1;
        var snake_tail_idx: usize = @intCast(state.snake[0]);
        state.field[snake_tail_idx] = 0;
        state.AdvanceSnake(growSnake, @intCast(snake_start_idx));
        state.snake_last_moved_dir = state.snake_dir;
    }

    //  Render
    var renderChunkSizeX = @divFloor(renderSize, play_area_x);
    var renderChunkSizeY = @divFloor(renderSize, play_area_y);
    rect.width = renderChunkSizeX;
    rect.height = renderChunkSizeY;

    try renderer.setColorRGB(0, 0, 100);
    try renderer.clear();
    for (state.field, 0..) |value, idx| {
        var index: usize = idx;
        rect.x = getXFromIndex(index) * renderChunkSizeX + startRenderX;
        rect.y = getYFromIndex(index) * renderChunkSizeY + startRenderY;
        if (value == 1) {
            try renderer.setColorRGB(0, 200, 0);
        } else if (value == 2) {
            try renderer.setColorRGB(200, 0, 0);
        } else {
            try renderer.setColorRGB(0, 0, 0);
        }
        try renderer.fillRect(rect);
    }

    renderer.present();
    return GameState.playing;
}

pub fn main() !void {
    try SDL.init(.{ .timer = true, .audio = true, .video = true, .events = true });
    defer SDL.quit();
    try SDL.ttf.init();
    defer SDL.ttf.quit();

    var font = try SDL.ttf.openFont("/usr/share/fonts/truetype/ubuntu/Ubuntu-L.ttf", 24);
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
    var stepTime: u32 = 150;
    var time: u32 = SDL.getTicks();
    defer renderer.destroy();
    var rand = RandGen.init(@intCast(std.time.timestamp()));
    //  initialize game state

    var playArea: [play_area_x * play_area_y]i32 = undefined;
    for (0..playArea.len) |idx| {
        playArea[idx] = 0;
    }
    var snake: [play_area_x * play_area_y]i32 = undefined;
    for (0..snake.len) |idx| {
        snake[idx] = -1;
    }
    snake[0] = @intCast(getIndexFromXY(15, 15));
    var state = GameStateData{ .score = 0, .field = playArea, .snake_dir = Direction.up, .snake_last_moved_dir = Direction.up, .snake = snake, .snake_head_idx = 0, .state = GameState.playing, .nextStepTime = time + stepTime };

    state.field[
        getIndexFromXY(
            15,
            15,
        )
    ] = 1;

    state.field[
        getIndexFromXY(
            rand.random().intRangeAtMost(i32, 0, 14),
            rand.random().intRangeAtMost(i32, 0, 14),
        )
    ] = 2;

    var size = window.getSize();
    var renderSize: i32 = @min(size.width, size.height);
    var startRenderX: i32 = @divFloor((size.width - renderSize), 2);
    var startRenderY: i32 = @divFloor((size.height - renderSize), 2);
    var renderChunkSizeX: i32 = @divFloor(renderSize, play_area_x);
    var renderChunkSizeY: i32 = @divFloor(renderSize, play_area_y);
    var rect = SDL.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var input: ?Input = null;

    mainLoop: while (true) {
        //  input
        input = null;
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_down => |key| {
                    input = switch (key.scancode) {
                        .q => Input.cancel,
                        .w, .up => Input.up,
                        .a, .left => Input.left,
                        .s, .down => Input.down,
                        .d, .right => Input.right,
                        else => Input.any,
                    };
                },
                else => {},
            }
        }

        //  update
        time = SDL.getTicks();
        size = window.getSize();
        renderSize = @min(size.width, size.height);
        startRenderX = @divFloor((size.width - renderSize), 2);
        startRenderY = @divFloor((size.height - renderSize), 2);
        renderChunkSizeX = @divFloor(renderSize, play_area_x);
        renderChunkSizeY = @divFloor(renderSize, play_area_y);
        rect.width = renderChunkSizeX;
        rect.height = renderChunkSizeY;
        state.state = switch (state.state) {
            GameState.playing => try updateAndRenderGame(time, input, &state, stepTime, &rand, renderSize, startRenderX, startRenderY, &renderer),
            GameState.over => try updateAndRenderGameOver(input, &renderer, &state, font, startRenderX, startRenderY, renderSize),
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
