-------------------------------------------------------------------------------
-- [1] KONFIGURASI UTAMA - Sesuaikan bagian ini sebelum menjalankan bot
-------------------------------------------------------------------------------

-- ============================================================
-- FARMING
-- ============================================================
-- Daftar titik jangkar — bot akan rotasi ke spot berikutnya jika monster
-- tidak terdeteksi di spot saat ini selama ANCHOR_ROTATE_TIMEOUT ms
-- Jika hanya ingin 1 spot, isi hanya 1 entry di tabel
local ANCHOR_SPOTS = {
    { x = 2136,  y = -1572, z = -7859 },  -- Spot 1
    -- { x = 1000,  y = -2000, z = -7859 },  -- Spot 2 (contoh, uncomment untuk aktifkan)
    -- { x = 3000,  y = -1000, z = -7859 },  -- Spot 3
}
local ANCHOR_ROTATE_TIMEOUT = 30000  -- ms tanpa monster sebelum rotasi ke spot berikutnya (30 detik)

local HUNT_RADIUS       = 150   -- Radius pencarian monster dari titik jangkar
local ARRIVAL_TOLERANCE = 15    -- Toleransi jarak dianggap sudah sampai di jangkar
local TARGET_MONSTERS   = { "Assassin Builder A", "[50] Assassin Builder A" }

local ENABLE_ANCHOR_RETURN = true  -- true = bot kembali ke jangkar saat tidak ada monster

-- Auto switch ke senjata utama saat monster terdeteksi
-- "LISTED" = hanya switch saat monster dari TARGET_MONSTERS terdeteksi
-- "ANY"    = switch saat monster apapun terdeteksi
local ENABLE_AUTO_WEAPON_SWITCH  = true
local WEAPON_SWITCH_DETECTION    = "LISTED"  -- "LISTED" atau "ANY"
local WEAPON_SWITCH_BAR          = 1   -- Tab action bar senjata utama (1-based)
local WEAPON_SWITCH_CELL         = 1   -- Slot senjata utama (1-based)

-- Deteksi awal farming — script tidak aktif penuh sampai monster terdeteksi
-- "LISTED" = tunggu monster dari TARGET_MONSTERS
-- "ANY"    = tunggu monster apapun dalam HUNT_RADIUS
local FARMING_START_DETECTION = "LISTED"

-- ============================================================
-- KEAMANAN
-- ============================================================
local ENABLE_GM_DETECTION   = true  -- true = bot berhenti saat GM terdeteksi
local ENABLE_GM_AUTO_RESUME = true  -- true = bot otomatis jalan lagi saat GM sudah pergi
local GM_DETECTION_RADIUS   = 1000

local ENABLE_DEATH_STOP  = false  -- true = bot berhenti setelah mati sejumlah MAX_DEATHS_ALLOWED
local MAX_DEATHS_ALLOWED = 2
local DEATH_RESET_TICKS  = 3000   -- Window tick untuk menghitung ulang kematian (~300ms per tick)

-- Death Log — kirim whisper ke semua REMOTE_WHITELIST saat player mati
-- Timestamp format hh:mm:ss dihitung dari saat script dijalankan
local ENABLE_DEATH_LOG = true

-- Blacklist player — bot AFK jika player yang diblacklist terdeteksi di radius
-- Bot otomatis jalan kembali jika player sudah keluar dari radius
local ENABLE_BLACKLIST         = true
local BLACKLIST_RADIUS         = 500   -- Radius pemantauan player blacklist
local BLACKLIST_CHECK_INTERVAL = 2000  -- Interval pengecekan dalam ms (jangan terlalu kecil)
local PLAYER_BLACKLIST = {
    -- "NamaMusuh1",
    -- "NamaMusuh2",
}

