local activeUnits={}
local activeSpikes={}
local activeRoadblocks={}
local pursuitActive=false
local currentStars=0
local incidentToken=0
local lastEvasion=0
local stopOfficer=nil
local stopIssued=false
local stopStart=0
local robberyActive=false
local robberyTarget=nil
local robberyCoords=nil
local robberyToken=0

local function DebugPrint(msg) if Config.Debug then print('[qb-aipolice DEBUG][CLIENT] '..tostring(msg)) end end

local function loadModel(model)
    local hash=type(model)=='string' and joaat(model) or model
    if not IsModelInCdimage(hash) then Utils.Log('Modelo no encontrado: '..tostring(model)); return nil end
    RequestModel(hash)
    local deadline=GetGameTimer()+8000
    while not HasModelLoaded(hash) do
        Wait(0); RequestModel(hash)
        if GetGameTimer()>deadline then return nil end
    end
    return hash
end

local function roadSpawn(minD,maxD)
    local p=PlayerPedId(); local o=GetEntityCoords(p)
    for _=1,12 do
        local a=math.random()*6.283185
        local d=minD+math.random()*(maxD-minD)
        local ok,c,h=GetClosestVehicleNodeWithHeading(o.x+math.cos(a)*d,o.y+math.sin(a)*d,o.z,1,3.0,0)
        if ok then return c,h end
    end
    return o-GetEntityForwardVector(p)*minD,GetEntityHeading(p)
end

local function addPed(ped,role,aggression)
    table.insert(activeUnits,{type='ped',entity=ped,role=role,state='driving',aggression=aggression})
    return ped
end

local function spawnOfficer(model,weapons,accuracy,armor,aggression,coords,heading,vehicle)
    local hash=loadModel(model); if not hash then return nil end
    local ped
    if vehicle and DoesEntityExist(vehicle) then
        ped=CreatePedInsideVehicle(vehicle,4,hash,-1,false,true)
    else
        ped=CreatePed(4,hash,coords.x,coords.y,coords.z,heading or 0.0,true,true)
    end
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil end
    SetEntityAsMissionEntity(ped,true,true)
    SetEntityVisible(ped,true,false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped,true,true)
    SetPedArmour(ped,armor or 0); SetPedAccuracy(ped,accuracy or 30)
    SetPedRelationshipGroupHash(ped,joaat('COP'))
    SetPedAsCop(ped,true)
    SetPedCanRagdoll(ped,true)
    SetPedCombatAttributes(ped,46,true)
    SetPedCombatAttributes(ped,5,true)
    SetPedCombatMovement(ped,(aggression or 1)>=6 and 2 or 1)
    SetPedCombatAbility(ped,(aggression or 1)>=6 and 2 or 1)
    SetPedFleeAttributes(ped,0,false)
    SetBlockingOfNonTemporaryEvents(ped,true)
    for _,w in ipairs(weapons or {}) do GiveWeaponToPed(ped,joaat(w),999,false,true) end
    table.insert(activeUnits,{type='ped',entity=ped,role='officer',state='idle',aggression=aggression or 1})
    return ped
end

local function countLivePatrolVehicles(roleFilter)
    local n=0
    for _,u in ipairs(activeUnits) do
        if u.type=='vehicle' and (not roleFilter or u.role==roleFilter) and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then n=n+1 end
    end
    return n
end

