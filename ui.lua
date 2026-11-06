local component = require("component")
local unicode = require("unicode")
local config = require("config")
local gpu = component.gpu

local ui = {}
local C = config.colors

function ui.drawFrame(x, y, w, h, color)
    gpu.setForeground(color)
    gpu.set(x, y, "╔" .. string.rep("═", w - 2) .. "╗")
    for i = 1, h - 2 do 
        gpu.set(x, y + i, "║")
        gpu.set(x + w - 1, y + i, "║") 
    end
    gpu.set(x, y + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
    gpu.setForeground(C.fg)
end

function ui.drawButton(x, y, w, text, pressed, bg)
    gpu.setBackground(pressed and C.hover or bg or C.btn)
    gpu.fill(x, y, w, 1, " ")
    
    local t = "[ " .. text .. " ]"
    gpu.setForeground(C.white)
    gpu.set(x + math.floor((w - unicode.len(t)) / 2) + (pressed and 1 or 0), y, t)
    
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawList(W, H, items, currentPage, totalPages)
    gpu.setBackground(C.bg)
    gpu.fill(2, 5, W - 3, H - 9, " ")
    
    if #items == 0 then 
        gpu.setForeground(0x888888)
        gpu.set(3, 6, "МЭ-сеть пуста...")
        return 
    end
    
    local startIdx = (currentPage - 1) * (H - 9) + 1
    local endIdx = math.min(currentPage * (H - 9), #items)
    local maxL = W - 20
    
    for i = startIdx, endIdx do
        local dLabel = items[i].label
        if unicode.len(dLabel) > maxL then 
            dLabel = unicode.sub(dLabel, 1, maxL - 3) .. "..." 
        end
        gpu.setForeground(C.fg)
        gpu.set(3, 5 + (i - startIdx), dLabel .. string.rep(" ", maxL - unicode.len(dLabel)) .. " | " .. string.format("%8d", items[i].size))
    end
    
    gpu.setForeground(0x888888)
    local pText = "Стр. " .. currentPage .. " из " .. totalPages
    gpu.set(W - unicode.len(pText) - 3, 2, pText)
end

function ui.drawMain(W, H, items, currentPage, totalPages)
    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H, " ")
    ui.drawFrame(1, 1, W, H, C.border)
    
    gpu.setForeground(C.title)
    local t = "--- Содержимое МЭ-сети ---"
    gpu.set(math.floor((W - unicode.len(t)) / 2) + 1, 2, t)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    
    ui.drawButton(5, H - 2, 12, "<<", false)
    ui.drawButton(19, H - 2, 15, "ОБНОВИТЬ", false)
    ui.drawButton(36, H - 2, 12, ">>", false)
    ui.drawButton(W - 20, H - 2, 15, "ВЫХОД", false)
    
    ui.drawList(W, H, items, currentPage, totalPages)
end

function ui.drawModal(W, H, item, quantity)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, W, H, " ")
    local mw, mh = 56, 16
    local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
    
    gpu.setBackground(C.modal)
    gpu.fill(mx, my, mw, mh, " ")
    ui.drawFrame(mx, my, mw, mh, C.title)
    
    gpu.setForeground(C.title)
    local t = " Инфо о предмете "
    gpu.set(mx + math.floor((mw - unicode.len(t)) / 2) + 1, my, t)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 2, "Название:")
    gpu.setForeground(C.fg)
    local n = item.label
    if unicode.len(n) > mw - 4 then n = unicode.sub(n, 1, mw - 7) .. "..." end
    gpu.set(mx + 2, my + 3, n)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 5, "В сети:")
    gpu.setForeground(C.ok); gpu.set(mx + 10, my + 5, tostring(item.size) .. " шт.")
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 7, "Количество:")
    ui.drawButton(mx + 2, my + 9, 6, "-10", false)
    ui.drawButton(mx + 9, my + 9, 6, "-1", false)
    
    gpu.setForeground(C.ok)
    local q = tostring(quantity) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", 10 - unicode.len(q)) .. q)
    
    ui.drawButton(mx + 29, my + 9, 6, "+1", false)
    ui.drawButton(mx + 36, my + 9, 6, "+10", false)
    ui.drawButton(mx + 2, my + mh - 2, 18, "ЗАБРАТЬ ИЗ МЭ", false, C.ok)
    ui.drawButton(mx + 22, my + mh - 2, 18, "ПОЛОЖИТЬ В МЭ", false, 0xAA5500)
    ui.drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, 0xAA0000)
end

return ui
