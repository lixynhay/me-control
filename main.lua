local component = require("component")
local event = require("event")
local unicode = require("unicode") -- ВАЖНО: Библиотека для работы с UTF-8 (русским языком)
local gpu = component.gpu
local screen = component.screen

if not component.isAvailable("me_interface") then
    print("Ошибка: ME Interface не найден!")
    os.exit()
end
local me = component.me_interface

-- Палитра цветов
local COLOR_BG = 0x1A1A1A
local COLOR_FG = 0xE0E0E0
local COLOR_BORDER = 0x0055AA
local COLOR_TITLE = 0x00AAFF
local COLOR_BTN = 0x333333
local COLOR_BTN_HOVER = 0x00AA00
local COLOR_WHITE = 0xFFFFFF
local COLOR_STATUS_OK = 0x00AA00
local COLOR_STATUS_ERR = 0xFF5555

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
    -- Рисуем фон кнопки
    if isPressed then
        gpu.setBackground(COLOR_BTN_HOVER)
    else
        gpu.setBackground(COLOR_BTN)
    end
    gpu.fill(x, y, width, 1, " ")
    
    -- Формируем текст и центрируем его с учетом UTF-8
    local btnText = "[ " .. text .. " ]"
    local textLen = unicode.len(btnText)
    local textX = x + math.floor((width - textLen) / 2)
    
    gpu.setForeground(COLOR_WHITE)
    if isPressed then
        -- Сдвигаем только по X, чтобы текст не вылезал за пределы кнопки по Y
        gpu.set(textX + 1, y, btnText)
    else
        gpu.set(textX, y, btnText)
    end
    
    -- Возвращаем цвета
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
    
    -- Сортируем предметы по алфавиту, чтобы они не прыгали при обновлении
    table.sort(itemList, function(a, b) 
        return a.label < b.label 
    end)
end

local function drawList()
    -- Очищаем область списка
    gpu.setBackground(COLOR_BG)
    gpu.fill(2, 5, 76, 15, " ")
    
    if #itemList == 0 then
        gpu.setForeground(0x888888)
        gpu.set(3, 6, "МЭ-сеть пуста...")
        return
    end
    
    for i = 1, math.min(#itemList, 15) do
        local item = itemList[i]
        local displayLabel = item.label
        
        -- Обрезаем длинные названия (с учетом UTF-8 символов)
        local maxLabelLen = 40
        if unicode.len(displayLabel) > maxLabelLen then
            displayLabel = unicode.sub(displayLabel, 1, maxLabelLen - 3) .. "..."
        end
        
        -- Вычисляем отступ для ровной колонки
        local paddingCount = maxLabelLen - unicode.len(displayLabel)
        local padding = string.rep(" ", paddingCount)
        
        -- Форматируем строку: Название + отступ + | + количество
        local line = displayLabel .. padding .. " | " .. string.format("%8d", item.size)
        
        gpu.setForeground(COLOR_FG)
        gpu.set(3, 4 + i, line)
    end
    
    -- Если предметов больше 15, показываем счетчик снизу
    if #itemList > 15 then
        gpu.setForeground(0x888888)
        gpu.set(3, 19, "... и еще " .. (#itemList - 15) .. " предметов")
    end
end

local buttons = {
    {x = 10, y = 22, width = 18, text = "ОБНОВИТЬ", action = "refresh"},
    {x = 40, y = 22, width = 18, text = "ВЫХОД", action = "exit"},
}

-- Первичная отрисовка
gpu.setBackground(COLOR_BG)
gpu.setForeground(COLOR_FG)
gpu.fill(1, 1, 80, 25, " ")

drawFrame(1, 1, 80, 25, COLOR_BORDER)

gpu.setForeground(COLOR_TITLE)
local title = "--- Содержимое МЭ-сети ---"
-- Центрирование заголовка с учетом UTF-8
gpu.set(math.floor((80 - unicode.len(title)) / 2) + 1, 2, title)

drawFrame(2, 4, 76, 17, COLOR_BORDER)

for _, btn in ipairs(buttons) do
    drawButton(btn.x, btn.y, btn.width, btn.text, false)
end

refreshList()
drawList()

-- Главный цикл
while true do
    local _, _, x, y = event.pull("touch")
    
    for i, btn in ipairs(buttons) do
        -- Проверка, попал ли клик в кнопку
        if y == btn.y and x >= btn.x and x < btn.x + btn.width then
            
            -- Эффект нажатия
            drawButton(btn.x, btn.y, btn.width, btn.text, true)
            os.sleep(0.15) 
            
            if btn.action == "refresh" then
                refreshList()
                drawList()
                gpu.setForeground(COLOR_STATUS_OK)
                gpu.set(3, 23, "Статус: Список успешно обновлен!      ")
                gpu.setForeground(COLOR_FG)
                
            elseif btn.action == "exit" then
                gpu.setForeground(COLOR_STATUS_ERR)
                gpu.set(3, 23, "Статус: Завершение работы...")
                os.sleep(0.5)
                os.exit()
            end
            
            -- Возвращаем кнопку в исходное состояние
            drawButton(btn.x, btn.y, btn.width, btn.text, false)
            break 
        end
    end
end
