local saved=nil

local function male()
    return GetEntityModel(PlayerPedId())==joaat('mp_m_freemode_01')
end

local function applyOutfit(outfit)
    local p=PlayerPedId()
    if not saved then
        saved={components={},props={}}
        for i=0,11 do
            saved.components[i]={GetPedDrawableVariation(p,i),GetPedTextureVariation(p,i),GetPedPaletteVariation(p,i)}
        end
        for i=0,7 do saved.props[i]={GetPedPropIndex(p,i),GetPedPropTextureIndex(p,i)} end
    end
    for id,data in pairs(outfit.components or {}) do
        id=tonumber(id)
        local drawable,texture,palette
        if type(data)=='table' then
            drawable=data.drawable or data[1] or 0
            texture=data.texture or data[2] or 0
            palette=data.palette or data[3] or 0
        else
            drawable=data; texture=0; palette=0
        end
        SetPedComponentVariation(p,id,tonumber(drawable) or 0,tonumber(texture) or 0,tonumber(palette) or 0)
    end
    for id,data in pairs(outfit.props or {}) do
        id=tonumber(id)
        local prop,texture
        if type(data)=='table' then prop=data.drawable or data[1] or -1; texture=data.texture or data[2] or 0
        else prop=data; texture=0 end
        prop=tonumber(prop) or -1
        if prop<0 then ClearPedProp(p,id) else SetPedPropIndex(p,id,prop,tonumber(texture) or 0,true) end
    end
end

RegisterNetEvent('qb-aipolice:client:applyJailOutfit',function()
    if not Config.Integrations.appearance.enabled then return end
    local outfit=male() and Config.Integrations.appearance.maleJailOutfit or Config.Integrations.appearance.femaleJailOutfit
    applyOutfit(outfit)
end)

RegisterNetEvent('qb-aipolice:client:restoreJailOutfit',function()
    if not saved then return end
    local p=PlayerPedId()
    for id,data in pairs(saved.components) do SetPedComponentVariation(p,id,data[1],data[2],data[3]) end
    for id,data in pairs(saved.props) do
        if data[1] and data[1]>=0 then SetPedPropIndex(p,id,data[1],data[2] or 0,true) else ClearPedProp(p,id) end
    end
    saved=nil
end)
