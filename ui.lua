RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)


local frozenNpcTarget = nil

local function freezeSelectedNpc(ped)
    if frozenNpcTarget and DoesEntityExist(frozenNpcTarget) and not IsPedAPlayer(frozenNpcTarget) then
        FreezeEntityPosition(frozenNpcTarget,false)
        SetBlockingOfNonTemporaryEvents(frozenNpcTarget,false)
        SetPedCanSwitchWeapon(frozenNpcTarget,true)
    end
    frozenNpcTarget=nil
    if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsEntityDead(ped) then
        frozenNpcTarget=ped
        SetBlockingOfNonTemporaryEvents(ped,true)
        ClearPedTasksImmediately(ped)
        FreezeEntityPosition(ped,true)
        SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true)
        SetPedCanSwitchWeapon(ped,false)
    end
end

local function releaseFrozenNpc()
    if frozenNpcTarget and DoesEntityExist(frozenNpcTarget) and not IsPedAPlayer(frozenNpcTarget) then
        FreezeEntityPosition(frozenNpcTarget,false)
        SetBlockingOfNonTemporaryEvents(frozenNpcTarget,false)
        SetPedCanSwitchWeapon(frozenNpcTarget,true)
        ClearPedTasks(frozenNpcTarget)
    end
    frozenNpcTarget=nil
end

local policeMenuOpen = false

local function closePoliceMenu()
    releaseFrozenNpc()
    policeMenuOpen = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePoliceMenu' })
end



-- Prevent GTA controls from leaking through the police NUI.
-- SetNuiFocusKeepInput(true) is intentional so the camera/world remains visible,
-- but combat/melee/weapon/vehicle controls are disabled until the menu closes.
CreateThread(function()
    while true do
        if policeMenuOpen then
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)   -- INPUT_ATTACK
            DisableControlAction(0, 25, true)   -- INPUT_AIM
            DisableControlAction(0, 45, true)   -- INPUT_RELOAD
            DisableControlAction(0, 47, true)   -- INPUT_DETONATE
            DisableControlAction(0, 58, true)   -- INPUT_THROW_GRENADE
            DisableControlAction(0, 69, true)   -- VEH_ATTACK
            DisableControlAction(0, 70, true)   -- VEH_ATTACK2
            DisableControlAction(0, 91, true)   -- VEH_PASSENGER_AIM
            DisableControlAction(0, 92, true)   -- VEH_PASSENGER_ATTACK
            DisableControlAction(0, 140, true)  -- MELEE_LIGHT
            DisableControlAction(0, 141, true)  -- MELEE_HEAVY
            DisableControlAction(0, 142, true)  -- MELEE_ALTERNATE
            DisableControlAction(0, 143, true)  -- MELEE_BLOCK
            DisableControlAction(0, 257, true)  -- ATTACK2
            DisableControlAction(0, 263, true)  -- MELEE_ATTACK1
            DisableControlAction(0, 264, true)  -- MELEE_ATTACK2
            DisableControlAction(0, 37, true)   -- WEAPON_WHEEL
            DisableControlAction(0, 68, true)   -- VEH_AIM
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)
        else
            Wait(150)
        end
    end
end)

RegisterCommand(Config.PoliceMenu.command, function()
    if not Config.PoliceMenu.enabled then return end
    if policeMenuOpen then
        closePoliceMenu()
        return
    end
    TriggerServerEvent('qb-aipolice:server:requestPoliceMenu')
end, false)

RegisterKeyMapping(Config.PoliceMenu.command, 'Abrir menú de despacho AI Police', 'keyboard', Config.PoliceMenu.key)

RegisterNetEvent('qb-aipolice:client:openPoliceMenu', function()
    policeMenuOpen = true
    -- El primer refresco se fuerza al abrir para que F6 no dependa de un tick anterior.
    -- The NUI keeps keyboard/mouse input for the menu, but GTA combat controls
    -- must never leak through while the menu is open. Otherwise a click on a
    -- menu button can also punch/shoot the nearby target.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({
        action = 'openPoliceMenu',
        maxUnits = Config.PoliceMenu.maxDispatchUnits,
        orders = Config.PoliceMenu.orders
    })
end)

RegisterNetEvent('qb-aipolice:client:policeMenuDenied', function()
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('~r~AI Police:~s~ Debes ser policía y estar de turno para usar el despacho.')
    EndTextCommandThefeedPostTicker(false, false)
end)

RegisterNUICallback('policeMenuClose', function(_, cb)
    closePoliceMenu()
    cb('ok')
end)