local function spawnPatrol(overrideBehavior, overrideOrigin, unitRole)
    local b=overrideBehavior or Utils.GetStarBehavior(currentStars)
    if not b then return end
    local targetCount=math.min(tonumber(b.units) or 1,Config.Response.maxActiveUnits)
    local existing=countLivePatrolVehicles(unitRole or 'patrol')
    if existing>=targetCount then return end

    local remaining=targetCount-existing
    local origin=overrideOrigin or GetEntityCoords(PlayerPedId())
    local vehicleModel=Utils.GetRandom(b.vehicles)
    local officerModel=b.tactical and Config.TacticalOfficerModel or (b.military and Config.MilitaryOfficerModel or Utils.GetRandom(Config.OfficerModels))

    while remaining>0 do
        local pos,heading=roadSpawn(Config.Response.minSpawnDistance,Config.Response.maxSpawnDistance)
        local vh=loadModel(vehicleModel); if not vh then return end
        local veh=CreateVehicle(vh,pos.x,pos.y,pos.z,heading,true,true)
        SetModelAsNoLongerNeeded(vh)
        if not veh or veh==0 or not DoesEntityExist(veh) then return end
        SetEntityAsMissionEntity(veh,true,true)
        NetworkRegisterEntityAsNetworked(veh)
        local netId=NetworkGetNetworkIdFromEntity(veh)
        if netId and netId ~= 0 then SetNetworkIdCanMigrate(netId,true); SetNetworkIdExistsOnAllMachines(netId,true) end
        SetEntityVisible(veh,true,false)
        ResetEntityAlpha(veh)
        SetVehicleOnGroundProperly(veh)
        SetVehicleEngineOn(veh,true,true,false)
        SetVehicleDoorsLocked(veh,1)
        SetVehicleHasMutedSirens(veh,currentStars<=2)
        SetVehicleSiren(veh,currentStars>=3)
        if Config.VehicleLivery[vehicleModel] then SetVehicleLivery(veh,Config.VehicleLivery[vehicleModel]) end
        table.insert(activeUnits,{type='vehicle',entity=veh,role=unitRole or 'patrol'})

        local driver=spawnOfficer(officerModel,b.weapons,b.accuracy,b.armor,b.aggression,pos,heading,veh)
        if not driver then
            DeleteEntity(veh)
            activeUnits[#activeUnits]=nil
            return
        end
        SetDriverAbility(driver,1.0)
        SetDriverAggressiveness(driver,math.min(1.0,(b.aggression or 1)/10.0))
        TaskVehicleDriveToCoord(driver,veh,origin.x,origin.y,origin.z,math.max(22.0,28.0+(b.aggression or 1)),0,GetEntityModel(veh),786603,6.0,true)

        if GetVehicleMaxNumberOfPassengers(veh)>=1 then
            local passHash=loadModel(officerModel)
            if passHash then
                local pass=CreatePedInsideVehicle(veh,4,passHash,0,false,true)
                SetModelAsNoLongerNeeded(passHash)
                if pass and pass~=0 and DoesEntityExist(pass) then
                    SetEntityAsMissionEntity(pass,true,true)
                    SetEntityVisible(pass,true,false); ResetEntityAlpha(pass)
                    SetPedArmour(pass,b.armor or 0); SetPedAccuracy(pass,b.accuracy or 30)
                    SetPedRelationshipGroupHash(pass,joaat('COP')); SetPedAsCop(pass,true)
                    SetBlockingOfNonTemporaryEvents(pass,true)
                    for _,w in ipairs(b.weapons or {}) do GiveWeaponToPed(pass,joaat(w),999,false,true) end
                    table.insert(activeUnits,{type='ped',entity=pass,role='officer',state='passenger',aggression=b.aggression or 1})
                end
            end
        end
        remaining=remaining-1
        Wait(900)
    end
end

local function clearUnits()
    for _,u in ipairs(activeUnits) do
        if DoesEntityExist(u.entity) then SetEntityAsMissionEntity(u.entity,true,true); DeleteEntity(u.entity) end
    end
    activeUnits={}
    for _,o in ipairs(activeSpikes) do if DoesEntityExist(o) then DeleteEntity(o) end end
    activeSpikes={}
    for _,o in ipairs(activeRoadblocks) do if DoesEntityExist(o) then DeleteEntity(o) end end
    activeRoadblocks={}
    stopOfficer=nil; stopIssued=false
end

local function deploySpikes()
    if #activeSpikes>0 then return end
    local p=PlayerPedId()
    local c=GetEntityCoords(p)+GetEntityForwardVector(p)*55.0
    local h=loadModel('p_ld_stinger_s'); if not h then return end
    local o=CreateObject(h,c.x,c.y,c.z,true,true,false)
    PlaceObjectOnGroundProperly(o); SetModelAsNoLongerNeeded(h)
    table.insert(activeSpikes,o)
end

local function deployRoadblock()
    if #activeRoadblocks>0 then return end
    local p=PlayerPedId(); local c=GetEntityCoords(p)+GetEntityForwardVector(p)*75.0
    local b=Utils.GetStarBehavior(currentStars)
    local model=b and b.vehicles[1] or 'police2'
    local h=loadModel(model); if not h then return end
    local v=CreateVehicle(h,c.x,c.y,c.z,GetEntityHeading(p)+90.0,true,true)
    SetModelAsNoLongerNeeded(h)
    if DoesEntityExist(v) then
        FreezeEntityPosition(v,true); SetVehicleDoorsLocked(v,2); table.insert(activeRoadblocks,v)
    end
end

local function spawnAir()
    if not Config.AirSupport.enabled or currentStars<Config.AirSupport.minStarsForHeli then return end
    for _,u in ipairs(activeUnits) do if u.role=='heli' and DoesEntityExist(u.entity) then return end end
    local p=PlayerPedId(); local c=GetEntityCoords(p)+vector3(0,0,55)
    local h=loadModel(Config.AirSupport.heliModel); if not h then return end
    local heli=CreateVehicle(h,c.x,c.y,c.z,GetEntityHeading(p),true,true)
    SetModelAsNoLongerNeeded(h); if not DoesEntityExist(heli) then return end
    table.insert(activeUnits,{type='vehicle',entity=heli,role='heli'})
    local pilot=spawnOfficer(Config.TacticalOfficerModel,{'WEAPON_CARBINERIFLE'},65,100,9,c,GetEntityHeading(p))
    if pilot then SetPedIntoVehicle(pilot,heli,-1); TaskHeliChase(pilot,p,25.0) end
end

local function robberyBehavior()
    local cfg=Config.RobberyResponse
    return {
        units=math.max(1,tonumber(cfg.tacticalUnits) or 2),
        response='robbery_tactical',
        vehicles={'riot','police3'},
        weapons={'WEAPON_CARBINERIFLE','WEAPON_PUMPSHOTGUN','WEAPON_STUNGUN'},
        roadblocks=false, spikes=false, helicopter=false,
        tactical=true, military=false,
        accuracy=65, armor=100, aggression=9
    }
end

local function deployRobberyTactical(coords)
    local cfg=Config.RobberyResponse
    if not cfg.enabled then return end
    local origin=coords or GetEntityCoords(PlayerPedId())
    robberyActive=true
    robberyCoords=origin
    robberyToken=robberyToken+1
    local token=robberyToken
    local b=robberyBehavior()
    local count=math.min(b.units,Config.Response.maxActiveUnits)
    for _=1,count do
        spawnPatrol(b,origin,'robbery_patrol')
        Wait(700)
    end
    SetTimeout((tonumber(cfg.clearAfterSeconds) or 180)*1000,function()
        if robberyToken~=token then return end
        robberyActive=false
        robberyTarget=nil
        robberyCoords=nil
        for i=#activeUnits,1,-1 do
            local u=activeUnits[i]
            if u.role=='robbery_patrol' then
                if DoesEntityExist(u.entity) then SetEntityAsMissionEntity(u.entity,true,true); DeleteEntity(u.entity) end
                table.remove(activeUnits,i)
            end
        end
    end)
end

RegisterNetEvent('qb-aipolice:client:robberyDetected',function(coords,reason)
    DebugPrint(('ROBO EVENT CLIENT RECIBIDO reason=%s coords=%s starsAntes=%s'):format(tostring(reason), tostring(coords), tostring(currentStars)))
    if not Config.RobberyResponse.enabled then
        DebugPrint('ROBO EVENT CLIENT BLOQUEADO: Config.RobberyResponse.enabled=false')
        return
    end
    robberyTarget=PlayerPedId()
    local c=coords
    if type(c)~='vector3' and type(c)~='vector4' then c=GetEntityCoords(robberyTarget) end
    -- Un robo siempre activa el controlador de respuesta, aunque el jugador
    -- todavía no tenga estrellas suficientes para la IA normal.
    if currentStars < (Config.RobberyResponse.minStars or 5) then
        currentStars=math.min(Config.MaxStars,Config.RobberyResponse.minStars or 5)
        pursuitActive=true
        SendNUIMessage({action='updateStars',stars=currentStars})
    end
    DebugPrint(('ROBO DETECTADO reason=%s coords=%.2f %.2f %.2f -> respuesta tactica'):format(tostring(reason),c.x,c.y,c.z))
    deployRobberyTactical(c)
end)

local function deployForStars(stars,force)
    DebugPrint(('RESPUESTA ESTRELLAS stars=%s force=%s'):format(tostring(stars),tostring(force)))
    incidentToken=incidentToken+1
    local token=incidentToken
    currentStars=stars
    pursuitActive=stars>0
    if stars<=0 then clearUnits(); return end
    local delay=force and 0 or (stars<=2 and Config.Response.firstResponseDelay or Config.Response.firstResponseDelay+math.min(stars*700,4000))
    CreateThread(function()
        Wait(delay)
        if token~=incidentToken or currentStars<=0 then return end
        spawnPatrol()
        if currentStars>=3 then
            SetTimeout(Config.Response.reinforcementDelay,function()
                if incidentToken==token and currentStars>=3 then
                    if currentStars>=3 and Config.StarBehavior[currentStars].spikes then deploySpikes() end
                    spawnPatrol()
                end
            end)
        end
        if currentStars>=4 then SetTimeout(Config.Response.reinforcementDelay*2,function() if incidentToken==token and currentStars>=4 then deployRoadblock() end end) end
        if currentStars>=5 then SetTimeout(Config.Response.reinforcementDelay*2,function() if incidentToken==token and currentStars>=5 then spawnAir() end end) end
        if currentStars>=7 and Config.AirSupport.allowJetAirSupport then
            -- Jet air support is intentionally gated and configurable.
        end
    end)
end

local function officerNearest()
    local p=PlayerPedId(); local pc=GetEntityCoords(p); local best,dist=nil,999
    for _,u in ipairs(activeUnits) do
        if u.type=='ped' and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
            local d=#(pc-GetEntityCoords(u.entity)); if d<dist then best,dist=u.entity,d end
        end
    end
    return best,dist
end

local function issueTrafficStop(officer)
    if stopIssued or not Config.TrafficStops.enabled then return end
    stopIssued=true; stopOfficer=officer; stopStart=GetGameTimer()
    ClearPedTasks(officer)
    TaskTurnPedToFaceEntity(officer,PlayerPedId(),2500)
    TriggerServerEvent('qb-aipolice:server:trafficWarning','warning')
    SetTimeout(5000,function()
        if currentStars<=2 and DoesEntityExist(officer) and not IsEntityDead(officer) then
            local p=PlayerPedId()
            local speed=IsPedInAnyVehicle(p,false) and GetEntitySpeed(GetVehiclePedIsIn(p,false))*3.6 or 0
            if speed<15.0 then
                TriggerServerEvent('qb-aipolice:server:trafficWarning',currentStars==1 and 'warning' or 'ticket')
            else
                TriggerServerEvent('qb-aipolice:server:reportCrime','policeEvasion')
                currentStars=math.min(3,currentStars+1)
                TriggerEvent('qb-aipolice:client:starsIncreased',currentStars)
            end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(750)
        if pursuitActive and currentStars>0 then
            local p=PlayerPedId(); local pc=GetEntityCoords(p)
            if not IsEntityDead(p) then
            local b=Utils.GetStarBehavior(currentStars)
            local peaceful=currentStars<=2
            for _,u in ipairs(activeUnits) do
                if u.type=='ped' and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
                    local ped=u.entity; local d=#(pc-GetEntityCoords(ped))
                    if robberyActive and u.role=='robbery_patrol' and robberyTarget and DoesEntityExist(robberyTarget) and not IsEntityDead(robberyTarget) then
                        local target=robberyTarget
                        local targetInVehicle=IsPedInAnyVehicle(target,false)
                        local targetShooting=IsPedShooting(target) or IsPedInCombat(target,ped)
                        if targetInVehicle then
                            if d>16.0 then
                                if u.state~='robbery_chase' or GetGameTimer()-(u.lastTask or 0)>4500 then
                                    TaskVehicleChase(ped,target); u.state='robbery_chase'; u.lastTask=GetGameTimer()
                                end
                            else
                                TaskVehicleTempAction(ped,GetVehiclePedIsIn(ped,false),27,1500)
                                if GetGameTimer()-(u.lastTask or 0)>900 then
                                    TaskLeaveVehicle(ped,GetVehiclePedIsIn(ped,false),0)
                                    u.state='robbery_exit'; u.lastTask=GetGameTimer()
                                end
                            end
                        elseif IsPedInAnyVehicle(ped,false) then
                            if d<=24.0 then
                                TaskLeaveVehicle(ped,GetVehiclePedIsIn(ped,false),256); SetBlockingOfNonTemporaryEvents(ped,false); u.state='robbery_exit'; u.lastTask=GetGameTimer()
                            else
                                TaskVehicleChase(ped,target); u.state='robbery_chase'; u.lastTask=GetGameTimer()
                            end
                        else
                            SetBlockingOfNonTemporaryEvents(ped,false)
                            if targetShooting or HasEntityBeenDamagedByEntity(ped,target,true) then
                                ClearPedTasks(ped)
                                TaskCombatPed(ped,target,0,16)
                                u.state='robbery_combat'; u.lastTask=GetGameTimer()
                                ClearEntityLastDamageEntity(ped)
                            elseif d>Config.Arrest.arrestDistance then
                                local runSpeed=GetEntitySpeed(target)
                                if runSpeed>4.0 or d>28.0 then
                                    if u.state~='robbery_foot_chase' or GetGameTimer()-(u.lastTask or 0)>3000 then
                                        ClearPedTasks(ped)
                                        TaskGoToEntity(ped,target,-1,1.2,4.8,1073741824,0)
                                        u.state='robbery_foot_chase'; u.lastTask=GetGameTimer()
                                    end
                                elseif u.state~='robbery_approach' or GetGameTimer()-(u.lastTask or 0)>3000 then
                                    TaskGoToEntity(ped,target,-1,2.0,1.8,1073741824,0)
                                    u.state='robbery_approach'; u.lastTask=GetGameTimer()
                                end
                            elseif not u.arrestIssued then
                                u.arrestIssued=true
                                ClearPedTasks(ped)
                                SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true)
                                SetPedCanSwitchWeapon(ped,false)
                                TaskTurnPedToFaceEntity(ped,target,700)
                                TriggerEvent('qb-aipolice:client:aiArrest',ped)
                            end
                        end
                    elseif IsPedInAnyVehicle(ped,false) then
                        local playerShooting=IsPedShooting(p) or HasEntityBeenDamagedByEntity(ped,p,true)
                        if d<24.0 then
                            local v=GetVehiclePedIsIn(ped,false)
                            TaskVehicleTempAction(ped,v,27,1800)
                            SetVehicleForwardSpeed(v,0.0)
                            TaskLeaveVehicle(ped,v,256)
                            SetBlockingOfNonTemporaryEvents(ped,false)
                            u.state=playerShooting and 'combat_exit' or 'approach'
                            u.lastTask=GetGameTimer()
                            ClearEntityLastDamageEntity(ped)
                        elseif not peaceful or playerShooting then
                            if u.state~='chase' or GetGameTimer()-(u.lastTask or 0)>4500 then
                                TaskVehicleChase(ped,p); u.state='chase'; u.lastTask=GetGameTimer()
                            end
                        end
                    else
                        -- IA a pie: el objetivo puede huir después de que el agente
                        -- ya se bajó de la patrulla. La IA decide continuamente si
                        -- debe acercarse, perseguir a pie o entrar en combate.
                        local targetInVehicle=IsPedInAnyVehicle(p,false)
                        local playerShooting=IsPedShooting(p) or HasEntityBeenDamagedByEntity(ped,p,true) or IsPedInCombat(p,ped)
                        local playerSpeed=GetEntitySpeed(p)
                        if playerShooting then
                            ClearPedTasks(ped)
                            SetBlockingOfNonTemporaryEvents(ped,false)
                            SetCurrentPedWeapon(ped,joaat('WEAPON_CARBINERIFLE'),true)
                            SetPedCanSwitchWeapon(ped,true)
                            TaskCombatPed(ped,p,0,16)
                            u.state='combat'; u.lastTask=GetGameTimer()
                            ClearEntityLastDamageEntity(ped)
                        elseif targetInVehicle then
                            -- Si el sospechoso volvió a montarse en un vehículo,
                            -- el agente intenta recuperar la patrulla y perseguirlo.
                            u.state='target_vehicle'
                            if u.lastTask==0 or GetGameTimer()-(u.lastTask or 0)>3500 then
                                u.lastTask=GetGameTimer()
                            end
                        elseif d > Config.Arrest.arrestDistance then
                            local fleeing=(playerSpeed>4.0 or d>28.0 or u.state=='foot_chase') and not peaceful
                            if fleeing then
                                if u.state~='foot_chase' or GetGameTimer()-(u.lastTask or 0)>3000 then
                                    ClearPedTasks(ped)
                                    SetBlockingOfNonTemporaryEvents(ped,false)
                                    TaskGoToEntity(ped,p,-1,1.2,4.8,1073741824,0)
                                    u.state='foot_chase'
                                    u.lastTask=GetGameTimer()
                                end
                            elseif peaceful then
                                if u.state~='approach_arrest' or GetGameTimer()-(u.lastTask or 0)>3000 then
                                    TaskGoToEntity(ped,p,-1,1.5,1.2,1073741824,0)
                                    u.state='approach_arrest'
                                    u.lastTask=GetGameTimer()
                                end
                            else
                                if u.state~='approach_arrest' or GetGameTimer()-(u.lastTask or 0)>3000 then
                                    TaskGoToEntity(ped,p,-1,2.0,2.0,1073741824,0)
                                    u.state='approach_arrest'
                                    u.lastTask=GetGameTimer()
                                end
                            end
                        elseif not u.arrestIssued then
                            u.arrestIssued=true
                            ClearPedTasks(ped)
                            SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true)
                            SetPedCanSwitchWeapon(ped,false)
                            TaskTurnPedToFaceEntity(ped,p,700)
                            TriggerEvent('qb-aipolice:client:aiArrest',ped)
                        end
                    end
                end
            end
            if currentStars>=1 and GetGameTimer()-lastEvasion>Config.Response.evasionCheckSeconds*1000 then
                lastEvasion=GetGameTimer()
                local nearest,d=officerNearest()
                if not nearest or d>180.0 then TriggerServerEvent('qb-aipolice:server:policeEvasion') end
            end
            end
        end
    end
