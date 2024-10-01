const rl = @import("raylib");
const std = @import("std");

// Define Car struct
const Car = struct {
    texture: rl.Texture2D,
    position: rl.Vector2,
    speed: i32,
};

// Define Pear struct
const Pear = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    lifetime: f32,
};

// Define screen dimensions
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

fn drawGrassTexture(texture: rl.Texture2D, offset: f32, side: enum { Left, Right }) void {
    const x = if (side == .Left) 0 else @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH * 2, 3)));
    rl.drawTextureRec(texture, rl.Rectangle{ .x = 0, .y = offset, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = @as(f32, @floatFromInt(SCREEN_HEIGHT)) }, rl.Vector2{ .x = x, .y = -offset }, rl.Color.white);
    rl.drawTextureRec(texture, rl.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(@divFloor(SCREEN_WIDTH, 3))), .height = offset }, rl.Vector2{ .x = x, .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) - offset }, rl.Color.white);
}

fn handleCarCollision(playerCar: *Car, otherCar: rl.Vector2, otherCarSize: rl.Vector2, vulnerable: *bool, lives: *i32, carCrash: rl.Sound, pears: *std.ArrayList(Pear), rand: std.Random) !void {
    const rec1 = rl.Rectangle{
        .x = playerCar.position.x,
        .y = playerCar.position.y,
        .width = @floatFromInt(playerCar.texture.width),
        .height = @floatFromInt(playerCar.texture.height),
    };

    const rec2 = rl.Rectangle{
        .x = otherCar.x,
        .y = otherCar.y,
        .width = otherCarSize.x,
        .height = otherCarSize.y,
    };

    if (rl.checkCollisionRecs(rec1, rec2)) {
        if (vulnerable.*) {
            lives.* -= 1;
            vulnerable.* = false;
            rl.playSound(carCrash);

            // Drop a pear at the collision location with random velocity
            try pears.append(Pear{
                .position = rl.Vector2{
                    .x = playerCar.position.x,
                    .y = playerCar.position.y,
                },
                .velocity = rl.Vector2{
                    .x = rand.float(f32) * 200 - 100, // Random x velocity between -100 and 100
                    .y = rand.float(f32) * 100 + 50, // Random y velocity between 50 and 150
                },
                .lifetime = 3.0, // 3 seconds lifetime
            });
        }
        playerCar.position.y -= @as(f32, @floatFromInt(playerCar.texture.height)) - 10;
    }
}

fn updateCarPosition(carPos: *rl.Vector2, carSpeed: *f32, rand: std.Random, carsTextures: rl.Texture2D) void {
    carPos.y += carSpeed.*;

    if (carPos.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) {
        carPos.y = -@as(f32, @floatFromInt(carsTextures.height));

        carPos.x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 +
            rand.float(f32) * @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3;

        carSpeed.* = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
    }
}

fn drawGameStats(score: i32, lives: i32) !void {
    rl.drawRectangle(10, 10, 100, 75, rl.Color.sky_blue.fade(0.9));
    rl.drawRectangleLines(10, 10, 100, 75, rl.Color.sky_blue.fade(0.9));

    rl.drawFPS(710, 10);
    rl.drawText("Game Stats", 20, 20, 10, rl.Color.black);

    var scoring: [20]u8 = undefined;
    const scoreText = try std.fmt.bufPrintZ(&scoring, "Score: {d}/1000", .{score});
    rl.drawText(scoreText, 20, 40, 10, rl.Color.dark_gray);
    var livesScoring: [20]u8 = undefined;
    const livesText = try std.fmt.bufPrintZ(&livesScoring, "Lives: {d}/9", .{lives});
    rl.drawText(livesText, 20, 60, 10, rl.Color.dark_gray);
}

