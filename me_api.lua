local component = require("component")
local config = require("config")
local me = component.me_interface
local pim = component.pim

local api = {}

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

function api.exportToPlayer(item, amount)
    -- Проверяем, сколько реально можем дать
    local realAmount = math.min(amount, item.size)
    if realAmount <= 0 then return false, "В МЭ нет предметов" end
    
    -- Пытаемся выдать
    local ok, err = me.exportItem({id = item.name, dmg = item.damage}, config.side_export, realAmount, 0)
    if ok then 
        return true, "Выдано: " .. realAmount .. " шт." 
    else 
        return false, "Ошибка: " .. tostring(err) 
    end
end

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

return api
