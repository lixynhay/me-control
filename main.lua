local component = require("component")
local event = require("event")
local unicode = require("unicode")
local gpu = component.gpu

local config = require("config")
local ui = require("ui")
local api = require("me_api")

-- Проверки
if not component.isAvailable("me_interface") or not component.isAvailable("pim") then
    print("Ошибка: ME Interface или PIM не найден!")
    os.exit()
end

gpu.setResolution(gpu.maxResolution())
local W, H = gpu.getResolution()

-- Состояние приложения
local state = {
    items = {},
    page = 1,
    totalPages = 1,
    selectedItem = nil,
    quantity = 1
}

local function setStatus(msg, isError)
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    gpu.setForeground(isError and config.colors.err or config.colors.ok)
    gpu.set(3, H - 1, msg)
end

local function updateList()
    state.items = api.getNetworkItems()
    state.totalPages = math.max(1, math.ceil(#state.items / (H - 9)))
    if state.page > state.totalPages then state.page = state.totalPages end
end

-- Инициализация
updateList()
ui.drawMain(W, H, state.items, state.page, state.totalPages)

-- Главный цикл
while true do
    local _, _, x, y = event.pull("touch")
    
    if state.selectedItem then
        local mw, mh = 56, 16
        local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
        
        -- Кнопки количества
        if y == my + 9 then
            local old = state.quantity
            if x >= mx + 2 and x < mx + 8 then state.quantity = math.max(1, state.quantity - 10) end
            if x >= mx + 9 and x < mx + 15 then state.quantity = math.max(1, state.quantity - 1) end
            if x >= mx + 29 and x < mx + 35 then state.quantity = math.min(state.selectedItem.size, state.quantity + 1) end
            if x >= mx + 36 and x < mx + 42 then state.quantity = math.min(state.selectedItem.size, state.quantity + 10) end
            if old ~= state.quantity then ui.drawModal(W, H, state.selectedItem, state.quantity) end
        end
        
        -- Забрать
        if y == my + mh - 2 and x >= mx + 2 and x < mx + 20 then
            local ok, msg = api.exportToPlayer(state.selectedItem, state.quantity)
            setStatus(msg, not ok)
            os.sleep(1.5)
            state.selectedItem = nil
            updateList()
            ui.drawMain(W, H, state.items, state.page, state.totalPages)
        end
        
        -- Положить
        if y == my + mh - 2 and x >= mx + 22 and x < mx + 40 then
            local ok, msg = api.pushFromPlayer(state.selectedItem.label, state.quantity)
            setStatus(msg, not ok)
            os.sleep(1.5)
            state.selectedItem = nil
            updateList()
            ui.drawMain(W, H, state.items, state.page, state.totalPages)
        end
        
        -- Закрыть
        if y == my + mh - 2 and x >= mx + mw - 14 and x < mx + mw - 2 then
            state.selectedItem = nil
            ui.drawMain(W, H, state.items, state.page, state.totalPages)
        end
        
    else
        local clicked = false
        -- Кнопки навигации
        if y == H - 2 then
            if x >= 5 and x < 17 then clicked = true; if state.page > 1 then state.page = state.page - 1; ui.drawMain(W, H, state.items, state.page, state.totalPages) end end
            if x >= 19 and x < 34 then clicked = true; updateList(); ui.drawMain(W, H, state.items, state.page, state.totalPages); setStatus("Список обновлен.") end
            if x >= 36 and x < 48 then clicked = true; if state.page < state.totalPages then state.page = state.page + 1; ui.drawMain(W, H, state.items, state.page, state.totalPages) end end
            if x >= W - 20 and x < W - 5 then clicked = true; setStatus("Выход...", true); os.sleep(0.5); os.exit() end
        end
        
        -- Клик по списку
        if not clicked and y >= 5 and y <= H - 5 and x >= 3 and x <= W - 3 then
            local idx = (state.page - 1) * (H - 9) + (y - 4)
            if state.items[idx] then 
                state.selectedItem = state.items[idx]
                state.quantity = 1
                ui.drawModal(W, H, state.selectedItem, state.quantity) 
            end
        end
    end
end
