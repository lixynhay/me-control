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
local shell = require("shell")
local gpu = component.gpu
local config = require("config")
local ui = require("ui")
local updater = require("updater")

local VERSION_FILE = "/home/version.txt"

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

-- Запуск панели: shell.execute + выход
local function launch()
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

-- ===== 1. Splash =====
render("Загрузка ME-CONTROL...", nil)

-- ===== 2. Локальная версия =====
local localVersion = readLocalVersion()

-- ===== 5. Отключённое автообновление =====
if config.boot and config.boot.autoUpdate == false then
    launch()
end

-- ===== 3. Проверка обновлений =====
render("Проверка обновлений...", nil)
local remote, err = updater.checkRemoteVersion()

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

local ok, res = updater.run(function(text)
    log(text)
    render("Обновление: " .. remote, progressFromLog(text))
end)

if ok then
    -- 7d. Успех
    render("Обновление завершено! Перезагрузка...", 100)
    os.sleep(1)
    computer.shutdown(true)
else
    -- 7e. Ошибка
    log("ОШИБКА: " .. tostring(res))
    render("Ошибка обновления: " .. tostring(res), nil)
    os.sleep(3)
end

-- ===== 8. Запуск панели =====
launch()
