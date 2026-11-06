local component = require("component")
local event = require("event")
local unicode = require("unicode")
local gpu = component.gpu
local screen = component.screen

-- Проверка наличия ME Interface и PIM
if not component.isAvailable("me_interface") then
    print("Ошибка: ME Interface не найден!")
    os.exit()
end
local me = component.me_interface

if not component.isAvailable("pim") then
    print("Ошибка: PIM не найден! Установите адаптер к PIM.")
    os.exit()
end
local pim = component.pim

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
local COLOR_MODAL_BG = 0x2A2A2A

local itemList = {}
local currentPage = 1
local itemsPerPage = 15
local totalPages = 1
local selectedItem = nil
local selectedQuantity = 1

gpu.setResolution(gpu.maxResolution())
local W, H = gpu.getResolution()

-- ... (функции drawFrame, drawButton, refreshList, drawList остаются без изменений) ...

-- ОБНОВЛЕННАЯ ФУНКЦИЯ ОТРИСОВКИ КАРТОЧКИ
local function drawModal()
    -- ... (очистка экрана и рамка) ...
    
    -- ... (вывод информации о предмете) ...

    -- Блок выбора количества
    gpu.setForeground(COLOR_WHITE)
    gpu.set(mx + 2, my + 7, "Количество:")
    drawButton(mx + 2, my + 9, 6, "-10", false)
    drawButton(mx + 9, my + 9, 6, "-1", false)
    gpu.setForeground(COLOR_STATUS_OK)
    local qtyText = tostring(selectedQuantity) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", 10 - unicode.len(qtyText)) .. qtyText)
    drawButton(mx + 29, my + 9, 6, "+1", false)
    drawButton(mx + 36, my + 9, 6, "+10", false)
    
    -- Кнопки действий
    drawButton(mx + 2, my + mh - 2, 18, "ЗАБРАТЬ ИЗ МЭ", false, 0x00AA00) -- Зеленая
    drawButton(mx + 22, my + mh - 2, 18, "ПОЛОЖИТЬ В МЭ", false, 0xAA5500) -- Оранжевая
    drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, 0xAA0000) -- Красная
end

-- ... (основная часть кода с кнопками и циклом) ...

while true do
    local _, _, x, y = event.pull("touch")
    
    if selectedItem then
        -- ... (логика для открытого окна) ...
        
        -- Обработка кнопки "ЗАБРАТЬ ИЗ МЭ" (Экспорт из МЭ в инвентарь игрока)
        if y == my + mh - 2 and x >= mx + 2 and x < mx + 20 then
            -- Находим предмет в сети, чтобы получить его fingerprint
            local targetItem = nil
            for _, item in pairs(me.getItemsInNetwork()) do
                if item.label == selectedItem.label then
                    targetItem = item
                    break
                end
            end
            
            if targetItem then
                -- Экспортируем предмет в сторону PIM (направление нужно указать ваше!)
                local success, errorMsg = me.exportItem({
                    id = targetItem.name,
                    dmg = targetItem.damage
                }, "UP", selectedQuantity, 0) -- "UP" - замените на ваше направление
                
                if success then
                    gpu.setForeground(COLOR_STATUS_OK)
                    gpu.set(mx + 2, my + mh - 4, "Успешно выдано: " .. selectedQuantity .. " шт.")
                else
                    gpu.setForeground(COLOR_STATUS_ERR)
                    gpu.set(mx + 2, my + mh - 4, "Ошибка: " .. tostring(errorMsg))
                end
            end
            os.sleep(1)
            selectedItem = nil
            drawMainScreen()
        end
        
        -- Обработка кнопки "ПОЛОЖИТЬ В МЭ" (Из инвентаря игрока в МЭ)
        if y == my + mh - 2 and x >= mx + 22 and x < mx + 40 then
            local movedCount = 0
            -- Проходим по всем слотам инвентаря игрока
            for slot = 1, pim.getInventorySize() do
                local stack = pim.getStackInSlot(slot)
                -- Если в слоте лежит тот же предмет, что выбран, выталкиваем его в МЭ
                if stack and stack.label == selectedItem.label then
                    -- Выталкиваем в направлении МЭ-интерфейса (направление нужно указать ваше!)
                    local moved = pim.pushItem("DOWN", slot, selectedQuantity) -- "DOWN" - замените на ваше направление
                    movedCount = movedCount + moved
                    if movedCount >= selectedQuantity then break end
                end
            end
            
            if movedCount > 0 then
                gpu.setForeground(COLOR_STATUS_OK)
                gpu.set(mx + 2, my + mh - 4, "Успешно сдано: " .. movedCount .. " шт.")
            else
                gpu.setForeground(COLOR_STATUS_ERR)
                gpu.set(mx + 2, my + mh - 4, "Предмет не найден в инвентаре.")
            end
            os.sleep(1)
            selectedItem = nil
            drawMainScreen()
        end
        
        -- ... (обработка кнопки "ЗАКРЫТЬ") ...
    else
        -- ... (логика для основного экрана) ...
    end
end