end)

-- CONTROL DE INTEGRIDAD DE UNIDADES AI
-- Repara patrullas que pierdan su conductor y evita vehículos vacíos/sirenas sin agente.
CreateThread(function()
    while true do
        Wait(3000)
        if pursuitActive and currentStars > 0 then
            for _,u in ipairs(activeUnits) do
                if u.type=='vehicle' and (u.role=='patrol' or u.role=='robbery_patrol') and DoesEntityExist(u.entity) then
                    local veh=u.entity
                    local driver=GetPedInVehicleSeat(veh,-1)
                    if driver==0 or not DoesEntityExist(driver) or IsEntityDead(driver) then
                        if DoesEntityExist(veh) then SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true) end
                    else
                        SetEntityVisible(driver,true,false); ResetEntityAlpha(driver)
                        SetPedAsCop(driver,true)
                        if u.role=='robbery_patrol' and robberyActive and robberyTarget and DoesEntityExist(robberyTarget) then
                            SetVehicleSiren(veh,true); SetVehicleHasMutedSirens(veh,false)
                            if not IsPedInCombat(driver,0) and GetGameTimer()-(u.lastTask or 0)>4500 then
                                TaskVehicleChase(driver,robberyTarget)
                                u.lastTask=GetGameTimer()
                            end
                        elseif currentStars >= 3 then
                            SetVehicleSiren(veh,true); SetVehicleHasMutedSirens(veh,false)
                            if not IsPedInCombat(driver,0) and GetGameTimer()-(u.lastTask or 0)>4500 then
                                TaskVehicleChase(driver,PlayerPedId())
                                u.lastTask=GetGameTimer()
                            end
                        else
                            SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true)
                            if not IsPedInCombat(driver,0) then
                                local c=GetEntityCoords(PlayerPedId())
                                TaskVehicleDriveToCoord(driver,veh,c.x,c.y,c.z,28.0,0,GetEntityModel(veh),786603,6.0,true)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- WATCHDOG DE RESPUESTA AI
-- Si por cualquier motivo el evento de estrellas llegó antes de que el
-- cliente terminara de inicializarse, este hilo garantiza que la respuesta
-- policial sí se cree. No genera unidades continuamente: respeta el máximo
-- definido para las estrellas actuales.
CreateThread(function()
    while true do
        Wait(2500)
        if currentStars > 0 and pursuitActive then
            local b=Utils.GetStarBehavior(currentStars)
            if b then
                local wanted=math.min(b.units,Config.Response.maxActiveUnits)
                if countLivePatrolVehicles() < wanted then
                    spawnPatrol()
                end
            end
        end
    end
end)

RegisterNetEvent('qb-aipolice:client:starsIncreased',function(stars)
    currentStars=math.min(Config.MaxStars,stars); pursuitActive=currentStars>0
    deployForStars(currentStars,false)
end)

RegisterNetEvent('qb-aipolice:client:starsDecreased',function(stars)
    currentStars=stars
    if stars<=0 then pursuitActive=false; clearUnits() end
end)

RegisterNetEvent('qb-aipolice:client:updateStars',function(stars)
    currentStars=stars
    if Config.UI.showStarsHud then SendNUIMessage({action='updateStars',stars=stars}) end
end)

RegisterNetEvent('qb-aipolice:client:starsChanged',function(stars)
    local old=currentStars
    currentStars=math.max(0,math.min(Config.MaxStars,tonumber(stars) or 0))
    if currentStars>0 then
        -- Recalcula la respuesta cada vez que sube el nivel de búsqueda.
        -- Antes solo se activaba al pasar de 0 -> 1, por lo que 1 -> 3 no
        -- llamaba refuerzos nuevos.
        pursuitActive=true
        if currentStars~=old then deployForStars(currentStars,false) end
    else
        pursuitActive=false
        incidentToken=incidentToken+1
        clearUnits()
    end
end)

exports('GetActivePoliceUnits',function() return activeUnits end)
exports('GetCurrentStars',function() return currentStars end)

-- ============================================================
-- DESPACHO MANUAL NUI PARA POLICÍA DE TURNO
-- Estas unidades son independientes del wanted automático.
-- ============================================================
local manualDispatch = {}
local manualDispatchBusy = false

local function commandTargetPed(targetId)
    if not targetId or targetId == '' then return nil end
    local value = tostring(targetId)

    -- Objetivo NPC seleccionado desde el NUI.
    if value:sub(1, 4) == 'npc:' then
        local ped = tonumber(value:sub(5))
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            return ped
        end
        return nil
    end

    -- Objetivo jugador real.
    local player = GetPlayerFromServerId(tonumber(value))
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if ped ~= 0 and DoesEntityExist(ped) then return ped end
    return nil
end

local function commandRoadSpawn(origin, minD, maxD)
    for _=1,16 do
        local a=math.random()*6.283185
        local d=minD+math.random()*(maxD-minD)
        local ok,c,h=GetClosestVehicleNodeWithHeading(origin.x+math.cos(a)*d,origin.y+math.sin(a)*d,origin.z,1,3.0,0)
        if ok then return c,h end
    end
    return origin-GetEntityForwardVector(PlayerPedId())*minD,GetEntityHeading(PlayerPedId())
end

local function commandBehavior(kind)
    if kind=='tactical' then
        return {vehicles={'riot','police3'},weapons={'WEAPON_CARBINERIFLE','WEAPON_PUMPSHOTGUN'},accuracy=65,armor=100,aggression=9,model=Config.TacticalOfficerModel}
    elseif kind=='military' then
        return {vehicles={'barracks','crusader'},weapons={'WEAPON_CARBINERIFLE','WEAPON_COMBATMG'},accuracy=75,armor=100,aggression=10,model=Config.MilitaryOfficerModel}
    end
    return {vehicles={'police','police2'},weapons={'WEAPON_PISTOL','WEAPON_STUNGUN'},accuracy=45,armor=25,aggression=4,model=Config.OfficerModels[1]}
end

local function addManualUnit(entity, role, target, order)
    table.insert(manualDispatch,{entity=entity,role=role,target=target,order=order})
end

local function spawnManualUnit(kind, targetPed, destination, aggressive)
    local b=commandBehavior(kind)
    local origin=GetEntityCoords(PlayerPedId())
    local pos,heading=commandRoadSpawn(origin,Config.PoliceMenu.dispatchDistance.min,Config.PoliceMenu.dispatchDistance.max)
    local vehicleModel=Utils.GetRandom(b.vehicles)
    local vh=loadModel(vehicleModel); if not vh then return nil end
    local veh=CreateVehicle(vh,pos.x,pos.y,pos.z,heading,true,true)
    SetModelAsNoLongerNeeded(vh)
    if not veh or veh==0 or not DoesEntityExist(veh) then return nil end
    SetEntityAsMissionEntity(veh,true,true)
    NetworkRegisterEntityAsNetworked(veh)
    local netId=NetworkGetNetworkIdFromEntity(veh)
    if netId and netId ~= 0 then SetNetworkIdCanMigrate(netId,true); SetNetworkIdExistsOnAllMachines(netId,true) end
    SetEntityVisible(veh,true,false); ResetEntityAlpha(veh)
    SetVehicleOnGroundProperly(veh); SetVehicleEngineOn(veh,true,true,false); SetVehicleDoorsLocked(veh,1)
    SetVehicleHasMutedSirens(veh,false); SetVehicleSiren(veh,true)
    local driver=spawnOfficer(b.model,b.weapons,b.accuracy,b.armor,b.aggression,pos,heading,veh)
    if not driver then DeleteEntity(veh); return nil end
    addManualUnit(veh,'manual_vehicle',targetPed,kind); addManualUnit(driver,kind,targetPed,kind)
    SetDriverAbility(driver,1.0); SetDriverAggressiveness(driver,math.min(1.0,(b.aggression or 4)/10.0))

    if targetPed and DoesEntityExist(targetPed) and not IsEntityDead(targetPed) then
        SetBlockingOfNonTemporaryEvents(targetPed,false)
        SetPedAsEnemy(targetPed,false)
        SetPedCanRagdoll(targetPed,true)
        if aggressive then
            TaskVehicleChase(driver,targetPed)
        else
            local tc=GetEntityCoords(targetPed)
            TaskVehicleDriveToCoord(driver,veh,tc.x,tc.y,tc.z,25.0,0,GetEntityModel(veh),786603,7.0,true)
        end
    elseif destination then
        TaskVehicleDriveToCoord(driver,veh,destination.x,destination.y,destination.z,24.0,0,GetEntityModel(veh),786603,5.0,true)
    else
        TaskVehicleDriveWander(driver,veh,24.0,786603)
    end
    return driver,veh
end

local function spawnManualUnits(kind,count,targetPed,destination,aggressive)
    count=math.max(1,math.min(tonumber(count) or 1,Config.PoliceMenu.maxDispatchUnits))
    local made=0
    for i=1,count do
        if spawnManualUnit(kind,targetPed,destination,aggressive) then made=made+1 end
        Wait(350)
    end
    return made
end

