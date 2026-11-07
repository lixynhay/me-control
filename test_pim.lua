-- test_pim.lua — диагностика формата данных PIM (OpenPeripheral)
-- Запуск в OpenOS: test_pim
-- Выводит структуру первого непустого слота инвентаря игрока на PIM.

local component = require("component")

if not component.isAvailable("pim") then
    print("PIM не найден (нужен OpenPeripheral)")
    return
end

local pim = component.pim

print("Игрок на PIM: " .. tostring(pim.getInventoryName()))
print("Размер инвентаря: " .. tostring(pim.getInventorySize()))
print(string.rep("-", 40))

local size = pim.getInventorySize() or 0
local found = false

for slot = 1, size do
    local ok, stack = pcall(pim.getStackInSlot, slot)
    if ok and stack then
        local count = stack.qty or stack.size or stack.amount or stack.count or 0
        local hasId = stack.name or stack.label or stack.display_name or stack.id
        if count > 0 or hasId then
            print("Первый непустой слот: " .. slot)
            local keys = {}
            for k in pairs(stack) do table.insert(keys, tostring(k)) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = stack[k]
                print("  " .. tostring(k) .. " = " .. tostring(v) .. "  [" .. type(v) .. "]")
            end
            found = true
            break
        end
    end
end

if not found then
    print("Непустых слотов не найдено.")
    local ok, stack = pcall(pim.getStackInSlot, 1)
    if ok and stack then
        print("Слот 1 (сырой):")
        for k, v in pairs(stack) do
            print("  " .. tostring(k) .. " = " .. tostring(v) .. "  [" .. type(v) .. "]")
        end
    end
end