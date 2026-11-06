local internet = require("internet")
local filesystem = require("filesystem")
local unicode = require("unicode")

-- НАСТРОЙКИ
-- Замените на ваш репозиторий и ветку, если нужно
local USER = "lixynhay"
local REPO = "OC-HiTech"
local BRANCH = "main" -- или "master", если основная ветка называется иначе

-- Базовый URL для сырых файлов
local RAW_BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. BRANCH .. "/"
-- URL для получения списка файлов через API
local API_URL = "https://api.github.com/repos/" .. USER .. "/" .. REPO .. "/git/trees/" .. BRANCH .. "?recursive=1"

local function printProgress(msg)
    -- Очищаем строку и выводим сообщение
    io.write("\r" .. string.rep(" ", 80) .. "\r" .. msg)
end

local function downloadFile(url, dest)
    -- Создаем директорию, если её нет
    local dir = filesystem.concat(filesystem.path(dest), "")
    if not filesystem.isDirectory(dir) then
        filesystem.makeDirectory(dir)
    end
    
    -- Скачиваем файл
    local ok, response = pcall(internet.request, url)
    if not ok then
        return false, "Ошибка запроса: " .. tostring(response)
    end
    
    local data = ""
    for chunk in response do
        data = data .. chunk
    end
    
    local file = io.open(dest, "w")
    if not file then
        return false, "Не удалось открыть файл для записи: " .. dest
    end
    file:write(data)
    file:close()
    
    return true
end

-- 1. Получаем список файлов из репозитория
printProgress("Получение списка файлов из репозитория...")
local ok, response = pcall(internet.request, API_URL)
if not ok then
    print("\nНе удалось подключиться к GitHub API. Проверьте интернет-карту.")
    os.exit()
end

local jsonData = ""
for chunk in response do
    jsonData = jsonData .. chunk
end

-- 2. Простой парсинг JSON для получения путей к файлам
-- (Ищем все "path": "...")
local files = {}
for path in jsonData:gmatch('"path":"([^"]+)"') do
    -- Пропускаем папки и файлы, которые не нужно скачивать
    if not path:match("/$") and not path:match("%.git") then
        table.insert(files, path)
    end
end

if #files == 0 then
    print("\nНе удалось найти файлы в репозитории. Проверьте название репозитория и ветку.")
    os.exit()
end

print("\nНайдено файлов: " .. #files)
print("Начинаю скачивание...")

-- 3. Скачиваем каждый файл
local successCount = 0
local failCount = 0

for i, filePath in ipairs(files) do
    printProgress(string.format("[%d/%d] Скачивание: %s", i, #files, filePath))
    
    local url = RAW_BASE .. filePath
    local dest = "/home/" .. filePath -- Сохраняем в /home с сохранением структуры папок
    
    local ok, err = downloadFile(url, dest)
    if ok then
        successCount = successCount + 1
    else
        print("\nОшибка при скачивании " .. filePath .. ": " .. tostring(err))
        failCount = failCount + 1
    end
end

print("\n\nГотово!")
print("Успешно скачано: " .. successCount)
if failCount > 0 then
    print("Ошибок: " .. failCount)
end
print("Все файлы сохранены в /home/")
