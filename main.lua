-------------------------------------------------------------------------------
-- [1] KONFIGURASI UTAMA - Sesuaikan bagian ini sebelum menjalankan bot
-------------------------------------------------------------------------------

-- Lock target ke player tertentu (berguna untuk assist/follow mode)
local ENABLE_PLAYER_LOCKING = true
local TARGET_PLAYER_NAME    = "NICKNAME"

-- Titik jangkar & radius berburu monster
local ANCHOR_POS        = { x = -2477, y = -1998, z = -987 }
local HUNT_RADIUS       = 150
local ARRIVAL_TOLERANCE = 15
local TARGET_MONSTERS   = { "Assassin Builder A", "[50] Assassin Builder A" }

-- Toggle fitur utama
local ENABLE_ANCHOR_RETURN     = true  -- false = bot tidak kembali ke jangkar
local ENABLE_DEATH_STOP        = true  -- false = bot tidak berhenti saat mati berulang
local ENABLE_ANIMUS_MANAGEMENT = true  -- false = bot tidak memanggil ulang animus
local ENABLE_GM_DETECTION      = true  -- false = bot tidak mendeteksi GM
local ENABLE_AUTO_HEAL         = true  -- false = bot tidak melakukan auto heal animus

-- Wiggle (gerak acak di sekitar jangkar agar tidak terlihat AFK)
local ENABLE_ANCHOR_WIGGLE = true
local WIGGLE_DISTANCE      = 35   -- Jarak langkah wiggle
local WIGGLE_INTERVAL_MIN  = 10   -- Tick minimum antar gerakan (1 tick ~300ms)
local WIGGLE_INTERVAL_MAX  = 25   -- Tick maksimum antar gerakan

-- Batas kematian sebelum bot berhenti total
local MAX_DEATHS_ALLOWED  = 2
local DEATH_RESET_TICKS   = 3000  -- Window tick untuk menghitung ulang kematian
local GM_DETECTION_RADIUS = 1000

-- Slot action bar untuk manajemen animus
-- Catatan: index API dimulai dari 0, konfigurasi ini memakai angka natural (1-based)
local A_TAB_PANEL_NOMOR = 1  -- Tab Fast Recall
local A_PANEL_BARIS_KE  = 1  -- Slot Fast Recall
local B_TAB_PANEL_NOMOR = 1  -- Tab Animus Rest
local B_PANEL_BARIS_KE  = 2  -- Slot Animus Rest
local C_TAB_PANEL_NOMOR = 1  -- Tab Summon Animus
local C_PANEL_BARIS_KE  = 3  -- Slot Summon Animus

-------------------------------------------------------------------------------
-- [2] STATE INTERNAL - Jangan diubah
-------------------------------------------------------------------------------
local is_returning               = false
local global_loop_counter        = 0
local death_loop_records         = {}
local loop_active                = true
local death_counted_this_session = false
local last_animus_check_ms       = 0
local last_player_lock_ms        = 0
local last_gm_check_ms           = 0
local last_heal_check_ms         = 0
local last_wiggle_tick           = 0
local bot_was_running            = false  -- Untuk deteksi transisi nyala → mati
local next_wiggle_delay          = WIGGLE_INTERVAL_MIN
local wiggle_pattern_step        = 1  -- Siklus: 1=Kiri, 2=Depan, 3=Kanan, 4=Belakang

-------------------------------------------------------------------------------
-- [3] FUNGSI UTILITAS
-------------------------------------------------------------------------------
local function get_distance(pos1, pos2)
    if not pos1 or not pos2 then return 999999 end
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-------------------------------------------------------------------------------
-- [4] LOGIKA BOT
-------------------------------------------------------------------------------
local function check_for_gm(current_pos)
    if not ENABLE_GM_DETECTION then return false end

    local current_ms = now_ms()
    if (current_ms - last_gm_check_ms) < 500 then return false end
    last_gm_check_ms = current_ms

    local gm_found = false
    pcall(function()
        local players = game.get_closest_characters(ActorGroup.OtherPlayers, current_pos.x, current_pos.y, current_pos.z, GM_DETECTION_RADIUS, {}) or {}
        for _, player in ipairs(players) do
            -- Deteksi GM berdasarkan nama (sesuai API yang tersedia)
            local name = (game.get_character_name(player.ptr) or ""):upper()
            if name:find("GM") or name:find("ADMIN") then
                gm_found = true
                break
            end
        end
    end)

    if gm_found then
        actions.display_message("EMERGENCY: GM TERDETEKSI! MEMATIKAN BOT SEGERA...")
        bot.show_notification("EMERGENCY: GM TERDETEKSI! BOT DIMATIKAN.")
        bot.clear_queue()
        actions.force_disable_auto_attack()
        bot.stop()
        loop_active = false
        return true
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

            actions.display_message("Death recorded! [" .. recent_deaths .. "/" .. MAX_DEATHS_ALLOWED .. " deaths within time window]")

            if recent_deaths >= MAX_DEATHS_ALLOWED then
                actions.display_message("CRITICAL: Death limit reached! Terminating bot...")
                bot.clear_queue()
                actions.restore_auto_attack()
                bot.stop()
                loop_active = false
                return
            end
        end
    end

    bot.clear_queue()
    actions.restore_auto_attack()
    is_returning = false
    bot.revive()
    sleep(5000)
end

