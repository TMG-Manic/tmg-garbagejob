local TMGCore = exports['tmg-core']:GetCoreObject()

GarbageState = {
    isLoggedIn = LocalPlayer.state['isLoggedIn'],
    playerJob = {},
    truck = nil,
    hasBag = false,
    bagObject = nil,
    currentStop = 0,
    currentStopNum = 0,
    bagsRemaining = 0,
    canTakeBag = true,
    blips = { main = nil, delivery = nil, returnRoute = nil },
    activeZone = nil,
    isNearBoss = false,
    isNearTruck = false,
    isNearBin = false,
    isFinishing = false,
    pedsSpawned = false,
    bossPeds = {}
}


local function LoadAnimation(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
end

local function ClearBlipRegistry()
    if GarbageState.blips.delivery then RemoveBlip(GarbageState.blips.delivery) end
    if GarbageState.blips.returnRoute then RemoveBlip(GarbageState.blips.returnRoute) end
    GarbageState.blips.delivery = nil
    GarbageState.blips.returnRoute = nil
end

local function ResetState()
    if GarbageState.bagObject then DeleteEntity(GarbageState.bagObject) end
    ClearBlipRegistry()
    GarbageState.truck = nil
    GarbageState.hasBag = false
    GarbageState.currentStop = 0
    GarbageState.currentStopNum = 0
    GarbageState.bagsRemaining = 0
    GarbageState.isFinishing = false
    if GarbageState.activeZone then GarbageState.activeZone:destroy() end
    print("^5[TMG]^7 Sanitation matrix reset. Asset memory purged.")
end


local function SetGarbageRoute()
    local CL = Config.Locations["trashcan"][GarbageState.currentStop]
    ClearBlipRegistry()
    
    local blip = AddBlipForCoord(CL.coords.x, CL.coords.y, CL.coords.z)
    SetBlipSprite(blip, 1)
    SetBlipDisplay(blip, 2)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 27)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(CL.name)
    EndTextCommandSetBlipName(blip)
    GarbageState.blips.delivery = blip

    if Config.UseTarget and not GarbageState.hasBag then
        exports['tmg-target']:AddCircleZone('garbagebin', CL.coords.xyz, 2.0, {
            name = 'garbagebin', debugPoly = false, useZ = true 
        }, {
            options = {{ label = Lang:t("target.grab_garbage"), icon = 'fa-solid fa-trash', action = function() TakeAnim() end }},
            distance = 2.0
        })
    end

    if GarbageState.activeZone then GarbageState.activeZone:destroy() end
    GarbageState.activeZone = CircleZone:Create(CL.coords.xyz, 15.0, { name = "GarbageZone", debugPoly = false })
    GarbageState.activeZone:onPlayerInOut(function(inside)
        if inside then
            SetVehicleDoorOpen(GarbageState.truck, 5, false, false)
            print("^5[TMG]^7 Arrived at stop. Rear compactor engaged.")
        else
            SetVehicleDoorShut(GarbageState.truck, 5, false)
            exports['tmg-core']:HideText()
        end
    end)
end

function TakeAnim()
    local ped = PlayerPedId()
    TMGCore.Functions.Progressbar("bag_pickup", Lang:t("info.picking_bag"), math.random(3000, 5000), false, true, {
        disableMovement = true, disableCombat = true,
    }, {
        animDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", anim = "machinic_loop_mechandplayer", flags = 16,
    }, {}, {}, function() -- Done
        LoadAnimation('missfbi4prepp1')
        TaskPlayAnim(ped, 'missfbi4prepp1', '_bag_walk_garbage_man', 6.0, -6.0, -1, 49, 0, 0, 0, 0)
        GarbageState.bagObject = CreateObject(`prop_cs_rub_binbag_01`, 0, 0, 0, true, true, true)
        AttachEntityToEntity(GarbageState.bagObject, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.0, -0.05, 220.0, 120.0, 0.0, true, true, false, true, 1, true)
        GarbageState.hasBag = true
        
        if Config.UseTarget then
            exports['tmg-target']:RemoveZone("garbagebin")
            exports['tmg-target']:AddTargetEntity(GarbageState.truck, {
                options = {{ label = Lang:t("target.dispose_garbage"), icon = 'fa-solid fa-truck', action = function() DeliverAnim() end, canInteract = function() return GarbageState.hasBag end }},
                distance = 2.0
            })
        end
    end)
