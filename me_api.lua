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

return api
