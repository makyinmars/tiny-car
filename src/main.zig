const rl = @import("raylib");
const std = @import("std");

// Define Car struct
const Car = struct {
    texture: rl.Texture2D,
    position: rl.Vector2,
    speed: i32,
};

// Define screen dimensions
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

pub fn main() anyerror!void {

    // Initialize window
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car Game");
    defer rl.closeWindow(); // Ensure window is closed when function exits

    rl.setTargetFPS(60); // Set target frame rate

    // Load car texture
    const carTexture = rl.loadTexture("resources/textures/car.png");
    defer rl.unloadTexture(carTexture);

    // // Initialize player car
    var car = Car{ .texture = carTexture, .position = rl.Vector2{
        .x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carTexture.width)) / 2,
        .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) * 3 / 5,
    }, .speed = 2 };

    try std.io.getStdOut().writer().print("Car {any}/n", .{car});
    const speedMovement = 4;

    // Load trees texture
    const treesTexture = rl.loadTexture("resources/textures/trees.png");
    defer rl.unloadTexture(treesTexture);

    // Define source rectangles for trees
    var sourceRects = [_]rl.Rectangle{.{
        .width = 48,
        .height = 48,
        .x = 0,
        .y = 0,
    }} ** 3;
    for (&sourceRects, 0..) |*rect, i| {
        rect.x = @as(f32, @floatFromInt(i)) * rect.width;
    }

    // Randomize positions of trees
    const treesNum = rl.getRandomValue(10, 27);
    var treesPos = try std.ArrayList(rl.Vector2).initCapacity(std.heap.page_allocator, @intCast(treesNum));
    defer treesPos.deinit();

    var i: usize = 0;

    while (i < treesNum) : (i += 1) {
        var pos = rl.Vector2{ .x = if (i < @divFloor(treesNum, 2))
            @as(f32, @floatFromInt(rl.getRandomValue(1, SCREEN_WIDTH / 3)))
        else
            @as(f32, @floatFromInt(rl.getRandomValue(2 * SCREEN_WIDTH / 3, SCREEN_WIDTH))), .y = @as(f32, @floatFromInt(rl.getRandomValue(0, SCREEN_HEIGHT - @as(i32, treesTexture.height)))) };

        // Adjust tree position if it's too close to the edge
        if (i < @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        } else if (i >= @divFloor(treesNum, 2) and pos.x + @as(f32, @floatFromInt(treesTexture.width)) / 3 > @as(f32, @floatFromInt(SCREEN_WIDTH))) {
            pos.x -= @as(f32, @floatFromInt(treesTexture.width)) / 3;
        }

        try treesPos.append(pos);
    }

    // // Load cars texture
    const carsTextures = rl.loadTexture("resources/textures/cars.png");
    defer rl.unloadTexture(carsTextures);

    // Define source rectangles for cars
    var sourcesRectsCars: [6]rl.Rectangle = [_]rl.Rectangle{.{ .width = 16, .height = 24, .x = 0, .y = 0 }} ** 6;
    var carsPos: [6]rl.Vector2 = [_]rl.Vector2{.{ .x = 0, .y = 0 }} ** 6;
    var carsSpeed: [6]f32 = [_]f32{0} ** 6;

    // Initialize random number generator
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = prng.random();

    // Initialize cars positions and speeds
    for (&sourcesRectsCars, 0..) |*rect, j| {
        rect.x = @as(f32, @floatFromInt(j)) * rect.width;

        const randomNumber = rand.intRangeAtMost(u8, 1, 3);
        carsPos[j].x = switch (randomNumber) {
            1 => @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 + @as(f32, @floatFromInt(SCREEN_WIDTH)) / 18 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
            2 => @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
            else => @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3 - @as(f32, @floatFromInt(SCREEN_WIDTH)) / 18 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
        };

        carsPos[j].y = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 0, SCREEN_HEIGHT - @as(i32, carsTextures.height))));
        carsSpeed[j] = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
    }

    // Define rectangle covering the entire screen
    const rmuteScreen = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(SCREEN_WIDTH)),
        .height = @as(f32, @floatFromInt(SCREEN_HEIGHT)),
    };

    // Initialize game state variables
    var lives: i32 = 9;
    var score: i32 = 0;
    var time: f64 = 0;
    var vulnerableTime: f64 = 0;
    var gaveOver: bool = false;
    var gameWon: bool = false;
    var vulnerable: bool = true;

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update game state
        if (!gaveOver) {
            // Handle player input
            if (rl.isKeyDown(rl.KeyboardKey.key_h)) {
                car.position.x -= @as(f32, @floatFromInt(car.speed));
            } else if (rl.isKeyDown(rl.KeyboardKey.key_l)) {
                car.position.x += @as(f32, @floatFromInt(car.speed));
            } else if (rl.isKeyDown(rl.KeyboardKey.key_k)) {
                car.position.y -= @as(f32, @floatFromInt(car.speed));
            } else if (rl.isKeyDown(rl.KeyboardKey.key_j)) {
                car.position.y += @as(f32, @floatFromInt(car.speed));
            }

            // Update trees positions
            for (treesPos.items) |*treePos| {
                treePos.y += @as(f32, @floatFromInt(car.speed));
                if (treePos.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) {
                    treePos.y = -@as(f32, @floatFromInt(treesTexture.height));
                }
            }

            // Update other cars positions and check for collisions
            for (&carsPos, 0..) |*carPos, k| {
                carPos.y += carsSpeed[k];

                if (carPos.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) {
                    carPos.y = -@as(f32, @floatFromInt(carsTextures.height));

                    const randomNumber = rand.intRangeAtMost(u8, 1, 3);
                    carPos.x = switch (randomNumber) {
                        1 => @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 + @as(f32, @floatFromInt(SCREEN_WIDTH)) / 18 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
                        2 => @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
                        else => @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3 - @as(f32, @floatFromInt(SCREEN_WIDTH)) / 18 - @as(f32, @floatFromInt(carsTextures.width)) / 12,
                    };

                    carsSpeed[k] = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
                }

                // Check for collision between player car and other cars
                const rec1 = rl.Rectangle{
                    .x = car.position.x,
                    .y = car.position.y,
                    .width = @floatFromInt(car.texture.width),
                    .height = @floatFromInt(car.texture.height),
                };

                const rec2 = rl.Rectangle{
                    .x = carPos.x,
                    .y = carPos.y,
                    .width = @as(f32, @floatFromInt(carsTextures.width)) / 6,
                    .height = @floatFromInt(carsTextures.height),
                };

                if (rl.checkCollisionRecs(rec1, rec2)) {
                    if (vulnerable) {
                        lives -= 1;
                        vulnerable = false;
                    }
                    car.position.y -= @as(f32, @floatFromInt(car.texture.height)) - 10;
                }
            }

            // Handle vulnerability period after collision
            if (!vulnerable) {
                vulnerableTime += rl.getFrameTime();
                if (vulnerableTime > 1) {
                    vulnerable = true;
                    vulnerableTime = 0;
                }
            }

            // Check for game over condition
            if (lives < 0) {
                gaveOver = true;
            }

            // Adjust car speed based on position
            if (car.position.x < @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 or car.position.x + @as(f32, @floatFromInt(car.texture.width)) > @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3) {
                car.speed = speedMovement / 2;
            } else {
                car.speed = speedMovement;
            }

            // Update score
            time += rl.getFrameTime();
            if (time > 1) {
                score += 1;
                time = 0;
            }

            // Check for win condition
            if (score > 999) {
                gameWon = true;
                gaveOver = true;
            }
        }

        // Draw game elements
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        rl.drawTexture(carTexture, @divFloor(SCREEN_WIDTH, 2) - @divFloor(carTexture.width, 2), @divFloor(SCREEN_HEIGHT, 2) - @divFloor(carTexture.height, 2), rl.Color.white);

        // Draw background
        rl.drawRectangle(0, 0, @divFloor(SCREEN_WIDTH, 3), SCREEN_HEIGHT, rl.Color.green);
        rl.drawRectangle(@divFloor(SCREEN_WIDTH * 2, 3), 0, @divFloor(SCREEN_WIDTH, 3), SCREEN_HEIGHT, rl.Color.green);
        rl.drawRectangle(@divFloor(SCREEN_WIDTH, 3), 0, @divFloor(SCREEN_WIDTH, 3), SCREEN_HEIGHT, rl.Color.gray);
        rl.drawRectangle(@divFloor(SCREEN_WIDTH, 3) + @divFloor(SCREEN_WIDTH, 9) - 1, 0, 2, SCREEN_HEIGHT, rl.Color.black);
        rl.drawRectangle(@divFloor(SCREEN_WIDTH, 3) + @divFloor(SCREEN_WIDTH * 2, 9) - 1, 0, 2, SCREEN_HEIGHT, rl.Color.black);

        // Draw player car
        if (!vulnerable) {
            const col = rl.Color{
                .r = 0,
                .g = 0,
                .b = 0,
                .a = 0,
            };
            rl.drawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), col);
        } else {
            rl.drawTexture(car.texture, @intFromFloat(car.position.x), @intFromFloat(car.position.y), rl.Color.white);
        }

        // Draw other cars
        for (sourcesRectsCars, 0..) |sourceRectCar, m| {
            rl.drawTextureRec(carsTextures, sourceRectCar, carsPos[m], rl.Color.white);
        }

        // Draw trees
        for (treesPos.items, 0..) |treePos, n| {
            rl.drawTextureRec(treesTexture, sourceRects[n % 3], treePos, rl.Color.white);
        }

        rl.drawRectangle(10, 10, 100, 75, rl.Color.sky_blue.fade(0.9));
        rl.drawRectangleLines(10, 10, 100, 75, rl.Color.sky_blue.fade(0.9));

        rl.drawFPS(710, 10);
        rl.drawText("Game Stats", 20, 20, 10, rl.Color.black);

        var scoring: [20]u8 = undefined;
        const scoreText = try std.fmt.bufPrintZ(&scoring, "Score: {d}/100", .{score});
        rl.drawText(scoreText, 20, 40, 10, rl.Color.dark_gray);
        var livesScoring: [20]u8 = undefined;
        const livesText = try std.fmt.bufPrintZ(&livesScoring, "Lives: {d}/9", .{lives});
        rl.drawText(livesText, 20, 60, 10, rl.Color.dark_gray);

        // Draw game over screen
        if (gaveOver) {
            const color = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 };
            rl.drawRectangle(@intFromFloat(rmuteScreen.x), @intFromFloat(rmuteScreen.y), @intFromFloat(rmuteScreen.width), @intFromFloat(rmuteScreen.height), color);
            if (gameWon) {
                rl.drawText("You Won!!", @divFloor(SCREEN_WIDTH - rl.measureText("You Won!!", 90), 2), @divFloor(SCREEN_HEIGHT, 2) - 45, 90, rl.Color.white);
            } else {
                rl.drawText("Game Over!!", @divFloor(SCREEN_WIDTH - rl.measureText("Game Over!!", 90), 2), @divFloor(SCREEN_HEIGHT, 2) - 45, 90, rl.Color.white);
            }
        }
    }
}
