local component = require("component")
local internet = require("internet")
local filesystem = require("filesystem")
local computer = require("computer")

-- ================= НАСТРОЙКИ =================
local USER = "lixynhay"
local REPO = "me-control"
local BRANCH = "main"
local TARGET_DIR = "/home/"
local REQUEST_RETRIES = 2   -- попыток на один запрос
local RETRY_DELAY = 1       -- пауза между попытками, сек
local READ_TIMEOUT = 60     -- мягкий таймаут чтения файла, сек
-- =============================================

if not component.isAvailable("internet") then
    print("[ОШИБКА] Интернет-карта не найдена!")
    return
end

local rawBase = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. BRANCH .. "/"
local cacheBuster = "?t=" .. math.floor(computer.uptime())

-- ============== УТИЛИТЫ ==============

-- Валидация пути из манифеста (защита от Path Traversal)
local function isSafePath(path)
    if type(path) ~= "string" or path == "" then return false end
    if path:find("..", 1, true) then return false end                  -- никаких ..
    if path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" then return false end
    if path:find(":", 1, true) then return false end                   -- Windows-диски (C:)
    if path:find("\\", 1, true) then return false end                  -- обратные слэши
    return true
end

-- Рекурсивное создание каталогов (filesystem.makeDirectory создаёт только 1 уровень)
local function mkdirp(path)
    if not path or path == "" then return true end
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if not filesystem.exists(acc) then
            local ok = filesystem.makeDirectory(acc)
            if not ok then return false, acc end
        end
    end
    return true
end

local function formatSize(bytes)
    if bytes < 1024 then return bytes .. " B"
    elseif bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024)
    else return string.format("%.1f MB", bytes / (1024 * 1024)) end
end

-- Запрос с ретраями. Возвращает response или nil, текст_ошибки
local function requestWithRetry(url)
    local lastErr = "неизвестная ошибка"
    for attempt = 1, REQUEST_RETRIES do
        local ok, response = pcall(internet.request, url)
        if ok and response then
            return response
        end
        lastErr = ok and "пустой ответ" or tostring(response)
        if attempt < REQUEST_RETRIES then
            os.sleep(RETRY_DELAY)
        end
    end
    return nil, lastErr
end

-- ============== 1. МАНИФЕСТ ==============

print("=== УСТАНОВЩИК ME-CONTROL ===")
print("Загрузка манифеста...")

local mResponse, mErr = requestWithRetry(rawBase .. "manifest.txt" .. cacheBuster)
if not mResponse then
    print("[ОШИБКА] Нет связи с GitHub | Причина: " .. tostring(mErr))
    return
end

local chunks = {}
local readOk, readErr = pcall(function()
    for chunk in mResponse do
        chunks[#chunks + 1] = chunk
    end
end)

local manifestData = table.concat(chunks)
if not readOk then
    print("[ОШИБКА] Не удалось прочитать manifest.txt | Причина: " .. tostring(readErr))
    return
end
if manifestData:find("404: Not Found", 1, true) or manifestData:match("^%s*$") then
    print("[ОШИБКА] manifest.txt не найден или пуст в репозитории!")
    return
end

-- ============== 2. ПАРСИНГ ==============

local filesToDownload = {}
local seen = {}
local skipped = 0

for line in manifestData:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")           -- обрезаем пробелы/CR
    if line ~= "" and not line:match("^#") then  -- пустые строки и комментарии
        if not isSafePath(line) then
            print("[ПРОПУСК] Небезопасный путь: " .. line)
            skipped = skipped + 1
        elseif seen[line] then
            print("[ПРОПУСК] Дубликат: " .. line)
            skipped = skipped + 1
        else
            seen[line] = true
            filesToDownload[#filesToDownload + 1] = line
        end
    end
end

if #filesToDownload == 0 then
    print("[ОШИБКА] В manifest.txt нет файлов для загрузки (пусто, только комментарии или небезопасные пути).")
    return
end

local totalFiles = #filesToDownload
print("Файлов к загрузке: " .. totalFiles .. (skipped > 0 and (" (пропущено: " .. skipped .. ")") or ""))

-- ============== 3. СКАЧИВАНИЕ ==============

local successCount, failed = 0, 0
local totalBytes = 0
local startTime = computer.uptime()

-- Скачивает один файл атомарно. Возвращает true, bytes | false, причина
local function downloadFile(filePath)
    local targetPath = TARGET_DIR .. filePath
    local tmpPath = targetPath .. ".tmp"

    -- Каталоги
    local dir = filesystem.path(targetPath)
    if dir ~= "" then
        local dOk, dBad = mkdirp(dir)
        if not dOk then
            return false, "не удалось создать каталог: " .. tostring(dBad)
        end
    end

    -- Запрос с ретраями
    local fResponse, fErr = requestWithRetry(rawBase .. filePath .. cacheBuster)
    if not fResponse then
        return false, "нет связи (" .. tostring(fErr) .. ")"
    end

    -- Пишем во временный файл, НЕ трогая целевой
    local file = io.open(tmpPath, "wb")
    if not file then
        return false, "не удалось открыть файл на запись"
    end

    local bytes = 0
    local startedAt = computer.uptime()
    local ok, err = pcall(function()
        local firstChunk = true
        for chunk in fResponse do
            if firstChunk then
                firstChunk = false
                if chunk:find("404: Not Found", 1, true) then
                    error("HTTP 404: Not Found")
                end
            end
            file:write(chunk)
            bytes = bytes + #chunk
            if computer.uptime() - startedAt > READ_TIMEOUT then
                error("timeout: превышен лимит " .. READ_TIMEOUT .. " с")
            end
        end
    end)

    -- Всегда закрываем дескриптор
    file:close()

    if not ok then
        filesystem.remove(tmpPath)
        return false, tostring(err)
    end

    -- Атомарная замена: удалить старый и переименовать .tmp
    if filesystem.exists(targetPath) then
        filesystem.remove(targetPath)
    end
    local renamed, renameErr = filesystem.rename(tmpPath, targetPath)
    if not renamed then
        filesystem.remove(tmpPath)
        return false, "не удалось переименовать: " .. tostring(renameErr)
    end

    return true, bytes
end

for i, filePath in ipairs(filesToDownload) do
    local ok, info = downloadFile(filePath)
    if ok then
        print(string.format("[%d/%d] OK: %s | %s", i, totalFiles, filePath, formatSize(info)))
        successCount = successCount + 1
        totalBytes = totalBytes + info
    else
        print(string.format("[%d/%d] ОШИБКА: %s | Причина: %s", i, totalFiles, filePath, tostring(info)))
        failed = failed + 1
    end
end

-- ============== 4. ИТОГИ ==============

local timeTaken = computer.uptime() - startTime
print("\n=== ГОТОВО ===")
print("Успешно: " .. successCount .. " | Ошибок: " .. failed)
print("Общий размер: " .. formatSize(totalBytes))
print(string.format("Время выполнения: %.2f сек.", timeTaken))

if successCount > 0 and failed == 0 then
    print("Все файлы обновлены до последней версии!")
    print("Запускайте: main.lua")
elseif failed > 0 then
    print("Часть файлов не обновлена — см. ошибки выше. Повторите запуск.")
end