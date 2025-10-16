-- Global tables
global.chunk_states = global.chunk_states or {}

-- Configuration
local RECHECK_INTERVAL_TICKS = 60 * 60       -- 60 seconds
local INPUT_THRESHOLD = 0.01                 -- 1% change triggers wake-up
local MAX_RECALIBRATING_CHUNKS = 50

-- Utility: Get chunk coordinates from position
local function get_chunk_coords(position)
    return {x = math.floor(position.x / 32), y = math.floor(position.y / 32)}
end

-- Utility: mark all entities in chunk active/inactive
local function set_chunk_active(surface, chunk_coords, active)
    local area = {
        left_top = {x = chunk_coords.x * 32, y = chunk_coords.y * 32},
        right_bottom = {x = (chunk_coords.x+1) * 32, y = (chunk_coords.y+1) * 32}
    }
    for _, entity in pairs(surface.find_entities_filtered{area = area}) do
        if entity.valid and entity.type ~= "electric-pole" then
            entity.active = active
        end
    end
end

-- Initialize chunk state
local function init_chunk(surface, chunk_coords)
    local key = chunk_coords.x .. "," .. chunk_coords.y
    if not global.chunk_states[key] then
        global.chunk_states[key] = {
            state = "active",
            last_input_count = 0,
            last_output_count = 0,
            steady_ticks = 0,
            recalibrating = false
        }
    end
end

-- Sample function: count items entering a chunk
local function count_chunk_input(surface, chunk_coords)
    -- For POC, we just count items on belts in the chunk
    local area = {
        left_top = {x = chunk_coords.x * 32, y = chunk_coords.y * 32},
        right_bottom = {x = (chunk_coords.x+1) * 32, y = (chunk_coords.y+1) * 32}
    }
    local count = 0
    for _, belt in pairs(surface.find_entities_filtered{area = area, type="transport-belt"}) do
        if belt.valid and belt.get_transport_line(1) then
            count = count + #belt.get_transport_line(1)
        end
    end
    return count
end

-- Main on_tick loop
script.on_event(defines.events.on_tick, function(event)
    if event.tick % RECHECK_INTERVAL_TICKS ~= 0 then return end

    local surface = game.surfaces["nauvis"]

    for _, chunk_coords in pairs(surface.get_chunks()) do
        init_chunk(surface, chunk_coords)
        local key = chunk_coords.x .. "," .. chunk_coords.y
        local chunk = global.chunk_states[key]

        local current_input = count_chunk_input(surface, chunk_coords)

        -- Check if input/output has changed significantly
        local input_delta = math.abs(current_input - chunk.last_input_count) / math.max(chunk.last_input_count, 1)
        
        if input_delta < INPUT_THRESHOLD then
            -- Stable: increment steady_ticks
            chunk.steady_ticks = chunk.steady_ticks + RECHECK_INTERVAL_TICKS
            if chunk.steady_ticks >= RECHECK_INTERVAL_TICKS then
                if chunk.state == "active" then
                    -- Enter light sleep
                    chunk.state = "light_sleep"
                    set_chunk_active(surface, chunk_coords, false)
                elseif chunk.state == "light_sleep" then
                    -- Could enter deep sleep if neighbor conditions met
                    chunk.state = "deep_sleep"
                    set_chunk_active(surface, chunk_coords, false)
                end
            end
        else
            -- Input changed significantly → wake up
            chunk.state = "active"
            chunk.steady_ticks = 0
            set_chunk_active(surface, chunk_coords, true)
        end

        -- Save current input/output for next check
        chunk.last_input_count = current_input
    end
end)
