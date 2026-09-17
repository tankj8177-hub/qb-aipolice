Storage = {}

local usingSQL = Utils.ResourceExists('oxmysql')
local jsonPath = 'data/records.json'
local cache = {}

-- ============================================================
--  Carga inicial
-- ============================================================
local function loadJson()
    local raw = LoadResourceFile(GetCurrentResourceName(), jsonPath)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and decoded then
            cache = decoded
            return
        end
    end
    cache = {}
end

local function saveJson()
    SaveResourceFile(GetCurrentResourceName(), jsonPath, json.encode(cache, { indent = true }), -1)
end

CreateThread(function()
    if usingSQL then
        exports.oxmysql:execute([[
            CREATE TABLE IF NOT EXISTS aipolice_records (
                citizenid VARCHAR(64) PRIMARY KEY,
                crimes LONGTEXT,
                warnings LONGTEXT,
                tickets LONGTEXT,
                warrants LONGTEXT,
                wanted_stars INT DEFAULT 0,
                fines INT DEFAULT 0,
                jail_history LONGTEXT,
                admin_actions LONGTEXT,
                jail_active INT DEFAULT 0,
                jail_end BIGINT DEFAULT 0,
                jail_reason LONGTEXT,
                updated_at BIGINT
            )
        ]], {})
        -- Compatibilidad segura con tablas creadas por versiones anteriores.
        -- Primero comprobamos qué columnas existen para NO ejecutar ALTER TABLE
        -- sobre columnas que ya están creadas (evita los errores Duplicate column name).
        exports.oxmysql:query([[
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'aipolice_records'
              AND COLUMN_NAME IN ('jail_active', 'jail_end', 'jail_reason')
        ]], {}, function(rows)
            local columns = {}
            for _, row in ipairs(rows or {}) do
                columns[row.COLUMN_NAME] = true
            end

            local missing = {}
            if not columns.jail_active then
                missing[#missing + 1] = 'ADD COLUMN jail_active INT DEFAULT 0'
            end
            if not columns.jail_end then
                missing[#missing + 1] = 'ADD COLUMN jail_end BIGINT DEFAULT 0'
            end
            if not columns.jail_reason then
                missing[#missing + 1] = 'ADD COLUMN jail_reason LONGTEXT'
            end

            if #missing > 0 then
                exports.oxmysql:execute('ALTER TABLE aipolice_records ' .. table.concat(missing, ', '), {}, function()
                    Utils.Log('Almacenamiento: columnas de prisión verificadas/actualizadas.')
                end)
            else
                Utils.Log('Almacenamiento: columnas de prisión ya existen; no se ejecutó ALTER TABLE.')
            end
        end)

        Utils.Log('Almacenamiento: oxmysql detectado, usando base de datos.')
    else
        loadJson()
        Utils.Log('Almacenamiento: oxmysql no encontrado, usando data/records.json')
    end
end)

-- ============================================================
--  Helpers internos
-- ============================================================
local function emptyRecord()
    return {
        crimes = {},
        warnings = {},
        tickets = {},
        warrants = {},
        wanted_stars = 0,
        fines = 0,
        jail_history = {},
        admin_actions = {},
        jail_active = 0,
        jail_end = 0,
        jail_reason = ''
    }
end

-- ============================================================
--  API pública
-- ============================================================
function Storage.GetRecord(citizenid, cb)
    if usingSQL then
        exports.oxmysql:single('SELECT * FROM aipolice_records WHERE citizenid = ?', { citizenid }, function(row)
            if not row then
                cb(emptyRecord())
                return
            end
            cb({
                crimes = json.decode(row.crimes or '[]'),
                warnings = json.decode(row.warnings or '[]'),
                tickets = json.decode(row.tickets or '[]'),
                warrants = json.decode(row.warrants or '[]'),
                wanted_stars = row.wanted_stars or 0,
                fines = row.fines or 0,
                jail_history = json.decode(row.jail_history or '[]'),
                admin_actions = json.decode(row.admin_actions or '[]'),
                jail_active = row.jail_active or 0,
                jail_end = row.jail_end or 0,
                jail_reason = row.jail_reason or ''
            })
        end)
    else
        if not cache[citizenid] then
            cache[citizenid] = emptyRecord()
        end
        cb(cache[citizenid])
    end
end

function Storage.SaveRecord(citizenid, record)
    if usingSQL then
        exports.oxmysql:execute([[
            INSERT INTO aipolice_records (citizenid, crimes, warnings, tickets, warrants, wanted_stars, fines, jail_history, admin_actions, jail_active, jail_end, jail_reason, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                crimes = VALUES(crimes), warnings = VALUES(warnings), tickets = VALUES(tickets),
                warrants = VALUES(warrants), wanted_stars = VALUES(wanted_stars), fines = VALUES(fines),
                jail_history = VALUES(jail_history), admin_actions = VALUES(admin_actions),
                jail_active = VALUES(jail_active), jail_end = VALUES(jail_end), jail_reason = VALUES(jail_reason),
                updated_at = VALUES(updated_at)
        ]], {
            citizenid,
            json.encode(record.crimes),
            json.encode(record.warnings),
            json.encode(record.tickets),
            json.encode(record.warrants),
            record.wanted_stars,
            record.fines,
            json.encode(record.jail_history),
            json.encode(record.admin_actions),
            record.jail_active or 0,
            record.jail_end or 0,
            record.jail_reason or '',
            os.time()
        })
    else
        cache[citizenid] = record
        saveJson()
    end
end

function Storage.AddCrime(citizenid, crimeType, heat)
    Storage.GetRecord(citizenid, function(record)
        table.insert(record.crimes, { type = crimeType, heat = heat, time = os.time() })
        Storage.SaveRecord(citizenid, record)
    end)
end

function Storage.AddJailHistory(citizenid, minutes, reason)
    Storage.GetRecord(citizenid, function(record)
        table.insert(record.jail_history, { minutes = minutes, reason = reason, time = os.time() })
        Storage.SaveRecord(citizenid, record)
    end)
end

function Storage.CountRecentArrests(citizenid, windowDays, cb)
    Storage.GetRecord(citizenid, function(record)
        local cutoff = os.time() - (windowDays * 86400)
        local count = 0
        for _, entry in ipairs(record.jail_history) do
            if entry.time >= cutoff then count = count + 1 end
        end
        cb(count)
    end)
end


function Storage.AddTicket(citizenid,kind,amount)
    Storage.GetRecord(citizenid,function(record)
        table.insert(record.tickets,{type=kind,amount=amount,time=os.time()})
        record.fines=(record.fines or 0)+amount
        Storage.SaveRecord(citizenid,record)
    end)
end

function Storage.AddWarning(citizenid,kind)
    Storage.GetRecord(citizenid,function(record)
        table.insert(record.warnings,{type=kind,time=os.time()})
        Storage.SaveRecord(citizenid,record)
    end)
end
