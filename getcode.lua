local internet = require("internet")
local filesystem = require("filesystem")

-- ================= НАСТРОЙКИ =================
local USER = "lixynhay"
local REPO = "me-control"
local BRANCHES = {"main", "master"}
local TARGET_DIR = "/home/"
-- =============================================

local function getAPIUrl(branch)
    return "https://api.github.com/repos/" .. USER .. "/" .. REPO .. "/git/trees/" .. branch .. "?recursive=1"
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
print("=== УСТАНОВЩИК ME-Control ===")
print("Подключение к GitHub API...")

local filesToDownload = {}
local activeBranch = nil

for _, branch in ipairs(BRANCHES) do
    local ok, response = pcall(internet.request, getAPIUrl(branch))
    if ok then
        local rawJson = ""
        for chunk in response do rawJson = rawJson .. chunk end
        
        if not rawJson:find("Not Found") then
            for path in rawJson:gmatch('"path":"([^"]+)"') do
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
    print("[ОШИБКА] Не удалось найти репозиторий или файлы!")
    print("Проверьте настройки USER, REPO и наличие интернет-карты.")
    return
end

print("Найдена ветка: " .. activeBranch)
print("Найдено файлов: " .. #filesToDownload)
print("Начинаю скачивание...\n")

-- 2. СКАЧИВАНИЕ (Чистый текст, без полосок)
local RAW_BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. activeBranch .. "/"
local successCount = 0
local failCount = 0

for i, filePath in ipairs(filesToDownload) do
    print("[" .. i .. "/" .. #filesToDownload .. "] Скачивание: " .. filePath)
    
    local url = RAW_BASE .. filePath
    local dest = TARGET_DIR .. filePath
    
    if downloadFile(url, dest) then
        successCount = successCount + 1
    else
        print("  -> ОШИБКА!")
        failCount = failCount + 1
    end
end

-- 3. ИТОГИ
print("\n=== УСТАНОВКА ЗАВЕРШЕНА ===")
print("Успешно скачано: " .. successCount)
if failCount > 0 then
    print("Ошибок при скачивании: " .. failCount)
else
    print("Все файлы загружены без ошибок!")
end
print("Вы можете запустить игру командой: main.lua")
