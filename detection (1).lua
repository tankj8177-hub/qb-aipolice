
local function IsLocalPolice()
    local fw=Utils.DetectFramework()
    local job=nil
    if fw=='qbox' then
        local ok,data=pcall(function() return exports.qbx_core:GetPlayerData() end)
        if ok and data then job=data.job end
    elseif fw=='qbcore' then
        local ok,QBCore=pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore and QBCore.Functions then
            local ok2,data=pcall(function() return QBCore.Functions.GetPlayerData() end)
            if ok2 and data then job=data.job end
        end
    elseif fw=='esx' then
        local ok,ESX=pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and ESX and ESX.GetPlayerData then
            local ok2,data=pcall(function() return ESX.GetPlayerData() end)
            if ok2 and data then job=data.job end
        end
    end
    if not job or not job.name then return false end
    for _,name in ipairs(Config.PoliceJobs or {}) do
        if job.name==name then return true end
    end
    return false
end

local lastCrime = {}
local vehicleSeen = {}
local reportedDead = {}
local lastSpeedReport = 0

local function canReport(key, cooldown)
    local now=GetGameTimer()
    if now-(lastCrime[key] or 0) >= cooldown*1000 then lastCrime[key]=now return true end
    return false
end

local function MaybeNpcWitness(crimeType)
    local cfg=Config.Detection.npcWitnesses
    if not cfg.enabled or math.random(100)>cfg.reportChance then return end
    local ped=PlayerPedId()
    local pos=GetEntityCoords(ped)
    local found=false
    for _,npc in ipairs(GetGamePool('CPed')) do
        if npc~=ped and DoesEntityExist(npc) and not IsPedAPlayer(npc) and not IsPedDeadOrDying(npc,true)
        and #(pos-GetEntityCoords(npc)) <= cfg.reportRadius then found=true break end
    end
    if found then
        SetTimeout(math.random(cfg.reportDelay.min,cfg.reportDelay.max),function()
            if DoesEntityExist(ped) then TriggerServerEvent('qb-aipolice:server:npcWitnessReport',crimeType) end
        end)
    end
end

CreateThread(function()
    while true do
        local wait=250
        local ped=PlayerPedId()
        if not IsLocalPolice() then
            if Config.Detection.shooting.enabled and IsPedShooting(ped) then
                wait=0
                if canReport('shooting',Config.Detection.shooting.cooldown) then
                    TriggerServerEvent('qb-aipolice:server:reportCrime','shooting')
                    MaybeNpcWitness('shooting')
                end
            end
        else
            wait=500
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        Wait(400)
        if not IsLocalPolice() then
            local ped=PlayerPedId()
            local pos=GetEntityCoords(ped)
            for _,npc in ipairs(GetGamePool('CPed')) do
                if npc~=ped and DoesEntityExist(npc) and not IsPedAPlayer(npc) and #(pos-GetEntityCoords(npc))<7.0 then
                    if IsEntityDead(npc) and GetPedSourceOfDeath(npc)==ped and not reportedDead[npc] then
                        reportedDead[npc]=true
                        if Config.Detection.murder.enabled and canReport('murder',Config.Detection.murder.cooldown) then
                            TriggerServerEvent('qb-aipolice:server:reportCrime','murder')
                            MaybeNpcWitness('murder')
                        end
                    elseif not IsEntityDead(npc) and HasEntityBeenDamagedByEntity(npc,ped,true) then
                        if Config.Detection.assault.enabled and canReport('assault_'..npc,Config.Detection.assault.cooldown) then
                            TriggerServerEvent('qb-aipolice:server:reportCrime','assault')
                            MaybeNpcWitness('assault')
                        end
                        ClearEntityLastDamageEntity(npc)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if not IsLocalPolice() and Config.Detection.vehicleTheft.enabled then
            local ped=PlayerPedId()
            if IsPedInAnyVehicle(ped,false) and GetPedInVehicleSeat(GetVehiclePedIsIn(ped,false),-1)==ped then
                local veh=GetVehiclePedIsIn(ped,false)
                local plate=GetVehicleNumberPlateText(veh)
                vehicleSeen[plate]=vehicleSeen[plate] or GetGameTimer()
                if GetGameTimer()-vehicleSeen[plate] >= Config.Detection.vehicleTheft.graceSeconds*1000
                and canReport('theft_'..plate,Config.Detection.vehicleTheft.cooldown) then
                    TriggerServerEvent('qb-aipolice:server:vehicleStolen',plate)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if not IsLocalPolice() then
            local cfg=Config.Detection.speeding
            if cfg.enabled then
                local ped=PlayerPedId()
                if IsPedInAnyVehicle(ped,false) and GetPedInVehicleSeat(GetVehiclePedIsIn(ped,false),-1)==ped then
                    local veh=GetVehiclePedIsIn(ped,false)
                    local kmh=GetEntitySpeed(veh)*3.6
                    if kmh>=cfg.speedLimit and GetGameTimer()-lastSpeedReport>=cfg.cooldown*1000 then
                        lastSpeedReport=GetGameTimer()
                        TriggerServerEvent('qb-aipolice:server:speeding',kmh,kmh>=cfg.recklessSpeed)
                    end
                end
            end
        end
    end
end)
