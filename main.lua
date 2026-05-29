-------------------------------------------------------------------------------
-- [1] KONFIGURASI UTAMA - Sesuaikan bagian ini sebelum menjalankan bot
-------------------------------------------------------------------------------

-- ============================================================
-- FARMING
-- ============================================================
-- Titik jangkar yang akan dituju & dijaga bot
local ANCHOR_POS        = { x = 2136, y = -1572, z = -7859 }
local HUNT_RADIUS       = 150   -- Radius pencarian monster dari titik jangkar
local ARRIVAL_TOLERANCE = 15    -- Toleransi jarak dianggap sudah sampai di jangkar
local TARGET_MONSTERS   = { "Assassin Builder A", "[50] Assassin Builder A" }

local ENABLE_ANCHOR_RETURN = true  -- true = bot kembali ke jangkar saat tidak ada monster

-- Deteksi awal farming — script tidak aktif penuh sampai monster terdeteksi
-- "LISTED" = tunggu monster dari TARGET_MONSTERS
-- "ANY"    = tunggu monster apapun dalam HUNT_RADIUS
local FARMING_START_DETECTION = "LISTED"

-- ============================================================
-- KEAMANAN
-- ============================================================
local ENABLE_GM_DETECTION  = true  -- true = bot berhenti saat GM terdeteksi
local ENABLE_GM_AUTO_RESUME = true  -- true = bot otomatis jalan lagi saat GM sudah pergi
local GM_DETECTION_RADIUS  = 1000

local ENABLE_DEATH_STOP  = false  -- true = bot berhenti setelah mati sejumlah MAX_DEATHS_ALLOWED
local MAX_DEATHS_ALLOWED = 2
local DEATH_RESET_TICKS  = 3000   -- Window tick untuk menghitung ulang kematian (~300ms per tick)

-- ============================================================
-- ANIMUS
-- ============================================================
local ENABLE_ANIMUS_MANAGEMENT = true  -- true = bot otomatis memanggil ulang animus jika hilang

-- Slot action bar animus (index dimulai dari 1, dikonversi otomatis ke 0-based)
local A_TAB_PANEL_NOMOR = 3   -- Tab Fast Recall
local A_PANEL_BARIS_KE  = 9   -- Slot Fast Recall
local B_TAB_PANEL_NOMOR = 3   -- Tab Animus Rest
local B_PANEL_BARIS_KE  = 10  -- Slot Animus Rest
local C_TAB_PANEL_NOMOR = 2   -- Tab Summon Animus
local C_PANEL_BARIS_KE  = 10  -- Slot Summon Animus

-- ============================================================
-- AUTO HEAL ANIMUS
-- ============================================================
local ENABLE_AUTO_HEAL = false  -- true = animus otomatis heal target yang sedang di-target

-- ============================================================
-- FOLLOW TARGET
-- ============================================================
local ENABLE_FOLLOW_TARGET = true
local FOLLOW_TARGET_NAME   = "NICKNAME"  -- Nama player yang diikuti
local FOLLOW_DISTANCE      = 150         -- Jarak ideal mengikuti target
local FOLLOW_TOLERANCE     = 20          -- Toleransi jarak sebelum bergerak

-- ============================================================
-- LOCK TARGET
-- ============================================================
local ENABLE_PLAYER_LOCKING = false
local TARGET_PLAYER_NAME    = "NICKNAME"  -- Nama player yang selalu di-target

-- ============================================================
-- BUFF REQUEST (via private chat)
-- ============================================================
local ENABLE_BUFF_REQUEST = true
local BUFF_RADIUS         = 200  -- Radius maksimal pemain bisa minta buff (100-1000)

-- keywords = kata kunci pesan private yang memicu buff
-- bar/cell  = posisi skill di action bar (dimulai dari 0)
local BUFF_CONFIG = {
    { keywords = {"velo", "speed"}, bar = 0, cell = 0 },
    { keywords = {"shield"},        bar = 0, cell = 1 },
    { keywords = {"dodge", "evade"},bar = 0, cell = 2 },
    { keywords = {"res", "ress"},   bar = 0, cell = 3 },
    { keywords = {"nj"},            bar = 0, cell = 4 },
}

-------------------------------------------------------------------------------
-- [2] STATE INTERNAL - Jangan diubah
-------------------------------------------------------------------------------
local is_returning               = false
local death_loop_records         = {}
local loop_active                = true
local death_counted_this_session = false
local last_animus_check_ms       = 0
local last_player_lock_ms        = 0
local last_gm_check_ms           = 0
local last_heal_check_ms         = 0
local last_follow_check_ms       = 0
local bot_was_running            = false  -- Untuk deteksi transisi nyala → mati
local buff_queue                 = {}
local farming_started            = false  -- true setelah monster pertama terdeteksi di spot
local gm_detected                = false  -- true saat GM sedang berada di radius

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
-- [4] SETUP EVENT LISTENER
-- Didaftarkan di awal agar tidak ada private message yang terlewat
-------------------------------------------------------------------------------
if ENABLE_BUFF_REQUEST then
    local function find_buff_config(message)
        local lower = message:lower()
        for _, config in ipairs(BUFF_CONFIG) do
            for _, keyword in ipairs(config.keywords) do
                if lower:match(string.lower(keyword)) then
                    return config
                end
            end
        end
        return nil
    end

    events.on_private_message(function(sender, message)
        local config = find_buff_config(message)
        if config then
            table.insert(buff_queue, { name = sender, bar = config.bar, cell = config.cell })
        end
    end)

    actions.display_message("[Buff Request] Mendengarkan private chat...")
