local Framework, Core = 'standalone', nil
local ESX = nil
local playerWanted = {}
local reportCooldowns = {}

CreateThread(function()
    Framework = Utils.DetectFramework()
    if Framework == 'qbox' then Core = exports.qbx_core
    elseif Framework == 'qbcore' then Core = exports['qb-core']:GetCoreObject()
    elseif Framework == 'esx' then ESX = exports['es_extended']:getSharedObject() end
    Utils.Log(('Framework detectado: %s'):format(Framework))
end)

local function GetPlayerObj(src)
    if Framework == 'qbox' then
        return exports.qbx_core:GetPlayer(src)
    elseif Framework == 'qbcore' then
        return Core.Functions.GetPlayer(src)
    elseif Framework == 'esx' and ESX then
        return ESX.GetPlayerFromId(src)
    end
end

local function GetCitizenId(src)
    local p = GetPlayerObj(src)
    if Framework == 'esx' and p then
        return p.identifier or ('SRC_'..src)
    end
    if p and p.PlayerData then
        return p.PlayerData.citizenid or p.PlayerData.citizenId or ('SRC_'..src)
    end
    return 'SRC_'..src
end
exports('GetCitizenId', GetCitizenId)

local function GetJobData(src)
    local p = GetPlayerObj(src)
    if Framework == 'esx' then
        if not p or not p.job then return nil end
        return { name=p.job.name, onduty=true }
    end
    if not p or not p.PlayerData or not p.PlayerData.job then return nil end
    return p.PlayerData.job
end

local function IsRealPolice(src)
    local job = GetJobData(src)
    if not job then return false end
    for _, name in ipairs(Config.PoliceJobs or {}) do
        if job.name == name then return true end
    end
    return false
end
exports('IsRealPolice', IsRealPolice)

local function CountRealPoliceOnline()
    local n=0
    for _, sid in ipairs(GetPlayers()) do if IsRealPolice(tonumber(sid)) then n=n+1 end end
    return n
end
exports('CountRealPoliceOnline', CountRealPoliceOnline)
exports('GetFramework', function() return Framework end)

local function ensureState(src)
    if not playerWanted[src] then
        playerWanted[src] = {stars=0, heat=0, lastSeen=os.time(), citizenid=GetCitizenId(src), active=false}
    end
    return playerWanted[src]
end

local function calcStars(heat)
    local stars=0
    for i=1,Config.MaxStars do
        if heat >= Config.StarThresholds[i] then stars=i end
    end
    return stars
end

local function sync(src, oldStars)
    local state=ensureState(src)
    if state.stars ~= oldStars then
        TriggerClientEvent('qb-aipolice:client:updateStars', src, state.stars)
        TriggerClientEvent('qb-aipolice:client:starsChanged', src, state.stars)
    end
end

function AddHeat(src, amount, crimeType, minimumStars)
    src=tonumber(src)
    if not src or not GetPlayerName(src) or not amount or amount <= 0 then return end
    -- Un agente policial nunca genera wanted por conducir su patrulla,
    -- acelerar, disparar, atropellar, etc. La comprobacion es server-side
    -- para que ningun evento externo pueda darle estrellas por accidente.
    if IsRealPolice(src) then
        local state = playerWanted[src]
        if state and (state.stars > 0 or state.heat > 0) then ClearWanted(src) end
        return
    end
    local state=ensureState(src)
    local old=state.stars
    state.heat=math.min(1000, state.heat+amount)
    state.lastSeen=os.time()
    local calculated=calcStars(state.heat)
    state.stars=math.max(calculated, math.min(Config.MaxStars, tonumber(minimumStars) or 0))
    if crimeType then Storage.AddCrime(state.citizenid, crimeType, amount) end
    sync(src,old)
end
exports('AddHeat', AddHeat)

function GetStars(src) return playerWanted[src] and playerWanted[src].stars or 0 end
exports('GetStars', GetStars)

function GetWantedState(src) return playerWanted[src] end
exports('GetWantedState', GetWantedState)

function ClearWanted(src)
    src=tonumber(src)
    if not src then return end
    local state=ensureState(src)
    state.heat=0; state.stars=0; state.active=false; state.lastSeen=os.time()
    TriggerClientEvent('qb-aipolice:client:updateStars',src,0)
    TriggerClientEvent('qb-aipolice:client:starsChanged',src,0)
end
exports('ClearWanted',ClearWanted)

