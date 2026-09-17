-- Eye targeting integration (ox_target).
-- This is an additional way to select the exact NPC/player before opening the NUI.
-- Existing F6 behavior is intentionally left intact as a fallback.

local eyeTarget = nil
local eyeFrozenNpc = nil
local eyeOptionsAdded = false

local function releaseEyeFrozenNpc()
    if eyeFrozenNpc and DoesEntityExist(eyeFrozenNpc) and not IsPedAPlayer(eyeFrozenNpc) then
        FreezeEntityPosition(eyeFrozenNpc, false)
        SetBlockingOfNonTemporaryEvents(eyeFrozenNpc, false)
        SetPedCanSwitchWeapon(eyeFrozenNpc, true)
        ClearPedTasks(eyeFrozenNpc)
    end
    eyeFrozenNpc = nil
end

local function freezeEyeNpc(entity)
    releaseEyeFrozenNpc()
    if entity and DoesEntityExist(entity) and not IsPedAPlayer(entity) and not IsEntityDead(entity) then
        eyeFrozenNpc = entity
        SetPedAsEnemy(entity, false)
        SetBlockingOfNonTemporaryEvents(entity, true)
        ClearPedTasksImmediately(entity)
        SetCurrentPedWeapon(entity, joaat('WEAPON_UNARMED'), true)
        SetPedCanSwitchWeapon(entity, false)
        -- El NPC queda físicamente retenido mientras está tageado.
        -- Las órdenes de movimiento lo liberan temporalmente y luego lo vuelven
        -- a asegurar cuando corresponde.
        FreezeEntityPosition(entity, true)
        TaskStandStill(entity, -1)
    end
end

local function targetIsValid(entity, allowPlayers)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if IsEntityDead(entity) then return false end
    if not IsPedHuman(entity) then return false end
    if entity == PlayerPedId() then return false end
    if allowPlayers then
        return true
    end
    return not IsPedAPlayer(entity)
end

local function describeTarget(entity)
    if not targetIsValid(entity, true) then return nil end

    local me = PlayerPedId()
    local distance = #(GetEntityCoords(me) - GetEntityCoords(entity))

    if IsPedAPlayer(entity) then
        local player = NetworkGetPlayerIndexFromPed(entity)
        if player == -1 then return nil end
        local sid = GetPlayerServerId(player)
        if not sid then return nil end
        return {
            id = tostring(sid),
            name = GetPlayerName(player) or ('ID '..tostring(sid)),
            distance = distance,
            kind = 'player'
        }
    end

    return {
        id = 'npc:'..tostring(entity),
        name = 'NPC seleccionado',
        distance = distance,
        kind = 'npc'
    }
end

local function openMenuForEyeTarget(entity)
    local target = describeTarget(entity)
    if not target then return end

    eyeTarget = entity
    -- Una vez seleccionado con el ojo, el NPC queda quieto y reservado para
    -- este menú. Las órdenes posteriores decidirán cuándo volver a liberarlo.
    freezeEyeNpc(entity)

    -- The server still performs the normal police/on-duty validation.
    -- This only replaces the old "find the nearest person" step with the exact
    -- entity selected by the eye.
    TriggerServerEvent('qb-aipolice:server:requestPoliceMenu')
end

RegisterNetEvent('qb-aipolice:client:openPoliceMenuFromTarget', function(entity)
    openMenuForEyeTarget(entity)
end)

local function sendEyeTargetToNui()
    if not eyeTarget or not DoesEntityExist(eyeTarget) or IsEntityDead(eyeTarget) then
        eyeTarget = nil
        return
    end

    local target = describeTarget(eyeTarget)
    if not target then
        eyeTarget = nil
        return
    end

    SendNUIMessage({
        action = 'policeTargets',
        targets = { target }
    })
end

RegisterNetEvent('qb-aipolice:client:openPoliceMenu', function()
    -- ui.lua also listens for this event and opens the NUI.
    -- Send the exact eye-selected target after the NUI receives its open message.
    CreateThread(function()
        Wait(50)
        if eyeTarget then
            sendEyeTargetToNui()
        end
    end)
end)