end

-------------------------------------------------------------------------------
-- [5] LOGIKA BOT
-------------------------------------------------------------------------------
local function check_for_gm(current_pos)
    if not ENABLE_GM_DETECTION then return false end
    if gm_detected then return true end  -- Sudah dalam mode AFK, skip deteksi ulang

    local current_ms = now_ms()
    if (current_ms - last_gm_check_ms) < 500 then return false end
    last_gm_check_ms = current_ms

    local gm_found = false
    pcall(function()
        local players = game.get_closest_characters(ActorGroup.OtherPlayers, current_pos.x, current_pos.y, current_pos.z, GM_DETECTION_RADIUS, {}) or {}
        for _, player in ipairs(players) do
            -- Deteksi GM berdasarkan prefix [GM] yang exact (bukan substring bebas)
            local name = (game.get_character_name(player.ptr) or ""):upper()
            if name:find("^%[GM%]") then
                gm_found = true
                break
            end
        end
    end)

    if gm_found then
        gm_detected = true
        actions.display_message("GM TERDETEKSI! Bot dimatikan sementara...")
        bot.show_notification("GM TERDETEKSI! Bot dimatikan sementara.")
        bot.clear_queue()
        actions.force_disable_auto_attack()
        bot.stop()
        return true
    end

    return false
end

local function check_gm_gone(current_pos)
    -- Hanya aktif jika GM pernah terdeteksi sebelumnya
    if not gm_detected then return end
    if not ENABLE_GM_AUTO_RESUME then return end

    local current_ms = now_ms()
    if (current_ms - last_gm_check_ms) < 500 then return end
    last_gm_check_ms = current_ms

    local gm_still_here = false
    pcall(function()
        local players = game.get_closest_characters(ActorGroup.OtherPlayers, current_pos.x, current_pos.y, current_pos.z, GM_DETECTION_RADIUS, {}) or {}
        for _, player in ipairs(players) do
            local name = (game.get_character_name(player.ptr) or ""):upper()
            if name:find("^%[GM%]") then
                gm_still_here = true
                break
            end
        end
    end)

    if not gm_still_here then
        gm_detected = false
        actions.display_message("GM sudah pergi. Menjalankan bot kembali...")
        bot.show_notification("GM sudah pergi. Bot dijalankan kembali.")
        actions.restore_auto_attack()
        bot.start()
    end
end

local function handle_player_death()
    if not death_counted_this_session then
        death_counted_this_session = true

        if ENABLE_DEATH_STOP then
            table.insert(death_loop_records, now_ms())

            local recent_deaths = 0
            local cutoff = now_ms() - (DEATH_RESET_TICKS * 300)
            for i = #death_loop_records, 1, -1 do
                if death_loop_records[i] >= cutoff then
                    recent_deaths = recent_deaths + 1
                else
                    table.remove(death_loop_records, i)
                end
            end

            actions.display_message("Death recorded! [" .. recent_deaths .. "/" .. MAX_DEATHS_ALLOWED .. "]")

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

    -- Beri jeda agar tools eksternal sempat menjalankan revive-nya sendiri
    sleep(1000)

    -- Cleanup state terlepas dari siapa yang revive
    bot.clear_queue()
    actions.restore_auto_attack()
    is_returning    = false
    farming_started = false  -- Tunggu monster terdeteksi lagi setelah revive

    local still_dead = false
    pcall(function() still_dead = game.is_player_dead() end)

    if still_dead then
        bot.revive()

        -- Tunggu sampai player benar-benar hidup, maksimal 10 detik
        local waited = 0
        while waited < 10000 do
            sleep(300)
            waited = waited + 300
            local dead = true
            pcall(function() dead = game.is_player_dead() end)
            if not dead then break end
        end
    end
end

local function manage_patrol_movement(current_pos)
    if not ENABLE_ANCHOR_RETURN then return end

    local dist = get_distance(current_pos, ANCHOR_POS)

    if dist <= ARRIVAL_TOLERANCE then
        if is_returning then
            actions.display_message("Back at anchor point. Monitoring area...")
            actions.restore_auto_attack()
            is_returning = false
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
        local target     = game.get_player_target()
        local name       = game.get_character_name(target)
        local is_player  = game.find_character_by_name(ActorGroup.OtherPlayers, name)
        local gid        = game.get_character_gid(target)
        local sid        = game.get_character_sid(target)
        local flag       = (is_player and is_player > 0) and 0x00 or 0x01
        actions.send_packet(string.char(0x16, 0x07), string.pack("<BI2I4", flag, sid, gid))
    end)