-- Player alert — whisper ke whitelist jika ada player lain terdeteksi di radius
-- Tidak AFK, hanya notifikasi saja
local ENABLE_PLAYER_ALERT         = true
local PLAYER_ALERT_RADIUS         = 300   -- Radius pemantauan
local PLAYER_ALERT_INTERVAL       = 10000 -- Interval pengecekan dalam ms (default 10 detik)
local PLAYER_ALERT_COOLDOWN       = 60000 -- Cooldown per nama agar tidak spam (default 60 detik)

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
-- INVENTORY
-- ============================================================
-- Jika inventory penuh, game akan ditutup otomatis
local ENABLE_KILL_ON_INVENTORY_FULL = true

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
-- REMOTE CONTROL (via private chat / common chat)
-- ============================================================
-- Whitelist nama player yang boleh mengirim perintah remote
-- Perintah via whisper atau chat umum:
--   "!stop"  = matikan bot & tools, hentikan Lua
--   "!start" = jalankan bot kembali (jika Lua masih aktif)
local ENABLE_REMOTE_CONTROL = true
local REMOTE_WHITELIST = {
    "NICKNAME_KAMU",   -- Ganti dengan nama char kamu sendiri atau teman terpercaya
}
local REMOTE_CMD_STOP  = "!stop"
local REMOTE_CMD_START = "!start"

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
local remote_stopped             = false  -- true jika bot dimatikan via remote command
local blacklist_detected         = false  -- true saat player blacklist terdeteksi di radius
local last_blacklist_check_ms    = 0
local last_inventory_check_ms    = 0
local last_player_alert_check_ms = 0
local player_alert_cooldowns     = {}  -- Tracking cooldown per nama player
local weapon_switched            = false  -- true setelah senjata utama dipasang
local current_anchor_index       = 1      -- Index spot aktif saat ini
local last_monster_seen_ms       = now_ms()  -- Terakhir kali monster terdeteksi di spot aktif
local session_start_ms           = now_ms()  -- Waktu script dijalankan, untuk format timestamp

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

-- Konversi millisecond (sejak script start) ke format hh:mm:ss
local function ms_to_timestamp(ms)
    local total_sec = math.floor(ms / 1000)
    local hh = math.floor(total_sec / 3600)
    local mm = math.floor((total_sec % 3600) / 60)
    local ss = total_sec % 60
    return string.format("%02d:%02d:%02d", hh, mm, ss)
end

-- Kirim death log ke semua player di REMOTE_WHITELIST
local function send_death_log(recent_deaths)
    if not ENABLE_DEATH_LOG then return end
    if #REMOTE_WHITELIST == 0 then return end

    local elapsed   = now_ms() - session_start_ms
    local timestamp = ms_to_timestamp(elapsed)
    local msg       = string.format("[Death Log] %s | Deaths: %d/%d | Uptime: %s",
                        game.get_player_name() or "Unknown",
                        recent_deaths, MAX_DEATHS_ALLOWED, timestamp)

    for _, name in ipairs(REMOTE_WHITELIST) do
        actions.send_private_message(name, msg)
        sleep(500)
    end
end

-------------------------------------------------------------------------------
-- [4] SETUP EVENT LISTENER
-- Didaftarkan di awal agar tidak ada private message yang terlewat
-------------------------------------------------------------------------------

-- Helper: cek apakah sender ada di whitelist (case-insensitive)
local function is_whitelisted(sender)
    local lower = sender:lower()
    for _, name in ipairs(REMOTE_WHITELIST) do
        if lower == name:lower() then return true end
    end
    return false
end

local function handle_remote_command(sender, message)
    if not ENABLE_REMOTE_CONTROL then return end
    if not is_whitelisted(sender) then return end

    local cmd = message:lower():match("^%s*(.-)%s*$")  -- trim whitespace

    if cmd == REMOTE_CMD_STOP then
        remote_stopped = true
        actions.display_message("[Remote] Diperintah stop oleh: " .. sender)
        bot.show_notification("[Remote] Bot dimatikan oleh: " .. sender)
        bot.clear_queue()
        actions.force_disable_auto_attack()
        bot.stop()
        loop_active = false

    elseif cmd == REMOTE_CMD_START then
        if not remote_stopped then return end  -- Jangan start jika belum pernah di-stop via remote
        remote_stopped = false
        loop_active    = true
        actions.display_message("[Remote] Diperintah start oleh: " .. sender)
        bot.show_notification("[Remote] Bot dijalankan oleh: " .. sender)
        actions.restore_auto_attack()
        bot.start()
    end
