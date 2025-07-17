local lib = exports.ox_lib
local isOnJob = false
local jobStats = {
    moneyEarned = 0,
    trashCollected = 0,
    jobStartTime = 0,
    bonusClaimed = 0 -- Antal poser der allerede er givet bonus for
}

local TRASH_BAG_MODEL = 'prop_rub_binbag_01'
local TRASH_BAG_RADIUS = 500.0
local GROVE_CENTER = vector3( -160.0, -1600.0, 33.0 ) -- Justér hvis du vil have mere præcis placering
local TRASH_BAGS_PER_WAVE = 5
local trashBags = {}
local collectedTrash = 0 -- Skrald samlet men ikke smidt i bilen endnu
local trashBagProp = nil -- Prop i hånden
local lastActionTime = 0 -- Anti-spam
local lastTrashPickup = 0 -- Cooldown mellem opsamlinger
local lastTrashThrow = 0 -- Cooldown mellem smid i bilen
local maxTrashPerMinute = 30-- Maksimalt antal sække per minut
local trashPickupCount = 0 -- Tæller for opsamlinger denne minut
local lastMinuteReset = 0 -- Timer for at nulstille tæller

-- Anti-cheat funktioner
local function isPlayerNearby(coords, maxDistance)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    return #(playerCoords - coords) <= maxDistance
end

local function checkCooldown(action, cooldownTime)
    local currentTime = GetGameTimer()
    if currentTime - lastActionTime < cooldownTime then
        return false
    end
    lastActionTime = currentTime
    return true
end

local function checkTrashPickupLimit()
    local currentTime = GetGameTimer()
    
    -- Nulstil tæller hver minut
    if currentTime - lastMinuteReset >= 60000 then
        trashPickupCount = 0
        lastMinuteReset = currentTime
    end
    
    -- Tjek om spilleren har overskredet grænsen
    if trashPickupCount >= maxTrashPerMinute then
        lib:notify({
            title = 'For hurtigt',
            description = 'Du samler skrald for hurtigt! Vent lidt.',
            type = 'error'
        })
        return false
    end
    
    trashPickupCount = trashPickupCount + 1   return true
end

local function validateJobState()
    if not isOnJob then
        lib:notify({
            title = 'Ikke på job',
            description = 'Du skal være på job for at samle skrald!',
            type = 'error'
        })
        return false
    end
    return true
end

-- Utility: random pos near Grove (kun på fortovet)
local function randomTrashPos()
    local attempts = 0
    while attempts < 50 do
        local angle = math.random() * math.pi * 2
        local dist = math.random(10, TRASH_BAG_RADIUS)
        local x = GROVE_CENTER.x + math.cos(angle) * dist
        local y = GROVE_CENTER.y + math.sin(angle) * dist
        local z = GROVE_CENTER.z
        
        -- Tjek om positionen er på fortovet
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z, 0)
        if found then
            -- Tjek om det er på fortovet (ikke på vej)
            local roadTest = GetClosestVehicle(x, y, groundZ, 3.0, 070)
            if roadTest == 0 then -- Ingen køretøjer tæt på = sandsynligvis fortov
                return vector3(x, y, groundZ)
            end
        end
        attempts = attempts + 1
    end
    -- Fallback hvis ingen god position findes
    return vector3(GROVE_CENTER.x + math.random(-20,20), GROVE_CENTER.y + math.random(-20,20), GROVE_CENTER.z)
end