local function notifyPoliceMenu(msg)
    SendNUIMessage({action='policeMenuStatus',message=msg})
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local deadline=GetGameTimer()+5000
    while not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function cleanupTransportUnit(u, target, ped, veh, keepTarget)
    -- Limpieza EXCLUSIVA de una unidad que ya terminó el traslado.
    -- No toca las unidades de la IA automática ni otras órdenes del NUI.
    if u then u.order='transport_done'; u.transportCleanupPending=true end

    if ped and ped ~= 0 and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped,true,true)
        ClearPedTasksImmediately(ped)
        SetBlockingOfNonTemporaryEvents(ped,false)
        DeletePed(ped)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end

    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh,true,true)
        SetVehicleSiren(veh,false)
        SetVehicleHasMutedSirens(veh,true)
        SetVehicleDoorsLocked(veh,1)
        DeleteVehicle(veh)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end

    -- El NPC detenido ya cumplió su proceso; no dejamos el ped congelado en la cárcel.
    if target and DoesEntityExist(target) and not IsPedAPlayer(target) and not keepTarget then
        SetEntityAsMissionEntity(target,true,true)
        FreezeEntityPosition(target,false)
        SetEnableHandcuffs(target,false)
        ClearPedTasksImmediately(target)
        DeletePed(target)
        if DoesEntityExist(target) then DeleteEntity(target) end
    end

    for i=#manualDispatch,1,-1 do
        local item=manualDispatch[i]
        if item==u or item==ped or item==veh or (u and item.entity==u.entity) or (veh and item.entity==veh) or (ped and item.entity==ped) then
            table.remove(manualDispatch,i)
        end
    end

    DebugPrint(('TRANSPORT cleanup ped=%s veh=%s target=%s'):format(tostring(ped),tostring(veh),tostring(target)))
end

local function getManualUnitForTarget(target, preferred)
    local best=nil; local bestDist=9999.0
    for _,u in ipairs(manualDispatch) do
        if u.role~='manual_vehicle' and u.target==target and u.entity and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
            if preferred and u.order==preferred then return u end
            local d=#(GetEntityCoords(u.entity)-GetEntityCoords(target))
            if d<bestDist then best=u; bestDist=d end
        end
    end
    return best
end

local function holdNpcTarget(target)
    if target and DoesEntityExist(target) and not IsPedAPlayer(target) and not IsEntityDead(target) then
        FreezeEntityPosition(target, true)
        SetBlockingOfNonTemporaryEvents(target, true)
        SetPedAsEnemy(target, false)
        SetCurrentPedWeapon(target, joaat('WEAPON_UNARMED'), true)
        SetPedCanSwitchWeapon(target, false)
        TaskStandStill(target, -1)
    end
end

local function releaseNpcTargetForOrder(target)
    if target and DoesEntityExist(target) and not IsPedAPlayer(target) and not IsEntityDead(target) then
        FreezeEntityPosition(target, false)
        SetBlockingOfNonTemporaryEvents(target, true)
        SetPedAsEnemy(target, false)
        SetCurrentPedWeapon(target, joaat('WEAPON_UNARMED'), true)
        SetPedCanSwitchWeapon(target, false)
        ClearPedTasks(target)
    end
end