end

-- Daftarkan listener untuk private chat dan common chat
events.on_private_message(function(sender, message)
    handle_remote_command(sender, message)

    if not ENABLE_BUFF_REQUEST then return end
    local lower = message:lower()
    for _, config in ipairs(BUFF_CONFIG) do
        for _, keyword in ipairs(config.keywords) do
            if lower:match(string.lower(keyword)) then
                table.insert(buff_queue, { name = sender, bar = config.bar, cell = config.cell })
                return
            end
        end
    end
end)

events.on_common_message(function(sender, message)
    handle_remote_command(sender, message)
end)

if ENABLE_BUFF_REQUEST then
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
        -- Kirim notifikasi GM ke semua whitelist
        if #REMOTE_WHITELIST > 0 then
            local gm_msg = "[GM Alert] GM terdeteksi di radius!"
            for _, name in ipairs(REMOTE_WHITELIST) do
                actions.send_private_message(name, gm_msg)
                sleep(500)
            end
        end
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

local function check_blacklist(current_pos)
    if not ENABLE_BLACKLIST or #PLAYER_BLACKLIST == 0 then return end

    local current_ms = now_ms()
    if (current_ms - last_blacklist_check_ms) < BLACKLIST_CHECK_INTERVAL then return end
    last_blacklist_check_ms = current_ms

    local found_name = nil
    pcall(function()
        for _, name in ipairs(PLAYER_BLACKLIST) do
            if game.are_characters_with_names_nearby(ActorGroup.OtherPlayers, BLACKLIST_RADIUS, { name }) then
                found_name = name
                break
            end
        end
    end)

    if found_name and not blacklist_detected then
        blacklist_detected = true
        actions.display_message("[Blacklist] " .. found_name .. " terdeteksi! Bot dimatikan sementara...")
        bot.show_notification("[Blacklist] " .. found_name .. " terdeteksi!")
        -- Kirim notifikasi ke whitelist
        if #REMOTE_WHITELIST > 0 then
            local notif_msg = "[Blacklist] " .. found_name .. " terdeteksi di radius!"
            for _, name in ipairs(REMOTE_WHITELIST) do
                actions.send_private_message(name, notif_msg)
                sleep(500)
            end
        end
        bot.clear_queue()
        actions.force_disable_auto_attack()
        bot.stop()

    elseif not found_name and blacklist_detected then
        blacklist_detected = false
        actions.display_message("[Blacklist] Area aman. Menjalankan bot kembali...")
        bot.show_notification("[Blacklist] Area aman. Bot dijalankan kembali.")
        actions.restore_auto_attack()
        bot.start()
    end
end

local function manage_player_alert(current_pos)
    if not ENABLE_PLAYER_ALERT then return end
    if #REMOTE_WHITELIST == 0 then return end

    local current_ms = now_ms()
    if (current_ms - last_player_alert_check_ms) < PLAYER_ALERT_INTERVAL then return end
    last_player_alert_check_ms = current_ms

    pcall(function()
        local players = game.get_closest_characters(ActorGroup.OtherPlayers, current_pos.x, current_pos.y, current_pos.z, PLAYER_ALERT_RADIUS, {}) or {}
        for _, player in ipairs(players) do
            local name = game.get_character_name(player.ptr) or ""
            if name == "" then goto continue end

            -- Skip jika nama ada di whitelist (teman sendiri)
            if is_whitelisted(name) then goto continue end

            -- Skip jika masih dalam cooldown
            local last_alerted = player_alert_cooldowns[name] or 0
            if (current_ms - last_alerted) < PLAYER_ALERT_COOLDOWN then goto continue end

            -- Kirim notifikasi ke whitelist
            player_alert_cooldowns[name] = current_ms
            local msg = "[Player Alert] " .. name .. " terdeteksi di radius! Jarak: " .. math.floor(player.dist)
            actions.display_message(msg)
            for _, wname in ipairs(REMOTE_WHITELIST) do
                actions.send_private_message(wname, msg)
                sleep(500)
            end

            ::continue::
        end
    end)
