Utils = {}

function Utils.DetectFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

function Utils.ResourceExists(name)
    return name and name ~= '' and GetResourceState(name) == 'started'
end

function Utils.Log(msg)
    if Config.Debug then print(('^3[qb-aipolice]^7 %s'):format(msg)) end
end

function Utils.GetStarBehavior(stars)
    stars = math.max(1, math.min(tonumber(stars) or 1, Config.MaxStars))
    return Config.StarBehavior[stars]
end

function Utils.GetRandom(list)
    return list[math.random(1, #list)]
end

function Utils.Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end
