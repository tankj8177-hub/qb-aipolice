RegisterNetEvent('qb-aipolice:server:vehicleStolen',function(plate)
    local src=source; local c=Config.Detection.vehicleTheft
    if c.enabled then AddHeat(src,c.heatPoints,'vehicleTheft',c.starsMin) end
end)

RegisterNetEvent('qb-aipolice:server:speeding',function(speedKmh,reckless)
    local src=source; local c=Config.Detection.speeding
    if c.enabled and tonumber(speedKmh) and speedKmh>=c.speedLimit then
        AddHeat(src,reckless and c.heatPoints*2 or c.heatPoints,reckless and 'reckless' or 'speeding',c.starsMin)
    end
end)

local function bindOptional(key,crime)
    local c=Config.Integrations[key]
    if not c or not c.enabled then return end
    RegisterNetEvent(c.eventName,function(data)
        local src=source
        local d=Config.Detection[crime]
        if d and d.enabled then AddHeat(src,d.heatPoints,crime,d.starsMin) end
    end)
end

bindOptional('jaksam_drugs','drugSelling')
bindOptional('jaksam_robberies','robbery')
bindOptional('ak47_territory','territory')


exports('ReportDrugCrime',function(src) local c=Config.Detection.drugSelling; if c.enabled then AddHeat(src,c.heatPoints,'drugSelling',c.starsMin) end end)
exports('ReportRobbery',function(src) local c=Config.Detection.robbery; if c.enabled then AddHeat(src,c.heatPoints,'robbery',c.starsMin) end end)
exports('ReportTerritoryCrime',function(src) local c=Config.Detection.territory; if c.enabled then AddHeat(src,c.heatPoints,'territory',c.starsMin) end end)


-- ============================================================
-- DETECCION DE ROBOS PARA IA POLICIAL
-- Compatible con eventos de QBOX/QBX y con alertas policiales comunes.
-- No reemplaza ni modifica los eventos de los recursos de robo: solo escucha.
-- ============================================================
local robberyCooldown = {}
local function DebugPrint(msg) if Config.Debug then print('[qb-aipolice DEBUG][DETECTION] '..tostring(msg)) end end

local function reportRobberyIncident(src, coords, reason)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    local cfg = Config.RobberyResponse
    if not cfg or not cfg.enabled then return end

    local now = GetGameTimer()
    if now - (robberyCooldown[src] or 0) < 10000 then return end
    robberyCooldown[src] = now

    -- IsRealPolice() existe como local en server/main.lua y por eso no puede
    -- llamarse directamente desde este archivo. Hacemos la comprobacion aqui
    -- sin depender de una funcion global que puede ser nil.
    local isRealPolice = false
    local playerObj = nil
    if Framework == 'qbox' then
        playerObj = exports.qbx_core:GetPlayer(src)
    elseif Framework == 'qbcore' and Core and Core.Functions then
        playerObj = Core.Functions.GetPlayer(src)
    end
    if playerObj and playerObj.PlayerData and playerObj.PlayerData.job then
        local jobName = playerObj.PlayerData.job.name
        for _, job in ipairs(Config.PoliceJobs or {}) do
            if jobName == job then isRealPolice = true break end
        end
    end
    DebugPrint(('ROBO CHECK src=%s name=%s framework=%s isPolice=%s'):format(tostring(src), tostring(GetPlayerName(src)), tostring(Framework), tostring(isRealPolice)))
    if isRealPolice then
        DebugPrint('ROBO IGNORADO: el source pertenece a policia real')
        return
    end

    DebugPrint(('ROBO ANTES AddHeat src=%s reason=%s heat=%s minStars=%s coords=%s'):format(tostring(src),tostring(reason),tostring(cfg.heatPoints),tostring(cfg.minStars),tostring(coords)))
    AddHeat(src, cfg.heatPoints, 'robbery', cfg.minStars)
    DebugPrint(('ROBO DESPUES AddHeat src=%s stars=%s'):format(tostring(src), tostring(GetStars(src))))
    DebugPrint(('ROBO ENVIANDO robberyDetected al cliente src=%s'):format(tostring(src)))
    TriggerClientEvent('qb-aipolice:client:robberyDetected', src, coords, reason or 'robbery')
end

local function sourceCoords(src)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        return GetEntityCoords(ped)
    end
    return nil
end

