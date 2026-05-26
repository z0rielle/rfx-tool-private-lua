-------------------------------------------------------------------------------
-- [1] USER CONFIGURATION (PRIORITY LINES)
-------------------------------------------------------------------------------
-- LOCK TARGET BY NICKNAME
local ENABLE_PLAYER_LOCKING = true       -- Set ke false untuk mematikan fitur lock target player
local TARGET_PLAYER_NAME    = "NICKNAME" -- Nama player yang selalu ingin Anda targetkan

-- TARGET MONSTERS & RADIUS
local ANCHOR_POS       = { x = -2477, y = -1998, z = -987 } 
local HUNT_RADIUS      = 150 
local ARRIVAL_TOLERANCE = 15 
local TARGET_MONSTERS   = { "Assassin Builder A", "[50] Assassin Builder A" }

-- MAIN SWITCHES
local ENABLE_ANCHOR_RETURN    = true   -- Jika false, bot tidak akan pulang ke jangkar & tidak wiggle
local ENABLE_DEATH_STOP        = true   
local ENABLE_ANIMUS_MANAGEMENT = true
local ENABLE_GM_DETECTION      = true   -- Jika true, BOT AKAN BERHENTI TOTAL saat ada GM

-- ADVANCED WASD POSITION-BASED WIGGLE 
local ENABLE_ANCHOR_WIGGLE   = true   -- Set to false to stand completely still at anchor
local WIGGLE_DISTANCE        = 35     -- Movement offset distance (equivalent to step size)
local WIGGLE_INTERVAL_MIN    = 10     -- Minimum wait loop ticks before next move (1 tick ~300ms)
local WIGGLE_INTERVAL_MAX    = 25     -- Maximum wait loop ticks before next move

-- SAFETY LIMITS
local MAX_DEATHS_ALLOWED = 2
local DEATH_RESET_TICKS  = 3000 
local GM_DETECTION_RADIUS = 1000        -- Radius maksimal pandangan untuk memindai GM

-- ANIMUS ACTION BAR PANEL POSITIONS
-- Note: Bar/Cell index in API uses (0-4 / 0-9). This config uses user-friendly (1-5 / 1-10)
local A_TAB_PANEL_NOMOR = 1  -- Fast Recall Panel Tab
local A_PANEL_BARIS_KE  = 1  -- Fast Recall Slot Row

local B_TAB_PANEL_NOMOR = 1  -- Animus Rest Panel Tab
local B_PANEL_BARIS_KE  = 2  -- Animus Rest Slot Row

local C_TAB_PANEL_NOMOR = 1  -- Summon Animus Panel Tab
local C_PANEL_BARIS_KE  = 3  -- Summon Animus Slot Row

-------------------------------------------------------------------------------
-- [2] INTERNAL STATE VARIABLES (DO NOT MODIFY)
-------------------------------------------------------------------------------
local is_returning                 = false
local global_loop_counter          = 0
local death_loop_records           = {}
local loop_active                  = true
local death_counted_this_session   = false 
local last_animus_check_ms         = 0 
local last_player_lock_ms          = 0
local last_gm_check_ms             = 0

-- Position-based WASD wiggle states
local last_wiggle_tick             = 0
local next_wiggle_delay            = WIGGLE_INTERVAL_MIN
local wiggle_pattern_step          = 1  -- Cycle: 1=A (Left), 2=W (Forward), 3=D (Right), 4=S (Backward)