local function executeNpcSuspectAction(action,target,officer,vehicle,actionToken,unit)
    DebugPrint(('EXEC NPC action=%s target=%s officer=%s'):format(tostring(action),tostring(target),tostring(officer)))
    if not target or not DoesEntityExist(target) or IsEntityDead(target) then return false end
    local function stillCurrent()
        return not unit or unit.actionToken == actionToken
    end
    local d=#(GetEntityCoords(officer)-GetEntityCoords(target))
    if d>3.2 then return false end
    -- El objetivo permanece retenido por defecto. Solo se libera durante una
    -- orden que explícitamente necesita que camine/conduzca.
    holdNpcTarget(target)
    ClearPedTasks(officer)
    TaskTurnPedToFaceEntity(officer,target,700)
    if action=='requestId' then
        local model=GetEntityModel(target)
        local vehicle=GetVehiclePedIsIn(target,false)
        local plate=vehicle~=0 and GetVehicleNumberPlateText(vehicle) or 'N/A'
        notifyPoliceMenu(('ID NPC | Modelo: %s | Placa: %s'):format(tostring(model),plate))
    elseif action=='vehicleSearch' then
        local v=GetVehiclePedIsIn(target,false)
        if v==0 then notifyPoliceMenu('El sospechoso no está dentro de un vehículo.'); return true end
        local plate=GetVehicleNumberPlateText(v)
        local weapon=GetSelectedPedWeapon(target)
        local illegal=weapon~=joaat('WEAPON_UNARMED')
        notifyPoliceMenu(illegal and ('Registro de vehículo: posible arma detectada | Placa %s'):format(plate) or ('Registro de vehículo: nada ilegal detectado | Placa %s'):format(plate))
    elseif action=='search' then
        if loadAnimDict('amb@medic@standing@kneel@base') then TaskPlayAnim(officer,'amb@medic@standing@kneel@base','base',4.0,-4.0,2200,49,0,false,false,false) end
        Wait(1800)
        if not stillCurrent() then return false end
        notifyPoliceMenu('Registro del NPC completado. No se encontró inventario ilegal verificable.')
    elseif action=='follow' then
        FreezeEntityPosition(target,false)
        SetBlockingOfNonTemporaryEvents(target,true)
        ClearPedTasks(target)
        TaskFollowToOffsetOfEntity(target,officer,0.8,0.8,0.0,1.6,-1,2.0,true)
        notifyPoliceMenu('El NPC está siguiendo al agente.')
    elseif action=='wrist' then
        if IsEntityPositionFrozen(target) then
            FreezeEntityPosition(target,false); ClearPedTasks(target); notifyPoliceMenu('NPC liberado de las muñecas.')
        else
            FreezeEntityPosition(target,true)
            if loadAnimDict('mp_arresting') then TaskPlayAnim(officer,'mp_arresting','a_uncuff',8.0,-8.0,1400,48,0,false,false,false) end
            notifyPoliceMenu('NPC sujetado de las muñecas.')
        end
    elseif action=='face' then
        ClearPedTasks(target); TaskTurnPedToFaceEntity(target,officer,1000); notifyPoliceMenu('NPC orientado hacia el agente.')
    elseif action=='releaseDrive' then
        FreezeEntityPosition(target,false); SetBlockingOfNonTemporaryEvents(target,false); ClearPedTasks(target)
        local v=GetVehiclePedIsIn(target,false); if v~=0 then TaskVehicleDriveWander(target,v,20.0,786603) else TaskWanderStandard(target,10.0,10) end
        notifyPoliceMenu('NPC liberado; puede marcharse conduciendo.')
    elseif action=='releaseWalk' then
        FreezeEntityPosition(target,false); SetBlockingOfNonTemporaryEvents(target,false); ClearPedTasks(target); TaskWanderStandard(target,10.0,10)
        notifyPoliceMenu('NPC liberado a pie.')
    elseif action=='detain' then
        -- Si el sospechoso está dentro de un vehículo, la orden DETENER
        -- primero detiene el auto y hace bajar al ocupante. Después aplica
        -- las esposas. Esto funciona tanto para NPC que conduce como para
        -- pasajeros NPC seleccionados por el ojo.
        if IsPedInAnyVehicle(target,false) then
            local suspectVeh=GetVehiclePedIsIn(target,false)
            if suspectVeh~=0 and DoesEntityExist(suspectVeh) then
                SetVehicleForwardSpeed(suspectVeh,0.0)
                SetVehicleHandbrake(suspectVeh,true)
                TaskVehicleTempAction(target,suspectVeh,27,3500)
                Wait(700)
                TaskLeaveVehicle(target,suspectVeh,256)
                local leaveDeadline=GetGameTimer()+3500
                while IsPedInAnyVehicle(target,false) and GetGameTimer()<leaveDeadline do Wait(100) end
                SetVehicleHandbrake(suspectVeh,false)
            end
        end
        SetPedAsEnemy(target,false)
        SetBlockingOfNonTemporaryEvents(target,true)
        ClearPedTasks(target)
        SetCurrentPedWeapon(target,joaat('WEAPON_UNARMED'),true)
        SetPedCanSwitchWeapon(target,false)
        TaskHandsUp(target,5000,officer,true,true)
        Wait(1200)
        if not stillCurrent() then return false end
        SetEnableHandcuffs(target,true)
        SetPedCanSwitchWeapon(target,false)
        FreezeEntityPosition(target,true)
        if loadAnimDict('mp_arresting') then
            TaskPlayAnim(target,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
            TaskPlayAnim(officer,'mp_arresting','a_uncuff',8.0,-8.0,1800,48,0,false,false,false)
        end
        notifyPoliceMenu('NPC detenido y esposado.')
    elseif action=='uncuff' then
        FreezeEntityPosition(target,false); SetEnableHandcuffs(target,false); ClearPedTasks(target); notifyPoliceMenu('NPC desesposado.')
    elseif action=='placeCar' then
        local v=vehicle or GetVehiclePedIsIn(officer,false)
        if not v or v==0 or not DoesEntityExist(v) then
            notifyPoliceMenu('No hay vehículo policial disponible para montar al NPC.')
            return false
        end
        SetVehicleDoorsLocked(v,1)
        local seat=2

        -- Si ya está dentro de ESTA misma patrulla, una segunda orden de
        -- 'Meter en vehículo' simplemente vuelve a asegurar el asiento.
        if IsPedInVehicle(target,v,false) then
            SetEnableHandcuffs(target,true)
            SetBlockingOfNonTemporaryEvents(target,true)
            SetPedCanSwitchWeapon(target,false)
            notifyPoliceMenu('NPC ya estaba en la patrulla; quedó asegurado.')
            return true
        end

        -- Si estaba en otro vehículo, primero se baja y después se vuelve a
        -- montar. Esto permite repetir la orden tantas veces como sea necesario.
        releaseNpcTargetForOrder(target)
        if IsPedInAnyVehicle(target,false) then
            local oldVeh=GetVehiclePedIsIn(target,false)
            TaskLeaveVehicle(target,oldVeh,256)
            local deadline=GetGameTimer()+3500
            while IsPedInAnyVehicle(target,false) and GetGameTimer()<deadline do
                Wait(100)
            end
        end

        local tc=GetOffsetFromEntityInWorldCoords(v,0.0,-2.0,0.0)
        TaskGoStraightToCoord(target,tc.x,tc.y,tc.z,1.2,5000,GetEntityHeading(v),0.1)
        local deadline=GetGameTimer()+4500
        while #(GetEntityCoords(target)-tc)>2.2 and GetGameTimer()<deadline do
            if not stillCurrent() then return false end
            Wait(100)
        end
        if not stillCurrent() then return false end

        ClearPedTasks(target)
        SetPedIntoVehicle(target,v,seat)
        if IsPedInVehicle(target,v,false) then
            SetEnableHandcuffs(target,true)
            SetBlockingOfNonTemporaryEvents(target,true)
            SetPedCanSwitchWeapon(target,false)
            notifyPoliceMenu('NPC colocado en el vehículo policial y asegurado.')
            return true
        end
        notifyPoliceMenu('No se pudo colocar al NPC en el vehículo policial.')
        holdNpcTarget(target)
        return false
    elseif action=='jail' then
        -- Un NPC no tiene server ID ni inventario persistente: no debemos encarcelar al oficial.
        -- Se procesa al NPC local llevándolo a la zona de prisión y dejándolo detenido.
        local jailPos = Config.Arrest.fallbackJailCoords
        FreezeEntityPosition(target,false)
        SetEnableHandcuffs(target,true)
        SetBlockingOfNonTemporaryEvents(target,true)
        ClearPedTasksImmediately(target)
        SetEntityCoordsNoOffset(target,jailPos.x,jailPos.y,jailPos.z,false,false,false)
        SetEntityHeading(target,0.0)
        FreezeEntityPosition(target,true)
        if loadAnimDict('mp_arresting') then
            TaskPlayAnim(target,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
        end
        notifyPoliceMenu('NPC enviado a prisión. El oficial no fue encarcelado.')
    end
    return true
end

local function manualNearestTarget(targetId)
    -- Nunca sustituir el objetivo elegido por "el NPC más cercano".
    -- El menú solo entrega el ped que el oficial tenía directamente al frente.
    local ped=commandTargetPed(targetId)
    if ped and DoesEntityExist(ped) and not IsEntityDead(ped) then return ped end
    return nil
end

local function manualDeploySpikesAt(targetPed)
    local c=targetPed and DoesEntityExist(targetPed) and GetEntityCoords(targetPed) or GetEntityCoords(PlayerPedId())
    local h=loadModel('p_ld_stinger_s'); if not h then return false end
    local o=CreateObject(h,c.x,c.y,c.z,true,true,false)
    PlaceObjectOnGroundProperly(o); SetEntityHeading(o,GetEntityHeading(PlayerPedId())); SetModelAsNoLongerNeeded(h)
    table.insert(activeSpikes,o)
    return true
end

local function manualRoadblockAt(targetPed)
    local c=targetPed and DoesEntityExist(targetPed) and GetEntityCoords(targetPed) or GetEntityCoords(PlayerPedId())
    local h=loadModel('police2'); if not h then return false end
    local v=CreateVehicle(h,c.x+18.0,c.y+18.0,c.z,GetEntityHeading(PlayerPedId())+90.0,true,true)
    SetModelAsNoLongerNeeded(h)
    if not DoesEntityExist(v) then return false end
    FreezeEntityPosition(v,true); SetVehicleDoorsLocked(v,2)
    table.insert(activeRoadblocks,v)
    return true
end

-- EJECUTOR DE ÓRDENES MANUALES + IA AUTÓNOMA
-- Las unidades no se quedan simplemente paradas después de aparecer.
-- Cada agente conserva su orden, vehículo y objetivo y vuelve a emitir su
-- tarea cuando GTA la pierde/interrumpe.

local function unitVehicle(ped)
    if ped and DoesEntityExist(ped) and IsPedInAnyVehicle(ped,false) then
        return GetVehiclePedIsIn(ped,false)
    end
    return 0
end

local function unitTargetAlive(target)
    return target and DoesEntityExist(target) and not IsEntityDead(target)
end

local function refreshVehicleChase(u, target)
    local ped=u.entity
    local veh=unitVehicle(ped)
    if veh~=0 and unitTargetAlive(target) then
        SetVehicleEngineOn(veh,true,true,false)
        SetVehicleSiren(veh,true)
        SetVehicleHasMutedSirens(veh,false)
        SetBlockingOfNonTemporaryEvents(ped,true)
        TaskVehicleChase(ped,target)
        u.state='chase'
        u.lastTask=GetGameTimer()
        return true
    end
    return false
end

local function refreshVehicleDrive(u, coords, speed)
    local ped=u.entity
    local veh=unitVehicle(ped)
    if veh~=0 then
        SetVehicleSiren(veh,false)
        SetVehicleHasMutedSirens(veh,true)
        SetBlockingOfNonTemporaryEvents(ped,true)
        TaskVehicleDriveToCoord(ped,veh,coords.x,coords.y,coords.z,speed or 22.0,0,GetEntityModel(veh),786603,6.0,true)
        u.lastTask=GetGameTimer()
        return true
    end
    return false
end

local function refreshPatrol(u)
    local ped=u.entity
    local veh=unitVehicle(ped)
    if veh~=0 then
        SetVehicleSiren(veh,false)
        SetVehicleHasMutedSirens(veh,true)
        SetBlockingOfNonTemporaryEvents(ped,true)
        TaskVehicleDriveWander(ped,veh,22.0,786603)
        u.state='patrolling'
        u.lastTask=GetGameTimer()
        return true
    end
    return false
end

local function refreshGuard(u)
    local ped=u.entity
    local player=PlayerPedId()
    local pc=GetEntityCoords(player)
    local d=#(GetEntityCoords(ped)-pc)
    if d>Config.AutonomousPolice.guardDistance then
        ClearPedTasks(ped)
        TaskGoToEntity(ped,player,-1,Config.AutonomousPolice.guardDistance-2.0,2.0,1073741824,0)
        u.state='guard_approach'
    else
        ClearPedTasks(ped)
        TaskStandStill(ped,Config.AutonomousPolice.idleTaskRefresh)
        u.state='guarding'
    end
    u.lastTask=GetGameTimer()
end

local function nearbyThreatForUnit(u)
    local ped=u.entity
    local pc=GetEntityCoords(ped)
    local best=nil
    local bestD=Config.AutonomousPolice.patrolSearchDistance
    for _,p in ipairs(GetGamePool('CPed')) do
        if p~=ped and DoesEntityExist(p) and not IsEntityDead(p)
        and not IsPedInAnyVehicle(p,false) then
            local d=#(pc-GetEntityCoords(p))
            if d<bestD then
                if IsPedShooting(p) or IsPedInMeleeCombat(p) then
                    best=p; bestD=d
                end
            end
        end
    end
    return best
end

CreateThread(function()
    while true do
        Wait(1000)
        local now=GetGameTimer()

        -- Limpieza de referencias destruidas.
        for i=#manualDispatch,1,-1 do
            local u=manualDispatch[i]
            if not u.entity or not DoesEntityExist(u.entity) then
                table.remove(manualDispatch,i)
            elseif u.role~='manual_vehicle' and IsEntityDead(u.entity) then
                table.remove(manualDispatch,i)
            end
        end

        for _,u in ipairs(manualDispatch) do
            if u.role~='manual_vehicle' and u.entity and DoesEntityExist(u.entity)
            and not IsEntityDead(u.entity) then
                local ped=u.entity
                local target=u.target
                local veh=unitVehicle(ped)
                local dTarget=target and unitTargetAlive(target) and #(GetEntityCoords(ped)-GetEntityCoords(target)) or 9999.0
                local player=PlayerPedId()

                -- Si el nivel de búsqueda del jugador sube, una patrulla
                -- manual puede reaccionar sin necesitar otro botón del menú.
                if Config.AutonomousPolice.enabled and currentStars>0
                and (u.order=='backup' or u.order=='patrol' or u.order=='investigate') then
                    if dTarget==9999.0 then
                        target=player
                        u.target=player
                    end
                    if currentStars>=3 then
                        if veh~=0 and (u.state~='chase' or now-(u.lastTask or 0)>5000) then
                            refreshVehicleChase(u,target)
                        elseif veh==0 and #(GetEntityCoords(ped)-GetEntityCoords(player))>4.0 then
                            TaskGoToEntity(ped,player,-1,3.0,2.5,1073741824,0)
                            u.state='foot_response'; u.lastTask=now
                        elseif veh==0 and #(GetEntityCoords(ped)-GetEntityCoords(player))<=4.0 then
                            TaskCombatPed(ped,player,0,16)
                            u.state='combat'; u.lastTask=now
                        end
                    end
                end

                if u.order=='backup' then
                    local pc=GetEntityCoords(player)
                    local d=#(GetEntityCoords(ped)-pc)
                    if veh~=0 and d>14.0 then
                        if now-(u.lastTask or 0)>5000 or u.state~='backup_drive' then
                            SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true)
                            TaskVehicleDriveToCoord(ped,veh,pc.x,pc.y,pc.z,24.0,0,GetEntityModel(veh),786603,6.0,true)
                            u.state='backup_drive'; u.lastTask=now
                        end
                    elseif veh~=0 and d<=14.0 then
                        TaskVehicleTempAction(ped,veh,27,2500)
                        SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true)
                        u.state='backup_arrived'
                        if now-(u.lastTask or 0)>Config.AutonomousPolice.idleTaskRefresh then
                            TaskVehicleDriveWander(ped,veh,5.0,786603)
                            u.lastTask=now
                        end
                    elseif veh==0 then
                        refreshGuard(u)
                    end

                elseif u.order=='investigate' then
                    local dest=u.destination or GetEntityCoords(player)
                    u.destination=dest
                    if veh~=0 then
                        if now-(u.lastTask or 0)>6000 or u.state~='investigate_drive' then
                            local dd=#(GetEntityCoords(ped)-dest)
                            if dd>18.0 then
                                refreshVehicleDrive(u,dest,20.0); u.state='investigate_drive'
                            else
                                TaskVehicleTempAction(ped,veh,27,2500)
                                u.state='investigate_scene'; u.sceneStart=u.sceneStart or now; u.lastTask=now
                            end
                        end
                    else
                        local dd=#(GetEntityCoords(ped)-dest)
                        if dd>5.0 then
                            TaskGoToCoordAnyMeans(ped,dest.x,dest.y,dest.z,1.5,0,false,786603,0.0)
                            u.state='investigate_foot'; u.lastTask=now
                        elseif now-(u.sceneStart or now)<Config.AutonomousPolice.investigateDuration then
                            local threat=nearbyThreatForUnit(u)
                            if threat then
                                TaskCombatPed(ped,threat,0,16); u.state='investigate_combat'
                            else
                                TaskStandStill(ped,3000); u.lastTask=now
                            end
                        else
                            u.order='patrol'; u.lastTask=0
                        end
                    end

                elseif u.order=='patrol' then
                    local threat=Config.AutonomousPolice.enabled and nearbyThreatForUnit(u) or nil
                    if currentStars>=3 then
                        target=player
                        u.target=player
                        if veh~=0 and (u.state~='chase' or now-(u.lastTask or 0)>5000) then
                            refreshVehicleChase(u,target)
                        elseif veh==0 then
                            TaskCombatPed(ped,player,0,16); u.state='combat'; u.lastTask=now
                        end
                    elseif threat then
                        TaskCombatPed(ped,threat,0,16)
                        u.state='patrol_response'; u.lastTask=now
                    elseif veh~=0 and (now-(u.lastTask or 0)>Config.AutonomousPolice.idleTaskRefresh or u.state~='patrolling') then
                        refreshPatrol(u)
                    elseif veh==0 and now-(u.lastTask or 0)>Config.AutonomousPolice.idleTaskRefresh then
                        TaskWanderStandard(ped,10.0,10)
                        u.state='foot_patrol'; u.lastTask=now
                    end

                elseif u.order=='traffic' then
                    if unitTargetAlive(target) then
                        if veh~=0 and dTarget>18.0 then
                            local tc=GetEntityCoords(target)
                            refreshVehicleDrive(u,tc,22.0)
                            u.state='traffic_drive'
                        elseif veh~=0 and dTarget<=18.0 then
                            TaskVehicleTempAction(ped,veh,27,3000)
                            SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true)
                            TaskLeaveVehicle(ped,veh,256)
                            u.order='traffic_on_foot'; u.lastTask=now
                        end
                    end

                elseif u.order=='traffic_on_foot' then
                    if unitTargetAlive(target) then
                        local d=#(GetEntityCoords(ped)-GetEntityCoords(target))
                        if d>7.0 then
                            TaskGoToEntity(ped,target,-1,2.0,2.0,1073741824,0)
                        elseif now-(u.lastTask or 0)>5000 then
                            ClearPedTasks(ped)
                            TaskTurnPedToFaceEntity(ped,target,1000)
                            if loadAnimDict('amb@world_human_cop_idles@male@idle_a') then
                                TaskPlayAnim(ped,'amb@world_human_cop_idles@male@idle_a','idle_a',4.0,-4.0,3500,49,0,false,false,false)
                            end
                            u.lastTask=now
                        end
                    end

                elseif u.order=='pursuit' then
                    if unitTargetAlive(target) then
                        if veh~=0 then
                            if u.state~='chase' or now-(u.lastTask or 0)>5000 then
                                refreshVehicleChase(u,target)
                            end
                        elseif dTarget>4.0 then
                            TaskGoToEntity(ped,target,-1,2.5,5.0,1073741824,0)
                            u.state='foot_chase'; u.lastTask=now
                        else
                            TaskCombatPed(ped,target,0,16)
                            u.state='combat'; u.lastTask=now
                        end
                    end

                elseif u.order=='tactical' or u.order=='military' then
                    if unitTargetAlive(target) then
                        if veh~=0 and dTarget>20.0 then
                            if u.state~='chase' or now-(u.lastTask or 0)>5000 then refreshVehicleChase(u,target) end
                        else
                            if u.state~='combat' or now-(u.lastTask or 0)>6000 then
                                TaskCombatPed(ped,target,0,16)
                                u.state='combat'; u.lastTask=now
                            end
                        end
                    end

                elseif u.order=='transport' then
                    if unitTargetAlive(target) then
                        if veh~=0 and dTarget>18.0 then
                            if u.state~='transport_chase' or now-(u.lastTask or 0)>5000 then
                                SetVehicleSiren(veh,true); SetVehicleHasMutedSirens(veh,false)
                                TaskVehicleChase(ped,target)
                                u.state='transport_chase'; u.lastTask=now
                            end
                        elseif veh~=0 and dTarget<=18.0 then
                            SetVehicleSiren(veh,false); SetVehicleHasMutedSirens(veh,true)
                            TaskVehicleTempAction(ped,veh,27,2500)
                            TaskLeaveVehicle(ped,veh,256)
                            u.order='transport_on_foot'; u.lastTask=now
                        end
                    end

                elseif u.order=='transport_on_foot' then
                    if unitTargetAlive(target) then
                        local d=#(GetEntityCoords(ped)-GetEntityCoords(target))
                        if d>3.5 then
                            TaskGoToEntity(ped,target,-1,2.0,2.0,1073741824,0)
                        elseif not u.actionDone then
                            u.actionDone=true
                            ClearPedTasks(ped)
                            TaskTurnPedToFaceEntity(ped,target,1000)
                            if loadAnimDict('mp_arresting') then
                                TaskHandsUp(target,5000,-1,true,true)
                                Wait(1200)
                                SetEnableHandcuffs(target,true)
                                TaskPlayAnim(target,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
                                TaskPlayAnim(ped,'mp_arresting','a_uncuff',8.0,-8.0,1800,48,0,false,false,false)
                            end
                            Wait(1800)
                            local v=GetVehiclePedIsIn(ped,false)
                            if v==0 then
                                -- Busca el vehículo policial asociado a la unidad.
                                for _,vu in ipairs(manualDispatch) do
                                    if vu.role=='manual_vehicle' and vu.target==target and DoesEntityExist(vu.entity) then
                                        v=vu.entity; break
                                    end
                                end
                            end
                            if v~=0 and DoesEntityExist(v) then
                                FreezeEntityPosition(target,false)
                                SetVehicleDoorsLocked(v,1)
                                if IsPedAPlayer(target) then
                                    local idx=NetworkGetPlayerIndexFromPed(target)
                                    if idx~=-1 then
                                        local sid=GetPlayerServerId(idx)
                                        TriggerServerEvent('qb-aipolice:server:policeSuspectPlacePlayer',tostring(sid),NetworkGetNetworkIdFromEntity(v))
                                        DebugPrint(('TRANSPORT solicitando montaje jugador sid=%s veh=%s'):format(sid,NetworkGetNetworkIdFromEntity(v)))
                                    end
                                    u.order='transport_mount'
                                    u.vehicle=v
                                    u.lastTask=GetGameTimer()
                                else
                                    SetPedIntoVehicle(target,v,2)
                                    u.order='transport_escort'
                                    u.vehicle=v
                                    u.lastTask=GetGameTimer()
                                end
                            else
                                notifyPoliceMenu('La unidad detuvo al objetivo, pero no encontró su vehículo.')
                                DebugPrint('TRANSPORT fallo: vehiculo no encontrado al montar')
                            end
                        end
                    end

                elseif u.order=='transport_mount' then
                    local v=u.vehicle
                    if unitTargetAlive(target) and v and DoesEntityExist(v) then
                        if GetPedInVehicleSeat(v,2)==target then
                            DebugPrint('TRANSPORT jugador confirmado en asiento, continuando a carcel')
                            u.order='transport_escort'
                            u.state='transport_to_jail'
                            u.lastTask=0
                        elseif not IsPedInAnyVehicle(target,false) and now-(u.lastTask or 0)>6000 then
                            DebugPrint('TRANSPORT jugador no entro a tiempo; reintentando montaje')
                            local idx=NetworkGetPlayerIndexFromPed(target)
                            if idx~=-1 then
                                local sid=GetPlayerServerId(idx)
                                TriggerServerEvent('qb-aipolice:server:policeSuspectPlacePlayer',tostring(sid),NetworkGetNetworkIdFromEntity(v))
                            end
                            u.lastTask=now
                        end
                    end

                elseif u.order=='transport_cleanup_route' then
                    -- El detenido ya fue procesado en la cárcel. La unidad sale
                    -- de la zona de entrega y desaparece en el punto configurado,
                    -- evitando que la patrulla se quede chocando dentro del penal.
                    local v=u.vehicle
                    local cleanup=Config.RobberyResponse and Config.RobberyResponse.transportCleanupCoords
                    local cleanupDistance=(Config.RobberyResponse and Config.RobberyResponse.transportCleanupDistance) or 12.0
                    if not cleanup then
                        cleanup=vector3(1682.18,2607.53,44.56)
                    end
                    if v and DoesEntityExist(v) and ped and DoesEntityExist(ped) then
                        local vc=GetEntityCoords(v)
                        local dCleanup=#(vc-cleanup)
                        if dCleanup <= cleanupDistance then
                            DebugPrint(('TRANSPORT cleanup en punto de salida %.1f m'):format(dCleanup))
                            cleanupTransportUnit(u,target,ped,v,IsPedAPlayer(target))
                        elseif u.state~='transport_cleanup_route' or GetGameTimer()-(u.lastTask or 0)>5000 then
                            SetVehicleSiren(v,false)
                            SetVehicleHasMutedSirens(v,true)
                            SetVehicleDoorsLocked(v,1)
                            SetBlockingOfNonTemporaryEvents(ped,true)
                            TaskVehicleDriveToCoordLongrange(ped,v,cleanup.x,cleanup.y,cleanup.z,22.0,786603,8.0)
                            u.state='transport_cleanup_route'
                            u.lastTask=GetGameTimer()
                        end
                    elseif v and not DoesEntityExist(v) then
                        DebugPrint('TRANSPORT cleanup: vehiculo ya no existe; limpiando unidad')
                        cleanupTransportUnit(u,target,ped,v,IsPedAPlayer(target))
                    end

                elseif u.order=='transport_escort' then
                    local v=u.vehicle
                    if unitTargetAlive(target) and v and DoesEntityExist(v) then
                        -- El sospechoso ya está montado: el agente conduce la patrulla
                        -- COMPLETA hasta la cárcel. No se procesa ni se elimina nada antes
                        -- de llegar al punto de entrega.
                        if GetPedInVehicleSeat(v,2)==target then
                            local jail=Config.Arrest.fallbackJailCoords
                            local vc=GetEntityCoords(v)
                            local dJail=#(vc-jail)
                            -- Dentro del penal la patrulla puede quedar atrapada
                            -- chocando contra la geometria. Consideramos la entrega
                            -- completada al entrar en un radio amplio del punto de
                            -- procesamiento y luego la llevamos al punto de limpieza.
                            if dJail <= 35.0 then
                                DebugPrint(('TRANSPORT llegada a prision detectada distancia=%.1f; procesando detenido'):format(dJail))
                                if IsPedAPlayer(target) then
                                    local idx=NetworkGetPlayerIndexFromPed(target)
                                    if idx~=-1 then
                                        local sid=GetPlayerServerId(idx)
                                        TriggerServerEvent('qb-aipolice:server:policeSuspectJail',sid)
                                    end
                                    Wait(1200)
                                    local cleanup=Config.RobberyResponse and Config.RobberyResponse.transportCleanupCoords or vector3(1682.18,2607.53,44.56)
                                    if DoesEntityExist(v) then
                                        SetEntityCoordsNoOffset(v,cleanup.x,cleanup.y,cleanup.z,false,false,false)
                                        SetEntityHeading(v,0.0)
                                    end
                                    DebugPrint(('TRANSPORT jugador procesado; patrulla movida al punto de limpieza %.2f %.2f %.2f'):format(cleanup.x,cleanup.y,cleanup.z))
                                    cleanupTransportUnit(u,target,ped,v,true)
                                else
                                    SetVehicleDoorsLocked(v,2)
                                    FreezeEntityPosition(target,true)
                                    SetEntityCoordsNoOffset(target,jail.x,jail.y,jail.z,false,false,false)
                                    SetEnableHandcuffs(target,false)
                                    ClearPedTasksImmediately(target)
                                    Wait(1200)
                                    if DoesEntityExist(target) then
                                        SetEntityAsMissionEntity(target,true,true)
                                        DeletePed(target)
                                        if DoesEntityExist(target) then DeleteEntity(target) end
                                    end
                                    local cleanup=Config.RobberyResponse and Config.RobberyResponse.transportCleanupCoords or vector3(1682.18,2607.53,44.56)
                                    if DoesEntityExist(v) then
                                        SetEntityCoordsNoOffset(v,cleanup.x,cleanup.y,cleanup.z,false,false,false)
                                        SetEntityHeading(v,0.0)
                                    end
                                    DebugPrint(('TRANSPORT NPC procesado; patrulla movida al punto de limpieza %.2f %.2f %.2f'):format(cleanup.x,cleanup.y,cleanup.z))
                                    cleanupTransportUnit(u,target,ped,v,false)
                                end
                            elseif u.state~='transport_to_jail' or GetGameTimer()-(u.lastTask or 0)>7000 then
                                SetVehicleSiren(v,true)
                                SetVehicleHasMutedSirens(v,false)
                                SetVehicleDoorsLocked(v,1)
                                SetBlockingOfNonTemporaryEvents(ped,true)
                                TaskVehicleDriveToCoordLongrange(ped,v,jail.x,jail.y,jail.z,24.0,786603,8.0)
                                u.state='transport_to_jail'
                                u.lastTask=GetGameTimer()
                            end

                        else
                            -- Si el sospechoso salió accidentalmente, vuelve a asegurarlo
                            -- en el asiento y continúa el traslado.
                            if IsPedInAnyVehicle(target,false) then
                                SetPedIntoVehicle(target,v,2)
                            else
                                SetPedIntoVehicle(target,v,2)
                            end
                        end
                    end

                elseif u.order=='suspect_action' then
                    if unitTargetAlive(target) then
                        local d=#(GetEntityCoords(ped)-GetEntityCoords(target))
                        local actuallyInVehicle = IsPedInAnyVehicle(ped,false)
                        if actuallyInVehicle and d>7.0 then
                            local tc=GetEntityCoords(target)
                            if u.state~='suspect_drive' or now-(u.lastTask or 0)>5000 then
                                refreshVehicleDrive(u,tc,18.0); u.state='suspect_drive'
                            end
                        elseif actuallyInVehicle and d<=7.0 and not u.actionDone then
                            local currentVeh=GetVehiclePedIsIn(ped,false)
                            TaskVehicleTempAction(ped,currentVeh,27,1800)
                            SetVehicleSiren(currentVeh,false); SetVehicleHasMutedSirens(currentVeh,true)
                            TaskLeaveVehicle(ped,currentVeh,256); u.state='approach_target'; u.lastTask=now
                            -- Guardamos la patrulla aunque el agente ya esté a pie.
                            -- Las órdenes posteriores (por ejemplo Meter en vehículo)
                            -- deben reutilizar esta misma patrulla.
                            u.vehicle=currentVeh
                        elseif d>3.0 and not actuallyInVehicle then
                            if u.state~='approach_target' or now-(u.lastTask or 0)>2500 then
                                TaskGoToEntity(ped,target,-1,2.0,2.0,1073741824,0)
                                u.state='approach_target'; u.lastTask=now
                            end
                        elseif not u.actionDone then
                            -- Arrest/detain gets a dedicated non-combat AI path.
                            -- Never use TaskCombatPed for a civilian suspect.
                            if u.action=='detain' and not IsPedAPlayer(target) then
                                SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true)
                                SetPedCanSwitchWeapon(ped,false)
                                SetPedCombatAttributes(ped,46,false)
                                SetPedAsEnemy(target,false)
                                FreezeEntityPosition(target,true)
                                ClearPedTasks(target)
                                TaskHandsUp(target,5000,ped,true,true)
                                Wait(1200)
                                SetEnableHandcuffs(target,true)
                                TaskPlayAnim(target,'mp_arresting','idle',8.0,-8.0,-1,49,0,false,false,false)
                                TaskPlayAnim(ped,'mp_arresting','a_uncuff',8.0,-8.0,1800,48,0,false,false,false)
                                Wait(1800)
                                u.actionDone=true
                                notifyPoliceMenu('Agente llegó, detuvo y esposó al NPC.')
                            elseif IsPedAPlayer(target) then
                                ClearPedTasks(ped)
                                TaskTurnPedToFaceEntity(ped,target,800)
                                local playerIdx=NetworkGetPlayerIndexFromPed(target)
                                if playerIdx~=-1 then
                                    local sid=GetPlayerServerId(playerIdx)
                                    if u.action=='requestId' or u.action=='search' or u.action=='vehicleSearch' then
                                        TriggerServerEvent('qb-aipolice:server:policeSuspectInspect',u.action,tostring(sid))
                                    elseif u.action=='placeCar' then
                                        local useVeh=u.vehicle or veh
                                        if useVeh~=0 and DoesEntityExist(useVeh) then
                                            TriggerServerEvent('qb-aipolice:server:policeSuspectPlacePlayer',tostring(sid),NetworkGetNetworkIdFromEntity(useVeh))
                                        end
                                    elseif u.action=='jail' then
                                        TriggerServerEvent('qb-aipolice:server:policeSuspectJail',tostring(sid))
                                    elseif u.action=='detain' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','cuff',tostring(sid))
                                    elseif u.action=='uncuff' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','uncuff',tostring(sid))
                                    elseif u.action=='wrist' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','wrist',tostring(sid))
                                    elseif u.action=='face' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','face',tostring(sid))
                                    elseif u.action=='follow' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','follow',tostring(sid))
                                    elseif u.action=='releaseDrive' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','releaseDrive',tostring(sid))
                                    elseif u.action=='releaseWalk' then
                                        TriggerServerEvent('qb-aipolice:server:policeTargetState','releaseWalk',tostring(sid))
                                    end
                                end
                                u.actionDone=true
                                notifyPoliceMenu(('Orden ejecutada sobre el jugador: %s.'):format(u.action))
                            else
                                local token=u.actionToken
                                local done=executeNpcSuspectAction(u.action,target,ped,u.vehicle or veh,token,u)
                                if u.actionToken==token then u.actionDone=done end
                            end
                        end
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('qb-aipolice:client:policeSuspectInspect',function(action,targetId)
    local target=manualNearestTarget(targetId)
    if not target or not IsPedAPlayer(target) then
        notifyPoliceMenu('No se encontró el jugador objetivo para el registro.')
        return
    end
    local idx=NetworkGetPlayerIndexFromPed(target)
    if idx==-1 then
        notifyPoliceMenu('No se pudo obtener el jugador objetivo.')
        return
    end
    local sid=GetPlayerServerId(idx)
    TriggerServerEvent('qb-aipolice:server:policeSuspectInspect',action,tostring(sid))
end)

