-- control.lua
-- Sleepy Chunks memory cell tracker and signal printer (decider combinator version with energy interface, all on Nauvis + hidden surface)

local memory_cells = {}

local storage = {}
storage.channels = {}
storage.transceivers = {}

local belt_ui = {}

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

    -- Hide from all forces
    for _, f in pairs(game.forces) do
        f.set_surface_hidden(surf, true)
    end

    -- Spawn central pole and energy interface at (0,0)
    local pole = surf.create_entity{name="big-electric-pole", position={0,0}, force="neutral"}
    local energy_interface = surf.create_entity{name="electric-energy-interface", position={0,0}, force="neutral"}
    energy_interface.energy = energy_interface.electric_buffer_size
    log("Spawned central pole and energy interface at (0,0) on hidden surface")

    return surf
end

-- === Hidden decider combinator (signal source) with energy interface ===
local function create_hidden_source(force, name, pos)
    local surf = get_hidden_surface()

    -- Decider combinator
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

    -- Set combinator parameters
    local behavior = comb.get_or_create_control_behavior()
    behavior.parameters = {
        comparator = "=",
        output_signal = {type="virtual", name="signal-everything"},
    }

    -- Connect combinator input/output together (red wire) for self-feedback
    local out_red = comb.get_wire_connector(defines.wire_connector_id.combinator_output_red)
    local in_red  = comb.get_wire_connector(defines.wire_connector_id.combinator_input_red)
    if out_red and in_red then
        out_red.connect_to(in_red, true, defines.wire_origin.player)
        log("Connected combinator input and output (red wire) for "..name)
    end

    storage.transceivers[comb.unit_number] = {entity=comb, force=force, name=name}
    log("Created hidden source "..name.." (unit_number="..comb.unit_number..") at "..pos.x..","..pos.y)
    return comb
end

-- === Create a memory cell ===
local function create_memory_cell(player)
    local force = player.force
    local surface = player.surface
    local pos = player.position

    log("Creating memory cell for player "..player.name.." at "..pos.x..","..pos.y)

    -- Create visible belt
    local belt = surface.create_entity{
        name="turbo-transport-belt",
        position={pos.x-1, pos.y},
        direction=defines.direction.east,
        force=force,
        create_build_effect_smoke=false
    }
    if not belt or not belt.valid then
        player.print("Failed to create belt")
        log("ERROR: belt creation failed")
        return nil
    end

    local belt_behavior = belt.get_or_create_control_behavior()
    belt_behavior.read_contents = true
    log("Belt created at "..(pos.x-1)..","..pos.y.." (unit_number="..belt.unit_number..")")

    -- Hidden decider combinator on hidden surface
    local hidden_pos = {x=0, y=0}
    local comb = create_hidden_source(force, "cell-"..belt.unit_number, hidden_pos)
    if not comb then
        log("ERROR: failed to create hidden source combinator")
        return nil
    end

    -- Connect belt to combinator via red wire
    local belt_conn = belt.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local comb_in = comb.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
    if belt_conn and comb_in then
        local connected = belt_conn.connect_to(comb_in, false, defines.wire_origin.player)
        log("Connected belt->combinator red wire: "..tostring(connected))
    else
        log("ERROR: failed to get connectors for belt->combinator connection")
    end

    memory_cells[#memory_cells+1] = {combinator=comb, belt=belt}
    player.print("Memory cell created and connected via hidden combinator.")
    return comb, belt
end

-- Update memory cell display above belts using belt signals
local function update_memory_cell_display()
    for i, cell in ipairs(memory_cells) do
        local belt = cell.belt
        if belt and belt.valid then
            local signals = belt.get_signals(defines.wire_connector_id.circuit_red) or {}

            -- Remove old renderings if any
            if belt_ui[belt.unit_number] then
                for _, id in pairs(belt_ui[belt.unit_number]) do
                    id.destroy()
                end
            end
            belt_ui[belt.unit_number] = {}

            local x = belt.position.x
            local y = belt.position.y - 1.5 -- above belt
            local row = 0

            for _, s in ipairs(signals) do
                -- Determine sprite type
                local sprite_name
                if s.signal.type == "virtual" then
                    sprite_name = "virtual-signal/" .. s.signal.name
                else
                    sprite_name = "item/" .. s.signal.name
                end

                -- Draw icon
                local icon_id = rendering.draw_sprite{
                    sprite = sprite_name,
                    target = {x=x-1, y=y - row*0.5},
                    surface = belt.surface,
                    x_scale = 0.5,
                    y_scale = 0.5
                }
                table.insert(belt_ui[belt.unit_number], icon_id)

                -- Draw text (signal name + count)
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

-- === Commands / ticks ===
commands.add_command("create_memory_cell", "Create Sleepy Chunks memory cell", function(cmd)
    local player = game.players[cmd.player_index]
    create_memory_cell(player)
end)

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
