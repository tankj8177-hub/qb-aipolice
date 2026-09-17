local activeJails={}
local savedAppearance={}

local function has(res) return Config.Integrations[res] and Config.Integrations[res].enabled and Utils.ResourceExists(Config.Integrations[res].resourceName) end

local function tryRcoreJail(src,minutes,reason)
    local c=Config.Integrations.rcore_prison
    if not has('rcore_prison') then return false end
    if c.mode=='event' then
        TriggerEvent(c.eventName,src,minutes,reason)
        return true
    end
    local ok=pcall(function() exports[c.resourceName][c.exportName](src,minutes,reason) end)
    return ok
end

local function tryRcoreRelease(src)
    local c=Config.Integrations.rcore_prison
    if not has('rcore_prison') then return false end
    if c.mode=='event' then TriggerEvent(c.releaseEvent,src); return true end
    return pcall(function() exports[c.resourceName][c.releaseExport](src) end)
end

RegisterNetEvent('qb-aipolice:server:jailPlayer',function(target,minutes,reason)
    local src=source
    target=tonumber(target) or src
    -- Permitir que el servidor encarcele al objetivo real enviado por una unidad AI/menú.
    -- Si lo solicita un jugador, solo se permite seleccionar otro objetivo cuando está de servicio policial.
    if src ~= 0 and target ~= src then
        if not exports['qb-aipolice']:IsPoliceOnDuty(src) then return end
        local a,b=GetPlayerPed(src),GetPlayerPed(target)
        if a==0 or b==0 then return end
        if #(GetEntityCoords(a)-GetEntityCoords(b)) > 150.0 then return end
    end
    minutes=math.max(1,tonumber(minutes) or Config.Arrest.fallbackJailTime)
    reason=reason or 'Arresto por unidad IA'
    if not GetPlayerName(target) then return end

    -- Reincidencia: se calcula en servidor, no en el cliente.
    local cid=exports['qb-aipolice']:GetCitizenId(target)
    local extra=0
    local done=function(count)
        if Config.RepeatOffender.enabled and count>=Config.RepeatOffender.threshold then
            extra=Config.RepeatOffender.extraStars
            minutes=minutes+Config.RepeatOffender.extraJailMinutes
        end
        Storage.AddJailHistory(cid,minutes,reason)
        local jailEnd=os.time()+minutes*60
        Storage.GetRecord(cid,function(record)
            record.jail_active=1
            record.jail_end=jailEnd
            record.jail_reason=reason
            Storage.SaveRecord(cid,record)
        end)
        activeJails[cid]={target=target,minutes=minutes,startedAt=os.time(),endAt=jailEnd,reason=reason}
        TriggerEvent('qb-aipolice:server:finishJail',target,minutes,reason,extra)
    end
    Storage.CountRecentArrests(cid,Config.RepeatOffender.windowDays,done)
end)

-- Flujo interno de encarcelamiento.
AddEventHandler('qb-aipolice:server:finishJail',function(target,minutes,reason,extra)
    target=tonumber(target)
    if not target or not GetPlayerName(target) then return end

    local revived=false
    local a=Config.Integrations.ambulance
    if a.enabled and a.reviveBeforePrison and Utils.ResourceExists(a.resourceName) then
        if a.mode=='event' then
            TriggerEvent(a.reviveEvent,target); revived=true
        else
            revived=pcall(function() exports[a.resourceName][a.reviveExport](target) end)
        end
    end
    if not revived then TriggerClientEvent('qb-aipolice:client:nativeRevive',target) end

    local sent=tryRcoreJail(target,minutes,reason)
    if not sent and Config.Integrations.rcore_prison.fallbackToNativeJail then
        TriggerClientEvent('qb-aipolice:client:nativeJail',target,minutes,reason,Config.Arrest.fallbackJailCoords)
    end

    TriggerClientEvent('qb-aipolice:client:applyJailOutfit',target)
    exports['qb-aipolice']:ClearWanted(target)
    if extra and extra>0 then
        -- Queda registrado para reincidencia; no se fuerza wanted después de encarcelar.
    end
end)