RegisterNetEvent('qb-aipolice:server:playerSeen', function()
    local src=source
    local state=ensureState(src)
    state.lastSeen=os.time()
end)

RegisterNetEvent('qb-aipolice:server:reportCrime', function(crimeType)
    local src=source
    local allowed={shooting=true,assault=true,murder=true,vehicleTheft=true,speeding=true,policeEvasion=true}
    if not allowed[crimeType] then return end
    local cfg=Config.Detection[crimeType]
    if not cfg or not cfg.enabled then return end
    reportCooldowns[src]=reportCooldowns[src] or {}
    local now=GetGameTimer()
    local last=reportCooldowns[src][crimeType] or 0
    if now-last < ((cfg.cooldown or 5)*1000) then return end
    reportCooldowns[src][crimeType]=now
    local heat=cfg.heatPoints
    if CountRealPoliceOnline() >= Config.RealPoliceThreshold then heat=math.max(1,math.floor(heat*0.5)) end
    AddHeat(src,heat,crimeType,cfg.starsMin)
end)

RegisterNetEvent('qb-aipolice:server:npcWitnessReport', function(crimeType)
    local src=source
    local cfg=Config.Detection[crimeType]
    if not cfg or not cfg.enabled or not Config.Detection.npcWitnesses.enabled then return end
    AddHeat(src,math.max(1,math.floor(cfg.heatPoints*0.5)),crimeType..'_witness',cfg.starsMin)
end)

RegisterNetEvent('qb-aipolice:server:policeEvasion', function()
    local src=source
    local cfg=Config.Detection.policeEvasion
    if cfg.enabled then AddHeat(src,cfg.heatPoints,'policeEvasion',cfg.starsMin) end
end)


RegisterNetEvent('qb-aipolice:server:trafficStopTarget', function(target)
    local src=source
    if not IsPoliceOnDuty(src) then return end
    target=tonumber(target)
    if not target or target<=0 or not GetPlayerName(target) then return end
    suspectAuthorizations[src]=suspectAuthorizations[src] or {}
    suspectAuthorizations[src][target]=GetGameTimer()+120000
    TriggerClientEvent('qb-aipolice:client:suspectTrafficStop',target,src)
end)

RegisterNetEvent('qb-aipolice:server:trafficWarning', function(kind)
    local src=source
    local cid=GetCitizenId(src)
    if kind=='ticket' then
        local amount=Config.TrafficStops.ticketAmounts.speeding
        Storage.AddTicket(cid,'speeding',amount)
        TriggerClientEvent('qb-aipolice:client:trafficNotice',src,'ticket',amount)
    else
        Storage.AddWarning(cid,kind or 'traffic')
        TriggerClientEvent('qb-aipolice:client:trafficNotice',src,'warning')
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now=os.time()
        for src,state in pairs(playerWanted) do
            if GetPlayerName(src) then
                if state.stars>0 and now-state.lastSeen >= Config.StarDecayTime then
                    local old=state.stars
                    state.heat=math.max(0,state.heat-Config.StarThresholds[1])
                    state.stars=calcStars(state.heat)
                    state.lastSeen=now
                    if state.stars~=old then
                        TriggerClientEvent('qb-aipolice:client:updateStars',src,state.stars)
                        TriggerClientEvent('qb-aipolice:client:starsChanged',src,state.stars)
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped',function()
    local src=source
    playerWanted[src]=nil
    reportCooldowns[src]=nil
end)

-- ============================================================
-- AUTORIZACIÓN DEL MENÚ NUI PARA POLICÍA DE TURNO
-- ============================================================
local function RefreshFramework()
    -- No dependemos de que el hilo de arranque haya terminado antes de que
    -- el policía pulse F6. Esto evita que Qbox sea tratado temporalmente
    -- como standalone.
    local detected = Utils.DetectFramework()
    if detected ~= Framework then
        Framework = detected
        if Framework == 'qbox' then
            Core = exports.qbx_core
        elseif Framework == 'qbcore' then
            Core = exports['qb-core']:GetCoreObject()
        elseif Framework == 'esx' then
            ESX = exports['es_extended']:getSharedObject()
        end
    end
    return Framework
end

local function IsPoliceOnDuty(src)
    src = tonumber(src)
    if not src then return false end
    RefreshFramework()

    if Framework == 'standalone' then
        return Config.PoliceMenu.allowStandalone and IsPlayerAceAllowed(src, Config.PoliceMenu.standaloneAce)
    end

    local job = GetJobData(src)
    if not job then return false end
    local validJob = false
    for _, name in ipairs(Config.PoliceJobs) do
        if job.name == name then validJob = true break end
    end
    if not validJob then return false end

    if not Config.PoliceMenu.requireOnDuty then return true end
    return job.onduty == true or job.onduty == 1
