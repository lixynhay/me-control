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

local okMain, mainErr = pcall(function()
    out("=== ME-Control Health Check ===")
    local okDate, dateStr = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    if okDate and dateStr then out("Время: " .. tostring(dateStr)) end

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