-------------------------------------------------------------------------------
-- [3] MATHEMATICAL & UTILITY FUNCTIONS
-------------------------------------------------------------------------------
local function get_distance(pos1, pos2)
    if not pos1 or not pos2 then return 999999 end
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-------------------------------------------------------------------------------
-- [4] BOT CORES & LOGIC SUBROUTINES
-------------------------------------------------------------------------------
local function check_for_gm(current_pos)
    if not ENABLE_GM_DETECTION then return false end
    
    local current_ms = now_ms()
    if (current_ms - last_gm_check_ms) >= 500 then
        last_gm_check_ms = current_ms
        
        local gm_found = false
        pcall(function()
            local players = game.get_closest_characters(ActorGroup.OtherPlayers, current_pos.x, current_pos.y, current_pos.z, GM_DETECTION_RADIUS, {}) or {}
            
            for _, player in ipairs(players) do
                if player.is_gm or (player.get_status and player.get_status().is_gm) then
                    gm_found = true
                    break
                end
                
                local name = player.name or ""
                if name:upper():find("GM") or name:upper():find("ADMIN") then
                    gm_found = true
                    break
                end
            end
        end)
        
        if gm_found then
            pcall(function()
                actions.display_message("EMERGENCY: GM TERDETEKSI! MEMATIKAN BOT SEGERA...")
                bot.show_notification("EMERGENCY: GM TERDETEKSI! BOT DIMATIKAN.")
                bot.clear_queue()
                actions.force_disable_auto_attack()
                bot.stop()
            end)
            loop_active = false
            return true
        end
    end
    
    return false
end

local function handle_player_death()
    if not death_counted_this_session then
        death_counted_this_session = true 

        if ENABLE_DEATH_STOP then
            table.insert(death_loop_records, global_loop_counter)

            local recent_deaths = 0
            for i = #death_loop_records, 1, -1 do
                if global_loop_counter - death_loop_records[i] <= DEATH_RESET_TICKS then
                    recent_deaths = recent_deaths + 1
                else
                    table.remove(death_loop_records, i)
                end
            end

            pcall(function()
                actions.display_message("Death recorded! [" .. recent_deaths .. "/" .. MAX_DEATHS_ALLOWED .. " deaths within time window]")
            end)

            if recent_deaths >= MAX_DEATHS_ALLOWED then
                pcall(function()
                    actions.display_message("CRITICAL: Death limit reached! Terminating bot...")
                    bot.clear_queue()
                    actions.restore_auto_attack()
                    bot.stop()
                end)
                loop_active = false
                return
            end
        end
    end

    pcall(function()
        bot.clear_queue()
        actions.restore_auto_attack()
        is_returning = false
        bot.revive()
    end)
    sleep(5000)
end

local function manage_patrol_movement(current_pos)
    if not ENABLE_ANCHOR_RETURN then return end

    local distance_to_target = get_distance(current_pos, ANCHOR_POS)

    if distance_to_target <= (ARRIVAL_TOLERANCE + WIGGLE_DISTANCE) then
        if is_returning then
            pcall(function()
                actions.display_message("Back at anchor point. Monitoring area...")
                actions.restore_auto_attack()
            end)
            is_returning = false
            pcall(function() math.randomseed(now_ms() + global_loop_counter) end)
            next_wiggle_delay = math.random(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX)
        end

        if ENABLE_ANCHOR_WIGGLE then
            if (global_loop_counter - last_wiggle_tick) >= next_wiggle_delay then
                last_wiggle_tick = global_loop_counter
                
                next_wiggle_delay = math.random(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX)
                
                local target_wiggle_x = ANCHOR_POS.x
                local target_wiggle_y = ANCHOR_POS.y
                
                if wiggle_pattern_step == 1 then     
                    target_wiggle_x = ANCHOR_POS.x - WIGGLE_DISTANCE
                elseif wiggle_pattern_step == 2 then 
                    target_wiggle_y = ANCHOR_POS.y + WIGGLE_DISTANCE
                elseif wiggle_pattern_step == 3 then 
                    target_wiggle_x = ANCHOR_POS.x + WIGGLE_DISTANCE
                elseif wiggle_pattern_step == 4 then 
                    target_wiggle_y = ANCHOR_POS.y - WIGGLE_DISTANCE
                end
                
                pcall(function()
                    bot.clear_queue()
                    actions.move_player(target_wiggle_x, target_wiggle_y, ANCHOR_POS.z)
                end)
                
                wiggle_pattern_step = wiggle_pattern_step + 1
                if wiggle_pattern_step > 4 then
                    wiggle_pattern_step = 1
                end
            end
        end
        return
    end

    if not is_returning then
        pcall(function()
            actions.display_message("Monsters cleared! Returning to anchor point...")
            bot.clear_queue()
            actions.force_disable_auto_attack()
            actions.move_player(ANCHOR_POS.x, ANCHOR_POS.y, ANCHOR_POS.z)
        end)
        is_returning = true
    else
        pcall(function()
            if bot.is_queue_empty() then
                actions.move_player(ANCHOR_POS.x, ANCHOR_POS.y, ANCHOR_POS.z)
            end
        end)
    end
