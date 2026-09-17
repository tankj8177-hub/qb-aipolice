local handcuffed=false
local escorting=false
local arrestBusy=false
local deathHandled=false
local nativeJailEnd=0
local detainedLocked=false

-- Cuando el policía ordena DETENER, el sospechoso queda inmóvil hasta que
-- se ordene seguir/muñecas, desesposar, liberar o meterlo en un vehículo.
-- Esto solo afecta al jugador que recibió la detención.
CreateThread(function()
    while true do
        if detainedLocked and handcuffed then
            Wait(0)
            local p=PlayerPedId()
            if IsPedInAnyVehicle(p,false) then
                FreezeEntityPosition(p,false)
                DisableControlAction(0,23,true)
                DisableControlAction(0,75,true)
            else
                FreezeEntityPosition(p,true)
                DisableControlAction(0,21,true)
                DisableControlAction(0,22,true)
                DisableControlAction(0,23,true)
                DisableControlAction(0,24,true)
                DisableControlAction(0,25,true)
                DisableControlAction(0,30,true)
                DisableControlAction(0,31,true)
                DisableControlAction(0,32,true)
                DisableControlAction(0,33,true)
                DisableControlAction(0,34,true)
                DisableControlAction(0,35,true)
                DisableControlAction(0,44,true)
                DisableControlAction(0,75,true)
            end
        else
            Wait(250)
        end
    end
end)

local function nearestOfficer()
    local p=PlayerPedId(); local pos=GetEntityCoords(p); local best,dist=nil,Config.Arrest.surrenderDistance+2
    for _,u in ipairs(exports['qb-aipolice']:GetActivePoliceUnits()) do
        if u.type=='ped' and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
            local d=#(pos-GetEntityCoords(u.entity))
            if d<dist then best,dist=u.entity,d end
        end
    end
    return best,dist
end

local function isHandsUp()
    local p=PlayerPedId()
    return IsControlPressed(0,73) or IsEntityPlayingAnim(p,'missminuteman_1ig_2','handsup_base',3)
end


