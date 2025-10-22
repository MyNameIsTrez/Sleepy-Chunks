-- control.lua
-- Sleepy Chunks memory cell tracker with chunk light_sleep/awake commands

local CHUNK_SIZE = 32
local drawn_rectangles = {}
local memory_cells = {}
local belt_ui = {}

local storage = {}
storage.channels = {}
storage.transceivers = {}

local MEMORY_CELL_SURFACE = "Sleepy Chunks"
local DEBUG_MODE = true

-- === Debug logger ===
local function log(msg)
    if DEBUG_MODE then game.print(msg) end
end

-- === Hidden surface ===
local function get_hidden_surface()
    local surf = game.surfaces[MEMORY_CELL_SURFACE]
    if surf then return surf end

    log("Creating hidden surface "..MEMORY_CELL_SURFACE)
    surf = game.create_surface(MEMORY_CELL_SURFACE, {
        width=1, height=1,
        autoplace_settings={
            ["decorative"]={treat_missing_as_default=false, settings={}},
            ["entity"]={treat_missing_as_default=false, settings={}},
            ["tile"]={treat_missing_as_default=false, settings={["out-of-map"]={}}}
        }
    })

    surf.request_to_generate_chunks({0,0}, 1)
    surf.force_generate_chunk_requests()
    log("Hidden surface chunks generated")

    for _, f in pairs(game.forces) do
        f.set_surface_hidden(surf, true)
    end

    local pole = surf.create_entity{name="big-electric-pole", position={0,0}, force="neutral"}
    local energy_interface = surf.create_entity{name="electric-energy-interface", position={0,0}, force="neutral"}
    energy_interface.energy = energy_interface.electric_buffer_size
    log("Spawned central pole and energy interface at (0,0) on hidden surface")

    return surf
end

-- === Hidden decider combinator (signal source) with energy interface ===
local function create_hidden_source(force, name, pos)
    local surf = get_hidden_surface()

    local comb = surf.create_entity{
        name="decider-combinator",
        position=pos,
        force=force,
        create_build_effect_smoke=false
    }
    if not comb or not comb.valid then
        log("ERROR: Failed to create hidden source "..name)
        return nil
    end

    local behavior = comb.get_or_create_control_behavior()
    behavior.parameters = {
        comparator = "=",
        output_signal = {type="virtual", name="signal-everything"},
    }

    local out_red = comb.get_wire_connector(defines.wire_connector_id.combinator_output_red)
    local in_red  = comb.get_wire_connector(defines.wire_connector_id.combinator_input_red)
    if out_red and in_red then
        out_red.connect_to(in_red, true, defines.wire_origin.player)
    end

    storage.transceivers[comb.unit_number] = {entity=comb, force=force, name=name}
    return comb
end