end

exports('IsPoliceOnDuty', IsPoliceOnDuty)

RegisterNetEvent('qb-aipolice:server:requestPoliceMenu', function()
    local src = source
    if not Config.PoliceMenu.enabled then return end
    if not IsPoliceOnDuty(src) then
        TriggerClientEvent('qb-aipolice:client:policeMenuDenied', src)
        return
    end
    TriggerClientEvent('qb-aipolice:client:openPoliceMenu', src)
end)

local validOrders = {
    backup=true, investigate=true, patrol=true, trafficStop=true, pursuit=true,
    spikes=true, roadblock=true, tactical=true, helicopter=true, military=true,
    transport=true, clearUnits=true
}
local policeCommandCooldown = {}

-- Acciones del menú de sospechoso. Estas son distintas de las órdenes de
-- despacho: primero validamos al policía y luego enviamos la acción al cliente
-- que controla las entidades AI. Para jugadores reales, algunas acciones se
-- replican además al cliente del sospechoso para que la detención sea visible.
local validSuspectActions = {
    requestId=true, vehicleSearch=true, search=true, follow=true, wrist=true,
    face=true, releaseDrive=true, releaseWalk=true, detain=true, uncuff=true,
    placeCar=true, jail=true
}
local suspectCommandCooldown = {}
local suspectAuthorizations = {}
local function DebugPrint(msg) if Config.Debug then print('[qb-aipolice DEBUG][SERVER] '..tostring(msg)) end end
local function isSuspectAuthorized(src,target)
    local t=suspectAuthorizations[src] and suspectAuthorizations[src][target]
    return t and GetGameTimer() <= t
end


RegisterNetEvent('qb-aipolice:server:policeSuspectAction', function(action, targetId)
    local src=source
    if not Config.PoliceMenu.enabled then return end
    if not IsPoliceOnDuty(src) then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'No estás de turno como policía.')
        return
    end

    action=tostring(action or '')
    targetId=tostring(targetId or '')
    DebugPrint(('SuspectAction src=%s action=%s target=%s'):format(src,action,targetId))
    if not validSuspectActions[action] then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Acción de sospechoso no válida.')
        return
    end

    -- IMPORTANTE: las acciones del sospechoso ya no dependen de una segunda
    -- llamada servidor -> cliente -> servidor. La orden del botón se ejecuta
    -- directamente después de validar policía + objetivo.
    local now=GetGameTimer()
    if now-(suspectCommandCooldown[src] or 0) < 150 then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Orden demasiado rápida; vuelve a pulsar.')
        return
    end
    suspectCommandCooldown[src]=now

    -- NPC local: no tiene server ID. El cliente del policía controla la unidad AI.
    if targetId:sub(1,4) == 'npc:' then
        if action == 'jail' then
            DebugPrint(('NPC %s -> iniciar traslado fisico a prision'):format(targetId))
            TriggerClientEvent('qb-aipolice:client:policeSuspectTransportTarget',src,targetId)
            TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Traslado a prisión iniciado: la unidad irá con el sospechoso en la patrulla.')
        else
            TriggerClientEvent('qb-aipolice:client:policeSuspectAction',src,action,targetId)
            TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,('Orden enviada al NPC: %s'):format(action))
        end
        return
    end

    local target=tonumber(targetId)
    if not target or target==src or not GetPlayerName(target) then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Objetivo no válido o desconectado.')
        return
    end

    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    if a==0 or b==0 then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'No se pudo localizar al objetivo.')
        return
    end

    local ac,bc=GetEntityCoords(a),GetEntityCoords(b)
    if #(ac-bc)>150.0 then
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'El objetivo está demasiado lejos.')
        return
    end

    suspectAuthorizations[src]=suspectAuthorizations[src] or {}
    suspectAuthorizations[src][target]=GetGameTimer()+120000

    -- Jugador real: ejecutar la acción inmediatamente en el cliente del objetivo.
    if action=='requestId' or action=='search' or action=='vehicleSearch' then
        TriggerClientEvent('qb-aipolice:client:policeSuspectInspect',src,action,target)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,action=='requestId' and 'ID solicitado.' or 'Registro iniciado.')
    elseif action=='detain' then
        TriggerClientEvent('qb-aipolice:client:suspectCuff',target,src)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,('Jugador ID %s esposado.'):format(target))
    elseif action=='uncuff' then
        TriggerClientEvent('qb-aipolice:client:suspectUncuff',target)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,('Jugador ID %s desesposado.'):format(target))
    elseif action=='wrist' then
        TriggerClientEvent('qb-aipolice:client:suspectWristToggle',target,src)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Orden de muñecas ejecutada.')
    elseif action=='face' then
        TriggerClientEvent('qb-aipolice:client:suspectFacePolice',target,src)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Orden de mirar al policía ejecutada.')
    elseif action=='follow' then
        TriggerClientEvent('qb-aipolice:client:suspectFollowPolice',target,src)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Orden de seguir ejecutada.')
    elseif action=='releaseDrive' then
        TriggerClientEvent('qb-aipolice:client:suspectRelease',target,'drive')
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Jugador liberado para conducir.')
    elseif action=='releaseWalk' then
        TriggerClientEvent('qb-aipolice:client:suspectRelease',target,'walk')
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Jugador liberado a pie.')
    elseif action=='placeCar' then
        -- La orden al jugador busca un vehículo policial cercano. Si no existe,
        -- el cliente del policía prepara una unidad/vehículo y la coloca por red.
        TriggerClientEvent('qb-aipolice:client:suspectPrepareVehicle',target,src)
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Orden de meter al jugador en vehículo enviada.')
    elseif action=='jail' then
        DebugPrint(('PLAYER %s -> iniciar traslado fisico a prision para target=%s'):format(src,target))
        TriggerClientEvent('qb-aipolice:client:policeSuspectTransportTarget',src,tostring(target))
        TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,('Traslado del jugador ID %s iniciado.'):format(target))
    end
