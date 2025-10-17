local chunk_size = 32

commands.add_command(
    "hello",
    "Prints 'Hello, World!'",
    function(command)
        game.print("Hello, World!")
    end
)
-- Table to store drawn rectangles per player
drawn_rectangles = {}
rendering.clear("SleepyChunks") -- Necessary for game.reload_mods()

script.on_event(defines.events.on_player_changed_position, function(event)
    local player = game.get_player(event.player_index)
    player.clear_console()
    local surface = player.surface
    local px, py = player.position.x, player.position.y
    local chunk_radius = 0  -- adjust as needed
    local chunk_size = 32   -- default Factorio chunk size

    -- Initialize player's cache if not exists
    drawn_rectangles[player.index] = drawn_rectangles[player.index] or {}

    local player_cache = drawn_rectangles[player.index]
    local new_cache = {}

    -- Loop over chunks in a square around the player
    for dx = -chunk_radius, chunk_radius do
        for dy = -chunk_radius, chunk_radius do
            local chunk_pos = {x = math.floor(px/chunk_size) + dx, y = math.floor(py/chunk_size) + dy}
            local key = chunk_pos.x .. "," .. chunk_pos.y

            -- Check if the chunk is visible
            if player.force.is_chunk_visible(surface, chunk_pos) then
                local left_top = {x = chunk_pos.x * chunk_size, y = chunk_pos.y * chunk_size}
                local right_bottom = {x = left_top.x + chunk_size, y = left_top.y + chunk_size}

                -- Reuse existing rectangle if it exists
                if player_cache[key] then
                    new_cache[key] = player_cache[key]
                    player_cache[key] = nil  -- mark as still active
                else
                    -- Draw new rectangle and store its ID
                    local rect_id = rendering.draw_rectangle{
                        color = {r=0, g=0, b=1, a=0.3},
                        filled = true,
                        left_top = left_top,
                        right_bottom = right_bottom,
                        surface = surface,
                        players = {player.index},
                        draw_on_ground = true
                    }
                    game.print("drawing rectangle at left_top={x=" .. left_top.x .. ",y=" .. left_top.y .. "}")
                    new_cache[key] = rect_id
                end
            end
        end
    end

    -- Destroy rectangles that are no longer visible
    for _, rect_id in pairs(player_cache) do
        -- game.print(rect_id)
        rect_id.destroy()
    end

    -- Update the cache
    drawn_rectangles[player.index] = new_cache
end)

-- script.on_event(defines.events.on_tick, function(event)
--     for _, player in pairs(game.connected_players) do
--         game.print("global:")
--         game.print(global)

--         -- local pos = player.position
--         -- player.print("Your position: x=" .. pos.x .. ", y=" .. pos.y)
--     end
-- end)

-- -- Global tables
-- global.chunk_states = global.chunk_states or {}

-- -- Configuration
-- local RECHECK_INTERVAL_TICKS = 60 * 60       -- 60 seconds
-- local INPUT_THRESHOLD = 0.01                 -- 1% change triggers wake-up
-- local MAX_RECALIBRATING_CHUNKS = 50

-- -- Utility: Get chunk coordinates from position
-- local function get_chunk_coords(position)
--     return {x = math.floor(position.x / 32), y = math.floor(position.y / 32)}
-- end

-- -- Utility: mark all entities in chunk active/inactive
-- local function set_chunk_active(surface, chunk_coords, active)
--     local area = {
--         left_top = {x = chunk_coords.x * 32, y = chunk_coords.y * 32},
--         right_bottom = {x = (chunk_coords.x+1) * 32, y = (chunk_coords.y+1) * 32}
--     }
--     for _, entity in pairs(surface.find_entities_filtered{area = area}) do
--         if entity.valid and entity.type ~= "electric-pole" then
--             entity.active = active
--         end
--     end
-- end

-- -- Initialize chunk state
-- local function init_chunk(surface, chunk_coords)
--     local key = chunk_coords.x .. "," .. chunk_coords.y
--     if not global.chunk_states[key] then
--         global.chunk_states[key] = {
--             state = "active",
--             last_input_count = 0,
--             last_output_count = 0,
--             steady_ticks = 0,
--             recalibrating = false
--         }
--     end
-- end

-- -- Sample function: count items entering a chunk
-- local function count_chunk_input(surface, chunk_coords)
--     -- For POC, we just count items on belts in the chunk
--     local area = {
--         left_top = {x = chunk_coords.x * 32, y = chunk_coords.y * 32},
--         right_bottom = {x = (chunk_coords.x+1) * 32, y = (chunk_coords.y+1) * 32}
--     }
--     local count = 0
--     for _, belt in pairs(surface.find_entities_filtered{area = area, type="transport-belt"}) do
--         if belt.valid and belt.get_transport_line(1) then
--             count = count + #belt.get_transport_line(1)
--         end
--     end
--     return count
-- end

-- -- Main on_tick loop
-- script.on_event(defines.events.on_tick, function(event)
--     if event.tick % RECHECK_INTERVAL_TICKS ~= 0 then return end

--     local surface = game.surfaces["nauvis"]

--     for _, chunk_coords in pairs(surface.get_chunks()) do
--         init_chunk(surface, chunk_coords)
--         local key = chunk_coords.x .. "," .. chunk_coords.y
--         local chunk = global.chunk_states[key]

--         local current_input = count_chunk_input(surface, chunk_coords)

--         -- Check if input/output has changed significantly
--         local input_delta = math.abs(current_input - chunk.last_input_count) / math.max(chunk.last_input_count, 1)
        
--         if input_delta < INPUT_THRESHOLD then
--             -- Stable: increment steady_ticks
--             chunk.steady_ticks = chunk.steady_ticks + RECHECK_INTERVAL_TICKS
--             if chunk.steady_ticks >= RECHECK_INTERVAL_TICKS then
--                 if chunk.state == "active" then
--                     -- Enter light sleep
--                     chunk.state = "light_sleep"
--                     set_chunk_active(surface, chunk_coords, false)
--                 elseif chunk.state == "light_sleep" then
--                     -- Could enter deep sleep if neighbor conditions met
--                     chunk.state = "deep_sleep"
--                     set_chunk_active(surface, chunk_coords, false)
--                 end
--             end
--         else
--             -- Input changed significantly → wake up
--             chunk.state = "active"
--             chunk.steady_ticks = 0
--             set_chunk_active(surface, chunk_coords, true)
--         end

--         -- Save current input/output for next check
--         chunk.last_input_count = current_input
--     end
-- end)