end

function DeliverAnim()
    local ped = PlayerPedId()
    LoadAnimation('missfbi4prepp1')
    TaskPlayAnim(ped, 'missfbi4prepp1', '_bag_throw_garbage_man', 8.0, 8.0, 1100, 48, 0.0, 0, 0, 0)
    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, GetEntityHeading(GarbageState.truck))
    GarbageState.canTakeBag = false

    SetTimeout(1250, function()
        if GarbageState.bagObject then DeleteEntity(GarbageState.bagObject) end
        FreezeEntityPosition(ped, false)
        GarbageState.bagObject = nil
        GarbageState.hasBag = false
        GarbageState.canTakeBag = true
        
        if (GarbageState.bagsRemaining - 1) <= 0 then
            TMGCore.Functions.TriggerCallback('tmg-garbagejob:server:NextStop', function(hasMore, nextStop, newAmount)
                if hasMore and nextStop ~= 0 then
                    GarbageState.currentStop, GarbageState.currentStopNum, GarbageState.bagsRemaining = nextStop, GarbageState.currentStopNum + 1, newAmount
                    SetGarbageRoute()
                    TMGCore.Functions.Notify(Lang:t("info.all_bags"))
                else
                    TMGCore.Functions.Notify(Lang:t("info.done_working"))
                    SetRouteBack()
                end
            end, GarbageState.currentStop, GarbageState.currentStopNum, GetEntityCoords(ped))
        else
            GarbageState.bagsRemaining = GarbageState.bagsRemaining - 1
            TMGCore.Functions.Notify(Lang:t("info.bags_left", { value = GarbageState.bagsRemaining }))
            if Config.UseTarget then SetGarbageRoute() end
        end
    end)
end

function SetRouteBack()
    local depot = Config.Locations["main"].coords
    ClearBlipRegistry()
    local blip = AddBlipForCoord(depot.x, depot.y, depot.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 3)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Depot Return")
    EndTextCommandSetBlipName(blip)
    GarbageState.blips.returnRoute = blip
    GarbageState.isFinishing = true
end