local function manage_patrol_movement(current_pos)
    if not ENABLE_ANCHOR_RETURN then return end

    local dist = get_distance(current_pos, ANCHOR_POS)

    if dist <= (ARRIVAL_TOLERANCE + WIGGLE_DISTANCE) then
        if is_returning then
            actions.display_message("Back at anchor point. Monitoring area...")
            actions.restore_auto_attack()
            is_returning = false
            math.randomseed(now_ms() + global_loop_counter)
            next_wiggle_delay = math.random(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX)
        end

        if ENABLE_ANCHOR_WIGGLE and (global_loop_counter - last_wiggle_tick) >= next_wiggle_delay then
            last_wiggle_tick  = global_loop_counter
            next_wiggle_delay = math.random(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX)

            local wx = ANCHOR_POS.x
            local wy = ANCHOR_POS.y

            if wiggle_pattern_step == 1 then
                wx = ANCHOR_POS.x - WIGGLE_DISTANCE
            elseif wiggle_pattern_step == 2 then
                wy = ANCHOR_POS.y + WIGGLE_DISTANCE
            elseif wiggle_pattern_step == 3 then
                wx = ANCHOR_POS.x + WIGGLE_DISTANCE
            elseif wiggle_pattern_step == 4 then
                wy = ANCHOR_POS.y - WIGGLE_DISTANCE
            end

            bot.clear_queue()
            actions.move_player(wx, wy, ANCHOR_POS.z)
            wiggle_pattern_step = wiggle_pattern_step % 4 + 1
        end
        return
    end

    if not is_returning then
        actions.display_message("Monsters cleared! Returning to anchor point...")
        bot.clear_queue()
        actions.force_disable_auto_attack()
        actions.move_player(ANCHOR_POS.x, ANCHOR_POS.y, ANCHOR_POS.z)
        is_returning = true
    elseif bot.is_queue_empty() then
        actions.move_player(ANCHOR_POS.x, ANCHOR_POS.y, ANCHOR_POS.z)
    end
end

local function manage_animus_summoning()
    if not ENABLE_ANIMUS_MANAGEMENT then return end

    local current_ms = now_ms()
    if (current_ms - last_animus_check_ms) < 2000 then return end
    last_animus_check_ms = current_ms

    local is_summoned = false
    pcall(function() is_summoned = game.is_animus_summoned() end)

    if not is_summoned then
        actions.display_message("Animus tidak aktif! Memanggil ulang...")
        sleep(100)
        actions.use_bar_action(A_TAB_PANEL_NOMOR - 1, A_PANEL_BARIS_KE - 1, false)
        sleep(100)
        actions.use_bar_action(B_TAB_PANEL_NOMOR - 1, B_PANEL_BARIS_KE - 1, false)
        sleep(100)
        actions.use_bar_action(C_TAB_PANEL_NOMOR - 1, C_PANEL_BARIS_KE - 1, false)
    end
end

local function manage_auto_heal()
    if not ENABLE_AUTO_HEAL then return end
    if not game.is_target_valid() or not game.is_animus_summoned() then return end

    local current_ms = now_ms()
    if (current_ms - last_heal_check_ms) < 1000 then return end
    last_heal_check_ms = current_ms

    pcall(function()
        local target  = game.get_player_target()
        local players = game.find_character_by_name(ActorGroup.OtherPlayers, game.get_character_name(target))
        local gid     = game.get_character_gid(target)
        local sid     = game.get_character_sid(target)
        local packetType = string.char(0x16, 0x07)

        if players > 0 then
            actions.send_packet(packetType, string.pack("<BI2I4", 0x00, sid, gid))
        else
            actions.send_packet(packetType, string.pack("<BI2I4", 0x01, sid, gid))
        end
    end)
end

local function manage_player_locking()
    if not ENABLE_PLAYER_LOCKING then return end

    local current_ms = now_ms()
    if (current_ms - last_player_lock_ms) < 100 then return end
    last_player_lock_ms = current_ms

    pcall(function()
        local target = game.find_character_by_name(ActorGroup.OtherPlayers, TARGET_PLAYER_NAME)
        if target then
            actions.set_target(target, false)
        end
    end)
end

local function main_farming_logic()
    death_counted_this_session = false

    local current_pos
    pcall(function() current_pos = game.get_player_coord() end)
    if not current_pos then return end

    if check_for_gm(current_pos) then return end

    manage_animus_summoning()
    manage_auto_heal()   -- Dipanggil sebelum player_locking agar target tidak di-override dulu
    manage_player_locking()

    local monsters        = {}
    local is_target_valid = false
    pcall(function()
        -- Cari monster dari posisi jangkar agar radius konsisten
        local sx = ENABLE_ANCHOR_RETURN and ANCHOR_POS.x or current_pos.x
        local sy = ENABLE_ANCHOR_RETURN and ANCHOR_POS.y or current_pos.y
        local sz = ENABLE_ANCHOR_RETURN and ANCHOR_POS.z or current_pos.z
        monsters        = game.get_closest_characters(ActorGroup.Monsters, sx, sy, sz, HUNT_RADIUS, TARGET_MONSTERS) or {}
        is_target_valid = game.is_target_valid()
    end)

    if is_target_valid or #monsters > 0 then
        if is_returning then
            actions.restore_auto_attack()
            is_returning = false
        end

        if not is_target_valid and #monsters > 0 then
            pcall(function() actions.click_on_target(monsters[1].ptr) end)
        end

        if bot.is_queue_empty() then
            bot.attack()
        end
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
-- [5] MAIN LOOP
-------------------------------------------------------------------------------
while loop_active do
    local ok, running = pcall(function() return bot.is_running() end)
    local is_running = ok and running

    -- Hanya break jika bot baru saja dimatikan (transisi nyala → mati)
    -- Jika bot memang sudah off sejak awal, Lua tetap berjalan
    if bot_was_running and not is_running then break end
    bot_was_running = is_running

    run_safe_loop()
    sleep(300)
end
