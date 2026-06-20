-- Table to track player fall heights, cooldowns, and successful smash flags
local mace_data = {
    cooldowns = {},
    fall_starts = {},
    safe_from_fall = {}
}

local COOLDOWN_TIME = 1.6
local WIND_BURST_BOUNCE = 12

-- 1. Heavy Core Node Registration
minetest.register_node("mace:heavy_core", {
    description = "Heavy Core",
    paramtype = "light",
    tiles = {"default_steel_block.png"}, 
    is_ground_content = false,
    groups = {cracky = 1, level = 2},
    sounds = default.node_sound_stone_defaults(),
    drawtype = "nodebox",
    node_box = {
        type = "fixed",
        fixed = {
            {-0.25, -0.5, -0.25, 0.25, 0.0, 0.25},
        },
    },
})

-- 2. Mace Item Registration
minetest.register_tool("mace:mace", {
    description = "Mace",
    inventory_image = "default_tool_steelsword.png^[colorize:#4a4a4a:120", 
    wield_scale = {x = 1.2, y = 1.2, z = 1.2},
    tool_capabilities = {
        full_punch_interval = 1.6,
        max_drop_level = 1,
        groupcaps = {
            snappy = {times = {1.5, 0.9, 0.4}, uses = 50, maxlevel = 3},
        },
        damage_groups = {fleshy = 6}, -- Base damage on the ground
    },

    on_use = function(itemstack, user, pointed_thing)
        if not user or not user:is_player() then return end
        
        local name = user:get_player_name()
        local current_time = minetest.get_gametime()
        
        -- Cooldown enforcement
        mace_data.cooldowns[name] = mace_data.cooldowns[name] or 0
        if current_time - mace_data.cooldowns[name] < COOLDOWN_TIME then
            return 
        end

        if pointed_thing.type == "object" then
            local target = pointed_thing.ref
            mace_data.cooldowns[name] = current_time
            
            -- Calculate precise drop distance
            local fall_height = 0
            if mace_data.fall_starts[name] then
                local current_pos = user:get_pos()
                fall_height = mace_data.fall_starts[name] - current_pos.y
            end

            local base_damage = 6
            local bonus_damage = 0

            -- Check if it qualifies as a falling smash hit
            if fall_height > 1.0 then
                -- 1 Block fallen = 0.5 additional damage
                bonus_damage = fall_height * 0.5
                
                -- Mark player as SAFE from their impending landing impact
                mace_data.safe_from_fall[name] = true
                
                -- Negate downward velocity and bounce up (Wind Burst effect)
                local current_vel = user:get_velocity()
                user:set_velocity(vector.new(current_vel.x, 0, current_vel.z))
                user:add_velocity(vector.new(0, WIND_BURST_BOUNCE, 0))
                
                -- Visual/Audio feedback on successful smash
                local target_pos = target:get_pos()
                minetest.sound_play("default_cool_lava", { pos = target_pos, gain = 1.0, max_hear_distance = 20 })
                
                minetest.add_particlespawner({
                    amount = 25,
                    time = 0.1,
                    minpos = vector.offset(target_pos, -0.6, 0, -0.6),
                    maxpos = vector.offset(target_pos, 0.6, 1, 0.6),
                    minvel = vector.new(-3, 1, -3),
                    maxvel = vector.new(3, 5, 3),
                    texture = "default_bubble.png",
                })
            end
            
            local total_damage = base_damage + bonus_damage

            -- Apply damage directly to the entity
            target:punch(user, 1.6, {
                full_punch_interval = 1.6,
                damage_groups = {fleshy = total_damage},
            }, nil)

            -- Handle tool degradation
            if not minetest.settings:get_bool("creative_mode") then
                itemstack:add_wear(65535 / 200) 
                return itemstack
            end
        end
    end,
})

-- 3. Physics Position Loop (Tracks where the player started descending)
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local velocity = player:get_velocity()
        local pos = player:get_pos()

        if velocity.y < -0.5 then
            -- Store initial height position right as they start dropping
            if not mace_data.fall_starts[name] then
                mace_data.fall_starts[name] = pos.y
            end
        else
            -- If they are standing still or moving upwards, clear tracking data
            -- Wrapped in a tiny delay so on_use has time to read fall_starts before it clears
            minetest.after(0.1, function()
                local p = minetest.get_player_by_name(name)
                if p and p:get_velocity().y >= 0 then
                    mace_data.fall_starts[name] = nil
                    -- Reset safety flag once they land safely or stop bouncing
                    mace_data.safe_from_fall[name] = nil
                end
            end)
        end
    end
end)

-- 4. Dynamic Fall Damage Interceptor 
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if reason.type == "fall" then
        local name = player:get_player_name()
        -- If the player successfully smashed a target, completely negate landing damage
        if mace_data.safe_from_fall[name] then
            mace_data.safe_from_fall[name] = nil -- Consume the shield flag
            return 0 -- Absolute immunity
        end
    end
    return hp_change
end, true)

-- 5. Memory Cleanup
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    mace_data.cooldowns[name] = nil
    mace_data.fall_starts[name] = nil
    mace_data.safe_from_fall[name] = nil
end)

-- 6. Basic Crafting Recipe
minetest.register_craft({
    output = "mace:mace",
    recipe = {
        { "", "mace:heavy_core" },
        { "", "default:steel_ingot" },
    }
})
