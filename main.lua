local component = require("component")
local event = require("event")
local gpu = component.gpu
local screen = component.screen

if not component.isAvailable("me_interface") then
    print("Ошибка: ME Interface не найден!")
    os.exit()
end
local me = component.me_interface

local COLOR_BG = 0x1A1A1A
local COLOR_FG = 0xE0E0E0
local COLOR_BORDER = 0x0055AA
local COLOR_TITLE = 0x00AAFF
local COLOR_BTN = 0x333333
local COLOR_BTN_HOVER = 0x00AA00
local COLOR_WHITE = 0xFFFFFF

local itemList = {}

local function drawFrame(x, y, w, h, color)
    gpu.setForeground(color)
    gpu.set(x, y, "╔" .. string.rep("═", w - 2) .. "╗")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "║")
        gpu.set(x + w - 1, y + i, "║")
    end
    gpu.set(x, y + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
    gpu.setForeground(COLOR_FG)
end

local function drawButton(x, y, width, text, isPressed)
    if isPressed then
        gpu.setBackground(COLOR_BTN_HOVER)
    else
        gpu.setBackground(COLOR_BTN)
    end
    gpu.fill(x, y, width, 1, " ")
    
    local btnText = "[ " .. text .. " ]"
    local textX = x + math.floor((width - #btnText) / 2)
    
    gpu.setForeground(COLOR_WHITE)
    if isPressed then
        gpu.set(textX + 1, y + 1, btnText)
    else
        gpu.set(textX, y, btnText)
    end
    
    gpu.setBackground(COLOR_BG)
    gpu.setForeground(COLOR_FG)
end

local function refreshList()
    local rawItems = me.getItemsInNetwork()
    itemList = {}
    for _, item in pairs(rawItems) do
        if item and item.label then
            table.insert(itemList, { label = item.label, size = item.size })
        end
    end
end

local function drawList()
    gpu.setBackground(COLOR_BG)
    gpu.fill(2, 5, 76, 15, " ")
    
    for i = 1, math.min(#itemList, 15) do
        local item = itemList[i]
        
        local displayLabel = item.label
        if #displayLabel > 45 then
            displayLabel = string.sub(displayLabel, 1, 42) .. "..."
        end
        
        local line = string.format("%-45s | %8d", displayLabel, item.size)
        gpu.setForeground(COLOR_FG)
        gpu.set(3, 4 + i, line)
    end
    
    if #itemList > 15 then
        gpu.setForeground(0x888888)
        gpu.set(3, 20, "... и еще " .. (#itemList - 15) .. " предметов")
    end
end

local buttons = {
    {x = 10, y = 22, width = 18, text = "ОБНОВИТЬ", action = "refresh"},
    {x = 40, y = 22, width = 18, text = "ВЫХОД", action = "exit"},
}

gpu.setBackground(COLOR_BG)
gpu.setForeground(COLOR_FG)
gpu.fill(1, 1, 80, 25, " ")

drawFrame(1, 1, 80, 25, COLOR_BORDER)

gpu.setForeground(COLOR_TITLE)
local title = "--- Содержимое МЭ-сети ---"
gpu.set(math.floor((80 - #title) / 2), 2, title)

drawFrame(2, 4, 76, 17, COLOR_BORDER)

for _, btn in ipairs(buttons) do
    drawButton(btn.x, btn.y, btn.width, btn.text, false)
end

refreshList()
drawList()

while true do
    local _, _, x, y = event.pull("touch")
    
    for i, btn in ipairs(buttons) do
        if y == btn.y and x >= btn.x and x < btn.x + btn.width then
            
            drawButton(btn.x, btn.y, btn.width, btn.text, true)
            os.sleep(0.1)
            
            if btn.action == "refresh" then
                refreshList()
                drawList()
                gpu.setForeground(0x00AA00)
                gpu.set(3, 23, "Статус: Список успешно обновлен!      ")
                gpu.setForeground(COLOR_FG)
                
            elseif btn.action == "exit" then
                gpu.setForeground(0xFF5555)
                gpu.set(3, 23, "Статус: Завершение работы...")
                os.sleep(0.5)
                os.exit()
            end
            
            drawButton(btn.x, btn.y, btn.width, btn.text, false)
            break 
        end
    end
end