local function forceArrestFromAI(officer)
    if arrestBusy or handcuffed then return end
    arrestBusy=true
    local p=PlayerPedId()
    if DoesEntityExist(officer) then
        ClearPedTasks(officer)
        TaskTurnPedToFaceEntity(officer,p,700)
    end
    RequestAnimDict('mp_arresting')
    local deadline=GetGameTimer()+4000
    while not HasAnimDictLoaded('mp_arresting') and GetGameTimer()<deadline do Wait(0) end
    if HasAnimDictLoaded('mp_arresting') then
        ClearPedTasks(p)
        TaskPlayAnim(p,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
    end
    Wait(math.max(800, tonumber(Config.Arrest.handcuffTime) or 2500))
    handcuffed=true
    SetEnableHandcuffs(p,true)
    DisablePlayerFiring(PlayerId(),true)
    TriggerServerEvent('qb-aipolice:server:arrestSearch')
    Wait(math.max(500, tonumber(Config.Arrest.searchTime) or 1500))
    if Config.Arrest.escortEnabled then
        TriggerEvent('qb-aipolice:client:escortToTransport',officer)
    else
        TriggerServerEvent('qb-aipolice:server:jailPlayer',GetPlayerServerId(PlayerId()),Config.Arrest.fallbackJailTime,'Arresto por unidad IA')
        arrestBusy=false
    end
end

RegisterNetEvent('qb-aipolice:client:aiArrest', function(officer)
    forceArrestFromAI(officer)
end)

local function performArrest(officer)
    if arrestBusy or handcuffed then return end
    arrestBusy=true
    local p=PlayerPedId()
    ClearPedTasks(officer)
    TaskTurnPedToFaceEntity(officer,p,1000)
    Wait(900)
    RequestAnimDict('mp_arresting')
    while not HasAnimDictLoaded('mp_arresting') do Wait(10) end
    TaskPlayAnim(p,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
    Wait(Config.Arrest.handcuffTime)
    handcuffed=true
    SetEnableHandcuffs(p,true)
    DisablePlayerFiring(PlayerId(),true)
    TriggerServerEvent('qb-aipolice:server:arrestSearch')
    Wait(Config.Arrest.searchTime)
    if Config.Arrest.escortEnabled then
        TriggerEvent('qb-aipolice:client:escortToTransport',officer)
    else
        TriggerServerEvent('qb-aipolice:server:jailPlayer',GetPlayerServerId(PlayerId()),Config.Arrest.fallbackJailTime,'Arresto por unidad IA')
        arrestBusy=false
    end
end

RegisterNetEvent('qb-aipolice:client:escortToTransport',function(officer)
    if escorting then return end
    escorting=true
    local p=PlayerPedId()
    local hash=joaat(Config.Arrest.transportVehicle)
    RequestModel(hash)
    local deadline=GetGameTimer()+5000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    local op=GetEntityCoords(p)
    local h=GetEntityHeading(officer)
    local v=CreateVehicle(hash,op.x+2.5,op.y+2.5,op.z,h,true,true)
    if DoesEntityExist(v) then NetworkRegisterEntityAsNetworked(v) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(v) then
        TriggerServerEvent('qb-aipolice:server:jailPlayer',GetPlayerServerId(PlayerId()),Config.Arrest.fallbackJailTime,'Arresto por unidad IA')
        escorting=false; arrestBusy=false; return
    end
    TaskGoStraightToCoord(p,op.x+2.0,op.y+2.0,op.z,1.0,3000,h,0.1)
    Wait(1800)
    SetPedIntoVehicle(p,v,2)
    SetTimeout(Config.Arrest.transportTime,function()
        if DoesEntityExist(v) then DeleteEntity(v) end
        TriggerServerEvent('qb-aipolice:server:jailPlayer',GetPlayerServerId(PlayerId()),Config.Arrest.fallbackJailTime,'Transportado por unidad IA')
        handcuffed=false; escorting=false; arrestBusy=false
        SetEnableHandcuffs(p,false); DisablePlayerFiring(PlayerId(),false); ClearPedTasksImmediately(p)
    end)
end)

CreateThread(function()
    while true do
        Wait(250)
        if Config.Arrest.allowSurrender and not arrestBusy and not handcuffed then
            local stars=exports['qb-aipolice']:GetCurrentStars()
            if stars>0 and stars<=2 and isHandsUp() then
                local officer,d=nearestOfficer()
                if officer and d<=Config.Arrest.surrenderDistance then performArrest(officer) end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        local p=PlayerPedId()
        if IsEntityDead(p) then
            if not deathHandled and exports['qb-aipolice']:GetCurrentStars()>0 and Config.Arrest.arrestWhenDowned then
                deathHandled=true
                TriggerServerEvent('qb-aipolice:server:suspectDied')
            end
        else
            deathHandled=false
        end
    end
end)

RegisterNetEvent('qb-aipolice:client:resumeArrest',function()
    deathHandled=false
    arrestBusy=false
    Wait(1200)
    local officer,d=nearestOfficer()
    if officer and d<=30.0 then performArrest(officer) end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if nativeJailEnd>0 and GetGameTimer() >= nativeJailEnd then
            nativeJailEnd=0
            TriggerServerEvent('qb-aipolice:server:unjailPlayer',GetPlayerServerId(PlayerId()))
        end
    end
end)

RegisterNetEvent('qb-aipolice:client:nativeJail',function(minutes,reason,coords)
    local p=PlayerPedId()
    DoScreenFadeOut(500); Wait(600)
    SetEntityCoords(p,coords.x,coords.y,coords.z)
    SetEntityHeading(p,0.0)
    DoScreenFadeIn(500)
    nativeJailEnd=GetGameTimer()+math.max(1,tonumber(minutes) or 1)*60000
    TriggerEvent('qb-aipolice:client:startJailTimer',minutes,reason)
end)

RegisterNetEvent('qb-aipolice:client:startJailTimer',function(minutes,reason)
    SendNUIMessage({action='showJailTimer',minutes=minutes,reason=reason})
end)

RegisterNetEvent('qb-aipolice:client:nativeUnjail',function()
    nativeJailEnd=0
    local p=PlayerPedId()
    SetEnableHandcuffs(p,false); DisablePlayerFiring(PlayerId(),false)
    handcuffed=false; escorting=false; arrestBusy=false
    ClearPedTasksImmediately(p)
    -- Al terminar la condena, sacar al jugador al exterior de la comisaría.
    local out=Config.Arrest.jailReleaseCoords
    if out then
        DoScreenFadeOut(500)
        Wait(600)
        SetEntityCoordsNoOffset(p,out.x,out.y,out.z,false,false,false)
        SetEntityHeading(p,out.w or 0.0)
        Wait(250)
        DoScreenFadeIn(500)
    end
    SendNUIMessage({action='hideJailTimer'})
end)

-- Salida de prisión: este punto NO mete a nadie en la cárcel.
-- Es un punto de interacción: acercarse y pulsar E teletransporta a la comisaría.
CreateThread(function()
    local b=Config.Arrest.jailReleaseBlip
    local c=Config.Arrest.jailReleaseCoords
    if not b or b.enabled==false or not c then return end
    local blip=AddBlipForCoord(c.x,c.y,c.z)
    SetBlipSprite(blip,b.sprite or 60)
    SetBlipColour(blip,b.color or 2)
    SetBlipScale(blip,b.scale or 0.75)
    SetBlipAsShortRange(true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(b.label or 'Salida de prisión')
    EndTextCommandSetBlipName(blip)

    local interactionDistance=Config.Arrest.jailExitInteractionDistance or 2.5
    local station=Config.Arrest.jailExitStationCoords
    if not station then return end

    while true do
        local wait=1000
        local p=PlayerPedId()
        local pc=GetEntityCoords(p)
        local dist=#(pc-vector3(c.x,c.y,c.z))
        if dist <= 15.0 then
            wait=0
            DrawMarker(2,c.x,c.y,c.z+0.15,0.0,0.0,0.0,0.0,0.0,0.0,0.35,0.35,0.35,255,255,255,180,false,true,2,false,nil,nil,false)
            if dist <= interactionDistance then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Pulsa ~INPUT_CONTEXT~ para ir a la ~b~comisaría~s~')
                EndTextCommandDisplayHelp(0,false,true,-1)
                if IsControlJustReleased(0,38) then
                    DoScreenFadeOut(500)
                    Wait(600)
                    SetEntityCoordsNoOffset(p,station.x,station.y,station.z,false,false,false)
                    SetEntityHeading(p,station.w or 0.0)
                    Wait(250)
                    DoScreenFadeIn(500)
                end
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('qb-aipolice:client:nativeRevive',function()
    local p=PlayerPedId(); local c=GetEntityCoords(p)
    NetworkResurrectLocalPlayer(c.x,c.y,c.z,GetEntityHeading(p),true,false)
    SetEntityHealth(p,GetEntityMaxHealth(p))
    ClearPedTasksImmediately(p)
end)

RegisterNetEvent('qb-aipolice:client:searchResult',function(items)
    -- El inventario se inspecciona server-side; UI/evento queda disponible para integraciones.
end)


RegisterNetEvent('qb-aipolice:client:jailTimeReduced',function(minutes)
    if nativeJailEnd>0 then nativeJailEnd=GetGameTimer()+math.max(1,tonumber(minutes))*60000 end
    SendNUIMessage({action='setJailMinutes',minutes=minutes})
end)

-- ============================================================
-- CONTROL DEL SOSPECHOSO DESDE EL MENÚ DEL POLICÍA AI
-- ============================================================
RegisterNetEvent('qb-aipolice:client:suspectWristToggle', function(policeSrc)
    local p=PlayerPedId()
    if handcuffed then
        handcuffed=false
        SetEnableHandcuffs(p,false)
        DisablePlayerFiring(PlayerId(),false)
        ClearPedTasks(p)
        return
    end
    handcuffed=true
    detainedLocked=false
    FreezeEntityPosition(p,false)
    SetEnableHandcuffs(p,true)
    DisablePlayerFiring(PlayerId(),true)
    RequestAnimDict('mp_arresting')
    while not HasAnimDictLoaded('mp_arresting') do Wait(0) end
    TaskPlayAnim(p,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
end)

RegisterNetEvent('qb-aipolice:client:suspectTrafficStop', function(policeSrc)
    local p=PlayerPedId()
    local v=GetVehiclePedIsIn(p,false)
    if v==0 or not DoesEntityExist(v) then return end

    -- Mantener al conductor dentro del vehículo, frenar y dejar el auto
    -- inmóvil para que la unidad policial pueda hacer la parada.
    SetBlockingOfNonTemporaryEvents(p,true)
    SetPedAsEnemy(p,false)
    ClearPedTasks(p)
    TaskVehicleTempAction(p,v,27,7000)
    SetVehicleForwardSpeed(v,0.0)
    SetVehicleHandbrake(v,true)

    -- Durante la parada no permitimos que el jugador vuelva a acelerar por
    -- accidente mientras la orden esté activa. Se libera al terminar el
    -- tiempo de la parada o cuando recibe otra orden policial.
    CreateThread(function()
        local untilTime=GetGameTimer()+7000
        while GetGameTimer()<untilTime and IsPedInVehicle(p,v,false) and DoesEntityExist(v) do
            SetVehicleForwardSpeed(v,0.0)
            SetVehicleHandbrake(v,true)
            Wait(250)
        end
    end)
end)

RegisterNetEvent('qb-aipolice:client:suspectCuff', function(policeSrc)
    local p=PlayerPedId()
    -- Un jugador dentro de un vehículo también puede ser detenido: primero
    -- se inmoviliza el auto y se hace bajar al conductor/pasajero.
    if IsPedInAnyVehicle(p,false) then
        local v=GetVehiclePedIsIn(p,false)
        if v~=0 and DoesEntityExist(v) then
            SetVehicleForwardSpeed(v,0.0)
            SetVehicleHandbrake(v,true)
            TaskVehicleTempAction(p,v,27,3500)
            Wait(700)
            TaskLeaveVehicle(p,v,256)
            local deadline=GetGameTimer()+3500
            while IsPedInAnyVehicle(p,false) and GetGameTimer()<deadline do Wait(100) end
            SetVehicleHandbrake(v,false)
        end
    end
    handcuffed=true
    detainedLocked=true
    SetEnableHandcuffs(p,true)
    DisablePlayerFiring(PlayerId(),true)
    RequestAnimDict('mp_arresting')
    while not HasAnimDictLoaded('mp_arresting') do Wait(0) end
    TaskPlayAnim(p,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
end)

RegisterNetEvent('qb-aipolice:client:suspectUncuff', function()
    local p=PlayerPedId()
    handcuffed=false
    detainedLocked=false
    FreezeEntityPosition(p,false)
    escorting=false
    arrestBusy=false
    SetEnableHandcuffs(p,false)
    DisablePlayerFiring(PlayerId(),false)
    ClearPedTasks(p)
end)

RegisterNetEvent('qb-aipolice:client:suspectFacePolice', function(policeSrc)
    local idx=GetPlayerFromServerId(tonumber(policeSrc) or -1)
    if idx==-1 then return end
    local policePed=GetPlayerPed(idx)
    if policePed==0 or not DoesEntityExist(policePed) then return end
    ClearPedTasks(PlayerPedId())
    TaskTurnPedToFaceEntity(PlayerPedId(),policePed,1200)
end)

RegisterNetEvent('qb-aipolice:client:suspectFollowPolice', function(policeSrc)
    detainedLocked=false
    FreezeEntityPosition(PlayerPedId(),false)
    local idx=GetPlayerFromServerId(tonumber(policeSrc) or -1)
    if idx==-1 then return end
    local policePed=GetPlayerPed(idx)
    if policePed==0 or not DoesEntityExist(policePed) then return end
    ClearPedTasks(PlayerPedId())
    TaskFollowToOffsetOfEntity(PlayerPedId(),policePed,0.7,1.0,0.0,1.4,-1,2.0,true)
end)

RegisterNetEvent('qb-aipolice:client:suspectRelease', function(mode)
    local p=PlayerPedId()
    handcuffed=false
    detainedLocked=false
    FreezeEntityPosition(p,false)
    escorting=false
    arrestBusy=false
    SetEnableHandcuffs(p,false)
    DisablePlayerFiring(PlayerId(),false)
    ClearPedTasks(p)
    if mode=='drive' and IsPedInAnyVehicle(p,false) then
        local v=GetVehiclePedIsIn(p,false)
        TaskVehicleDriveWander(p,v,20.0,786603)
    elseif mode=='walk' then
        TaskWanderStandard(p,10.0,10)
    end
end)

RegisterNetEvent('qb-aipolice:client:suspectPrepareVehicle', function(policeSrc)
    local p=PlayerPedId()
    local pos=GetEntityCoords(p)
    local best=nil; local dist=12.0
    for _,v in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(v) and GetDistanceBetweenCoords(pos,GetEntityCoords(v),true)<dist then
            local model=GetEntityModel(v)
            if model==joaat('police') or model==joaat('police2') or model==joaat('police3') or model==joaat('policet') or model==joaat('fbi2') or model==joaat('riot') then
                best=v; dist=GetDistanceBetweenCoords(pos,GetEntityCoords(v),true)
            end
        end
    end
    if best then
        SetVehicleDoorsLocked(best,1)
        ClearPedTasks(p)
        TaskGoStraightToCoord(p,GetOffsetFromEntityInWorldCoords(best,0.0,-2.0,0.0).x,GetOffsetFromEntityInWorldCoords(best,0.0,-2.0,0.0).y,GetOffsetFromEntityInWorldCoords(best,0.0,-2.0,0.0).z,1.2,3500,GetEntityHeading(best),0.1)
        Wait(2500)
        SetPedIntoVehicle(p,best,2)
    end
end)


RegisterNetEvent('qb-aipolice:client:suspectPlaceInVehicle', function(vehicleNetId)
    local p=PlayerPedId()
    detainedLocked=false
    FreezeEntityPosition(p,false)
    local net=tonumber(vehicleNetId)
    if not net then return end
    local deadline=GetGameTimer()+5000
    local v=NetworkGetEntityFromNetworkId(net)
    while (v==0 or not DoesEntityExist(v)) and GetGameTimer()<deadline do
        Wait(100); v=NetworkGetEntityFromNetworkId(net)
    end
    if v~=0 and DoesEntityExist(v) then
        SetVehicleDoorsLocked(v,1)
        ClearPedTasks(p)
        SetPedIntoVehicle(p,v,2)
    end
end)
