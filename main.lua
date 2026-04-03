--[[
Main gameplay file.
This script wires together player movement, jumping, animation state,
platform spawning, and simple projectile shooting.
]]

-- Base sprite used to initialize player dimensions and default frame.
local SPRITE_PATH = "sprites/darla/walk/darlawalk-1.png"

--[[
Builds an ordered frame list from files named like "prefix1.png", "prefix2.png", etc.
Used for walk, jump, and shoot animation sequences.
]]
local function loadSequentialFrames(prefix, count)
    local frames = {}
    for i = 1, count do
        frames[i] = love.graphics.newImage(("%s%d.png"):format(prefix, i))
    end
    return frames
end

--[[
Platform generation config:
- count: how many floating platforms to spawn.
- width/height: rectangle size for each platform.
- color: RGB draw color for platform rectangles.
]]
local platformSettings = {
    count = 7,
    width = 200,
    height = 22,
    color = {1, 0, 0}
}

-- Runtime list of generated platforms.
local platforms = {}

--[[
Projectile config:
- maxActive: hard cap of concurrent shots on-screen.
- speed: horizontal velocity in pixels/second.
- radius: circle size for each projectile.
- color: RGB draw color for projectiles.
]]
local projectileSettings = {
    maxActive = 6,
    speed = 520,
    radius = 6,
    color = {1, 0, 0}
}

local rocketSettings = {
    frames = loadSequentialFrames("sprites/projectiles/rocket/rocket", 4),
    fps = 12
}
rocketSettings.frameDuration = 1 / rocketSettings.fps
rocketSettings.width = rocketSettings.frames[1]:getWidth()
rocketSettings.height = rocketSettings.frames[1]:getHeight()

-- Runtime list of active projectiles.
local projectiles = {}

--list of active powerups, currently unused but can be extended for pickup logic and effects.
local powerups = {}
--[[
Core player state:
- x/y: top-left world position.
- speed: horizontal move speed (A/D).
- sprite/width/height: currently drawn frame and visual bounds.
- direction/current: facing and animation state (stand/walk/jump/shoot).
- velocityY/jumpStrength/gravity/isJumping: vertical movement and jump physics.
- groundY: fallback ground position (window floor).
- actions: preloaded frame data grouped by action.
]]
local player = {
    x = 0,
    y = 0,
    speed = 220,
    sprite = nil,
    width = 64,
    height = 64,
    direction = "right",
    current = "stand",
    velocityY = 0,
    jumpStrength = 600,
    gravity = 900,
    isJumping = false,
    groundY = 0,
    actions = {
        walk = {
            animations = {
                stand = {
                    frames = {
                        love.graphics.newImage("sprites/darla/walk/darlawalk-1.png"),
                    }
                },
                walk = {
                    animation = {
                        frames = loadSequentialFrames("sprites/darla/walk/darlawalk-", 6)
                    }
                }
            }
        },
        jump = {
            animations = {
                jump = {
                    frames = loadSequentialFrames("sprites/darla/jump/darlajump-", 8)
                }
            }
        },
        shoot = {
            animations = {
                shoot = {
                    frames = loadSequentialFrames("sprites/darla/shoot/darlashoot-", 3)
                }
            }
        }
    },
    useRocketShots = false
}