local function spawnPeds()
    if not Config.Peds or GarbageState.pedsSpawned then return end
    for i = 1, #Config.Peds do
        local data = Config.Peds[i]
        local model = type(data.model) == 'string' and GetHashKey(data.model) or data.model
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end
        local ped = CreatePed(0, model, data.coords, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        data.pedHandle = ped
        if Config.UseTarget then
            exports['tmg-target']:AddTargetEntity(ped, {
                options = {{ event = "tmg-garbagejob:client:MainMenu", label = Lang:t("target.talk"), icon = 'fa-solid fa-recycle', job = Config.Jobname }},
                distance = 2.0
            })
        end
    end
    GarbageState.pedsSpawned = true
    print("^5[TMG]^7 Sanitation boss nodes materialized.")
end

local function deletePeds()
    if not GarbageState.pedsSpawned then return end
    for i = 1, #Config.Peds do
        if Config.Peds[i].pedHandle then DeletePed(Config.Peds[i].pedHandle) end
    end
    GarbageState.pedsSpawned = false
end


CreateThread(function()
    while true do
        local sleep = 1000
        if GarbageState.isLoggedIn then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            if GarbageState.hasBag and not IsEntityPlayingAnim(ped, 'missfbi4prepp1', '_bag_throw_garbage_man', 3) then
                if not IsEntityPlayingAnim(ped, 'missfbi4prepp1', '_bag_walk_garbage_man', 3) then
                    LoadAnimation('missfbi4prepp1')
                    TaskPlayAnim(ped, 'missfbi4prepp1', '_bag_walk_garbage_man', 6.0, -6.0, -1, 49, 0, 0, 0, 0)
                end
            end

            if not Config.UseTarget and GarbageState.currentStop ~= 0 then
                local stopCoords = Config.Locations["trashcan"][GarbageState.currentStop].coords
                if #(pos - stopCoords.xyz) < 2.0 and not GarbageState.hasBag then
                    sleep = 0
                    exports['tmg-core']:DrawText(Lang:t("info.grab_garbage"))
                    if IsControlJustPressed(0, 51) then TakeAnim() end
                elseif GarbageState.hasBag and DoesEntityExist(GarbageState.truck) then
                    local trunk = GetOffsetFromEntityInWorldCoords(GarbageState.truck, 0.0, -4.5, 0.0)
                    if #(pos - trunk) < 2.0 then
                        sleep = 0
                        exports['tmg-core']:DrawText(Lang:t("info.dispose_garbage"))
                        if IsControlJustPressed(0, 51) then DisposeBag() end
                    else exports['tmg-core']:HideText() end
                else exports['tmg-core']:HideText() end
            end
        end
        Wait(sleep)
    end
end)


RegisterNetEvent('tmg-garbagejob:client:MainMenu', function()
    if GarbageState.playerJob.name ~= Config.Jobname then return TMGCore.Functions.Notify(Lang:t("error.job"), 'error') end
    local menu = {
        { isMenuHeader = true, header = Lang:t("menu.header") },
        { header = Lang:t("menu.collect"), txt = Lang:t("menu.return_collect"), params = { event = 'tmg-garbagejob:client:RequestPaycheck' } }
    }
    if not GarbageState.truck or GarbageState.isFinishing then
        menu[#menu+1] = { header = Lang:t("menu.route"), txt = Lang:t("menu.request_route"), params = { event = 'tmg-garbagejob:client:RequestRoute' } }
    end
    exports['tmg-menu']:openMenu(menu)
end)

RegisterNetEvent('tmg-garbagejob:client:RequestRoute', function()
    local continue = GarbageState.truck ~= nil
    if continue then TriggerServerEvent('tmg-garbagejob:server:PayShift', true) end
    TMGCore.Functions.TriggerCallback('tmg-garbagejob:server:NewShift', function(ok, stop, bags)
        if ok then
            if not GarbageState.truck then
                for _, loc in pairs(Config.Locations["vehicle"].coords) do
                    if not IsAnyVehicleNearPoint(loc.x, loc.y, loc.z, 2.5) then
                        TMGCore.Functions.TriggerCallback('TMGCore:Server:SpawnVehicle', function(netId)
                            local veh = NetToVeh(netId)
                            GarbageState.truck = veh
                            SetVehicleNumberPlateText(veh, "TRASH" .. math.random(10, 99))
                            exports['LegacyFuel']:SetFuel(veh, 100.0)
                            TriggerEvent("vehiclekeys:client:SetOwner", TMGCore.Functions.GetPlate(veh))
                            GarbageState.currentStop, GarbageState.currentStopNum, GarbageState.bagsRemaining = stop, 1, bags
                            SetGarbageRoute()
                            TMGCore.Functions.Notify(Lang:t("info.started"))
                        end, Config.Vehicle, loc, true)
                        return
                    end
                end
            else
                GarbageState.currentStop, GarbageState.currentStopNum, GarbageState.bagsRemaining = stop, 1, bags
                SetGarbageRoute()
            end
        end
    end, continue)
end)

RegisterNetEvent('tmg-garbagejob:client:RequestPaycheck', function()
    if GarbageState.truck then TMGCore.Functions.DeleteVehicle(GarbageState.truck) ResetState() end
    TriggerServerEvent('tmg-garbagejob:server:PayShift')
end)

RegisterNetEvent('tmg-garbagejob:client:SetWaypointHome', function()
    SetNewWaypoint(Config.Locations["main"].coords.x, Config.Locations["main"].coords.y)
end)

RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    GarbageState.playerJob = TMGCore.Functions.GetPlayerData().job
    GarbageState.isLoggedIn = true
    spawnPeds()
end)

RegisterNetEvent('TMGCore:Client:OnJobUpdate', function(JobInfo)
    GarbageState.playerJob = JobInfo
    if GarbageState.blips.main then RemoveBlip(GarbageState.blips.main) end
    ClearBlipRegistry()
    spawnPeds()
end)

AddEventHandler('onResourceStart', function(res) if GetCurrentResourceName() == res then GarbageState.playerJob = TMGCore.Functions.GetPlayerData().job GarbageState.isLoggedIn = true spawnPeds() end end)
AddEventHandler('onResourceStop', function(res) if GetCurrentResourceName() == res then deletePeds() end end)