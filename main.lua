local SPRITE_PATH = "sprites/darla/walk/darlawalk-1.png"  -- Replace with your sprite path

-- Utility to build ordered frame lists for similarly named sprite sheets.
local function loadSequentialFrames(prefix, count)
    local frames = {}
    for i = 1, count do
        frames[i] = love.graphics.newImage(("%s%d.png"):format(prefix, i))
    end
    return frames
end

local platformSettings = {
    count = 4,
    width = 200,
    height = 22,
    color = {1, 0, 0}
}

local platforms = {}

-- Player state tracks position, motion speed, facing direction, and animation info.
-- Sprite dimensions default to 64x64 but will update to match the loaded asset.
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
    jumpStrength = 600, -- Integer knob that simultaneously governs jump speed and height.
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
        }
    }
}

local function loadPlatforms()
    platforms = {}
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local baseGround = player.groundY > 0 and player.groundY or (windowHeight - player.height)
    local minY = math.floor(windowHeight * 0.35)
    local maxY = math.floor(baseGround - platformSettings.height - 40)
    if maxY < minY then
        maxY = minY
    end

    for i = 1, platformSettings.count do
        local width = platformSettings.width
        local xMax = math.max(0, math.floor(windowWidth - width))
        local x = math.random(0, xMax)
        local y = math.random(minY, maxY)
        platforms[#platforms + 1] = {
            x = x,
            y = y,
            width = width,
            height = platformSettings.height
        }
    end
end

-- Initialize window title, load the main sprite, and place the player at the floor center.
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

-- Read A/D input to update direction, choose walk/stand states, and translate the player.
local function handleMovement(dt)
    local horizontal = 0
    local moving = false
    -- Capture whether either movement key is pressed and decide which animation should play.
    if love.keyboard.isDown("a") or love.keyboard.isDown("d") then
        if love.keyboard.isDown("a") then
            horizontal = horizontal - 1
            moving = true
            player.direction = "left"
        end

        if love.keyboard.isDown("d") then
            horizontal = horizontal + 1
            moving = true
            player.direction = "right"
        end
    end

    if not player.isJumping then
        player.current = moving and "walk" or "stand"
    end

    -- Apply horizontal velocity scaled by delta-time and the configured movement speed.
    player.x = player.x + horizontal * player.speed * dt

    -- Keep the player within the window bounds so they cannot walk off-screen.
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

-- Basic collision stub so jumps can clamp to the floor (later extended for platforms).
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

-- Delegate per-frame updates to the movement helper so logic stays centralized.
function love.update(dt)
    local moving = handleMovement(dt)
    handleJump(dt, moving)
end

function love.keypressed(key)
    if key == "space" and not player.isJumping then
        player.isJumping = true
        player.velocityY = -player.jumpStrength
        player.current = "jump"
    end
end

-- Pick the correct animation frame, mirror it if facing left, and render or fallback to a box.
function love.draw()
    love.graphics.setColor(platformSettings.color[1], platformSettings.color[2], platformSettings.color[3])
    for _, platform in ipairs(platforms) do
        love.graphics.rectangle("fill", math.floor(platform.x), math.floor(platform.y), platform.width, platform.height)
    end
    love.graphics.setColor(1, 1, 1)

    if player.sprite then
        -- Switch between walk cycle frames or idle frame depending on current action state.
        if player.current == "walk" then
            local walkAnimation = player.actions.walk.animations.walk.animation
            local frameIndex = math.floor(love.timer.getTime() * 10) % #walkAnimation.frames + 1
            player.sprite = walkAnimation.frames[frameIndex]
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
        -- Provide a simple rectangle fallback when the sprite failed to load.
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", math.floor(player.x), math.floor(player.y), player.width, player.height)
    end
end
