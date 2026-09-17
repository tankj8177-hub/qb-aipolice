Config = {}

-- qb-aipolice
-- Deteccion automatica: QBX/Qbox, QBCore, ESX y Standalone.
Config.Framework = 'auto' -- auto | qbox | qbcore | esx | standalone

Config.MaxStars = 7
Config.Debug = true

-- IA policial autónoma para las unidades creadas por el menú.
-- Las unidades de patrulla/respaldo continúan trabajando aunque no haya una orden nueva.
Config.AutonomousPolice = {
    enabled = true,
    patrolSearchDistance = 70.0,
    investigateDuration = 45000,
    guardDistance = 18.0,
    idleTaskRefresh = 7000
}

-- No hace que la IA aparezca inmediatamente en la cara del jugador.
Config.Response = {
    minSpawnDistance = 45.0,
    maxSpawnDistance = 85.0,
    firstResponseDelay = 4500,
    reinforcementDelay = 12000,
    reengageCooldown = 15000,
    maxActiveUnits = 6,
    evasionCheckSeconds = 12
}

Config.RealPoliceThreshold = 2
Config.PoliceJobs = { 'police', 'sheriff', 'bcso', 'sast' }

Config.StarDecayTime = 90
Config.StarThresholds = { [1]=10, [2]=30, [3]=60, [4]=100, [5]=150, [6]=220, [7]=300 }

-- La respuesta escala. 1-2 = investigación/advertencia; 3-4 = persecución;
-- 5-6 = táctica; 7 = manhunt/militar.
Config.StarBehavior = {
    [1] = { units=1, response='investigation', vehicles={'police'}, weapons={'WEAPON_STUNGUN'}, roadblocks=false, spikes=false, helicopter=false, tactical=false, military=false, accuracy=20, armor=0, aggression=1 },
    [2] = { units=2, response='warning',       vehicles={'police'}, weapons={'WEAPON_STUNGUN','WEAPON_PISTOL'}, roadblocks=false, spikes=false, helicopter=false, tactical=false, military=false, accuracy=25, armor=0, aggression=2 },
    [3] = { units=2, response='pursuit',       vehicles={'police','police2'}, weapons={'WEAPON_PISTOL'}, roadblocks=false, spikes=true, helicopter=false, tactical=false, military=false, accuracy=35, armor=25, aggression=4 },
    [4] = { units=3, response='pursuit',       vehicles={'police2','police3'}, weapons={'WEAPON_PISTOL','WEAPON_PUMPSHOTGUN'}, roadblocks=true, spikes=true, helicopter=false, tactical=false, military=false, accuracy=45, armor=50, aggression=6 },
    [5] = { units=4, response='tactical',      vehicles={'police3','riot'}, weapons={'WEAPON_CARBINERIFLE'}, roadblocks=true, spikes=true, helicopter=true, tactical=true, military=false, accuracy=55, armor=75, aggression=8 },
    [6] = { units=5, response='tactical',      vehicles={'riot','fbi2'}, weapons={'WEAPON_CARBINERIFLE','WEAPON_COMBATMG'}, roadblocks=true, spikes=true, helicopter=true, tactical=true, military=false, accuracy=65, armor=100, aggression=9 },
    [7] = { units=6, response='manhunt',      vehicles={'barracks','crusader'}, weapons={'WEAPON_CARBINERIFLE','WEAPON_COMBATMG'}, roadblocks=true, spikes=true, helicopter=true, tactical=true, military=true, accuracy=80, armor=100, aggression=10 },
}

Config.AirSupport = {
    enabled=true,
    minStarsForHeli=5,
    minStarsForJet=7,
    allowJetAirSupport=false,
    heliModel='polmav',
    jetModel='lazer'
}

Config.OfficerModels = { 's_m_y_cop_01', 's_f_y_cop_01', 's_m_y_swat_01' }
Config.TacticalOfficerModel = 's_m_y_swat_01'
Config.MilitaryOfficerModel = 's_m_y_marine_01'
Config.VehicleLivery = { police=0, police2=0, police3=0, riot=0, fbi2=0, barracks=0, crusader=0, policet=0 }

Config.RobberyResponse = {
    enabled = true,
    minStars = 5,
    heatPoints = 120,
    tacticalUnits = 2,
    responseRadius = 180.0,
    clearAfterSeconds = 180,
    -- Punto donde la patrulla termina el traslado y puede desaparecer,
    -- evitando que se quede chocando dentro de la entrada de prisión.
    transportCleanupCoords = vector3(1682.18, 2607.53, 44.56),
    transportCleanupDistance = 12.0,
    -- Detecta robos QBOX/QBX conocidos y también alertas policiales comunes.
    -- Puedes añadir aquí eventos de otros recursos sin tocar el sistema existente.
    events = {
        'qbx_jewelery:server:endcabinet',
        'qbx_bankrobbery:server:callCops'
    }
}

