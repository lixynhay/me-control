-- boot.lua — смарт-загрузчик ME-Control.
-- Проверяет обновления на GitHub и запускает main.lua.
--
-- Логика:
--   1. splash + проверка версии;
--   2. если есть новая версия — updater.run() с прогрессом;
--   3. запуск main.lua (через shell) и выход.
--
-- Отключить автообновление: config.boot.autoUpdate = false.

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local shell = require("shell")
local gpu = component.gpu
local config = require("config")
local ui = require("ui")
-- pcall: если updater.lua оказался несовместимой/битой версией, boot всё равно
-- должен запустить панель, а не упасть.
local okUpdater, updater = pcall(require, "updater")
if not okUpdater or type(updater) ~= "table" then updater = {} end

local VERSION_FILE = "/home/version.txt"
local SHRC_FILE = "/home/.shrc"

-- ===== Экран =====
pcall(function() gpu.setResolution(gpu.maxResolution()) end)
local okRes, resW, resH = pcall(function() return gpu.getResolution() end)
local W = (okRes and tonumber(resW)) or 80
local H = (okRes and tonumber(resH)) or 25

local logs = {}

local function log(line)
    logs[#logs + 1] = tostring(line)
    while #logs > 100 do table.remove(logs, 1) end
end

local function render(status, progress)
    pcall(ui.drawBootScreen, W, H, {
        status = status,
        progress = progress,
        logs = logs,
        version = config.version,
    })
end

local function readLocalVersion()
    local f = io.open(VERSION_FILE, "r")
    if not f then return "не установлено" end
    local v = f:read("*a")
    f:close()
    if not v then return "не установлено" end
    v = v:gsub("%s+", "")
    if v == "" then return "не установлено" end
    return v
end

-- Активация автозапуска boot.lua в /home/.shrc.
-- Нужно, чтобы при первом же запуске загрузчик прописал себя на будущие перезагрузки.
--   * .shrc нет            -> создаём с содержимым "boot.lua";
--   * есть "main.lua"      -> заменяем на "boot.lua";
--   * нет "boot.lua"       -> дописываем в конец.
local function ensureShrc()
    local exists = filesystem.exists(SHRC_FILE)
    local text
    if exists then
        local f = io.open(SHRC_FILE, "r")
        if f then
            text = f:read("*a") or ""
            f:close()
        end
    end

    if not exists then
        local w = io.open(SHRC_FILE, "w")
        if w then
            w:write("boot.lua\n")
            w:close()
            log(".shrc создан: boot.lua")
        else
            log("Не удалось создать .shrc")
        end
        return
    end

    if text == nil then
        log("Не удалось прочитать .shrc")
        return
    end

    if text:find("main.lua", 1, true) then
        local updated = text:gsub("main%.lua", "boot.lua")
        local w = io.open(SHRC_FILE, "w")
        if w then
            w:write(updated)
            w:close()
            log(".shrc обновлён: main.lua -> boot.lua")
        end
        return
    end

    if not text:find("boot.lua", 1, true) then
        local w = io.open(SHRC_FILE, "a")
        if w then
            if text ~= "" and text:sub(-1) ~= "\n" then w:write("\n") end
            w:write("boot.lua\n")
            w:close()
            log(".shrc дополнен: boot.lua")
        end
    end
end

-- Запуск панели: активируем автозапуск, затем shell.execute + выход
local function launch()
    ensureShrc()
    render("Запуск панели...", nil)
    pcall(shell.execute, "main.lua")
    os.exit()
end

-- Прогресс из строк вида "[3/10] ..."
local function progressFromLog(text)
    local i, total = tostring(text):match("^%[(%d+)/(%d+)%]")
    if i and total and tonumber(total) and tonumber(total) > 0 then
        return math.floor(tonumber(i) / tonumber(total) * 100)
    end
    return nil
end

-- Полное обновление через updater.run (общий путь для обычного и fallback-режима).
local function runUpdate(label)
    if type(updater.run) ~= "function" then
        log("updater.run недоступен — запуск локальной версии")
        return
    end
    local ok, res = updater.run(function(text)
        log(text)
        render(label, progressFromLog(text))
    end)
    if ok then
        -- 7d. Успех
        ensureShrc() -- активируем boot.lua до перезагрузки
        render("Обновление завершено! Перезагрузка...", 100)
        os.sleep(1)
        computer.shutdown(true)
    else
        -- 7e. Ошибка
        log("ОШИБКА: " .. tostring(res))
        render("Ошибка обновления: " .. tostring(res), nil)
        os.sleep(3)
    end
end

-- ===== 1. Splash =====
render("Загрузка ME-CONTROL...", nil)

-- ===== 2. Локальная версия =====
local localVersion = readLocalVersion()

-- ===== 5. Отключённое автообновление =====
if config.boot and config.boot.autoUpdate == false then
    launch()
end

-- ===== 3. Проверка обновлений =====
if type(updater.checkRemoteVersion) == "function" then
    render("Проверка обновлений...", nil)
    local okCheck, remote, err = pcall(updater.checkRemoteVersion)
    if not okCheck then
        remote, err = nil, tostring(remote)
    end

    -- ===== 5. Нет связи =====
    if remote == nil then
        log("Нет связи: " .. tostring(err))
        render("Нет связи с GitHub. Запуск локальной версии...", nil)
        os.sleep(2)
        launch()
    end

    -- ===== 6. Версия актуальна =====
    if remote == localVersion then
        render("Версия актуальна: " .. remote, nil)
        os.sleep(1)
        launch()
    end

    -- ===== 7. Доступно обновление =====
    render("Доступно обновление: " .. localVersion .. " → " .. remote, 0)
    os.sleep(1)
    runUpdate("Обновление: " .. remote)
else
    -- ===== 3a. Старый/несовместимый updater.lua =====
    -- Метода проверки версии нет — принудительно запускаем полное обновление.
    log("updater.checkRemoteVersion недоступен — полное обновление")
    render("Проверка версии недоступна. Полное обновление...", 0)
    os.sleep(1)
    runUpdate("Обновление системы...")
end

-- ===== 8. Запуск панели =====
launch()