end

local function handle_player_death()
    local pending_death_log = nil  -- Ditahan sampai player hidup kembali

    if not death_counted_this_session then
        death_counted_this_session = true

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

        -- Simpan dulu, kirim setelah hidup kembali karena chat tidak bisa dikirim saat mati
        pending_death_log = recent_deaths

        if ENABLE_DEATH_STOP and recent_deaths >= MAX_DEATHS_ALLOWED then
            actions.display_message("CRITICAL: Death limit reached! Terminating bot...")
            bot.clear_queue()
            actions.restore_auto_attack()
            bot.stop()
            loop_active = false
            return
        end
    end

    -- Beri jeda agar tools eksternal sempat menjalankan revive-nya sendiri
    sleep(1000)

    -- Cleanup state terlepas dari siapa yang revive
    bot.clear_queue()
    actions.restore_auto_attack()
    is_returning         = false
    farming_started      = false  -- Tunggu sampai di anchor & monster terdeteksi lagi
    weapon_switched      = false  -- Switch senjata ulang setelah revive
    last_monster_seen_ms = now_ms()  -- Reset timer rotasi agar tidak langsung rotasi spot

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

    -- Kirim death log setelah player hidup kembali
    if pending_death_log then
        send_death_log(pending_death_log)
    end
end

local function manage_inventory()
    if not ENABLE_KILL_ON_INVENTORY_FULL then return end

    local current_ms = now_ms()
    if (current_ms - last_inventory_check_ms) < 5000 then return end
    last_inventory_check_ms = current_ms

    local is_full = false
    pcall(function() is_full = game.is_inventory_full() end)

    if not is_full then return end

    actions.display_message("Inventory penuh! Menutup game...")
    bot.show_notification("Inventory penuh! Game akan ditutup.")

    -- Notifikasi ke whitelist sebelum game ditutup
    if #REMOTE_WHITELIST > 0 then
        local msg = "[Inventory] Inventory penuh! Game ditutup."
        for _, name in ipairs(REMOTE_WHITELIST) do
            actions.send_private_message(name, msg)
            sleep(500)
        end
    end

    sleep(500)
    actions.kill_game_process()
end

local function get_current_anchor()
    return ANCHOR_SPOTS[current_anchor_index]
end