RegisterNetEvent('qb-aipolice:client:policeSuspectInfo',function(message)
    notifyPoliceMenu(message)
end)

local function startTransportToJail(targetId)
    local target=manualNearestTarget(targetId)
    if not target then
        DebugPrint(('TRANSPORT fallo: target no encontrado %s'):format(tostring(targetId)))
        notifyPoliceMenu('No se encontró el sospechoso para iniciar el traslado.')
        return false
    end
    local existing=getManualUnitForTarget(target,'transport') or getManualUnitForTarget(target)
    local officer=existing
    if not officer then
        local driver,veh=spawnManualUnit('backup',target,nil,true)
        officer=getManualUnitForTarget(target)
        if not officer and driver then officer={entity=driver,target=target,vehicle=veh} end
    end
    if not officer or not officer.entity or not DoesEntityExist(officer.entity) then
        DebugPrint('TRANSPORT fallo: no se pudo crear/reutilizar guardia')
        notifyPoliceMenu('No se pudo crear la unidad de transporte.')
        return false
    end
    officer.order='transport'
    officer.target=target
    officer.actionDone=false
    officer.state='transport_chase'
    officer.lastTask=0
    officer.vehicle=unitVehicle(officer.entity)
    ClearPedTasks(officer.entity)
    SetBlockingOfNonTemporaryEvents(officer.entity,true)
    if not IsPedAPlayer(target) then
        holdNpcTarget(target)
    else
        SetPedAsEnemy(target,true)
        SetBlockingOfNonTemporaryEvents(target,false)
    end
    DebugPrint(('TRANSPORT iniciado target=%s player=%s officer=%s veh=%s'):format(tostring(targetId),tostring(IsPedAPlayer(target)),tostring(officer.entity),tostring(officer.vehicle)))
    notifyPoliceMenu('Traslado iniciado: el agente detendrá al sospechoso, lo montará y conducirá hasta la cárcel.')
    return true
