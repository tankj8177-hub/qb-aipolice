local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'qb-aipolice.admin')
end

-- ============================================================
--  COMANDOS DE JUGADOR
-- ============================================================
RegisterCommand('aipstatus', function(source)
    local src = source
    local state = GetWantedState(src)
    local stars = state and state.stars or 0
    TriggerClientEvent('chat:addMessage', src, {
        args = { 'AI Police', ('Nivel de búsqueda actual: %d estrella(s)'):format(stars) }
    })
end, false)

RegisterCommand('myaiprecord', function(source)
    local src = source
    local citizenid = exports['qb-aipolice']:GetCitizenId(src)
    Storage.GetRecord(citizenid, function(record)
        local crimeCount = #record.crimes
        local jailCount = #record.jail_history
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'Historial', ('Crímenes: %d | Multas pendientes: $%d | Veces encarcelado: %d')
                :format(crimeCount, record.fines, jailCount) }
        })
    end)
end, false)

RegisterCommand('payaipbill', function(source)
    local src = source
    local citizenid = exports['qb-aipolice']:GetCitizenId(src)
    Storage.GetRecord(citizenid, function(record)
        if record.fines <= 0 then
            TriggerClientEvent('chat:addMessage', src, { args = { 'AI Police', 'No tienes multas pendientes.' } })
            return
        end
        -- Aquí se debe conectar a tu sistema económico (framework) para cobrar realmente.
        -- Se deja como evento para que lo conectes a tu banco/economy:
        TriggerEvent('qb-aipolice:server:chargePlayer', src, record.fines, function(success)
            if success then
                record.fines = 0
                Storage.SaveRecord(citizenid, record)
                TriggerClientEvent('chat:addMessage', src, { args = { 'AI Police', 'Multa pagada correctamente.' } })
            else
                TriggerClientEvent('chat:addMessage', src, { args = { 'AI Police', 'No tienes fondos suficientes.' } })
            end
        end)
    end)
end, false)

RegisterCommand('payjail', function(source)
    local src = source
    TriggerEvent('qb-aipolice:server:payToLeaveJail', src)
end, false)

-- ============================================================
--  COMANDOS DE ADMIN
-- ============================================================
RegisterCommand('aiclearwanted', function(source, args)
    local src = source
    if src ~= 0 and not isAdmin(src) then return end
    local target = tonumber(args[1])
    if not target then return end
    ClearWanted(target)
    TriggerClientEvent('chat:addMessage', target, { args = { 'AI Police', 'Tu nivel de búsqueda ha sido eliminado por un administrador.' } })
end, true)

RegisterCommand('aipjail', function(source, args)
    local src = source
    if src ~= 0 and not isAdmin(src) then return end
    local target = tonumber(args[1])
    local minutes = tonumber(args[2]) or 5
    local reason = table.concat(args, ' ', 3) or 'Sin especificar'
    if not target then return end
    TriggerEvent('qb-aipolice:server:jailPlayer', target, minutes, reason)
end, true)

RegisterCommand('aipunjail', function(source, args)
    local src = source
    if src ~= 0 and not isAdmin(src) then return end
    local target = tonumber(args[1])
    if not target then return end
    TriggerEvent('qb-aipolice:server:unjailPlayer', target)
end, true)

RegisterCommand('unjailaip', function(source, args)
    ExecuteCommand(('aipunjail %s'):format(args[1] or ''))
end, true)
