local internet = require("internet")
local filesystem = require("filesystem")
local colors = require("colors")

-- ================= НАСТРОЙКИ =================
local USER = "lixynhay"
local REPO = "OC-HiTech"
local BRANCHES = {"main", "master"}
local TARGET_DIR = "/home/"
-- =============================================

local function getAPIUrl(branch)
    return "https://api.github.com/repos/" .. USER .. "/" .. REPO .. "/git/trees/" .. branch .. "?recursive=1"
end

local function printStatus(msg, color)
    if color then term.setTextColor(color) end
    print(msg)
    if color then term.setTextColor(colors.white) end
end

local function drawProgress(current, total, filename)
    local percent = math.floor((current / total) * 100)
    local filled = math.floor(percent / 4)
    local empty = 25 - filled
    local bar = string.rep("█", filled) .. string.rep("░", empty)
    if string.len(filename) > 30 then filename = string.sub(filename, 1, 27) .. "..." end
    term.clearLine()
    term.write(" [" .. bar .. "] " .. percent .. "% | " .. filename)
    term.setCursorPos(1, term.getCursorPos())
end

local function createDirectories(path)
    local dir = filesystem.path(path)
    if dir and not filesystem.exists(dir) then
        filesystem.makeDirectory(dir)
    end
end

local function downloadFile(url, dest)
    createDirectories(dest)
    local ok, response = pcall(internet.request, url)
    if not ok then return false end
    local file = io.open(dest, "wb")
    if not file then return false end
    local success = false
    for chunk in response do
        file:write(chunk)
        success = true
    end
    file:close()
    return success
end

-- 1. ПОИСК ВЕТКИ И ПОЛУЧЕНИЕ СПИСКА ФАЙЛОВ
term.clear()
printStatus("=== УСТАНОВЩИК OC-HiTech ===", colors.cyan)
printStatus("Подключение к GitHub API...", colors.gray)

local filesToDownload = {}
local activeBranch = nil

for _, branch in ipairs(BRANCHES) do
    local ok, response = pcall(internet.request, getAPIUrl(branch))
    if ok then
        local rawJson = ""
        for chunk in response do rawJson = rawJson .. chunk end
        
        -- Если ответ не содержит "Not Found", ветка существует
        if not rawJson:find("Not Found") then
            -- Извлекаем пути к файлам из JSON без библиотеки json
            for path in rawJson:gmatch('"path":"([^"]+)"') do
                -- Пропускаем папки (в JSON у папок есть "type":"tree")
                -- и служебные файлы
                if not path:match("%.$") and not path:find("%.git") then
                    table.insert(filesToDownload, path)
                end
            end
            if #filesToDownload > 0 then
                activeBranch = branch
                break
            end
        end
    end
end

if not activeBranch then
    printStatus("Ошибка: Не удалось найти репозиторий или файлы!", colors.red)
    printStatus("Проверьте настройки USER, REPO и наличие интернет-карты.", colors.red)
    return
end

printStatus("Найдена ветка: " .. activeBranch, colors.green)
printStatus("Найдено файлов: " .. #filesToDownload, colors.cyan)
printStatus("Начинаю скачивание...", colors.gray)
print("")

-- 2. СКАЧИВАНИЕ
local RAW_BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. activeBranch .. "/"
local successCount = 0
local failCount = 0

for i, filePath in ipairs(filesToDownload) do
    drawProgress(i, #filesToDownload, filePath)
    local url = RAW_BASE .. filePath
    local dest = TARGET_DIR .. filePath
    if downloadFile(url, dest) then
        successCount = successCount + 1
    else
        failCount = failCount + 1
    end
end

-- 3. ИТОГИ
print("\n")
printStatus("=== УСТАНОВКА ЗАВЕРШЕНА ===", colors.cyan)
printStatus("Успешно скачано: " .. successCount, colors.green)
if failCount > 0 then
    printStatus("Ошибок при скачивании: " .. failCount, colors.red)
else
    printStatus("Все файлы загружены без ошибок!", colors.green)
end
printStatus("Вы можете запустить игру командой: main.lua", colors.yellow)