end

local function manage_buff_request()
    if not ENABLE_BUFF_REQUEST or #buff_queue == 0 then return end

    local req       = table.remove(buff_queue, 1)
    local group     = ActorGroup.OtherPlayers
    local char_ptr  = game.find_character_by_name(group, req.name)
    local is_nearby = game.are_characters_with_names_nearby(group, BUFF_RADIUS, { req.name })

    if char_ptr == 0 then
        actions.display_message("[Buff] Pemain tidak ditemukan: " .. req.name)
        return
    end

    if not is_nearby then
        actions.display_message("[Buff] " .. req.name .. " di luar radius jangkauan")
        return
    end

    actions.display_message("[Buff] Memberikan buff ke " .. req.name)
    actions.force_disable_auto_attack()
    sleep(100)
    actions.use_bar_action(req.bar, req.cell, true)
    sleep(500)
    actions.click_on_target(char_ptr)
    sleep(500)
    actions.restore_auto_attack()
end

local function manage_follow_target()
    if not ENABLE_FOLLOW_TARGET then return end

    local current_ms = now_ms()
    if (current_ms - last_follow_check_ms) < 250 then return end
    last_follow_check_ms = current_ms

    pcall(function()
        local ptr = game.find_character_by_name(ActorGroup.OtherPlayers, FOLLOW_TARGET_NAME)
        if not ptr or ptr == 0 then return end

        local target_pos = game.get_character_coord(ptr)
        local my_pos     = game.get_player_coord()
        if not target_pos or not my_pos then return end

        local dx   = target_pos.x - my_pos.x
        local dy   = target_pos.y - my_pos.y
        local dz   = target_pos.z - my_pos.z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist == 0 then return end

        -- Hanya bergerak jika di luar toleransi
        if dist > FOLLOW_DISTANCE + FOLLOW_TOLERANCE or dist < FOLLOW_DISTANCE - FOLLOW_TOLERANCE then
            local nx = dx / dist
            local ny = dy / dist
            actions.move_player(
                target_pos.x - nx * FOLLOW_DISTANCE,
                target_pos.y - ny * FOLLOW_DISTANCE,
                target_pos.z
            )
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
        if target then actions.set_target(target, false) end
    end)
end

local function check_farming_started(current_pos)
    if farming_started then return true end

    local detected = false
    pcall(function()
        if FARMING_START_DETECTION == "ANY" then
            -- Terdeteksi monster apapun dalam radius
            detected = game.are_characters_nearby(ActorGroup.Monsters, HUNT_RADIUS)
        else
            -- Hanya terdeteksi jika ada monster dari TARGET_MONSTERS
            local found = game.get_closest_characters(ActorGroup.Monsters, current_pos.x, current_pos.y, current_pos.z, HUNT_RADIUS, TARGET_MONSTERS) or {}
            detected = #found > 0
        end
    end)

    if detected then
        farming_started = true
        actions.display_message("Monster terdeteksi! Farming dimulai.")
    end

    return farming_started
end

local function main_farming_logic()
    death_counted_this_session = false

    local current_pos
    pcall(function() current_pos = game.get_player_coord() end)
    if not current_pos then return end

    if check_for_gm(current_pos) then return end
    check_gm_gone(current_pos)

    -- Selama GM masih ada, hanya jalankan pengecekan — tidak ada farming
    if gm_detected then return end

    -- Fitur pasif tetap berjalan saat traveling
    manage_animus_summoning()
    manage_buff_request()
    manage_follow_target()
    manage_auto_heal()   -- Sebelum player_locking agar target tidak di-override dulu
    manage_player_locking()

    -- Tunggu sampai monster terdeteksi sebelum farming logic aktif
    if not check_farming_started(current_pos) then return end

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
        if not is_target_valid then
            pcall(function() actions.click_on_target(monsters[1].ptr) end)
        end
        if bot.is_queue_empty() then
            bot.attack()
        end
    else
        manage_patrol_movement(current_pos)
    end
end

-------------------------------------------------------------------------------
-- [6] MAIN LOOP
-------------------------------------------------------------------------------
while loop_active do
    local ok, running = pcall(function() return bot.is_running() end)
    local is_running  = ok and running

    -- Hanya break jika bot baru saja dimatikan (transisi nyala → mati)
    -- Jika bot memang sudah off sejak awal, Lua tetap berjalan
    if bot_was_running and not is_running then break end
    bot_was_running = is_running

    local is_dead = false
    pcall(function() is_dead = game.is_player_dead() end)

    if is_dead then
        handle_player_death()
    else
        main_farming_logic()
    end

    sleep(300)
end