RegisterNUICallback('policeMenuOrder', function(data, cb)
    if type(data) ~= 'table' or not data.order then cb('ok') return end
    TriggerServerEvent('qb-aipolice:server:policeMenuOrder', data.order, data)
    cb('ok')
end)

RegisterNUICallback('policeSuspectAction', function(data, cb)
    if type(data) ~= 'table' or not data.action or not data.targetId or tostring(data.targetId)=='' then
        print('[qb-aipolice DEBUG][NUI] policeSuspectAction invalida')
        cb('ok')
        return
    end
    print(('[qb-aipolice DEBUG][NUI] action=%s target=%s'):format(tostring(data.action), tostring(data.targetId)))
    TriggerServerEvent('qb-aipolice:server:policeSuspectAction', tostring(data.action), tostring(data.targetId))
    cb('ok')
end)

RegisterNUICallback('policeMenuSetUnits', function(data, cb)
    local n = math.floor(tonumber(data and data.units) or 1)
    n = math.max(1, math.min(Config.PoliceMenu.maxDispatchUnits, n))
    SendNUIMessage({ action = 'setDispatchUnits', units = n })
    cb('ok')
end)

RegisterNetEvent('qb-aipolice:client:policeMenuOrderResult', function(message)
    SendNUIMessage({ action = 'policeMenuStatus', message = tostring(message or '') })
end)

RegisterNetEvent('qb-aipolice:client:closePoliceMenu', closePoliceMenu)

local function isPolicePed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return true end
    local rel = GetPedRelationshipGroupHash(ped)
    local model = GetEntityModel(ped)
    return rel == joaat('COP') or rel == joaat('SECURITY_GUARD')
        or model == joaat('s_m_y_cop_01') or model == joaat('s_f_y_cop_01')
        or model == joaat('s_m_y_swat_01') or model == joaat('s_m_y_marine_01')
        or model == joaat('s_m_y_ranger_01')
end

local function getPeopleNearby(maxDistance)
    local me = PlayerPedId()
    local maxDist = maxDistance or 20.0
    local mePos = GetEntityCoords(me)
    local people = {}

    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and DoesEntityExist(ped) and not IsEntityDead(ped)
        and IsPedHuman(ped) and not isPolicePed(ped) then
            local d = #(mePos - GetEntityCoords(ped))
            if d <= maxDist then
                people[#people+1] = { ped = ped, distance = d, kind = 'npc' }
            end
        end
    end

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped)
        and not isPolicePed(ped) then
            local d = #(mePos - GetEntityCoords(ped))
            if d <= maxDist then
                people[#people+1] = { ped = ped, distance = d, kind = 'player', player = player }
            end
        end
    end

    table.sort(people, function(a,b) return a.distance < b.distance end)
    return people
end

-- Mantiene una función compatible para cualquier código antiguo que todavía
-- necesite obtener solamente la persona más cercana.
local function getPersonInFront(maxDistance)
    local people = getPeopleNearby(maxDistance)
    if people[1] then return people[1].ped, people[1].distance end
    return nil, nil
end

-- El selector muestra las personas cercanas para que el oficial pueda escoger
-- manualmente un NPC o jugador. Ya no depende de que el NPC esté exactamente
-- delante de la cámara en el momento del refresco.
local function sendNearbyPoliceTargets()
    if not policeMenuOpen then return end
    local people = getPeopleNearby(20.0)
    local targets = {}

    for i, entry in ipairs(people) do
        if i > 15 then break end
        if entry.kind == 'player' then
            local sid = GetPlayerServerId(entry.player)
            targets[#targets+1] = {
                id = tostring(sid),
                name = GetPlayerName(entry.player) or ('ID '..sid),
                distance = entry.distance,
                kind = 'player'
            }
        else
            targets[#targets+1] = {
                id = 'npc:'..tostring(entry.ped),
                name = 'NPC cercano # '..tostring(i),
                distance = entry.distance,
                kind = 'npc'
            }
        end
    end

    SendNUIMessage({action='policeTargets',targets=targets})
end


CreateThread(function()
    while true do
        Wait(500)
        if policeMenuOpen then
            sendNearbyPoliceTargets()
            -- Do not freeze the selected target while the NUI is open. The target
            -- must remain able to react to arrest/escort/vehicle orders.
            if frozenNpcTarget then releaseFrozenNpc() end
        end
    end
end)

RegisterCommand('policemenu', function()
    if not Config.PoliceMenu.enabled then return end
    if policeMenuOpen then closePoliceMenu() else TriggerServerEvent('qb-aipolice:server:requestPoliceMenu') end
end, false)
RegisterKeyMapping('policemenu', 'Abrir menú AI Police (alternativo)', 'keyboard', 'F7')
