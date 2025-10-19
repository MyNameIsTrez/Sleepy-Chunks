local CHUNK_SIZE = 32

commands.add_command(
    "hello",
    "Prints 'Hello, World!'",
    function(command)
        game.print("Hello, World!")
    end
)

local drawn_rectangles = {}
rendering.clear("SleepyChunks") -- Guarantees old rectangles are not drawn anymore

-- Helper to draw a rectangle for a chunk
local function draw_chunk_rectangle(surface, player_index, left_top, right_bottom)
    local rect_id = rendering.draw_rectangle{
        color = {r=0, g=0, b=1, a=0.001},
        filled = true,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = surface,
        players = {player_index},
        draw_on_ground = true
    }
    return rect_id
end

-- Helper to set all entities in a chunk to active
local function wake_chunk_entities(surface, chunk_pos)
    local left_top = {x = chunk_pos.x * CHUNK_SIZE, y = chunk_pos.y * CHUNK_SIZE}
    local right_bottom = {x = left_top.x + CHUNK_SIZE, y = left_top.y + CHUNK_SIZE}

    local area = {left_top = left_top, right_bottom = right_bottom}
    local entities = surface.find_entities(area)
    for _, entity in pairs(entities) do
        if entity.valid then
            entity.active = true
        end
    end
end

local DIRECTION_VECTORS = {
    [defines.direction.north] = {x = 0, y = -1},
    [defines.direction.east]  = {x = 1, y = 0},
    [defines.direction.south] = {x = 0, y = 1},
    [defines.direction.west]  = {x = -1, y = 0},
}

local function classify_chunk_edge_belt(x, y, belt_direction, surface)
    local local_x, local_y = x % CHUNK_SIZE, y % CHUNK_SIZE
    if local_x >= 1 and local_x <= CHUNK_SIZE - 1 and local_y >= 1 and local_y <= CHUNK_SIZE - 1 then
        return false
    end

    -- Determine which edge
    local neighbor_pos
    if local_y < 1 then neighbor_pos = {x = x, y = y - 1}       -- north
    elseif local_y > CHUNK_SIZE - 1 then neighbor_pos = {x = x, y = y + 1} -- south
    elseif local_x < 1 then neighbor_pos = {x = x - 1, y = y}  -- west
    elseif local_x > CHUNK_SIZE - 1 then neighbor_pos = {x = x + 1, y = y} -- east
    else return false end

    local neighbor_belt = surface.find_entity("transport-belt", neighbor_pos)
    if not neighbor_belt then return false end

    local this_vec = DIRECTION_VECTORS[belt_direction]
    local neighbor_vec = DIRECTION_VECTORS[neighbor_belt.direction]

    local neighbor_flows_to_this = (neighbor_pos.x + neighbor_vec.x == x and neighbor_pos.y + neighbor_vec.y == y)
    local this_flows_to_neighbor = (x + this_vec.x == neighbor_pos.x and y + this_vec.y == neighbor_pos.y)

    -- If both belts flow into each other, treat as no edge
    if neighbor_flows_to_this and this_flows_to_neighbor then
        return false
    end

    if neighbor_flows_to_this then
        return true, "incoming"
    elseif this_flows_to_neighbor then
        return true, "outgoing"
    else
        return false
    end
end

script.on_event(defines.events.on_player_changed_position, function(event)
    local player = game.get_player(event.player_index)
    -- player.clear_console() -- TODO: REMOVE!

    local surface = player.surface
    local px, py = player.position.x, player.position.y
    local chunk_radius = 0

    -- Initialize player's cache if not exists
    drawn_rectangles[player.index] = drawn_rectangles[player.index] or {}
    local player_cache = drawn_rectangles[player.index]
    local new_cache = {}

    -- Loop over chunks in a square around the player
    for dx = -chunk_radius, chunk_radius do
        for dy = -chunk_radius, chunk_radius do
            local chunk_pos = {x = math.floor(px/CHUNK_SIZE) + dx, y = math.floor(py/CHUNK_SIZE) + dy}
            local key = chunk_pos.x .. "," .. chunk_pos.y

            -- Check if the chunk is visible
            if player.force.is_chunk_visible(surface, chunk_pos) then
                local left_top = {x = chunk_pos.x * CHUNK_SIZE, y = chunk_pos.y * CHUNK_SIZE}
                local right_bottom = {x = left_top.x + CHUNK_SIZE, y = left_top.y + CHUNK_SIZE}

                -- Wake all entities in the chunk
                wake_chunk_entities(surface, chunk_pos, CHUNK_SIZE)

                -- Reuse existing rectangle if it exists
                if player_cache[key] then
                    new_cache[key] = player_cache[key]
                    player_cache[key] = nil  -- mark as still active
                else
                    -- Draw new rectangle and store its ID
                    local rect_id = draw_chunk_rectangle(surface, player.index, left_top, right_bottom)
                    new_cache[key] = rect_id

                    local area = {left_top, right_bottom}
                    for _, belt in pairs(surface.find_entities_filtered{area = area, type="transport-belt"}) do
                        game.print(belt)

                        local pos = belt.position

                        local valid, flow_type = classify_chunk_edge_belt(pos.x, pos.y, belt.direction, surface)
                        game.print(serpent.line{valid=valid, flow_type=flow_type})
                    end
                end
            end
        end
    end

    -- Destroy rectangles that are no longer visible
    for _, rect_id in pairs(player_cache) do
        rect_id.destroy()
    end

    -- Update the cache
    drawn_rectangles[player.index] = new_cache
end)