end

local function manage_animus_summoning()
    if not ENABLE_ANIMUS_MANAGEMENT then return end

    local current_ms = now_ms()
    
    if (current_ms - last_animus_check_ms) >= 2000 then
        last_animus_check_ms = current_ms
        
        local is_summoned = false
        pcall(function() is_summoned = game.is_animus_summoned() end)
        
        if not is_summoned then
            pcall(function()
                actions.display_message("Animus tidak aktif! Memanggil ulang...")
                
                sleep(100)
                
                -- Fast Recall
                actions.use_bar_action(A_TAB_PANEL_NOMOR - 1, A_PANEL_BARIS_KE - 1, false)
                sleep(100)
                -- Animus Rest
                actions.use_bar_action(B_TAB_PANEL_NOMOR - 1, B_PANEL_BARIS_KE - 1, false)
                sleep(100)
                -- Summon Animus
                actions.use_bar_action(C_TAB_PANEL_NOMOR - 1, C_PANEL_BARIS_KE - 1, false)
            end)
        end
    end
end

local function manage_player_locking()
    -- Hanya berjalan jika toggle ENABLE_PLAYER_LOCKING disetel ke true
    if not ENABLE_PLAYER_LOCKING then return end

    local current_ms = now_ms()
    
    if (current_ms - last_player_lock_ms) >= 100 then
        last_player_lock_ms = current_ms
        
        pcall(function()
            local players = game.find_character_by_name(ActorGroup.OtherPlayers, TARGET_PLAYER_NAME)
            if players then
                actions.set_target(players, false)
            end
        end)
    end
end

local function main_farming_logic()
    death_counted_this_session = false

    local current_pos = nil
    pcall(function() current_pos = game.get_player_coord() end)
    if not current_pos then return end

    if check_for_gm(current_pos) then 
        return 
    end

    manage_animus_summoning()
    manage_player_locking() 

    local monsters = {}
    local is_target_valid = false

    pcall(function()
        local search_x = ENABLE_ANCHOR_RETURN and ANCHOR_POS.x or current_pos.x
        local search_y = ENABLE_ANCHOR_RETURN and ANCHOR_POS.y or current_pos.y
        local search_z = ENABLE_ANCHOR_RETURN and ANCHOR_POS.z or current_pos.z

        monsters = game.get_closest_characters(ActorGroup.Monsters, search_x, search_y, search_z, HUNT_RADIUS, TARGET_MONSTERS) or {}
        is_target_valid = game.is_target_valid()
    end)

    if is_target_valid or #monsters > 0 then
        if is_returning then
            pcall(function() actions.restore_auto_attack() end)
            is_returning = false
        end

        if not is_target_valid and #monsters > 0 then
            pcall(function()
                actions.click_on_target(monsters[1].ptr)
            end)
        end

        pcall(function()
            if bot.is_queue_empty() then
                bot.attack()
            end
        end)
    else
        manage_patrol_movement(current_pos)
    end
end

local function run_safe_loop()
    global_loop_counter = global_loop_counter + 1

    local is_dead = false
    pcall(function() is_dead = game.is_player_dead() end)
    
    if is_dead then
        handle_player_death()
    else
        main_farming_logic()
    end
end

-------------------------------------------------------------------------------
-- [5] MAIN RUNNER EXECUTION BLOCK
-------------------------------------------------------------------------------
while loop_active do
    local status, running = pcall(function() return bot.is_running() end)
    if status and not running then 
        break 
    end

    run_safe_loop()
    sleep(300) 
end