RegisterNetEvent('qb-aipolice:server:unjailPlayer',function(target)
    local caller=source
    target=tonumber(target) or caller
    -- Nunca sustituir el objetivo seleccionado por el jugador que pulsa el menú.
    if caller ~= 0 and target ~= caller then
        if not exports['qb-aipolice']:IsPoliceOnDuty(caller) then return end
        local a,b=GetPlayerPed(caller),GetPlayerPed(target)
        if a==0 or b==0 then return end
        if #(GetEntityCoords(a)-GetEntityCoords(b)) > 150.0 then return end
    end
    local cid=exports['qb-aipolice']:GetCitizenId(target)
    activeJails[cid]=nil
    Storage.GetRecord(cid,function(record)
        record.jail_active=0
        record.jail_end=0
        record.jail_reason=''
        Storage.SaveRecord(cid,record)
    end)
    local released=tryRcoreRelease(target)
    -- Siempre avisar al cliente para que salga al punto configurado de la comisaría.
    -- Si rcore_prison está activo, su liberación sigue ejecutándose primero.
    TriggerClientEvent('qb-aipolice:client:nativeUnjail',target)
    TriggerClientEvent('qb-aipolice:client:restoreJailOutfit',target)
end)

RegisterNetEvent('qb-aipolice:server:suspectDied',function()
    local src=source
    if exports['qb-aipolice']:GetStars(src)<=0 then return end
    local a=Config.Integrations.ambulance
    local ok=false
    if a.enabled and Utils.ResourceExists(a.resourceName) then
        if a.mode=='event' then TriggerEvent(a.reviveEvent,src); ok=true
        else ok=pcall(function() exports[a.resourceName][a.reviveExport](src) end) end
    end
    if not ok then TriggerClientEvent('qb-aipolice:client:nativeRevive',src) end
    SetTimeout(1500,function()
        if GetPlayerName(src) then TriggerClientEvent('qb-aipolice:client:resumeArrest',src) end
    end)
end)

RegisterNetEvent('qb-aipolice:server:arrestSearch',function()
    local src=source
    local found={}
    if GetResourceState('ox_inventory')=='started' then
        for _,item in ipairs(Config.IllegalItems) do
            -- ox_inventory puede devolver un número o una tabla según la versión/configuración.
            local result=exports.ox_inventory:Search(src,'count',item)
            local count=0

            if type(result)=='number' then
                count=result
            elseif type(result)=='table' then
                -- Formatos habituales: { [itemName] = count }, { count = count }
                count=tonumber(result[item]) or tonumber(result.count) or 0

                -- Compatibilidad adicional si la tabla contiene cantidades anidadas.
                if count==0 then
                    for _,v in pairs(result) do
                        if type(v)=='number' then
                            count=count+v
                        elseif type(v)=='table' then
                            count=count+(tonumber(v.count) or tonumber(v.amount) or 0)
                        end
                    end
                end
            end

            if count>0 then found[item]=count end
        end
    else
        local p=nil
        local fw=exports['qb-aipolice']:GetFramework()
        if fw=='qbox' then p=exports.qbx_core:GetPlayer(src)
        elseif fw=='qbcore' then p=exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
        elseif fw=='esx' then
            local esx=exports['es_extended']:getSharedObject()
            p=esx and esx.GetPlayerFromId(src)
        end
        if fw=='esx' and p and p.getInventoryItem then
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
    TriggerClientEvent('qb-aipolice:client:searchResult',src,found)
end)

RegisterNetEvent('qb-aipolice:server:chargePlayer',function(target,amount,cb)
    -- Solo el propio jugador puede cobrar una multa desde red; comandos internos usan source=0.
    local caller=source
    target=tonumber(target) or caller
    if caller ~= 0 then target=caller end
    amount=tonumber(amount) or 0
    local ok=false
    local fw=exports['qb-aipolice']:GetFramework()
    if fw=='qbox' then
        local p=exports.qbx_core:GetPlayer(target)
        ok=p and p.Functions and p.Functions.RemoveMoney and p.Functions.RemoveMoney('bank',amount) or false
    elseif fw=='qbcore' then
        local p=exports['qb-core']:GetCoreObject().Functions.GetPlayer(target)
        ok=p and p.Functions.RemoveMoney('bank',amount) or false
    elseif fw=='esx' then
        local esx=exports['es_extended']:getSharedObject()
        local p=esx and esx.GetPlayerFromId(target)
        if p then
            local account=p.getAccount('bank')
            if account and (account.money or 0)>=amount then
                p.removeAccountMoney('bank',amount)
                ok=true
            end
        end
    elseif fw=='standalone' then ok=true end
    if type(cb)=='function' then cb(ok) end
end)