-- Spawn trash bags (5 ad gangen)
local function spawnTrashBags()
    RequestModel(TRASH_BAG_MODEL)
    while not HasModelLoaded(TRASH_BAG_MODEL) do Wait(10) end
    for i = 1, TRASH_BAGS_PER_WAVE do
        local pos = randomTrashPos()
        local obj = CreateObject(TRASH_BAG_MODEL, pos.x, pos.y, pos.z-1.0, false, true, true)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, 1)
        SetBlipScale(blip, 0.7)
        SetBlipColour(blip, 2)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Skraldesæk')
        EndTextCommandSetBlipName(blip)
        -- Tilføj ox_target til skraldesækken
        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'collect_trash',
                label = 'Saml skrald',
                icon = 'fa-solid fa-hand-paper',
                onSelect = function(data)
                    CollectTrashBag(data.entity)
                end
            }
        })
        trashBags[#trashBags+1] = {obj=obj, blip=blip, pos=pos, taken=false}
    end
end

-- Funktion til at samle skraldesæk (nu med flere poser)
function CollectTrashBag(entity)
    -- Find den rigtige pose i arrayet
    local bagIndex, bag = nil, nil
    for i, b in ipairs(trashBags) do
        if b.obj == entity then
            bagIndex = i
            bag = b
            break
        end
    end
    if not bag or bag.taken then return end
    -- Anti-cheat validering
    if not validateJobState() then return end
    if not checkCooldown('pickup',1000) then return end -- 1 sek. cooldown
    if not checkTrashPickupLimit() then return end
    -- Afstandskontrol
    if not isPlayerNearby(bag.pos,3) then
        lib:notify({
            title = 'For langt væk',
            description = 'Du skal være tættere på skraldesækken!',
            type = 'error'
        })
        return
    end
    -- Animation
    local ped = PlayerPedId()
    RequestAnimDict('pickup_object')
    while not HasAnimDictLoaded('pickup_object') do Wait(10) end
    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1500, 0, false, false, false)
    Wait(1200)
    ClearPedTasks(ped)
    -- Fjern objekt og blip
    if DoesEntityExist(bag.obj) then DeleteObject(bag.obj) end
    if DoesBlipExist(bag.blip) then RemoveBlip(bag.blip) end
    bag.taken = true
    collectedTrash = collectedTrash + 1   
    table.remove(trashBags, bagIndex)
    -- Tilføj trash bag prop i hånden
    if not trashBagProp then
        local propModel = GetHashKey('p_binbag_01_s')
        RequestModel(propModel)
        while not HasModelLoaded(propModel) do Wait(10) end
        trashBagProp = CreateObject(propModel, 0,0, true, true, true)
        AttachEntityToEntity(trashBagProp, ped, GetPedBoneIndex(ped, 5705), 0.12, 0.0, 0.0, 0.0, 25, 80, true, true, false, true, 1)
        -- Start bære-animation
        RequestAnimDict('anim@heists@box_carry@')
        while not HasAnimDictLoaded('anim@heists@box_carry@') do Wait(10) end
        TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 8.0, -8.0,-19, 0, false, false, false)
    end
    lib:notify({title='Skrald Samlet', description='Gå til skraldebilen og smid det i!', type='success'})
    -- Hvis alle poser er samlet, spawn 5 nye
    if #trashBags == 0 then
        Wait(500)
        spawnTrashBags()
    end
end

-- Funktion til at smide skrald i bilen
function ThrowTrashInTruck()
    -- Anti-cheat validering
    if not validateJobState() then return end
    if not checkCooldown('throw',2000) then return end -- 2 sekunder cooldown
    
    if collectedTrash <= 0 then
        lib:notify({
            title = 'Ingen skrald',
            description = 'Du har ikke noget skrald at smide i bilen!',
            type = 'error'
        })
        return
    end
    
    -- Afstandskontrol til bilen
    if spawnedTruck and DoesEntityExist(spawnedTruck) then
        local truckCoords = GetEntityCoords(spawnedTruck)
        if not isPlayerNearby(truckCoords, 7.0) then
            lib:notify({
                title = 'For langt væk',
                description = 'Du skal være tættere på skraldebilen!',
                type = 'error'
            })
            return
        end
    end
    
    -- Progress completed
    if trashBagProp and DoesEntityExist(trashBagProp) then
        DeleteObject(trashBagProp)
        trashBagProp = nil
        ClearPedTasks(PlayerPedId()) -- Stop bære-animation
    end
    
    jobStats.trashCollected = jobStats.trashCollected + collectedTrash
    collectedTrash = 0   
    lib:notify({
        title = 'Skrald smidt i bilen',
        description = string.format('Du smed %d stykker skrald i bilen!', jobStats.trashCollected),
        type = 'success'
    })
end

function OpenChefMenu()
    lib:registerContext({
        id = 'chef_menu',
        title = 'Skraldemand Chef',
        options = {
            {
                title = isOnJob and 'Stop Job' or 'Begynd at samle skrald',
                description = isOnJob and 'Stop med at samle skrald' or 'Begynd at samle skrald',
                icon = isOnJob and 'fa-solid fa-stop' or 'fa-solid fa-play',
                onSelect = function()
                    if isOnJob then
                        StopJob()
                    else
                        StartJob()
                    end
                end
            },
            -- Statistikker-knappen fjernet
            {
                title = 'Sælg Skrald',
                description = 'Få penge for dit samlede skrald',
                icon = 'fa-solid fa-dollar-sign',
                onSelect = function()
                    SellTrash()
                end
            }
        }
    })
    lib:showContext('chef_menu')
end