end

RegisterNetEvent('qb-aipolice:client:policeSuspectTransportTarget',function(targetId)
    startTransportToJail(targetId)
end)

RegisterNetEvent('qb-aipolice:client:policeSuspectAction',function(action,targetId)
    DebugPrint(('MENU action=%s target=%s'):format(tostring(action),tostring(targetId)))
    local target=manualNearestTarget(targetId)
    if not target then notifyPoliceMenu('No se encontró el sospechoso seleccionado.'); return end

    -- Los jugadores reales se procesan por servidor y el propio jugador objetivo
    -- recibe los estados (esposar, muñecas, seguir, mirar, etc.).
    if IsPedAPlayer(target) then
        local idx=NetworkGetPlayerIndexFromPed(target)
        local sid=idx~=-1 and GetPlayerServerId(idx) or nil
        if not sid then notifyPoliceMenu('No se pudo obtener el ID del jugador objetivo.'); return end
        if action=='requestId' or action=='search' or action=='vehicleSearch' then
            TriggerServerEvent('qb-aipolice:server:policeSuspectInspect',action,tostring(sid))
            notifyPoliceMenu(action=='requestId' and 'Solicitando identificación...' or 'Realizando registro...')
            return
        end
        if action=='detain' then TriggerServerEvent('qb-aipolice:server:policeTargetState','cuff',tostring(sid))
        elseif action=='uncuff' then TriggerServerEvent('qb-aipolice:server:policeTargetState','uncuff',tostring(sid))
        elseif action=='wrist' then TriggerServerEvent('qb-aipolice:server:policeTargetState','wrist',tostring(sid))
        elseif action=='face' then TriggerServerEvent('qb-aipolice:server:policeTargetState','face',tostring(sid))
        elseif action=='follow' then TriggerServerEvent('qb-aipolice:server:policeTargetState','follow',tostring(sid))
        elseif action=='releaseDrive' then TriggerServerEvent('qb-aipolice:server:policeTargetState','releaseDrive',tostring(sid))
        elseif action=='releaseWalk' then TriggerServerEvent('qb-aipolice:server:policeTargetState','releaseWalk',tostring(sid))
        elseif action=='jail' then
            startTransportToJail(tostring(sid))
            return
        elseif action=='placeCar' then
            local officer=getManualUnitForTarget(target)
            local veh=officer and unitVehicle(officer.entity) or 0
            if veh and veh~=0 then
                TriggerServerEvent('qb-aipolice:server:policeSuspectPlacePlayer',tostring(sid),NetworkGetNetworkIdFromEntity(veh))
            else
                local _,v=spawnManualUnit('backup',target,nil,false)
                if v and v~=0 then
                    TriggerServerEvent('qb-aipolice:server:policeSuspectPlacePlayer',tostring(sid),NetworkGetNetworkIdFromEntity(v))
                else
                    notifyPoliceMenu('No se pudo preparar el vehículo policial.')
                    return
                end
            end
        end
        notifyPoliceMenu(('Orden ejecutada sobre jugador ID %s: %s'):format(sid,action))
        return
    end

    -- NPC: una unidad AI se crea y el controlador manual ejecuta la interacción
    -- cuando llega al objetivo. No se usa combate ni se sustituye por el policía.
    local existing=getManualUnitForTarget(target)
    local officer=existing
    if not officer then
        local driver,veh=spawnManualUnit('backup',target,nil,false)
        officer=getManualUnitForTarget(target)
        if not officer and driver then officer={entity=driver,target=target,vehicle=veh} end
    end
    if not officer then notifyPoliceMenu('No se pudo enviar un agente al NPC.'); return end
    -- Reutiliza la unidad existente, pero SIEMPRE reinicia por completo su
    -- estado de la orden anterior. Antes de este reset, después de la primera
    -- orden la unidad podía quedarse con una tarea/estado anterior y las
    -- siguientes órdenes parecían no hacer nada.
    officer.action=action
    officer.order='suspect_action'
    DebugPrint(('MENU NPC unidad asignada action=%s officer=%s vehicle_saved=%s'):format(tostring(action),tostring(officer.entity),tostring(officer.vehicle)))
    officer.target=target
    officer.actionDone=false
    officer.lastTask=0
    officer.state='suspect_drive'
    -- IMPORTANTE: después de DETENER al NPC, el agente ya está a pie.
    -- No debemos perder la referencia de la patrulla original, porque
    -- PLACE CAR se ejecuta después y necesita exactamente ese vehículo.
    local savedVehicle=officer.vehicle
    local liveVehicle=unitVehicle(officer.entity)
    if liveVehicle~=0 and DoesEntityExist(liveVehicle) then
        officer.vehicle=liveVehicle
    elseif savedVehicle and savedVehicle~=0 and DoesEntityExist(savedVehicle) then
        officer.vehicle=savedVehicle
    else
        officer.vehicle=0
    end
    ClearPedTasks(officer.entity)
    SetBlockingOfNonTemporaryEvents(officer.entity,true)

    -- El objetivo tageado con el ojo usa TaskStandStill, no un freeze duro.
    -- Limpiamos esa tarea al comenzar una orden para que la nueva Task pueda
    -- ejecutarse inmediatamente. Detener/muñecas vuelven a inmovilizarlo.
    if not IsPedAPlayer(target) then
        holdNpcTarget(target)
    end

    -- Si el agente ya está junto al NPC, ejecuta la nueva orden inmediatamente
    -- en vez de obligarlo a pasar otra vez por el viaje en vehículo.
    local officerDist=#(GetEntityCoords(officer.entity)-GetEntityCoords(target))
    if officerDist<=3.2 and officer.vehicle==0 then
        local token=officer.actionToken
        local done=executeNpcSuspectAction(action,target,officer.entity,0,token,officer)
        if officer.actionToken==token then officer.actionDone=done end
        if officer.actionDone then
            notifyPoliceMenu(('Orden ejecutada sobre NPC: %s'):format(action))
            return
        end
    end

    notifyPoliceMenu(('Unidad enviada para: %s'):format(action))
end)

