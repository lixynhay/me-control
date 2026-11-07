local internet = require("internet")
local filesystem = require("filesystem")
local computer = require("computer")

-- ================= НАСТРОЙКИ =================
local USER = "lixynhay"
local REPO = "OC-HiTech"
local BRANCHES = {"main", "master"}
local TARGET_DIR = "/home/"
-- =============================================

-- Функция для красивого вывода размера файла
local function formatSize(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

local function getAPIUrl(branch)
    return "https://api.github.com/repos/" .. USER .. "/" .. REPO .. "/git/trees/" .. branch .. "?recursive=1"
end

local function createDirectories(path)
    local dir = filesystem.path(path)
    if dir and not filesystem.exists(dir) then
        filesystem.makeDirectory(dir)
    end
end

-- Возвращает true/false и количество скачанных байт
local function downloadFile(url, dest)
    createDirectories(dest)
    local ok, response = pcall(internet.request, url)
    if not ok then return false, 0 end
    
    local file = io.open(dest, "wb")
    if not file then return false, 0 end
    
    local bytes = 0
    for chunk in response do
        file:write(chunk)
        bytes = bytes + #chunk
    end
    file:close()
    return true, bytes
end

-- 1. ПОИСК ВЕТКИ И ПОЛУЧЕНИЕ СПИСКА ФАЙЛОВ
print("=== УСТАНОВЩИК OC-HiTech ===")
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
    return
end

print("Ветка: " .. activeBranch)
print("Найдено файлов: " .. #filesToDownload)
print("Начинаю скачивание...\n")

-- 2. СКАЧИВАНИЕ
local startTime = computer.uptime()
local RAW_BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. activeBranch .. "/"
local successCount = 0
local failCount = 0
local totalBytes = 0

-- Генерируем уникальный параметр, чтобы обойти кэш GitHub (Cache Busting)
local cacheBuster = "?t=" .. math.floor(computer.uptime()) .. math.random(1000, 9999)

for i, filePath in ipairs(filesToDownload) do
    -- Добавляем cacheBuster к ссылке, чтобы всегда качать свежий файл
    local url = RAW_BASE .. filePath .. cacheBuster
    local dest = TARGET_DIR .. filePath
    
    local success, bytes = downloadFile(url, dest)
    
    if success then
        print(string.format("[%d/%d] %-25s | %s", i, #filesToDownload, filePath, formatSize(bytes)))
        successCount = successCount + 1
        totalBytes = totalBytes + bytes
    else
        print(string.format("[%d/%d] %-25s | ОШИБКА", i, #filesToDownload, filePath))
        failCount = failCount + 1
    end
end

-- 3. ИТОГИ
local timeTaken = computer.uptime() - startTime

print("\n=== УСТАНОВКА ЗАВЕРШЕНА ===")
print("Успешно: " .. successCount .. " | Ошибок: " .. failCount)
print("Общий размер: " .. formatSize(totalBytes))
print(string.format("Время выполнения: %.2f сек.", timeTaken))
print("Запуск: main.lua")
