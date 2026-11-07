-- locale.lua — русские названия предметов.
-- Основной словарь — locale_generated.lua (byLabel: английское имя -> русское),
-- сгенерирован из языковых файлов модпака.
-- Ручные переопределения по registry id — в locale.manual (имеют приоритет).

local locale = {}
locale.names = {}
locale.byLabel = {}

local okGen, gen = pcall(require, "locale_generated")
if okGen and type(gen) == "table" then
    if type(gen.names) == "table" then
        for k, v in pairs(gen.names) do locale.names[k] = v end
    end
    if type(gen.byLabel) == "table" then
        for k, v in pairs(gen.byLabel) do locale.byLabel[k] = v end
    end
end

-- Ручные переопределения по registry id (приоритетнее сгенерированных)
locale.manual = {
    -- ["appliedenergistics2:certus_quartz_crystal"] = "Кристалл истинного кварца",
}
for k, v in pairs(locale.manual) do locale.names[k] = v end

-- itemName — registry id (name), damage — метаданные, fallback — игровое (английское) имя.
function locale.getName(itemName, damage, fallback)
    if itemName then
        local v = locale.names[itemName]
        if v ~= nil then
            if type(v) == "table" then
                local d = tonumber(damage) or 0
                return v[d] or v["*"] or fallback
            end
            return v
        end
    end
    if fallback then
        local clean = tostring(fallback):gsub("§.", "")
        clean = clean:match("^%s*(.-)%s*$") or clean
        if clean ~= "" and locale.byLabel[clean] then
            return locale.byLabel[clean]
        end
    end
    return fallback
end

return locale