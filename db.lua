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
            }
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

return db
