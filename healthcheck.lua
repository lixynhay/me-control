-- healthcheck.lua — диагностический отчёт ME-Control.
-- Запуск:  healthcheck.lua
--
-- Ничего не меняет в панели: только читает компоненты, БД и настройки,
-- замеряет скорость ME API и пишет тот же отчёт в /home/healthcheck.log.
--
-- Что проверяется:
--   * наличие me_interface и pim;
--   * память компьютера (totalMemory / freeMemory, KB);
--   * первый (холодный) и повторный (кэш me_api) вызовы getNetworkItems;
--   * количество уникальных предметов в сети;
--   * ключи allowUserWithdraw / allowUserDeposit / allowUserCraft в db.getConfig();
--   * версия config.version.
--
-- Отчёт можно прислать текстом из /home/healthcheck.log.

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

local LOG_PATH = "/home/healthcheck.log"
local DB_PATH = "/home/database.dat"
local report = {}
local chunkArgs = { ... }

local function out(line)
    report[#report + 1] = tostring(line)
end

-- Безопасная проверка наличия компонента (не падает на старых сборках).
local function componentAvailable(name)
    local ok, avail = pcall(function() return component.isAvailable(name) end)
    if ok then return avail and true or false end
    local ok2, comp = pcall(function() return component[name] end)
    return ok2 and comp ~= nil
end

local function getComponent(name)
    local ok, comp = pcall(function() return component[name] end)
    if ok then return comp end
    return nil
end

-- Количество уникальных предметов. Поддерживает и массив, и map-таблицу
-- (me.getItemsInNetwork() в разных сборках возвращает разные формы).
local function countItems(items)
    if type(items) ~= "table" then return 0 end
    local n = 0
    for _, v in pairs(items) do
        if type(v) == "table" and (v.name or v.label) then n = n + 1 end
    end
    return n
end

-- Прямой вызов me.getItemsInNetwork() в обход кэша me_api.
local function rawCall()
    local me = getComponent("me_interface")
    if not me then return nil, "me_interface недоступен", 0 end
    local t0 = computer.uptime()
    local ok, items = pcall(function() return me.getItemsInNetwork() end)
    local dt = computer.uptime() - t0
    if not ok then return nil, items, dt end
    return items, nil, dt
end

local startedAt = computer.uptime()

-- ===== Режим --append: одна компактная JSON-строка в healthcheck.history =====
local HISTORY_PATH = "/home/healthcheck.history"
local HISTORY_MAX_LINES = 200
local HISTORY_KEEP_LINES = 100

local function hasAppendArg()
    local arg = rawget(_G, "arg")
    if type(arg) == "table" then
        for _, v in ipairs(arg) do
            if v == "--append" then return true end
        end
    end
    for _, v in ipairs(chunkArgs) do
        if v == "--append" then return true end
    end
    return false
end

local function jsonEscape(value)
    local s = tostring(value or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function jsonString(value)
    return '"' .. jsonEscape(value) .. '"'
end

local function jsonBool(value)
    if value == true then return "true" end
    if value == false then return "false" end
    return "null"
end

local function jsonInt(value)
    return tostring(math.floor(tonumber(value) or 0))
end

-- Те же измерения, что и в полном отчёте, но без повторов и без записи лога.
local function collectMetrics()
    local metrics = {
        version = "unknown",
        mem_total_kb = 0,
        mem_free_kb = 0,
        items_count = -1,
        cold_call_ms = -1,
        me_iface_ok = false,
        pim_ok = false,
        allow_withdraw = nil,
        allow_deposit = nil,
        allow_craft = nil,
    }

    local okDate, dateStr = pcall(os.date, "%Y-%m-%dT%H:%M:%S")
    local okTime, nowSecs = pcall(os.time)
    nowSecs = okTime and tonumber(nowSecs) or nil
    metrics.uptime_secs = math.floor(tonumber(computer.uptime()) or 0)

    -- Без RTC и без синхронизации os.time() отдаёт 1970-й: все записи слились бы
    -- в одну дату. В этом случае пишем uptime, чтобы строки различались.
    if nowSecs and nowSecs >= 1000000000 then
        metrics.ts = (okDate and dateStr) or ("uptime_" .. metrics.uptime_secs)
    else
        metrics.ts = "uptime_" .. metrics.uptime_secs
    end

    local okCfg, config = pcall(require, "config")
    if okCfg and type(config) == "table" and config.version then
        metrics.version = tostring(config.version)
    end

    pcall(function()
        metrics.mem_total_kb = math.floor(tonumber(computer.totalMemory()) or 0)
        metrics.mem_free_kb = math.floor(tonumber(computer.freeMemory()) or 0)
    end)

    metrics.me_iface_ok = componentAvailable("me_interface")
    metrics.pim_ok = componentAvailable("pim")

    if metrics.me_iface_ok then
        local okApi, api = pcall(require, "me_api")
        local t0 = computer.uptime()
        local okCall, items
        if okApi and type(api) == "table" and type(api.getNetworkItems) == "function" then
            okCall, items = pcall(api.getNetworkItems)
        else
            local me = getComponent("me_interface")
            if me then
                okCall, items = pcall(function() return me.getItemsInNetwork() end)
            else
                okCall, items = false, "me_interface недоступен"
            end
        end
        local dt = computer.uptime() - t0
        if okCall then
            metrics.items_count = countItems(items)
            metrics.cold_call_ms = math.floor(dt * 1000 + 0.5)
        end
    end

    local okDb, db = pcall(require, "db")
    if okDb and type(db) == "table" then
        local dbExists = filesystem.exists(DB_PATH) or filesystem.exists(DB_PATH .. ".tmp")
        if dbExists then pcall(db.load) end
        local okGet, cfg = pcall(db.getConfig)
        if okGet and type(cfg) == "table" then
            if cfg.allowUserWithdraw ~= nil then
                metrics.allow_withdraw = cfg.allowUserWithdraw ~= false
            end
            if cfg.allowUserDeposit ~= nil then
                metrics.allow_deposit = cfg.allowUserDeposit ~= false
            end
            if cfg.allowUserCraft ~= nil then
                metrics.allow_craft = cfg.allowUserCraft ~= false
            end
        end
    end

    return metrics
end

local function buildHistoryLine(metrics)
    return string.format(
        '{"ts":%s,"version":%s,"mem_total_kb":%s,"mem_free_kb":%s,"items_count":%s,"cold_call_ms":%s,"me_iface_ok":%s,"pim_ok":%s,"allow_withdraw":%s,"allow_deposit":%s,"allow_craft":%s,"uptime_secs":%s}',
        jsonString(metrics.ts),
        jsonString(metrics.version),
        jsonInt(metrics.mem_total_kb),
        jsonInt(metrics.mem_free_kb),
        jsonInt(metrics.items_count),
        jsonInt(metrics.cold_call_ms),
        jsonBool(metrics.me_iface_ok),
        jsonBool(metrics.pim_ok),
        jsonBool(metrics.allow_withdraw),
        jsonBool(metrics.allow_deposit),
        jsonBool(metrics.allow_craft),
        jsonInt(metrics.uptime_secs)
    )
end

local function readTextFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content or ""
end

local function readHistoryLines()
    if not filesystem.exists(HISTORY_PATH) then return {} end
    local content = readTextFile(HISTORY_PATH)
    if content == nil then
        return nil, "не удалось прочитать " .. HISTORY_PATH
    end
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- Атомарная запись: *.tmp -> rename. Если ФС не перезаписывает цель,
-- используем remove + повторный rename; при неудаче восстанавливаем старый файл.
local function safeSaveText(path, content)
    local tmpPath = path .. ".tmp"
    local oldContent = filesystem.exists(path) and readTextFile(path) or nil

    local f = io.open(tmpPath, "w")
    if not f then return false, "не удалось открыть " .. tmpPath end
    local okWrite, writeErr = pcall(function() f:write(content) end)
    f:close()
    if not okWrite then
        filesystem.remove(tmpPath)
        return false, writeErr
    end

    local renamed, renameErr = filesystem.rename(tmpPath, path)
    if not renamed then
        if filesystem.exists(path) then filesystem.remove(path) end
        renamed, renameErr = filesystem.rename(tmpPath, path)
        if not renamed and oldContent ~= nil then
            local restore = io.open(path, "w")
            if restore then
                pcall(function() restore:write(oldContent) end)
                restore:close()
            end
        end
    end

    if not renamed then
        filesystem.remove(tmpPath)
        return false, renameErr or "не удалось переименовать " .. tmpPath
    end
    return true
end

local function appendHistory(line)
    local lines, readErr = readHistoryLines()
    if not lines then return false, readErr end

    lines[#lines + 1] = line
    if #lines > HISTORY_MAX_LINES then
        local kept = {}
        local start = #lines - HISTORY_KEEP_LINES + 1
        for i = start, #lines do kept[#kept + 1] = lines[i] end
        lines = kept
    end

    return safeSaveText(HISTORY_PATH, table.concat(lines, "\n") .. "\n")
end

if hasAppendArg() then
    local okAppend, appendErr = pcall(function()
        local metrics = collectMetrics()
        local okWrite, writeErr = appendHistory(buildHistoryLine(metrics))
        if not okWrite then
            error("не удалось записать историю: " .. tostring(writeErr), 0)
        end
        print(string.format("healthcheck: history +1 (items=%d, cold=%d ms)",
            metrics.items_count, metrics.cold_call_ms))
    end)
    if not okAppend then
        print("healthcheck: ошибка — " .. tostring(appendErr))
        error(appendErr, 0)
    end
    return
end

local okMain, mainErr = pcall(function()
    out("=== ME-Control Health Check ===")
    local okDate, dateStr = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    local okTime, nowSecs = pcall(os.time)
    nowSecs = okTime and tonumber(nowSecs) or nil
    if nowSecs and nowSecs >= 1000000000 then
        if okDate and dateStr then out("Время: " .. tostring(dateStr)) end
    else
        -- Нет RTC/синхронизации: вместо 1970-го показываем uptime.
        out(string.format("Время: нет синхронизации (uptime %.0f с)", computer.uptime()))
    end

    -- ===== Версия =====
    local okCfg, config = pcall(require, "config")
    local version = (okCfg and type(config) == "table" and config.version) or "неизвестна"
    out("Версия ME-Control: " .. tostring(version))
    out("")

    -- ===== Память =====
    local totalKB, freeKB = 0, 0
    local okMem, memErr = pcall(function()
        totalKB = math.floor(tonumber(computer.totalMemory()) or 0)
        freeKB = math.floor(tonumber(computer.freeMemory()) or 0)
    end)
    if okMem then
        local usedKB = totalKB - freeKB
        if usedKB < 0 then usedKB = 0 end
        local pct = (totalKB > 0) and (usedKB / totalKB * 100) or 0
        out(string.format("Память: всего %d KB, свободно %d KB, занято %d KB (%.1f%%)",
            totalKB, freeKB, usedKB, pct))
    else
        out("Память: НЕДОСТУПНА (" .. tostring(memErr) .. ")")
    end

    -- ===== Компоненты =====
    local hasME = componentAvailable("me_interface")
    local hasPIM = componentAvailable("pim")
    out("me_interface: " .. (hasME and "OK" or "НЕ НАЙДЕН"))
    out("pim: " .. (hasPIM and "OK" or "НЕ НАЙДЕН"))

    if hasPIM then
        local pim = getComponent("pim")
        local okName, pimName = pcall(function() return pim.getInventoryName() end)
        local okSize, pimSize = pcall(function() return pim.getInventorySize() end)
        if okName and pimName then out("  PIM: " .. tostring(pimName)) end
        if okSize and pimSize then out("  Слотов в PIM: " .. tostring(pimSize)) end
    end
    out("")

    -- ===== ME API: холодный вызов и кэш =====
    out("--- ME API ---")
    local apiFirstDt = nil
    if not hasME then
        out("ОШИБКА: me_interface не найден — замеры ME API пропущены.")
    else
        local okApi, api = pcall(require, "me_api")
        if okApi and type(api) ~= "table" then
            okApi, api = false, "me_api вернул не таблицу"
        end

        if okApi then
            local t0 = computer.uptime()
            local ok1, list1 = pcall(api.getNetworkItems)
            local dt1 = computer.uptime() - t0
            apiFirstDt = dt1

            if not ok1 then
                out("ОШИБКА первого вызова me_api.getNetworkItems(): " .. tostring(list1))
            else
                out(string.format("Первый вызов (me_api, без кэша): %.3f с", dt1))
                out("Уникальных предметов: " .. countItems(list1))

                if dt1 > 7.5 then
                    out("Повторный вызов пропущен: первый занял > 7.5 с (тайм-бюджет).")
                else
                    local t1 = computer.uptime()
                    local ok2, list2 = pcall(api.getNetworkItems)
                    local dt2 = computer.uptime() - t1
                    if not ok2 then
                        out("ОШИБКА повторного вызова: " .. tostring(list2))
                    else
                        out(string.format("Повторный вызов (кэш me_api): %.3f с", dt2))
                        if dt2 > 0 and dt1 > dt2 then
                            out(string.format("Кэш сработал: быстрее в %.1f раза", dt1 / dt2))
                        else
                            out("Кэш не дал ускорения (возможно, истёк TTL 2 с).")
                        end
                        out("Уникальных предметов: " .. countItems(list2))
                    end
                end

                -- Сырой повтор для сравнения — только если холодный вызов быстрый,
                -- чтобы уложиться в 10–15 секунд на большой сети.
                if dt1 <= 3.0 then
                    local raw, rawErr, dtRaw = rawCall()
                    if raw then
                        out(string.format("Прямой повтор (без кэша): %.3f с, предметов: %d",
                            dtRaw, countItems(raw)))
                    else
                        out("Прямой повтор: ОШИБКА " .. tostring(rawErr))
                    end
                end
            end
        else
            -- me_api недоступен: меряем «сырые» вызовы напрямую.
            out("me_api недоступен (" .. tostring(api) .. ") — прямые замеры.")
            local raw1, err1, dt1 = rawCall()
            apiFirstDt = dt1
            if not raw1 then
                out("ОШИБКА me.getItemsInNetwork(): " .. tostring(err1))
            else
                out(string.format("Первый прямой вызов me.getItemsInNetwork(): %.3f с", dt1))
                out("Уникальных предметов: " .. countItems(raw1))
                if dt1 > 5.0 then
                    out("Повторный вызов пропущен: первый занял > 5 с (тайм-бюджет).")
                else
                    local raw2, err2, dt2 = rawCall()
                    if raw2 then
                        out(string.format("Повторный прямой вызов (без кэша): %.3f с", dt2))
                        out("Уникальных предметов: " .. countItems(raw2))
                    else
                        out("ОШИБКА повторного вызова: " .. tostring(err2))
                    end
                end
            end
        end
    end
    out("")

    -- ===== БД и глобальные права =====
    out("--- База данных / права ---")
    local okDb, db = pcall(require, "db")
    local cfg = {}
    if not okDb or type(db) ~= "table" then
        out("ОШИБКА: не удалось загрузить db: " .. tostring(db))
    else
        local dbExists = filesystem.exists(DB_PATH) or filesystem.exists(DB_PATH .. ".tmp")
        if dbExists then
            local okLoad, loadErr = pcall(db.load)
            if not okLoad then
                out("ОШИБКА загрузки database.dat: " .. tostring(loadErr))
            end
        else
            out("database.dat не найден — используются дефолтные права (true).")
        end

        local okGet, res = pcall(db.getConfig)
        if okGet and type(res) == "table" then
            cfg = res
        else
            out("ОШИБКА db.getConfig(): " .. tostring(res))
        end

        for _, key in ipairs({ "allowUserWithdraw", "allowUserDeposit", "allowUserCraft" }) do
            local v = cfg[key]
            local state
            if v == nil then
                state = "nil (ключ отсутствует)"
            elseif v == true then
                state = "true"
            elseif v == false then
                state = "false"
            else
                state = tostring(v)
            end
            out("  " .. key .. " = " .. state)
        end
    end

    -- ===== Короткие выводы =====
    out("")
    out("--- Заметки ---")
    local notes = 0
    if totalKB > 0 and (freeKB / totalKB) < 0.15 then
        out("[!] Свободной памяти меньше 15%.")
        notes = notes + 1
    end
    if apiFirstDt and apiFirstDt > 2.0 then
        out("[!] Первый вызов ME API дольше 2 с — возможен таймаут интерфейса.")
        notes = notes + 1
    end
    if cfg.allowUserCraft == false then
        out("[i] Глобальный крафт для пользователей запрещён (allowUserCraft=false).")
        notes = notes + 1
    end
    if notes == 0 then out("Проблем не обнаружено.") end
end)

if not okMain then
    out("")
    out("КРИТИЧЕСКАЯ ОШИБКА: " .. tostring(mainErr))
end

out("")
out(string.format("Общее время: %.2f с", computer.uptime() - startedAt))

-- ===== Запись лога =====
local okWrite, writeErr = pcall(function()
    local f = assert(io.open(LOG_PATH, "w"))
    f:write(table.concat(report, "\n") .. "\n")
    f:close()
end)

-- ===== Вывод в консоль (тот же отчёт) =====
for _, line in ipairs(report) do
    print(line)
end
if okWrite then
    print("Лог сохранён: " .. LOG_PATH)
else
    print("ОШИБКА записи лога: " .. tostring(writeErr))
end