-- Generates platform positions within screen bounds and above floor level.
local function loadPlatforms()
    platforms = {}
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local baseGround = player.groundY > 0 and player.groundY or (windowHeight - player.height)
    local minY = math.floor(windowHeight * 0.35)
    local maxY = math.floor(baseGround - platformSettings.height - 40)
    if maxY < minY then
        maxY = minY
    end

    local function overlaps(x, y, width, height)
        for _, platform in ipairs(platforms) do
            local horizontally = x < platform.x + platform.width and (x + width) > platform.x
            local vertically = y < platform.y + platform.height and (y + height) > platform.y
            if horizontally and vertically then
                return true
            end
        end
        return false
    end

    for _ = 1, platformSettings.count do
        local width = platformSettings.width
        local height = platformSettings.height
        local xMax = math.max(0, math.floor(windowWidth - width))

        local attempts = 0
        local placed = false
        while attempts < 40 and not placed do
            local x = math.random(0, xMax)
            local y = math.random(minY, maxY)
            if not overlaps(x, y, width, height) then
                platforms[#platforms + 1] = {x = x, y = y, width = width, height = height}
                placed = true
            else
                attempts = attempts + 1
            end
        end

        if not placed then
            -- Deterministic fallback: stack upwards until space is found.
            local fallbackY = minY
            local fallbackX = math.random(0, xMax)
            while overlaps(fallbackX, fallbackY, width, height) and fallbackY > 0 do
                fallbackY = fallbackY - (height + 10)
            end
            platforms[#platforms + 1] = {x = fallbackX, y = math.max(fallbackY, 0), width = width, height = height}
        end
    end
end

-- Creates one projectile traveling in the requested direction, respecting maxActive.
local function spawnProjectile(direction, useRocket)
    if #projectiles >= projectileSettings.maxActive then
        return
    end

    local dir = direction == "left" and -1 or 1
    local spawnX = dir == 1 and (player.x + player.width) or player.x
    local spawnY = player.y + player.height * 0.45
    useRocket = useRocket or false

    if useRocket then
        projectiles[#projectiles + 1] = {
            kind = "rocket",
            x = spawnX,
            y = spawnY,
            vx = projectileSettings.speed * dir,
            width = rocketSettings.width,
            height = rocketSettings.height,
            direction = direction,
            animationTime = 0
        }
    else
        projectiles[#projectiles + 1] = {
            kind = "bullet",
            x = spawnX,
            y = spawnY,
            vx = projectileSettings.speed * dir,
            radius = projectileSettings.radius
        }
    end
end

-- Moves projectiles every frame and removes any that leave screen horizontally.
local function updateProjectiles(dt)
    local windowWidth = love.graphics.getWidth()
    for i = #projectiles, 1, -1 do
        local projectile = projectiles[i]
        projectile.x = projectile.x + projectile.vx * dt
        if projectile.kind == "rocket" then
            projectile.animationTime = projectile.animationTime + dt
        end

        local remove = false
        if projectile.kind == "rocket" then
            local halfWidth = (projectile.width or rocketSettings.width) * 0.5
            local offLeft = projectile.x + halfWidth < 0
            local offRight = projectile.x - halfWidth > windowWidth
            remove = offLeft or offRight
        else
            local offLeft = projectile.x + projectile.radius < 0
            local offRight = projectile.x - projectile.radius > windowWidth
            remove = offLeft or offRight
        end

        if remove then
            table.remove(projectiles, i)
        end
    end
end

-- Love2D load hook: initialize random seed, player sprite sizing, start position, and platforms.
function love.load()
    math.randomseed(os.time())
    love.window.setTitle("Sprite Boilerplate")
    player.sprite = love.graphics.newImage(SPRITE_PATH)
    if love.filesystem.getInfo(SPRITE_PATH) then
        player.width = player.sprite:getWidth()
        player.height = player.sprite:getHeight()
    end

    local windowWidth, windowHeight = love.graphics.getDimensions()
    player.x = (windowWidth - player.width) * 0.5
    player.y = (windowHeight - player.height)
    player.groundY = player.y
    loadPlatforms()
end

--[[
Reads movement and shooting input, updates facing direction,
picks stand/walk/shoot animation state, and applies horizontal movement.
]]
local function handleMovement(dt)
    local horizontal = 0
    local moving = false
    local shootingLeft = love.keyboard.isDown("left")
    local shootingRight = love.keyboard.isDown("right")
    local shooting = shootingLeft or shootingRight
    local speedVar=1.0
    if love.keyboard.isDown("a") or love.keyboard.isDown("d") then
        if love.keyboard.isDown("a") then
            horizontal = horizontal - speedVar
            moving = true
            player.direction = "left"
        end

        if love.keyboard.isDown("d") then
            horizontal = horizontal + speedVar
            moving = true
            player.direction = "right"
        end
    end

    if not player.isJumping then
        if shooting then
            player.current = "shoot"
            if shootingLeft then
                player.direction = "left"
            else
                player.direction = "right"
            end
        else
            player.current = moving and "walk" or "stand"
        end
    end

    -- Horizontal movement integrates speed over frame delta time.
    player.x = player.x + horizontal * player.speed * dt

    -- Clamp to screen so the player cannot move out of view.
    local windowWidth = love.graphics.getWidth()
    local minX = 0
    local maxX = windowWidth - player.width
    if player.x < minX then
        player.x = minX
    elseif player.x > maxX then
        player.x = maxX
    end

    return moving
end

--[[
Checks vertical landing collisions against platforms and floor.
Returns whether a collision happened and the corrected Y position.
]]
local function collision(nextY)
    local ground = player.groundY or (love.graphics.getHeight() - player.height)
    local collided = false
    local resolvedY = nil

    local function setLanding(y)
        if not resolvedY or y < resolvedY then
            resolvedY = y
        end
        collided = true
    end

    if player.velocityY >= 0 then
        for _, platform in ipairs(platforms) do
            local withinX = player.x + player.width > platform.x and player.x < platform.x + platform.width
            local wasAbove = player.y + player.height <= platform.y + 1
            local willIntersect = nextY + player.height >= platform.y
            if withinX and wasAbove and willIntersect then
                setLanding(platform.y - player.height)
            end
        end
    end

    if nextY >= ground then
        setLanding(ground)
    end

    if collided then
        return true, resolvedY
    end

    return false, nextY
end

-- Applies jump/gravity and transitions between airborne and grounded states.
local function handleJump(dt, isMoving)
    player.groundY = love.graphics.getHeight() - player.height

    local function applyGravityStep()
        player.velocityY = player.velocityY + player.gravity * dt
        local nextY = player.y + player.velocityY * dt
        local hitGround, correctedY = collision(nextY)
        if hitGround then
            player.y = correctedY
            player.velocityY = 0
            player.isJumping = false
            player.current = isMoving and "walk" or "stand"
        else
            player.y = nextY
        end
    end

    if player.isJumping then
        applyGravityStep()
    else
        local onSurface, correctedY = collision(player.y)
        if onSurface then
            player.y = correctedY
        else
            player.isJumping = true
            player.velocityY = 0
            applyGravityStep()
        end
    end
end

-- Love2D update hook: run movement, jump physics, and projectile simulation.
function love.update(dt)
    local moving = handleMovement(dt)
    handleJump(dt, moving)
    updateProjectiles(dt)
end

-- Love2D keypress hook: jump with space, shoot with left/right arrows.
function love.keypressed(key)
    if key == "space" and not player.isJumping then
        player.isJumping = true
        player.velocityY = -player.jumpStrength
        player.current = "jump"
    elseif key == "left" or key == "right" then
        player.direction = key == "left" and "left" or "right"
        spawnProjectile(player.direction, player.useRocketShots)
    elseif key == "1" then
        player.useRocketShots = not player.useRocketShots
    end
end

--[[
Love2D draw hook:
1) draw platforms
2) choose and draw current player animation frame (mirrored for left-facing)
3) draw active projectiles as red circles
]]
function love.draw()
    love.graphics.setColor(platformSettings.color[1], platformSettings.color[2], platformSettings.color[3])
    for _, platform in ipairs(platforms) do
        love.graphics.rectangle("fill", math.floor(platform.x), math.floor(platform.y), platform.width, platform.height)
    end
    love.graphics.setColor(1, 1, 1)

    if player.sprite then
        if player.current == "walk" then
            local walkAnimation = player.actions.walk.animations.walk.animation
            local frameIndex = math.floor(love.timer.getTime() * 10) % #walkAnimation.frames + 1
            player.sprite = walkAnimation.frames[frameIndex]
        elseif player.current == "shoot" then
            local shootAnimation = player.actions.shoot.animations.shoot
            local frameIndex = math.floor(love.timer.getTime() * 14) % #shootAnimation.frames + 1
            player.sprite = shootAnimation.frames[frameIndex]
        elseif player.current == "jump" then
            local jumpAnimation = player.actions.jump.animations.jump
            local frameIndex = math.floor(love.timer.getTime() * 12) % #jumpAnimation.frames + 1
            player.sprite = jumpAnimation.frames[frameIndex]
        else
            player.sprite = player.actions.walk.animations.stand.frames[1]
        end

        local drawX = math.floor(player.x)
        local drawY = math.floor(player.y)
        if player.direction == "left" then
            love.graphics.draw(player.sprite, drawX + player.width, drawY, 0, -1, 1)
        else
            love.graphics.draw(player.sprite, drawX, drawY)
        end
    else
        -- Rectangle fallback if sprite loading fails.
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", math.floor(player.x), math.floor(player.y), player.width, player.height)
    end

    local modeLabel = player.useRocketShots and "Rocket" or "Normal"
    love.graphics.setColor(1, 1, 0)
    love.graphics.print(("Shots: %s"):format(modeLabel), 12, 12)
    love.graphics.setColor(1, 1, 1)

    for _, projectile in ipairs(projectiles) do
        if projectile.kind == "rocket" then
            local frameCount = #rocketSettings.frames
            local frameIndex = math.floor(projectile.animationTime / rocketSettings.frameDuration) % frameCount + 1
            local frame = rocketSettings.frames[frameIndex]
            local scaleX = projectile.direction == "left" and -1 or 1
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(
                frame,
                math.floor(projectile.x),
                math.floor(projectile.y),
                0,
                scaleX,
                1,
                frame:getWidth() * 0.5,
                frame:getHeight() * 0.5
            )
        else
            love.graphics.setColor(projectileSettings.color[1], projectileSettings.color[2], projectileSettings.color[3])
            love.graphics.circle("fill", math.floor(projectile.x), math.floor(projectile.y), projectile.radius)
        end
    end
    love.graphics.setColor(1, 1, 1)
end
