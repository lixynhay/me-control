local component = require("component")
local event = require("event")
local unicode = require("unicode")
local gpu = component.gpu

local config = require("config")
local ui = require("ui")
local api = require("me_api")
local db = require("db")

if not component.isAvailable("me_interface") or not component.isAvailable("pim") then
    print("Ошибка: ME Interface или PIM не найден!") os.exit()
end

db.load()
gpu.setResolution(gpu.maxResolution())
local W, H = gpu.getResolution()

local state = {
    items = {}, page = 1, totalPages = 1, selectedItem = nil, quantity = 1,
    currentTab = "ME", player = nil, isAdmin = false, adminPlayers = {}
}

local function setStatus(msg, isError)
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    gpu.setForeground(isError and config.colors.err or config.colors.ok)
    gpu.set(3, H - 1, msg)
end

local function updateList()
    if state.currentTab == "ME" then
        state.items = api.getNetworkItems()
    elseif state.currentTab == "INV" then
        state.items = api.getPlayerInventory()
    elseif state.currentTab == "ADMIN" then
        state.adminPlayers = db.getAllPlayers()
    end
    state.totalPages = math.max(1, math.ceil(#state.items / (H - 10)))
    if state.page > state.totalPages then state.page = state.totalPages end
end

local function drawScreen()
    ui.drawMain(W, H, state)
end

updateList(); drawScreen()

while true do
    local eventName, p1, p2 = event.pull("touch", "player_on", "player_off")
    
    if eventName == "player_on" then
        state.player = tostring(p1)
        local pData = db.getPlayer(state.player)
        
        if not pData then
            db.registerPlayer(state.player)
            pData = db.getPlayer(state.player)
            setStatus("Новый игрок: " .. state.player)
        else
            setStatus("С возвращением, " .. state.player)
        end
        
        state.isAdmin = (pData.role == "admin")
        if state.isAdmin then setStatus("Вы вошли как Админ.") end
        
        state.currentTab = "ME" -- Сбрасываем на главную
        updateList(); drawScreen()
        
    elseif eventName == "player_off" then
        state.player = nil
        state.isAdmin = false
        state.currentTab = "ME" -- Если админ ушел, вкладка админа пропадет
        setStatus("Игрок ушел с PIM.", true)
        updateList(); drawScreen()
        
    elseif eventName == "touch" then
        local x, y = p1, p2
        
        -- Переключение вкладок (сложная математика, чтобы совпадало с ui.lua)
        if y == 2 then
            local t1, t2, t3 = " МЭ-сеть ", " Инвентарь ", " Админ "
            local totalW = unicode.len(t1) + unicode.len(t2) + 4
            if state.isAdmin then totalW = totalW + unicode.len(t3) + 2 end
            local startX = math.floor((W - totalW) / 2) + 1
            
            if x >= startX and x < startX + unicode.len(t1) then
                state.currentTab = "ME"
            elseif x >= startX + unicode.len(t1) + 2 and x < startX + unicode.len(t1) + unicode.len(t2) + 2 then
                state.currentTab = "INV"
            elseif state.isAdmin and x >= startX + unicode.len(t1) + unicode.len(t2) + 4 then
                state.currentTab = "ADMIN"
            end
            state.page = 1; state.selectedItem = nil
            updateList(); drawScreen()
            
        elseif state.currentTab == "ADMIN" and state.isAdmin then
            -- Клик по списку игроков в админке
            local row = y - 5
            if row >= 1 then
                local i = 1
                for name, data in pairs(state.adminPlayers) do
                    if i == row then
                        -- Меняем роль
                        local newRole = "user"
                        if data.role == "user" then newRole = "admin"
                        elseif data.role == "admin" then newRole = "banned" end
                        db.setRole(name, newRole)
                        setStatus("Роль " .. name .. " изменена на " .. newRole)
                        updateList(); drawScreen()
                        break
                    end
                    i = i + 1
                end
            end
            
        elseif state.selectedItem then
            local mw, mh = 56, 16
            local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
            
            -- Кнопки количества
            if y == my + 9 then
                local old = state.quantity
                if x >= mx + 2 and x < mx + 8 then state.quantity = math.max(1, state.quantity - 10) end
                if x >= mx + 9 and x < mx + 15 then state.quantity = math.max(1, state.quantity - 1) end
                if x >= mx + 29 and x < mx + 35 then state.quantity = math.min(state.selectedItem.size, state.quantity + 1) end
                if x >= mx + 36 and x < mx + 42 then state.quantity = math.min(state.selectedItem.size, state.quantity + 10) end
                if old ~= state.quantity then 
                    local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct) 
                end
            end
            
            -- Кнопка действия
            if y == my + mh - 2 and x >= mx + 2 and x < mx + 20 then
                if not state.player then
                    setStatus("Ошибка: на PIM никого нет!", true)
                elseif state.currentTab == "ME" and not api.canWithdraw(state.player) then
                    setStatus("Вам запрещено забирать предметы!", true)
                elseif state.currentTab == "INV" and not api.canDeposit(state.player) then
                    setStatus("Вам запрещено сдавать предметы!", true)
                else
                    local ok, msg
                    if state.currentTab == "ME" then
                        ok, msg = api.exportToPlayer(state.selectedItem, state.quantity)
                    else
                        ok, msg = api.pushFromPlayer(state.selectedItem.label, state.quantity)
                    end
                    setStatus(msg, not ok)
                end
                os.sleep(1.5); state.selectedItem = nil; updateList(); drawScreen()
            end
            
            -- Закрыть
            if y == my + mh - 2 and x >= mx + mw - 14 and x < mx + mw - 2 then
                state.selectedItem = nil; drawScreen()
            end
            
        else
            -- Навигация и список
            local clicked = false
            if y == H - 2 then
                if x >= 5 and x < 17 then clicked = true; if state.page > 1 then state.page = state.page - 1; drawScreen() end end
                if x >= 19 and x < 34 then clicked = true; updateList(); drawScreen(); setStatus("Обновлено.") end
                if x >= 36 and x < 48 then clicked = true; if state.page < state.totalPages then state.page = state.page + 1; drawScreen() end end
                if x >= W - 20 and x < W - 5 then setStatus("Выход...", true); os.sleep(0.5); os.exit() end
            end
            
            if not clicked and y >= 5 and y <= H - 5 and x >= 3 and x <= W - 3 then
                local idx = (state.page - 1) * (H - 10) + (y - 4)
                if state.items[idx] then 
                    state.selectedItem = state.items[idx]
                    state.quantity = 1
                    local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct) 
                end
            end
        end
    end
end
