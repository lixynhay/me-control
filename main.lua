local component = require("component")
local event = require("event")
local computer = require("computer") -- Для выхода
local gpu = component.gpu
local screen = component.screen

if not component.isAvailable("me_interface") then
    print("Ошибка: ME Interface не найден!")
    os.exit()
end
local me = component.me_interface

local COLOR_BG = 0x000000
local COLOR_FG = 0xFFFFFF
local COLOR_BTN = 0x333333
local COLOR_BTN_ACTIVE = 0x00AA00
local COLOR_HEADER = 0x00AAAA

local itemList = {}

local function drawButton(x, y, width, text, isActive)
    if isActive then
        gpu.setBackground(COLOR_BTN_ACTIVE)
    else
        gpu.setBackground(COLOR_BTN)
    end
    gpu.fill(x, y, width, 1, " ")
    gpu.setForeground(COLOR_FG)
    local textX = x + math.floor((width - #text) / 2)
    gpu.set(textX, y, text)
    gpu.setBackground(COLOR_BG)
    gpu.setForeground(COLOR_FG)
end

local function refreshList()
    local rawItems = me.getItemsInNetwork()
    itemList = {}
    
    for _, item in pairs(rawItems) do
        if item and item.label then
            table.insert(itemList, {
                label = item.label,
                size = item.size
            })
        end
    end
end

local function drawList()
    gpu.setBackground(COLOR_BG)
    gpu.fill(2, 6, 76, 15, " ")
    
    gpu.setForeground(COLOR_HEADER)
    gpu.set(2, 5, "--- Содержимое МЭ-сети ---")
    gpu.setForeground(COLOR_FG)
    
    for i = 1, math.min(#itemList, 15) do
        local item = itemList[i]
        local line = string.format("%-40s %10d", item.label, item.size)
        gpu.set(2, 5 + i, line)
    end
    
    if #itemList > 15 then
        gpu.set(2, 5 + 16, "... и еще " .. (#itemList - 15) .. " предметов")
    end
end

local buttons = {
    {x = 10, y = 22, width = 15, text = "Обновить", action = "refresh"},
    {x = 30, y = 22, width = 15, text = "Выход", action = "exit"},
}

gpu.setBackground(COLOR_BG)
gpu.setForeground(COLOR_FG)
gpu.fill(1, 1, 80, 25, " ")

for _, btn in ipairs(buttons) do
    drawButton(btn.x, btn.y, btn.width, btn.text, false)
end

refreshList()
drawList()

while true do
    local _, _, x, y = event.pull("touch")
    
    for i, btn in ipairs(buttons) do
        if y == btn.y and x >= btn.x and x < btn.x + btn.width then
            for j, otherBtn in ipairs(buttons) do
                drawButton(otherBtn.x, otherBtn.y, otherBtn.width, otherBtn.text, j == i)
            end
            
            if btn.action == "refresh" then
                refreshList()
                drawList()
                gpu.set(2, 24, "Список обновлен!")
            elseif btn.action == "exit" then
                gpu.set(2, 24, "Завершение работы...")
                os.sleep(0.5)
                os.exit()
            end
            
            for j, otherBtn in ipairs(buttons) do
                drawButton(otherBtn.x, otherBtn.y, otherBtn.width, otherBtn.text, false)
            end
            
            break
        end
    end
end
