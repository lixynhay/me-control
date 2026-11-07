local serialization = require("serialization")
local filesystem = require("filesystem")

local db = {}
local DB_PATH = "/home/database.dat"
local data = nil

-- Загрузка базы данных из файла
function db.load()
    if filesystem.exists(DB_PATH) then
        local file = io.open(DB_PATH, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, loaded = pcall(serialization.unserialize, content)
            if ok and type(loaded) == "table" then
                data = loaded
                data.players = data.players or {}
                data.config = data.config or { allowUserWithdraw = true, allowUserDeposit = true }
                data.thresholds = data.thresholds or {}
                data.logs = data.logs or {}
            end
        end
    end
    
    -- Если файла нет или он поврежден, создаем структуру по умолчанию
    if not data then
        data = {
            players = {
                ["lixynhay"] = { role = "admin" }
            },
            config = {
                allowUserWithdraw = true,
                allowUserDeposit = true
            },
            thresholds = {},
            logs = {}
        }
        db.save() -- Сразу сохраняем стандартные настройки
    end
end

-- Сохранение базы данных в файл
function db.save()
    if data then
        local content = serialization.serialize(data)
        local file = io.open(DB_PATH, "w")
        if file then
            file:write(content)
            file:close()
        end
    end
end

-- Получить данные игрока
function db.getPlayer(name)
    if data and data.players[name] then
        return data.players[name]
    end
    return nil
end

-- Зарегистрировать нового игрока
function db.registerPlayer(name)
    if data and not data.players[name] then
        data.players[name] = { role = "user" }
        db.save()
        return true
    end
    return false
end

-- Проверить, является ли игрок админом
function db.isAdmin(name)
    local player = db.getPlayer(name)
    return player and player.role == "admin"
end

-- Установить роль игрока
function db.setRole(name, role)
    if data and data.players[name] then
        data.players[name].role = role
        db.save()
        return true
    end
    return false
end

-- Получить список всех игроков
function db.getAllPlayers()
    if data then
        return data.players
    end
    return {}
end

-- Получить глобальные настройки
function db.getConfig()
    return data and data.config or {}
end

-- Изменить глобальную настройку
function db.setConfig(key, value)
    if data and data.config then
        data.config[key] = value
        db.save()
    end
end

-- Получить лимиты предметов
function db.getThresholds()
    if not data then return {} end
    if not data.thresholds then data.thresholds = {} end
    return data.thresholds
end

-- Установить лимит предмета: itemName -> {label, min}; minAmount == 0 удаляет лимит
function db.setThreshold(itemName, itemLabel, minAmount)
    if not data then return false end
    if not data.thresholds then data.thresholds = {} end
    if not itemName or itemName == "" then return false end
    if minAmount == 0 then
        data.thresholds[itemName] = nil
    else
        data.thresholds[itemName] = { label = itemLabel or itemName, min = minAmount }
    end
    db.save()
    return true
end

-- Добавить запись в лог операций (свежие сверху, максимум 200)
function db.addLog(player, action, item, amount)
    if not data then return end
    if not data.logs then data.logs = {} end
    
    local okT, t = pcall(os.time)
    local time = (okT and tonumber(t)) or 0
    local entry = {
        time = time,
        player = player or "Unknown",
        action = action, -- "take" (взял) или "put" (сдал)
        item = item or "Unknown",
        amount = amount or 0
    }
    
    table.insert(data.logs, 1, entry) -- свежие сверху
    if #data.logs > 200 then
        table.remove(data.logs)
    end
    db.save()
end

-- Получить массив логов (свежие первыми)
function db.getLogs()
    if not data then return {} end
    if not data.logs then data.logs = {} end
    return data.logs
end

return db