function StartJob()
    -- Anti-cheat validering
    if not checkCooldown('startjob',5000) then return end -- 5 sekunder cooldown
    
    if isOnJob then
        lib:notify({
            title = 'Fejl',
            description = 'Du er allerede på job!',
            type = 'error'
        })
        return
    end
    
    isOnJob = true
    jobStats.jobStartTime = GetGameTimer()
    collectedTrash = 0    -- Spawn skraldebil
    local truckModel = 'trash'
    local spawnCoords = vector4(-313.9518, -1524.2922, 27.5714, 249.6976)
    RequestModel(truckModel)
    while not HasModelLoaded(truckModel) do Wait(10) end
    spawnedTruck = CreateVehicle(truckModel, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, true, false)
    SetVehicleNumberPlateText(spawnedTruck, 'SKRALD')
    SetEntityAsMissionEntity(spawnedTruck, true, true)
    -- Sæt spiller ind i bilen
    TaskWarpPedIntoVehicle(PlayerPedId(), spawnedTruck, -1)

    lib:notify({
        title = 'Job Startet',
        description = 'Du er nu på skraldemand job! Din skraldebil er klar.',
        type = 'success'
    })
    
    -- Start job thread
    CreateThread(function()
        while isOnJob do
            Wait(10) -- Check hver sekund
            -- Her kan du tilføje logik for at finde skrald
        end
    end)

    -- Spawn trash bags
    trashBags = {} -- Ryd gamle sække
    spawnTrashBags()
    
    -- Tilføj ox_target til bilen
    exports.ox_target:addLocalEntity(spawnedTruck, {
        {
            name = 'throw_trash',
            label = 'Smid skrald i bilen',
            icon = 'fa-solid fa-trash',
            onSelect = function()
                ThrowTrashInTruck()
            end
        }
    })
end

function StopJob()
    -- Anti-cheat validering
    if not checkCooldown('stopjob',3000) then return end -- 3 sekunder cooldown
    
    -- Ryd trash bags
    for _, bag in ipairs(trashBags) do
        if DoesEntityExist(bag.obj) then DeleteObject(bag.obj) end
        if DoesBlipExist(bag.blip) then RemoveBlip(bag.blip) end
    end
    trashBags = {}

    -- Fjern trash bag prop hvis den eksisterer
    if trashBagProp and DoesEntityExist(trashBagProp) then
        DeleteObject(trashBagProp)
        trashBagProp = nil
        ClearPedTasks(PlayerPedId()) -- Stop bære-animation
    end

    -- Fjern skraldebil hvis den eksisterer
    if spawnedTruck and DoesEntityExist(spawnedTruck) then
        DeleteVehicle(spawnedTruck)
        spawnedTruck = nil
    end

    if not isOnJob then
        lib:notify({
            title = 'Fejl',
            description = 'Du er ikke på job!',
            type = 'error'
        })
        return
    end
    
    local jobDuration = math.floor((GetGameTimer() - jobStats.jobStartTime) / 1000 / 60) -- Minutter
    isOnJob = false
    collectedTrash = 0   
    trashPickupCount = 0 -- Nulstil anti-cheat tæller
    lib:notify({
        title = 'Job Stoppet',
        description = string.format('Job afsluttet! Du arbejdede i %d minutter.', jobDuration),
        type = 'info'
    })
end

-- Fjern hele ShowStats og ClaimBonus funktionerne

function SellTrash()
    if jobStats.trashCollected <= 0 then
        lib:notify({
            title = 'Ingen Skrald',
            description = 'Du har ikke noget skrald at sælge!',
            type = 'error'
        })
        return
    end
    
    local moneyPerTrash = 10 -- $10 per stykke skrald
    local totalMoney = jobStats.trashCollected * moneyPerTrash
    
    jobStats.moneyEarned = jobStats.moneyEarned + totalMoney
    jobStats.trashCollected = 0  
    -- Her skal du tilføje ESX.GiveMoney eller lignende
    -- ESX.GiveMoney(cash', totalMoney)
    
    lib:notify({
        title = 'Skrald Solgt',
        description = string.format('Du fik $%d for dit skrald!', totalMoney),
        type = 'success'
    })

    -- Stop jobbet automatisk
    StopJob()
end

-- Test funktion til at tilføje skrald (kan fjernes senere)
function AddTestTrash()
    if not isOnJob then
        lib:notify({
            title = 'Ikke på job',
            description = 'Du skal være på job for at samle skrald!',
            type = 'error'
        })
        return
    end

    if IsPedInAnyVehicle(PlayerPedId(), false) then
        lib:notify({
            title = 'I køretøj',
            description = 'Du skal være på fod for at samle skrald!',
            type = 'error'
        })
        return
    end

    jobStats.trashCollected = jobStats.trashCollected + 1
    lib:notify({
        title = 'Skrald Samlet',
        description = 'Du samlede 1 stykke skrald!',
        type = 'success'
    })
end

CreateThread(function()
    local model = GetHashKey('s_m_m_gardener_01')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end
    local coords = vector4(-321.7, -1545.8, 31.0, 20.0)
    local npc = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityHeading(npc, coords.w)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    -- Blip
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 318)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Skraldemand Chef')
    EndTextCommandSetBlipName(blip)
    -- ox_target integration
    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'chef_menu',
            label = 'Åben menu',
            icon = 'fa-solid fa-bars',
            onSelect = function()
                OpenChefMenu()
            end
        }
    })
end)

-- Test kommando til at tilføje skrald (kan fjernes senere)
RegisterCommand('addtrash', function()
    AddTestTrash()
end, false) 