local function rotate_anchor()
    if #ANCHOR_SPOTS <= 1 then return end
    local prev = current_anchor_index
    current_anchor_index = (current_anchor_index % #ANCHOR_SPOTS) + 1
    last_monster_seen_ms = now_ms()
    is_returning         = false
    farming_started      = false  -- Tunggu deteksi monster di spot baru
    actions.display_message("Rotasi spot: " .. prev .. " → " .. current_anchor_index)
end

local function manage_weapon_switch(monsters)
    if not ENABLE_AUTO_WEAPON_SWITCH then return end
    if weapon_switched then return end

    local should_switch = false
    if WEAPON_SWITCH_DETECTION == "ANY" then
        should_switch = #monsters > 0 or game.is_target_valid()
    else
        should_switch = #monsters > 0
    end

    if not should_switch then return end

    pcall(function()
        bot.switch_weapon(WEAPON_SWITCH_BAR - 1, WEAPON_SWITCH_CELL - 1)
        weapon_switched = true
        actions.display_message("Senjata utama dipasang.")
    end)
end

local function manage_patrol_movement(current_pos)
    if not ENABLE_ANCHOR_RETURN then return end

    local anchor = get_current_anchor()
    local dist   = get_distance(current_pos, anchor)

    if dist <= ARRIVAL_TOLERANCE then
        if is_returning then
            actions.display_message("Back at anchor point " .. current_anchor_index .. ". Monitoring area...")
            actions.restore_auto_attack()
            is_returning = false
        end
        return
    end

    if not is_returning then
        actions.display_message("Returning to anchor point " .. current_anchor_index .. "...")
        bot.clear_queue()
        actions.force_disable_auto_attack()
        actions.move_player(anchor.x, anchor.y, anchor.z)
        is_returning = true
    elseif bot.is_queue_empty() then
        actions.move_player(anchor.x, anchor.y, anchor.z)
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

    -- Jika anchor return aktif, pastikan player sudah tiba di anchor sebelum farming dimulai
    if ENABLE_ANCHOR_RETURN then
        local anchor = get_current_anchor()
        if get_distance(current_pos, anchor) > ARRIVAL_TOLERANCE then return false end
    end

    local detected = false
    pcall(function()
        if FARMING_START_DETECTION == "ANY" then
            detected = game.are_characters_nearby(ActorGroup.Monsters, HUNT_RADIUS)
        else
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
    check_blacklist(current_pos)
    manage_player_alert(current_pos)

    -- Selama GM atau blacklist player masih ada, skip farming
    if gm_detected or blacklist_detected then return end

    -- Fitur pasif tetap berjalan saat traveling
    manage_animus_summoning()
    manage_inventory()
    manage_buff_request()
    manage_follow_target()
    manage_auto_heal()   -- Sebelum player_locking agar target tidak di-override dulu
    manage_player_locking()

    -- Tunggu sampai monster terdeteksi sebelum farming logic aktif
    -- Jika anchor return aktif, pastikan player sudah tiba di anchor dulu
    if not check_farming_started(current_pos) then return end

    local monsters        = {}
    local is_target_valid = false
    pcall(function()
        -- Cari monster dari posisi jangkar aktif agar radius konsisten
        local anchor = get_current_anchor()
        local sx = ENABLE_ANCHOR_RETURN and anchor.x or current_pos.x
        local sy = ENABLE_ANCHOR_RETURN and anchor.y or current_pos.y
        local sz = ENABLE_ANCHOR_RETURN and anchor.z or current_pos.z
        monsters        = game.get_closest_characters(ActorGroup.Monsters, sx, sy, sz, HUNT_RADIUS, TARGET_MONSTERS) or {}
        is_target_valid = game.is_target_valid()
    end)

    if is_target_valid or #monsters > 0 then
        -- Update timer monster terakhir terdeteksi
        last_monster_seen_ms = now_ms()
        manage_weapon_switch(monsters)
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
        -- Rotasi spot hanya jika anchor return aktif dan ada lebih dari 1 spot
        if ENABLE_ANCHOR_RETURN and #ANCHOR_SPOTS > 1 and (now_ms() - last_monster_seen_ms) >= ANCHOR_ROTATE_TIMEOUT then
            rotate_anchor()
        end
        manage_patrol_movement(current_pos)
    end
end

-------------------------------------------------------------------------------
-- [6] MAIN LOOP
-------------------------------------------------------------------------------
repeat
    loop_active     = true
    bot_was_running = false

    while loop_active do
        local ok, running = pcall(function() return bot.is_running() end)
        local is_running  = ok and running

        -- Hanya break jika bot baru saja dimatikan (transisi nyala → mati)
        -- Jika bot memang sudah off sejak awal, atau dalam mode standby, Lua tetap berjalan
        if bot_was_running and not is_running and not remote_stopped and not gm_detected and not blacklist_detected then break end
        bot_was_running = is_running

        local is_dead = false
        pcall(function() is_dead = game.is_player_dead() end)

        if is_dead then
            -- Revive selalu dijalankan terlepas dari state GM/blacklist
            handle_player_death()
        else
            main_farming_logic()
        end

        sleep(math.random(250, 400))
    end

    -- Jika keluar loop karena remote stop, tunggu perintah !start
    if remote_stopped then
        sleep(500)
    end
until not remote_stopped  -- Keluar outer loop hanya jika bukan karena remote stop