-- QBOX jewelry: endcabinet confirma que la vitrina terminó de romperse.
-- La alerta oficial del robo llega inmediatamente después desde fireAlarm()
-- mediante police:server:policeAlert. La usamos como fuente principal para
-- evitar que el mismo robo se reporte dos veces y para leer exactamente la
-- alerta que ya genera qbx_jewelery.
local JewelryCabinets = {
    vector3(-626.83, -235.35, 38.05), vector3(-625.81, -234.70, 38.05),
    vector3(-626.95, -233.14, 38.05), vector3(-628.00, -233.86, 38.05),
    vector3(-625.70, -237.80, 38.05), vector3(-626.70, -238.58, 38.05),
    vector3(-624.55, -231.06, 38.05), vector3(-623.13, -232.94, 38.05),
    vector3(-620.29, -234.44, 38.05), vector3(-619.15, -233.66, 38.05),
    vector3(-620.19, -233.44, 38.05), vector3(-617.63, -230.58, 38.05),
    vector3(-618.33, -229.55, 38.05), vector3(-619.70, -230.33, 38.05),
    vector3(-620.95, -228.60, 38.05), vector3(-619.79, -227.60, 38.05),
    vector3(-620.42, -226.60, 38.05), vector3(-623.94, -227.18, 38.05),
    vector3(-624.91, -227.87, 38.05), vector3(-623.94, -228.05, 38.05)
}

RegisterNetEvent('qbx_jewelery:server:endcabinet', function(...)
    local src = source
    local coords = sourceCoords(src)
    local nearest, nearestDist
    if coords then
        for i, cab in ipairs(JewelryCabinets) do
            local d = #(coords - cab)
            if not nearestDist or d < nearestDist then nearestDist, nearest = d, i end
        end
    end
    DebugPrint(('JEWELRY CABINET EVENT #endcabinet src=%s playerCoords=%s nearestCabinet=%s distance=%.2f'):format(tostring(src), tostring(coords), tostring(nearest), nearestDist or -1.0))
    DebugPrint('JEWELRY CABINET CONFIRMADO -> NO esperamos policeAlert; reportamos directamente')
    reportRobberyIncident(src, coords, 'jewelry_cabinet_broken')
end)

-- QBOX bank robbery: este evento ya significa que el robo llamó a la policía.
RegisterNetEvent('qbx_bankrobbery:server:callCops', function(robberyType, bank, coords)
    local src = source
    reportRobberyIncident(src, coords or sourceCoords(src), 'bank:'..tostring(robberyType or bank or 'unknown'))
end)

-- Muchos recursos de robo/QB usan este evento común para avisar a policía.
-- Se escucha sin impedir que otros handlers del servidor sigan funcionando.
AddEventHandler('police:server:policeAlert', function(message, camId, playerSource, ...)
    -- QBOX qbx_jewelery dispara este evento con TriggerEvent y pasa el
    -- criminal en el tercer argumento. En ese caso `source` NO es el criminal.
    -- Usar playerSource evita perder la alerta aunque no haya policías reales.
    local src = tonumber(playerSource) or tonumber(source)
    local text = string.lower(tostring(message or ''))

    -- qbx_jewelery actual usa la misma alerta policial del servidor y pasa
    -- el source del ladrón como tercer argumento. No dependemos únicamente
    -- del texto de locale('notify.police'), porque ese texto puede cambiar.
    local isJewelryText = text:find('vangelico') or text:find('jewelry') or text:find('jewel') or text:find('jewellery') or text:find('joyer')
    local isRobberyAlert = text:find('rob') or text:find('robo') or text:find('robar') or text:find('store') or text:find('tienda') or text:find('shop') or text:find('pawn') or text:find('bank') or text:find('banco')

    -- La alarma de qbx_jewelery se dispara desde el propio servidor.
    -- Si el mensaje del locale no contiene una palabra reconocible, usamos
    -- la ubicación conocida de Vangelico como respaldo, siempre que exista
    -- un playerSource válido. Así leemos la MISMA alerta de la alarma sin
    -- generar un segundo reporte desde endcabinet.
    local jewelryCenter = vector3(-624.12, -228.25, 37.06)
    local jewelryDistance = 180.0
    local playerCoords = sourceCoords(src)
    local isNearJewelry = playerCoords and #(playerCoords - jewelryCenter) <= jewelryDistance
    local isJewelryAlert = isJewelryText or (playerSource and isNearJewelry)

    if isJewelryAlert or isRobberyAlert then
        DebugPrint(('policeAlert ROBO recibido src=%s playerSource=%s camId=%s texto=%s jewelryText=%s nearJewelry=%s'):format(tostring(src),tostring(playerSource),tostring(camId),text,tostring(isJewelryText ~= nil),tostring(isNearJewelry)))
        reportRobberyIncident(src, playerCoords, isJewelryAlert and 'jewelry_alarm' or 'policeAlert')
    end
end)

-- Compatibilidad con robos QB/Qbox de tiendas y otros recursos que llaman
-- directamente a un evento de "call cops" en lugar de police:server:policeAlert.
local function reportRobberyEvent(src, coords, reason)
    reportRobberyIncident(src, coords or sourceCoords(src), reason)
end

RegisterNetEvent('qbx_storerobbery:server:callCops', function(_, _, _, coords)
    reportRobberyEvent(source, coords, 'store')
end)

RegisterNetEvent('qb-storerobbery:server:callCops', function(_, _, _, coords)
    reportRobberyEvent(source, coords, 'store_legacy')
end)

AddEventHandler('playerDropped', function()
    robberyCooldown[source] = nil
end)
