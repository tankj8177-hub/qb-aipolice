local currentStars=0

local function notify(msg,type)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false,false)
end

RegisterNetEvent('qb-aipolice:client:updateStars',function(stars)
    currentStars=math.max(0,math.min(Config.MaxStars,tonumber(stars) or 0))
    if Config.UI.showStarsHud then SendNUIMessage({action='updateStars',stars=currentStars}) end
end)

RegisterNetEvent('qb-aipolice:client:trafficNotice',function(kind,amount)
    if kind=='warning' then notify('Advertencia: reduzca la velocidad y deténgase para la unidad policial.','warning')
    elseif kind=='ticket' then notify('Ha recibido una multa de $'..tostring(amount or 0)..'.','warning') end
end)

CreateThread(function()
    while true do
        Wait(15000)
        if currentStars>0 then TriggerServerEvent('qb-aipolice:server:playerSeen') end
    end
end)

exports('GetCurrentStars',function() return currentStars end)