end)

RegisterNetEvent('qb-aipolice:server:policeTargetState', function(state, targetId)
    local src=source
    if not IsPoliceOnDuty(src) then return end
    local target=tonumber(targetId)
    if not target or not GetPlayerName(target) or target==src then return end
    local auth=suspectAuthorizations[src] and suspectAuthorizations[src][target]
    if not auth or GetGameTimer()>auth then return end
    state=tostring(state or '')
    if state=='cuff' then
        TriggerClientEvent('qb-aipolice:client:suspectCuff',target,src)
    elseif state=='wrist' then
        TriggerClientEvent('qb-aipolice:client:suspectWristToggle',target,src)
    elseif state=='uncuff' then
        TriggerClientEvent('qb-aipolice:client:suspectUncuff',target)
    elseif state=='face' then
        TriggerClientEvent('qb-aipolice:client:suspectFacePolice',target,src)
    elseif state=='follow' then
        TriggerClientEvent('qb-aipolice:client:suspectFollowPolice',target,src)
    elseif state=='releaseDrive' then
        TriggerClientEvent('qb-aipolice:client:suspectRelease',target,'drive')
    elseif state=='releaseWalk' then
        TriggerClientEvent('qb-aipolice:client:suspectRelease',target,'walk')
    end
end)

RegisterNetEvent('qb-aipolice:server:policeSuspectInspect', function(action,targetId)
    local src=source
    if not IsPoliceOnDuty(src) then return end
    local target=tonumber(targetId)
    if not target or not GetPlayerName(target) then return end
    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    if a==0 or b==0 then return end
    if not isSuspectAuthorized(src,target) then
        local pa,pb=GetPlayerPed(src),GetPlayerPed(target)
        if pa==0 or pb==0 or #(GetEntityCoords(pa)-GetEntityCoords(pb))>150.0 then return end
    end
    if action=='requestId' then
        local p=GetPlayerObj(target)
        local name=GetPlayerName(target) or ('ID '..target)
        local cid=GetCitizenId(target)
        local job=(Framework=='esx' and p and p.job and p.job.name) or (p and p.PlayerData and p.PlayerData.job and p.PlayerData.job.name) or 'civil'
        TriggerClientEvent('qb-aipolice:client:policeSuspectInfo',src,('Licencia/ID | ID %s | Nombre: %s | Citizen ID: %s | Trabajo: %s'):format(target,name,cid,job))
        return
    end
    local found={}
    if GetResourceState('ox_inventory')=='started' then
        for _,item in ipairs(Config.IllegalItems) do
            local count=exports.ox_inventory:Search(target,'count',item)
            if count and count>0 then found[item]=count end
        end
    else
        local p=GetPlayerObj(target)
        if Framework=='esx' and p and p.getInventoryItem then
            for _,item in ipairs(Config.IllegalItems) do
                local it=p.getInventoryItem(item)
                local count=it and (it.count or it.amount) or 0
                if tonumber(count) and tonumber(count)>0 then found[item]=tonumber(count) end
            end
        elseif p and p.Functions and p.Functions.GetItemByName then
            for _,item in ipairs(Config.IllegalItems) do
                local it=p.Functions.GetItemByName(item)
                if it then found[item]=it.amount or 1 end
            end
        end
    end
    local vehicle=GetVehiclePedIsIn(b,false)
    local plate=vehicle~=0 and GetVehicleNumberPlateText(vehicle) or 'N/A'
    local parts={}
    for item,count in pairs(found) do parts[#parts+1]=('%s x%s'):format(item,count) end
    if #parts==0 then parts[1]='Nada ilegal detectado' end
    local label=action=='vehicleSearch' and 'Registro de vehículo' or 'Registro individual'
    TriggerClientEvent('qb-aipolice:client:policeSuspectInfo',src,('%s | Placa: %s | %s'):format(label,plate,table.concat(parts,', ')))
end)

RegisterNetEvent('qb-aipolice:server:policeSuspectPlacePlayer', function(targetId, vehicleNetId)
    local src=source
    if not IsPoliceOnDuty(src) then return end
    local target=tonumber(targetId); local net=tonumber(vehicleNetId)
    if not target or not net or not GetPlayerName(target) then return end
    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    if a==0 or b==0 or not isSuspectAuthorized(src,target) then return end
    TriggerClientEvent('qb-aipolice:client:suspectPlaceInVehicle',target,net)
end)

RegisterNetEvent('qb-aipolice:server:policeSuspectJail', function(targetId)
    local src=source
    if not IsPoliceOnDuty(src) then return end
    local target=tonumber(targetId)
    if not target or not GetPlayerName(target) then return end
    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    if a==0 or b==0 or not isSuspectAuthorized(src,target) then return end
    local cid=GetCitizenId(target)
    local minutes=Config.Arrest.fallbackJailTime
    local reason='Arresto ordenado por policía AI'
    Storage.AddJailHistory(cid,minutes,reason)
    local jailEnd=os.time()+minutes*60
    Storage.GetRecord(cid,function(record)
        record.jail_active=1; record.jail_end=jailEnd; record.jail_reason=reason
        Storage.SaveRecord(cid,record)
    end)
    TriggerEvent('qb-aipolice:server:finishJail',target,minutes,reason,0)
    TriggerClientEvent('qb-aipolice:client:policeMenuOrderResult',src,'Sospechoso enviado al proceso de prisión.')
end)

RegisterNetEvent('qb-aipolice:server:applySuspectAction', function()
    -- Compatibilidad con versiones antiguas. No ejecuta acciones por sí solo.
end)

AddEventHandler('playerDropped', function()
    suspectCommandCooldown[source]=nil
end)

RegisterNetEvent('qb-aipolice:server:policeMenuOrder', function(order, data)
    local src = source
    if not Config.PoliceMenu.enabled or not IsPoliceOnDuty(src) then return end
    if not validOrders[tostring(order)] or not Config.PoliceMenu.orders[tostring(order)] then return end

    local now = GetGameTimer()
    if now - (policeCommandCooldown[src] or 0) < Config.PoliceMenu.commandCooldown then return end
    policeCommandCooldown[src] = now

    data = type(data) == 'table' and data or {}
    if data.targetId and tostring(data.targetId) ~= '' then
        local targetValue = tostring(data.targetId)
        -- Los NPC se resuelven en el cliente del policía; no tienen server ID.
        if targetValue:sub(1, 4) == 'npc:' then
            data.targetId = targetValue
        else
            local target = tonumber(targetValue)
            if not target or target == src or not GetPlayerName(target) then return end
            local sourcePed, targetPed = GetPlayerPed(src), GetPlayerPed(target)
            if sourcePed == 0 or targetPed == 0 then return end
            local a, b = GetEntityCoords(sourcePed), GetEntityCoords(targetPed)
            if #(a - b) > 150.0 then return end
            data.targetId = target
        end
    end
    TriggerClientEvent('qb-aipolice:client:policeMenuOrder', src, tostring(order), data)
end)

AddEventHandler('playerDropped', function()
    policeCommandCooldown[source] = nil
end)