Config.Detection = {
    shooting={enabled=true, heatPoints=15, starsMin=2, cooldown=4, witnessRadius=40.0},
    assault={enabled=true, heatPoints=20, starsMin=2, cooldown=5},
    murder={enabled=true, heatPoints=60, starsMin=3, cooldown=5},
    vehicleTheft={enabled=true, heatPoints=25, starsMin=2, graceSeconds=8, cooldown=20},
    drugSelling={enabled=true, heatPoints=10, starsMin=1, cooldown=8},
    robbery={enabled=true, heatPoints=40, starsMin=3, cooldown=12},
    territory={enabled=true, heatPoints=15, starsMin=2, cooldown=10},
    speeding={enabled=true, speedLimit=110, heatPoints=5, starsMin=1, cooldown=15, recklessSpeed=160},
    policeEvasion={enabled=true, heatPoints=10, starsMin=1, cooldown=20},
    npcWitnesses={enabled=true, reportChance=65, reportRadius=30.0, reportDelay={min=3000,max=9000}}
}

Config.TrafficStops = {
    enabled=true,
    checkRadius=35.0,
    ticketAmounts={speeding=250, reckless=500, noLicense=150},
    warningStars=1,
    ticketStars=2
}

Config.RepeatOffender = { enabled=true, threshold=3, windowDays=7, extraStars=1, extraJailMinutes=2 }

Config.Arrest = {
    handcuffTime=3500,
    searchTime=2500,
    escortEnabled=true,
    transportVehicle='policet',
    transportTime=9000,
    fallbackJailTime=5,
    fallbackJailCoords=vector3(1651.41,2570.28,45.56),
    -- Punto de salida: exterior de la comisaría después de cumplir la condena.
    jailReleaseCoords=vector4(1651.42,2573.72,44.56,0.0), -- SOLO SALIDA: aqui aparece el personaje al cumplir la condena
    jailReleaseBlip={enabled=true, sprite=60, color=2, scale=0.75, label='Salida de prisión'},
    -- Al llegar aquí, pulsa E para viajar a la comisaría.
    jailExitStationCoords=vector4(441.0,-981.2,30.69,90.0),
    jailExitInteractionDistance=2.5,
    surrenderDistance=7.0,
    arrestDistance=3.0,
    allowSurrender=true,
    arrestWhenDowned=true
}

-- Integraciones de terceros son opcionales.
-- rcore_prison: usa export/event configurables porque las versiones pueden exponer APIs distintas.
Config.Integrations = {
    rcore_prison={
        enabled=true, resourceName='rcore_prison',
        mode='export', exportName='SendToPrison', eventName='rcore_prison:server:jailPlayer',
        releaseExport='ReleasePlayer', releaseEvent='rcore_prison:server:releasePlayer', reductionExport='ReduceSentence', reductionEvent='rcore_prison:server:reduceSentence',
        fallbackToNativeJail=true
    },
    ambulance={
        enabled=true, resourceName='ak47_ambulance',
        mode='export', reviveExport='Revive', reviveEvent='hospital:server:RevivePlayer',
        reviveBeforePrison=true
    },
    appearance={
        enabled=true, resourceName='illenium-appearance',
        maleJailOutfit={components={['4']=0,['6']=0,['8']=0,['11']=0}},
        femaleJailOutfit={components={['4']=0,['6']=0,['8']=0,['11']=0}},
        restoreOnRelease=true
    },
    jaksam_drugs={enabled=false, resourceName='jaksam_drugscreator', eventName='jaksam_drugscreator:crimeDetected'},
    jaksam_robberies={enabled=false, resourceName='jaksam_robberiescreator', eventName='jaksam_robberiescreator:robberyProgress'},
    ak47_territory={enabled=false, resourceName='ak47_territory', eventName='ak47_territory:illegalActivity'}
}

Config.IllegalItems = { 'weed','coke','meth','weapon_pistol_dirty' }

Config.WantedReduction = {
    layLowEnabled=true,
    changeClothesReduces=true,
    changeClothesAmount=1
}

Config.UI = { showStarsHud=true, position='top-right', sound=true }

-- ============================================================
-- MENÚ NUI PARA POLICÍA / SHERIFF DE TURNO
-- ============================================================
Config.PoliceMenu = {
    enabled = true,
    command = 'aipolice',
    key = 'F6',
    requireOnDuty = true,
    allowStandalone = true,
    standaloneAce = 'qb-aipolice.police',
    maxDispatchUnits = 6,
    dispatchDistance = { min = 35.0, max = 65.0 },
    commandCooldown = 2500,
    orders = {
        backup = true,
        investigate = true,
        patrol = true,
        trafficStop = true,
        pursuit = true,
        spikes = true,
        roadblock = true,
        tactical = true,
        helicopter = true,
        military = true,
        transport = true,
        clearUnits = true
    }
}