RegisterNetEvent('qb-aipolice:client:policeMenuOrder',function(order,data)
    if manualDispatchBusy then notifyPoliceMenu('Despacho ocupado. Espera unos segundos.'); return end
    manualDispatchBusy=true
    data=data or {}
    local count=math.max(1,math.min(tonumber(data.units) or 1,Config.PoliceMenu.maxDispatchUnits))
    local target=manualNearestTarget(data.targetId)
    local origin=GetEntityCoords(PlayerPedId())
    local made=0

    if order=='clearUnits' then
        for _,u in ipairs(manualDispatch) do if u.entity and DoesEntityExist(u.entity) then SetEntityAsMissionEntity(u.entity,true,true); DeleteEntity(u.entity) end end
        manualDispatch={}
        clearUnits()
        notifyPoliceMenu('Todas las unidades AI activas fueron retiradas.')

    elseif order=='backup' then
        made=spawnManualUnits('backup',count,nil,origin,false)
        notifyPoliceMenu(('Enviando %d unidad(es) de respaldo a tu ubicación.'):format(made))

    elseif order=='investigate' then
        made=spawnManualUnits('investigate',count,nil,origin,false)
        notifyPoliceMenu(('Enviando %d unidad(es) para investigar la zona.'):format(made))

    elseif order=='patrol' then
        made=spawnManualUnits('patrol',count,nil,origin,false)
        notifyPoliceMenu(('Patrulla enviada: %d unidad(es).'):format(made))

    elseif order=='trafficStop' then
        if not target then
            notifyPoliceMenu('No hay un jugador/NPC objetivo seleccionado.')
        else
            -- Parada de tráfico real: si el objetivo ya va en un vehículo,
            -- primero ordenamos que detenga ese vehículo. Para NPC lo hacemos
            -- localmente; para jugadores se envía la orden a su cliente.
            local targetVeh=GetVehiclePedIsIn(target,false)
            if targetVeh~=0 and DoesEntityExist(targetVeh) then
                if IsPedAPlayer(target) then
                    local idx=NetworkGetPlayerIndexFromPed(target)
                    if idx~=-1 then
                        TriggerServerEvent('qb-aipolice:server:trafficStopTarget',GetPlayerServerId(idx))
                    end
                else
                    ClearPedTasks(target)
                    SetBlockingOfNonTemporaryEvents(target,true)
                    SetPedAsEnemy(target,false)
                    TaskVehicleTempAction(target,targetVeh,27,5000)
                    SetVehicleForwardSpeed(targetVeh,0.0)
                    SetVehicleHandbrake(targetVeh,true)
                end
            end
            made=spawnManualUnits('traffic',1,target,nil,false)
            notifyPoliceMenu(made>0 and 'Unidad enviada para detener al vehículo y realizar la parada.' or 'No se pudo crear la unidad.')
        end

    elseif order=='pursuit' then
        if not target then
            notifyPoliceMenu('No hay un jugador/NPC objetivo cercano seleccionado.')
        else
            -- La persecución es una de las pocas órdenes que explícitamente
            -- permite que el NPC se vaya. Todas las demás órdenes mantienen al
            -- objetivo retenido hasta que la propia orden necesite moverlo.
            if not IsPedAPlayer(target) then
                releaseNpcTargetForOrder(target)
                SetPedAsEnemy(target,true)
                SetBlockingOfNonTemporaryEvents(target,false)
                TaskSmartFleePed(target,PlayerPedId(),250.0,-1,false,false)
            end
            made=spawnManualUnits('pursuit',count,target,nil,true)
            notifyPoliceMenu(('Persecución iniciada con %d unidad(es).'):format(made))
        end

    elseif order=='spikes' then
        notifyPoliceMenu(manualDeploySpikesAt(target) and 'Pinchos desplegados en la ubicación del objetivo.' or 'No se pudieron desplegar los pinchos.')

    elseif order=='roadblock' then
        made=spawnManualUnits('backup',math.min(count,2),nil,target and GetEntityCoords(target) or origin,false)
        manualRoadblockAt(target)
        notifyPoliceMenu(('Bloqueo desplegado con %d unidad(es) de apoyo.'):format(made))

    elseif order=='tactical' then
        made=spawnManualUnits('tactical',math.min(count,Config.PoliceMenu.maxDispatchUnits),target,nil,target~=nil)
        notifyPoliceMenu(('Unidad táctica enviada: %d agente(s).'):format(made))

    elseif order=='helicopter' then
        local p=target or PlayerPedId()
        local c=GetEntityCoords(p)+vector3(0,0,55)
        local h=loadModel(Config.AirSupport.heliModel)
        if h then
            local heli=CreateVehicle(h,c.x,c.y,c.z,GetEntityHeading(p),true,true); SetModelAsNoLongerNeeded(h)
            if DoesEntityExist(heli) then
                addManualUnit(heli,'manual_heli',target,'helicopter')
                local pilot=spawnOfficer(Config.TacticalOfficerModel,{'WEAPON_CARBINERIFLE'},65,100,9,c,GetEntityHeading(p))
                if pilot then
                    addManualUnit(pilot,'manual_heli_pilot',target,'helicopter'); SetPedIntoVehicle(pilot,heli,-1)
                    if target then TaskHeliChase(pilot,target,25.0) else TaskHeliMission(pilot,heli,0,0,c.x,c.y,c.z,23,30.0,10.0,GetEntityHeading(p),80.0,40.0) end
                    notifyPoliceMenu('Apoyo aéreo enviado.')
                end
            end
        end

    elseif order=='military' then
        made=spawnManualUnits('military',math.min(count,Config.PoliceMenu.maxDispatchUnits),target,nil,target~=nil)
        notifyPoliceMenu(('Respuesta militar enviada: %d unidad(es).'):format(made))

    elseif order=='transport' then
        if not target then
            notifyPoliceMenu('No hay un jugador/NPC objetivo cercano seleccionado.')
        else
            made=spawnManualUnits('pursuit',1,target,nil,true)
            if made>0 then
                for _,u in ipairs(manualDispatch) do if u.target==target and u.role=='pursuit' then u.order='transport' end end
                -- La unidad recibe la orden de persecución; cuando el objetivo
                -- es NPC, además queda marcado como sospechoso para que el
                -- agente pueda reducirlo/detenerlo sin necesitar un jugador real.
                if not IsPedAPlayer(target) then
                    holdNpcTarget(target)
                else
                    SetPedAsEnemy(target,true)
                    SetBlockingOfNonTemporaryEvents(target,false)
                end
                notifyPoliceMenu('Unidad de transporte enviada para detener y procesar al objetivo.')
            else
                notifyPoliceMenu('No se pudo crear la unidad.')
            end
        end
    end

    Wait(400)
    manualDispatchBusy=false
end)