local function addEyeOptions()
    if eyeOptionsAdded then return true end
    if GetResourceState('ox_target') ~= 'started' then return false end

    exports.ox_target:addGlobalPed({
        {
            name = 'qb-aipolice_eye_npc',
            icon = 'fa-solid fa-eye',
            label = 'Abrir AI Police',
            distance = 3.0,
            canInteract = function(entity)
                return targetIsValid(entity, false)
            end,
            onSelect = function(data)
                openMenuForEyeTarget(data.entity)
            end
        }
    })

    exports.ox_target:addGlobalPlayer({
        {
            name = 'qb-aipolice_eye_player',
            icon = 'fa-solid fa-eye',
            label = 'Abrir AI Police',
            distance = 3.0,
            canInteract = function(entity)
                return targetIsValid(entity, true)
            end,
            onSelect = function(data)
                openMenuForEyeTarget(data.entity)
            end
        }
    })

    -- VEHÍCULOS: al apuntar con el ojo a un auto, ox_target entrega el vehículo,
    -- no el ped. Convertimos ese vehículo en su ocupante para que el menú pueda
    -- detener a NPCs y jugadores que estén conduciendo.
    exports.ox_target:addGlobalVehicle({
        {
            name = 'qb-aipolice_eye_vehicle',
            icon = 'fa-solid fa-car-side',
            label = 'Abrir AI Police — conductor',
            distance = 4.0,
            canInteract = function(vehicle)
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
                local driver = GetPedInVehicleSeat(vehicle, -1)
                return targetIsValid(driver, true)
            end,
            onSelect = function(data)
                local vehicle = data.entity
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
                local driver = GetPedInVehicleSeat(vehicle, -1)
                if targetIsValid(driver, true) then
                    openMenuForEyeTarget(driver)
                end
            end
        }
    })

    eyeOptionsAdded = true
    return true
end

CreateThread(function()
    while not addEyeOptions() do
        Wait(1000)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_target' then
        CreateThread(function()
            Wait(500)
            addEyeOptions()
        end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('ox_target') == 'started' and eyeOptionsAdded then
        pcall(function()
            exports.ox_target:removeGlobalPed('qb-aipolice_eye_npc')
        end)
        pcall(function()
            exports.ox_target:removeGlobalPlayer('qb-aipolice_eye_player')
        end)
        pcall(function()
            exports.ox_target:removeGlobalVehicle('qb-aipolice_eye_vehicle')
        end)
    end
end)

-- When the menu is closed, keep the selected entity only as long as it exists.
RegisterNetEvent('qb-aipolice:client:closePoliceMenu', function()
    -- Cerrar F6 NO libera al NPC seleccionado: queda reservado/quieto hasta
    -- que una orden (seguir, liberar, desesposar, meter al coche, etc.) lo libere.
    if eyeTarget and (not DoesEntityExist(eyeTarget) or IsEntityDead(eyeTarget)) then
        eyeTarget = nil
        releaseEyeFrozenNpc()
    end
end)

CreateThread(function()
    while true do
        Wait(350)
        if eyeFrozenNpc and DoesEntityExist(eyeFrozenNpc) and not IsEntityDead(eyeFrozenNpc) then
            -- El tag mantiene al NPC físicamente quieto mientras no esté dentro
            -- de un vehículo. Las órdenes que necesitan moverlo lo descongelan
            -- desde police.lua; al terminar, las órdenes de retención lo vuelven
            -- a asegurar.
            if not IsPedInAnyVehicle(eyeFrozenNpc,false) and IsEntityPositionFrozen(eyeFrozenNpc) then
                SetBlockingOfNonTemporaryEvents(eyeFrozenNpc,true)
                SetPedAsEnemy(eyeFrozenNpc,false)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        releaseEyeFrozenNpc()
    end
end)