-- === Create memory cell for belt ===
local function create_memory_cell_for_belt(belt)
    local surface = belt.surface
    local force = belt.force
    local pos = belt.position

    local belt_behavior = belt.get_or_create_control_behavior()
    belt_behavior.read_contents = true

    local hidden_pos = {x=0, y=0}
    local comb = create_hidden_source(force, "cell-"..belt.unit_number, hidden_pos)
    if not comb then return nil end

    -- Connect belt to combinator via red wire
    local belt_conn = belt.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local comb_in = comb.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
    if belt_conn and comb_in then
        local connected = belt_conn.connect_to(comb_in, false, defines.wire_origin.player) -- TODO: Change to defines.wire_origin.script
        log("Connected belt->combinator red wire: "..tostring(connected))
    else
        log("ERROR: failed to get connectors for belt->combinator connection")
    end

    memory_cells[#memory_cells+1] = {combinator=comb, belt=belt}
    return comb
end

-- === Update memory cell display above belts ===
local function update_memory_cell_display()
    for _, cell in ipairs(memory_cells) do
        local belt = cell.belt
        if belt and belt.valid then
            local signals = belt.get_signals(defines.wire_connector_id.circuit_red) or {}

            if belt_ui[belt.unit_number] then
                for _, id in pairs(belt_ui[belt.unit_number]) do
                    id.destroy()
                end
            end
            belt_ui[belt.unit_number] = {}

            local x = belt.position.x
            local y = belt.position.y - 1.5
            local row = 0

            for _, s in ipairs(signals) do
                local sprite_name = (s.signal.type == "virtual") and ("virtual-signal/"..s.signal.name) or ("item/"..s.signal.name)

                local icon_id = rendering.draw_sprite{
                    sprite = sprite_name,
                    target = {x=x-1, y=y - row*0.5},
                    surface = belt.surface,
                    x_scale = 0.5,
                    y_scale = 0.5
                }
                table.insert(belt_ui[belt.unit_number], icon_id)

                local text_id = rendering.draw_text{
                    text = s.signal.name .. ": " .. s.count,
                    surface = belt.surface,
                    target = {x=x+0.2, y=y - row*0.5},
                    color = {r=1, g=1, b=1},
                    scale = 0.5,
                    alignment = "left"
                }
                table.insert(belt_ui[belt.unit_number], text_id)
                row = row + 1
            end
        end
    end
end

-- === Blue rectangle and chunk cache ===
local function draw_chunk_rectangle(surface, player_index, left_top, right_bottom)
    return rendering.draw_rectangle{
        color = {r=0, g=0, b=1, a=0.001},
        filled = true,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = surface,
        players = {player_index},
        draw_on_ground = true
    }
end

local function wake_chunk_entities(surface, chunk_pos, active)
    local left_top = {x = chunk_pos.x * CHUNK_SIZE, y = chunk_pos.y * CHUNK_SIZE}
    local right_bottom = {x = left_top.x + CHUNK_SIZE, y = left_top.y + CHUNK_SIZE}
    local area = {left_top, right_bottom}
    local entities = surface.find_entities(area)
    for _, e in pairs(entities) do
        if e.valid then e.active = active end
    end
end

-- === Chunk edge belt classification ===
local DIRECTION_VECTORS = {
    [defines.direction.north] = {x = 0, y = -1},
    [defines.direction.east]  = {x = 1, y = 0},
    [defines.direction.south] = {x = 0, y = 1},
    [defines.direction.west]  = {x = -1, y = 0},
}

local function classify_chunk_edge_belt(x, y, belt_direction, surface)
    local local_x, local_y = x % CHUNK_SIZE, y % CHUNK_SIZE
    if local_x >= 1 and local_x <= CHUNK_SIZE-1 and local_y >= 1 and local_y <= CHUNK_SIZE-1 then
        return nil
    end

    -- TODO: When a belt is on the corner of chunk, it should check both of its neighboring chunks!
    local neighbor_pos
    if local_y < 1 then neighbor_pos = {x=x, y=y-1}
    elseif local_y > CHUNK_SIZE-1 then neighbor_pos = {x=x, y=y+1}
    elseif local_x < 1 then neighbor_pos = {x=x-1, y=y}
    elseif local_x > CHUNK_SIZE-1 then neighbor_pos = {x=x+1, y=y}
    else return nil end

    local neighbor_belts = surface.find_entities_filtered{position=neighbor_pos, type="transport-belt"}
    local neighbor_belt = neighbor_belts[1]
    if not neighbor_belt then return nil end

    local this_vec = DIRECTION_VECTORS[belt_direction]
    local neighbor_vec = DIRECTION_VECTORS[neighbor_belt.direction]

    local neighbor_flows_to_this = (neighbor_pos.x + neighbor_vec.x == x and neighbor_pos.y + neighbor_vec.y == y)
    local this_flows_to_neighbor = (x + this_vec.x == neighbor_pos.x and y + this_vec.y == neighbor_pos.y)

    if neighbor_flows_to_this and this_flows_to_neighbor then
        return nil
    end

    if neighbor_flows_to_this then return "incoming"
    elseif this_flows_to_neighbor then return "outgoing"
    else return nil
    end
end

-- === Light sleep / awake commands ===
local chunk_rectangles = {} -- store rectangle IDs per chunk
local chunk_memory_cells = {} -- store memory cells per chunk

commands.add_command("light_sleep", "Mark chunk inactive", function(cmd)
    local player = game.players[cmd.player_index]
    local args = {}
    for s in string.gmatch(cmd.parameter or "", "%S+") do table.insert(args, s) end
    local cx, cy = tonumber(args[1]), tonumber(args[2])
    if not cx or not cy then player.print("Usage: /light_sleep <chunk_x> <chunk_y>") return end

    local surface = player.surface
    local chunk_pos = {x=cx, y=cy}

    -- Mark entities inactive
    wake_chunk_entities(surface, chunk_pos, false)

    -- Draw blue rectangle
    local left_top = {x=cx*CHUNK_SIZE, y=cy*CHUNK_SIZE}
    local right_bottom = {x=left_top.x+CHUNK_SIZE, y=left_top.y+CHUNK_SIZE}
    local rect_id = draw_chunk_rectangle(surface, player.index, left_top, right_bottom)
    chunk_rectangles[cx..","..cy] = rect_id

    -- Detect belts on chunk edges and create memory cells
    local area = {left_top, right_bottom}
    chunk_memory_cells[cx..","..cy] = {}
    for _, belt in pairs(surface.find_entities_filtered{area=area, type="transport-belt"}) do
        local flow = classify_chunk_edge_belt(belt.position.x, belt.position.y, belt.direction, surface)
        game.print("belt.position.x: " .. tostring(belt.position.x) .. ", belt.position.y: " .. tostring(belt.position.y) .. ", flow: " .. tostring(flow))
        if flow then
            local comb = create_memory_cell_for_belt(belt)
            if comb then
                table.insert(chunk_memory_cells[cx..","..cy], comb)
            end
        end
    end

    update_memory_cell_display()
    player.print("Chunk ("..cx..","..cy..") marked light_sleep")
end)

commands.add_command("awake", "Mark chunk active", function(cmd)
    local player = game.players[cmd.player_index]
    local args = {}
    for s in string.gmatch(cmd.parameter or "", "%S+") do table.insert(args, s) end
    local cx, cy = tonumber(args[1]), tonumber(args[2])
    if not cx or not cy then player.print("Usage: /awake <chunk_x> <chunk_y>") return end

    local surface = player.surface
    local chunk_pos = {x=cx, y=cy}

    -- Mark entities active
    wake_chunk_entities(surface, chunk_pos, true)

    -- Remove rectangle
    local rect_id = chunk_rectangles[cx..","..cy]
    if rect_id then rect_id.destroy() end
    chunk_rectangles[cx..","..cy] = nil

    -- Remove memory cells for belts
    local cells = chunk_memory_cells[cx..","..cy] or {}
    for _, cell in ipairs(cells) do
        if cell and cell.valid then
            cell.destroy()
        end
    end
    chunk_memory_cells[cx..","..cy] = nil

    update_memory_cell_display()
    player.print("Chunk ("..cx..","..cy..") marked awake")
end)

-- === Periodic update ===
script.on_nth_tick(1, update_memory_cell_display)

-- === Init / configuration changed ===
script.on_init(function()
    storage.channels = storage.channels or {}
    storage.transceivers = storage.transceivers or {}
    log("Sleepy Chunks initialized")
end)

script.on_configuration_changed(function()
    storage.channels = storage.channels or {}
    storage.transceivers = storage.transceivers or {}
    log("Sleepy Chunks configuration changed")
end)
