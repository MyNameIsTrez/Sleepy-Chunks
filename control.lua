-- control.lua
-- Sleepy Chunks memory cell tracker and signal printer (decider combinator version with energy interface)

memory_cells = memory_cells or {}

if not storage then storage = {} end
storage.channels = storage.channels or {}
storage.transceivers = storage.transceivers or {}

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

    return surf
end

-- === Hidden central pole for a channel ===
local function get_hidden_pole(force, channel)
    storage.channels[force.name] = storage.channels[force.name] or {}
    local pole = storage.channels[force.name][channel]
    if pole and pole.valid then
        log("Reusing existing hidden pole for "..force.name.." / "..channel)
        return pole
    end

    local surf = get_hidden_surface()
    pole = surf.create_entity{name="big-electric-pole", position={1,0}, force=force}
    pole.teleport({0,0})
    storage.channels[force.name][channel] = pole
    log("Created hidden pole for "..force.name.." / "..channel)
    return pole
end

-- === Hidden decider combinator (signal source) with energy interface ===
local function create_hidden_source(force, name)
    local surf = get_hidden_surface()

    -- Energy interface to power the combinator
    local energy_interface = surf.create_entity{
        name="electric-energy-interface",
        position={0,0},
        force=force,
        create_build_effect_smoke=false
    }
    if not energy_interface or not energy_interface.valid then
        log("ERROR: Failed to create energy interface for "..name)
        return nil
    end
    energy_interface.energy = energy_interface.electric_buffer_size -- fully charged
    log("Created energy interface at 0,0 for "..name)

    -- Decider combinator
    local comb = surf.create_entity{
        name="decider-combinator",
        position={0,0},
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
        output_signal = {type="virtual", name="signal-anything"},
    }

    storage.transceivers[comb.unit_number] = {entity=comb, force=force, name=name}
    log("Created hidden source "..name.." (unit_number="..comb.unit_number..")")
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
        name="transport-belt",
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

    -- Hidden decider combinator as signal source
    local comb = create_hidden_source(force, "cell-"..belt.unit_number)
    if not comb then
        log("ERROR: failed to create hidden source combinator")
        return nil
    end

    -- Hidden central pole for the channel
    local pole = get_hidden_pole(force, "cell-pole-"..belt.unit_number)
    if not pole or not pole.valid then
        log("ERROR: failed to create hidden pole")
        return nil
    end

    -- Connect combinator to pole
    local comb_out = comb.get_wire_connector(defines.wire_connector_id.combinator_output_red, true)
    local pole_conn = pole.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local comb_connected = comb_out.connect_to(pole_conn, false, defines.wire_origin.player)
    log("Comb->Pole connect_to returned: "..tostring(comb_connected))

    -- Connect belt to pole
    local belt_out = belt.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    local belt_connected = belt_out.connect_to(pole_conn, false, defines.wire_origin.player)
    log("Belt->Pole connect_to returned: "..tostring(belt_connected))

    memory_cells[#memory_cells+1] = {combinator=comb, belt=belt, pole=pole}
    player.print("Memory cell created and connected via hidden source and pole.")
    return comb, belt
end

-- === Print memory cell signals ===
local function print_memory_cell_signals()
    log("=== Checking memory cell signals ===")
    for i, cell in ipairs(memory_cells) do
        local comb = cell.combinator
        if comb and comb.valid then
            local net = comb.get_circuit_network(defines.wire_type.red)
            if net and net.valid then
                local signals = net.signals or {}
                local str = "Memory Cell "..i..": "
                for _, s in ipairs(signals) do
                    str = str..string.format("[%s]=%d ", s.signal.name, s.count)
                end
                game.print(str)
                log("Memory Cell "..i.." network valid with "..#signals.." signals")
            elseif net then
                log("Memory Cell "..i.." network is invalid")
            else
                log("Memory Cell "..i.." network is nil")
            end
        else
            log("Memory Cell "..i.." combinator invalid")
        end
    end
end

-- === Commands / ticks ===
commands.add_command("create_memory_cell", "Create Sleepy Chunks memory cell", function(cmd)
    local player = game.players[cmd.player_index]
    create_memory_cell(player)
end)

script.on_nth_tick(60, print_memory_cell_signals)

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
