local component = require("component")
local config = require("config")
local db = require("db")
local me = component.me_interface
local pim = component.pim

local api = {}

-- Получить предметы из МЭ
function api.getNetworkItems()
    local raw = me.getItemsInNetwork()
    local list = {}
    for _, i in pairs(raw) do 
        if i and i.label then 
            table.insert(list, {label = i.label, size = i.size, name = i.name, damage = i.damage}) 
        end 
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- Получить инвентарь игрока (сгруппированный)
function api.getPlayerInventory()
    local inv = {}
    if not api.isPlayerPresent() then return inv end
    
    local size = pim.getInventorySize()
    for slot = 1, size do
        local stack = pim.getStackInSlot(slot)
        if stack and stack.label then
            local found = false
            for _, item in ipairs(inv) do
                if item.label == stack.label and item.damage == stack.damage then
                    item.size = item.size + stack.size
                    found = true
                    break
                end
            end
            if not found then
                table.insert(inv, {label = stack.label, size = stack.size, name = stack.name, damage = stack.damage})
            end
        end
    end
    table.sort(inv, function(a, b) return a.label < b.label end)
    return inv
end

-- Выдать игроку из МЭ
function api.exportToPlayer(item, amount)
    local realAmount = math.min(amount, item.size)
    if realAmount <= 0 then return false, "В МЭ нет предметов" end
    
    local ok, err = me.exportItem({id = item.name, dmg = item.damage}, config.side_export, realAmount, 0)
    if ok then return true, "Выдано: " .. realAmount .. " шт." 
    else return false, "Ошибка: " .. tostring(err) end
end

-- Забрать у игрока в МЭ
function api.pushFromPlayer(itemLabel, amount)
    local moved = 0
    for slot = 1, pim.getInventorySize() do
        local stack = pim.getStackInSlot(slot)
        if stack and stack.label == itemLabel then
            local canMove = math.min(amount - moved, stack.size)
            if canMove > 0 then
                moved = moved + pim.pushItem(config.side_push, slot, canMove)
                if moved >= amount then break end
            end
        end
    end
    
    if moved > 0 then return true, "Сдано: " .. moved .. " шт." 
    else return false, "Предмет не найден в инвентаре" end
end

-- Проверка наличия игрока
function api.isPlayerPresent()
    local name = pim.getInventoryName()
    return name ~= nil and name ~= ""
end

-- Проверки прав
function api.canWithdraw(playerName)
    if not playerName then return false end
    local player = db.getPlayer(playerName)
    if not player or player.role == "banned" then return false end
    return db.getConfig().allowUserWithdraw ~= false
end

function api.canDeposit(playerName)
    if not playerName then return false end
    local player = db.getPlayer(playerName)
    if not player or player.role == "banned" then return false end
    return db.getConfig().allowUserDeposit ~= false
end

-- Получить информацию о МЭ-сети (для вкладки «Статистика»)
function api.getNetworkInfo()
    local info = { totalItems = 0, totalTypes = 0, energyStored = nil, energyMax = nil, cpus = nil }
    
    -- Считаем предметы
    local items = me.getItemsInNetwork()
    info.totalTypes = #items
    for _, item in ipairs(items) do
        info.totalItems = info.totalItems + item.size
    end
    
    -- Пробуем получить энергию через me_controller
    if component.isAvailable("me_controller") then
        local ctrl = component.me_controller
        info.energyStored = ctrl.getEnergyStored()
        info.energyMax = ctrl.getMaxEnergyStored()
    end
    
    -- Пробуем получить список сопроцессоров (если метод есть)
    if me.getCpus then
        local ok, cpus = pcall(me.getCpus)
        if ok and cpus then
            info.cpus = #cpus
        end
    end
    
    return info
end

-- Статус по лимитам: массив {label, current, min, isOk}, отсортирован по имени
function api.getThresholdStatus()
    local list = {}
    local thresholds = db.getThresholds()
    
    -- Карта текущих количеств по имени предмета
    local currentMap = {}
    local items = me.getItemsInNetwork()
    for _, item in ipairs(items) do
        if item and item.name then
            currentMap[item.name] = (currentMap[item.name] or 0) + item.size
        end
    end
    
    for name, th in pairs(thresholds) do
        local current = currentMap[name] or 0
        table.insert(list, {
            label = th.label or name,
            current = current,
            min = th.min,
            isOk = current >= th.min
        })
    end
    
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- Сдать весь инвентарь игрока в МЭ
function api.depositAll()
    local moved = 0
    for slot = 1, pim.getInventorySize() do
        local stack = pim.getStackInSlot(slot)
        if stack and stack.size and stack.size > 0 then
            moved = moved + pim.pushItem(config.side_push, slot, stack.size)
        end
    end
    if moved > 0 then
        return moved, "Сдано всё: " .. moved .. " шт."
    end
    return 0, "Нечего сдавать"
end

return api