fn updatePears(pears: *std.ArrayList(Pear), deltaTime: f32) !void {
    var i: usize = 0;
    while (i < pears.items.len) {
        var pear = &pears.items[i];
        pear.position.x += pear.velocity.x * deltaTime;
        pear.position.y += pear.velocity.y * deltaTime;
        pear.velocity.y += 500 * deltaTime; // Add gravity
        pear.lifetime -= deltaTime;

        if (pear.lifetime <= 0 or pear.position.y > SCREEN_HEIGHT) {
            _ = pears.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn main() anyerror!void {

    // Initialize window
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car Game");
    defer rl.closeWindow(); // Ensure window is closed when function exits

    // Initialize Audio
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60); // Set target frame rate

    // Load car texture
    const carTexture = rl.loadTexture("resources/textures/car.png");
    defer rl.unloadTexture(carTexture);

    // Load pear texture
    const pearTexture = rl.loadTexture("resources/textures/pear.png");
    defer rl.unloadTexture(pearTexture);

    // Initialize pears list
    var pears = std.ArrayList(Pear).init(std.heap.page_allocator);
    defer pears.deinit();

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

    // Load cars texture
    const carsTextures = rl.loadTexture("resources/textures/cars.png");
    defer rl.unloadTexture(carsTextures);

    // Load grass texture
    const grassTexture = rl.loadTexture("resources/textures/grass.png");
    defer rl.unloadTexture(grassTexture);

    // Variable to track grass scroll offset
    var grassScrollOffset: f32 = 0;

    // Load road texture
    const roadTexture = rl.loadTexture("resources/textures/road.png");
    defer rl.unloadTexture(roadTexture);

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

        carsPos[j].x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3 +
            rand.float(f32) * @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3;

        carsPos[j].y = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 0, SCREEN_HEIGHT - @as(i32, carsTextures.height))));
        carsSpeed[j] = @as(f32, @floatFromInt(rand.intRangeAtMost(i32, 6, 10)));
    }

    // Load audio
    const backgroundMusic = rl.loadMusicStream("resources/sound/speeding.mp3");
    defer rl.unloadMusicStream(backgroundMusic);

    const carBrake = rl.loadSound("resources/sound/brake.mp3");
    defer rl.unloadSound(carBrake);
    rl.setSoundVolume(carBrake, 0.3); // Set volume to 30%

    const carCrash = rl.loadSound("resources/sound/car-crash.mp3");
    defer rl.unloadSound(carCrash);
    rl.setSoundVolume(carCrash, 0.1); // Set volume to 30%

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

    rl.playMusicStream(backgroundMusic);

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update game state
        if (!gaveOver) {
            const deltaTime = rl.getFrameTime();

            // Update grass scroll offset
            grassScrollOffset += @as(f32, @floatFromInt(car.speed));
            if (grassScrollOffset >= @as(f32, @floatFromInt(grassTexture.height))) {
                grassScrollOffset -= @as(f32, @floatFromInt(grassTexture.height));
            }

            // Update pears
            try updatePears(&pears, deltaTime);

            // Handle player input
            if (rl.isKeyDown(rl.KeyboardKey.key_h)) {
                car.position.x = @max(car.position.x - @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) / 3);
            } else if (rl.isKeyDown(rl.KeyboardKey.key_l)) {
                car.position.x = @min(car.position.x + @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_WIDTH)) * 2 / 3 - @as(f32, @floatFromInt(car.texture.width)));
            } else if (rl.isKeyDown(rl.KeyboardKey.key_k)) {
                car.position.y = @max(car.position.y - @as(f32, @floatFromInt(car.speed)), 0);
            } else if (rl.isKeyDown(rl.KeyboardKey.key_j)) {
                rl.playSound(carBrake);
                car.position.y = @min(car.position.y + @as(f32, @floatFromInt(car.speed)), @as(f32, @floatFromInt(SCREEN_HEIGHT)) - @as(f32, @floatFromInt(car.texture.height)));
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
                updateCarPosition(carPos, &carsSpeed[k], rand, carsTextures);

                // Check if the player's car has passed the other cars
                if (car.position.y < carPos.y + @as(f32, @floatFromInt(carsTextures.height)) and car.position.y + @as(f32, @floatFromInt(car.texture.height)) > carPos.y + @as(f32, @floatFromInt(carsTextures.height))) {
                    // Player's car has passed this car
                    score += 1;
                }

                try handleCarCollision(&car, carPos.*, rl.Vector2{ .x = @as(f32, @floatFromInt(carsTextures.width)) / 6, .y = @floatFromInt(carsTextures.height) }, &vulnerable, &lives, carCrash, &pears, rand);
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

        // Play background music
        rl.updateMusicStream(backgroundMusic);

        // Draw game elements
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        rl.drawTexture(carTexture, @divFloor(SCREEN_WIDTH, 2) - @divFloor(carTexture.width, 2), @divFloor(SCREEN_HEIGHT, 2) - @divFloor(carTexture.height, 2), rl.Color.white);

        // Draw background

        // Draw grass textures
        drawGrassTexture(grassTexture, grassScrollOffset, .Left);
        drawGrassTexture(grassTexture, grassScrollOffset, .Right);

        // Draw road texture (middle)
        rl.drawRectangle(@divFloor(SCREEN_WIDTH, 3), 0, @divFloor(SCREEN_WIDTH, 3), SCREEN_HEIGHT, rl.Color.gray);

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

        // Draw pears
        for (pears.items) |pear| {
            const alpha = @as(u8, @intFromFloat(@min(pear.lifetime / 3.0, 1.0) * 255));
            const color = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };
            rl.drawTexture(pearTexture, @intFromFloat(pear.position.x), @intFromFloat(pear.position.y), color);
        }

        try drawGameStats(score, lives);

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