RegisterNetEvent('qb-aipolice:server:payToLeaveJail',function(target)
    local caller=source
    target=tonumber(target) or caller
    if caller ~= 0 then target=caller end
    local cid=exports['qb-aipolice']:GetCitizenId(target)
    if not activeJails[cid] then TriggerClientEvent('chat:addMessage',target,{args={'AI Police','No estás en prisión.'}}); return end
    TriggerEvent('qb-aipolice:server:chargePlayer',target,500,function(ok)
        if ok then TriggerEvent('qb-aipolice:server:unjailPlayer',target) else TriggerClientEvent('chat:addMessage',target,{args={'AI Police','No tienes fondos suficientes.'}}) end
    end)
end)


-- Reducción de condena. Si rcore_prison ofrece la API configurada se usa esa API;
-- de lo contrario se reduce el contador del fallback nativo.
RegisterNetEvent('qb-aipolice:server:reduceSentence',function(minutes)
    local src=source
    minutes=math.max(1,tonumber(minutes) or 1)
    local c=Config.Integrations.rcore_prison
    if has('rcore_prison') then
        if c.mode=='event' then TriggerEvent(c.reductionEvent,src,minutes)
        else pcall(function() exports[c.resourceName][c.reductionExport](src,minutes) end) end
    end
    local cid=exports['qb-aipolice']:GetCitizenId(src)
    local jail=activeJails[cid]
    if jail then
        local remaining=math.max(1,math.ceil((jail.endAt-os.time())/60))
        jail.minutes=math.max(1,remaining-minutes)
        jail.endAt=os.time()+jail.minutes*60
        jail.reduced=(jail.reduced or 0)+minutes
        Storage.GetRecord(cid,function(record)
            record.jail_end=jail.endAt
            Storage.SaveRecord(cid,record)
        end)
        TriggerClientEvent('qb-aipolice:client:jailTimeReduced',src,jail.minutes)
    end
end)



-- Expiración centralizada: funciona tanto con rcore_prison como con el jail nativo.
-- Esto evita que un jugador real quede atrapado después de cumplir la condena.
CreateThread(function()
    while true do
        Wait(1000)
        local now=os.time()
        local expired={}
        for cid,jail in pairs(activeJails) do
            if jail and tonumber(jail.endAt or 0)>0 and tonumber(jail.endAt) <= now then
                expired[#expired+1]={cid=cid,target=tonumber(jail.target)}
            end
        end
        for _,entry in ipairs(expired) do
            activeJails[entry.cid]=nil
            local target=entry.target
            if target and GetPlayerName(target) then
                -- rcore_prison puede liberar al jugador correctamente pero no usar nuestro punto
                -- de salida. Siempre ejecutamos nativeUnjail despues de la liberacion para que
                -- el personaje termine en Config.Arrest.jailReleaseCoords (SALIDA).
                pcall(function()
                    tryRcoreRelease(target)
                end)
                TriggerClientEvent('qb-aipolice:client:nativeUnjail',target)
                TriggerClientEvent('qb-aipolice:client:restoreJailOutfit',target)
                Storage.GetRecord(entry.cid,function(record)
                    record.jail_active=0
                    record.jail_end=0
                    record.jail_reason=''
                    Storage.SaveRecord(entry.cid,record)
                end)
            else
                Storage.GetRecord(entry.cid,function(record)
                    record.jail_active=0
                    record.jail_end=0
                    record.jail_reason=''
                    Storage.SaveRecord(entry.cid,record)
                end)
            end
        end
    end
end)


AddEventHandler('playerJoining',function()
    local src=source
    SetTimeout(5000,function()
        if not GetPlayerName(src) then return end
        local cid=exports['qb-aipolice']:GetCitizenId(src)
        Storage.GetRecord(cid,function(record)
            if tonumber(record.jail_active or 0)==1 and tonumber(record.jail_end or 0)>os.time() then
                local remaining=math.max(1,math.ceil((record.jail_end-os.time())/60))
                activeJails[cid]={target=src,minutes=remaining,endAt=record.jail_end,reason=record.jail_reason}
                if not has('rcore_prison') then
                    TriggerClientEvent('qb-aipolice:client:nativeJail',src,remaining,record.jail_reason,Config.Arrest.fallbackJailCoords)
                end
                TriggerClientEvent('qb-aipolice:client:applyJailOutfit',src)
            elseif tonumber(record.jail_active or 0)==1 then
                record.jail_active=0; record.jail_end=0; record.jail_reason=''
                Storage.SaveRecord(cid,record)
            end
        end)
    end)
end)
