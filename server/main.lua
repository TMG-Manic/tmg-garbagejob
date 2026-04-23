local TMGCore = exports['tmg-core']:GetCoreObject()
local Routes = {}

local function CanPay(Player)
    return Player.PlayerData.money['bank'] >= Config.TruckPrice
end

local function SaveGarbageRoute(citizenId)
    local routeData = Routes[citizenId]
    if routeData then
        exports['tmgnosql']:SaveToCollection('work_routes', { citizenid = citizenId, job = "garbage" }, routeData)
    else
        exports['tmgnosql']:DeleteOne('work_routes', { citizenid = citizenId, job = "garbage" })
    end
end

TMGCore.Functions.CreateCallback('tmg-garbagejob:server:NewShift', function(source, cb, continueShift)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return cb(false) end
    local citizenId = Player.PlayerData.citizenid

    local savedRoute = exports['tmgnosql']:FetchOne('work_routes', { 
        ["citizenid"] = citizenId, 
        ["job"] = "garbage" 
    })

    if savedRoute and continueShift then
        Routes[citizenId] = savedRoute
        local currentData = Routes[citizenId].stops[Routes[citizenId].currentStop]
        
        print(string.format("^5[TMG]^7 Mainframe: Garbage route resumed for CID %s", citizenId))
        return cb(true, currentData.stop, currentData.bags, Routes[citizenId].totalNumberOfStops)
    end

    if CanPay(Player) or continueShift then
        math.randomseed(os.time())
        local maxStops = math.random(Config.MinStops, #Config.Locations['trashcan'])
        local allStops = {}

        for _ = 1, maxStops do
            allStops[#allStops + 1] = { 
                ["stop"] = math.random(#Config.Locations['trashcan']), 
                ["bags"] = math.random(Config.MinBagsPerStop, Config.MaxBagsPerStop) 
            }
        end

        local newRoute = {
            ["citizenid"] = citizenId,
            ["job"] = "garbage",
            ["stops"] = allStops,
            ["currentStop"] = 1,
            ["started"] = true,
            ["depositPay"] = Config.TruckPrice,
            ["actualPay"] = 0,
            ["stopsCompleted"] = 0,
            ["totalNumberOfStops"] = #allStops,
            ["startTime"] = os.time()
        }

        Routes[citizenId] = newRoute

        exports['tmgnosql']:UpdateOne('work_routes', 
            { ["citizenid"] = citizenId, ["job"] = "garbage" }, 
            { ["$set"] = newRoute }, 
            { ["upsert"] = true }
        )
        
        print(string.format("^5[TMG]^7 Mainframe: New garbage shift anchored | CID: %s | Stops: %d", citizenId, #allStops))
        cb(true, allStops[1].stop, allStops[1].bags, #allStops)
    else
        TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Insufficient funds for truck deposit.", 'error')
        cb(false)
    end
end)

RegisterNetEvent('tmg-garbagejob:server:payDeposit', function()
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player.Functions.RemoveMoney('bank', Config.TruckPrice, 'garbage-deposit') then
        TriggerClientEvent('TMGCore:Notify', source, Lang:t('error.not_enough', { value = Config.TruckPrice }), 'error')
    end
end)

TMGCore.Functions.CreateCallback('tmg-garbagejob:server:NextStop', function(source, cb, currentStop, currentStopNum, currLocation)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not Routes[Player.PlayerData.citizenid] then return cb(false) end
    local CitizenId = Player.PlayerData.citizenid
    
    local currStopCoords = Config.Locations['trashcan'][currentStop].coords
    currStopCoords = vector3(currStopCoords.x, currStopCoords.y, currStopCoords.z)
    local distance = #(currLocation - currStopCoords)
    
    local newStop = 0
    local shouldContinue = false
    local newBagAmount = 0

    if distance <= 20 then
        if (math.random(100) >= Config.CryptoStickChance) and Config.GiveCryptoStick then
            exports['tmg-inventory']:AddItem(source, 'cryptostick', 1)
            TriggerClientEvent('tmg-inventory:client:ItemBox', source, TMGCore.Shared.Items['cryptostick'], 'add')
        end

        if currentStopNum >= #Routes[CitizenId].stops then
            Routes[CitizenId].stopsCompleted += 1
            newStop = currentStop
        else
            newStop = Routes[CitizenId].stops[currentStopNum + 1].stop
            newBagAmount = Routes[CitizenId].stops[currentStopNum + 1].bags
            shouldContinue = true
            
            local totalNewPay = 0
            for _ = 1, Routes[CitizenId].stops[currentStopNum].bags do
                totalNewPay += math.random(Config.BagLowerWorth, Config.BagUpperWorth)
            end

            Routes[CitizenId].actualPay += math.ceil(totalNewPay)
            Routes[CitizenId].stopsCompleted += 1
            Routes[CitizenId].currentStop = currentStopNum + 1
        end

        SaveGarbageRoute(CitizenId)
    else
        TriggerClientEvent('TMGCore:Notify', source, Lang:t('error.too_far'), 'error')
    end

    cb(shouldContinue, newStop, newBagAmount)
end)

TMGCore.Functions.CreateCallback('tmg-garbagejob:server:EndShift', function(source, cb)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    local CitizenId = Player.PlayerData.citizenid
    
    local status = (Routes[CitizenId] ~= nil)
    cb(status)
end)

RegisterNetEvent('tmg-garbagejob:server:PayShift', function(continue)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local CitizenId = Player.PlayerData.citizenid

    if Routes[CitizenId] ~= nil then
        local route = Routes[CitizenId]
        local depositPay = route.depositPay

        if tonumber(route.stopsCompleted) < tonumber(route.totalNumberOfStops) then
            depositPay = 0
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.early_finish', { 
                completed = route.stopsCompleted, 
                total = route.totalNumberOfStops 
            }), 'error')
        end

        if continue then depositPay = 0 end

        local totalToPay = depositPay + route.actualPay
        local payoutDeposit = depositPay > 0 and Lang:t('info.payout_deposit', { value = depositPay }) or ''

        Player.Functions.AddMoney('bank', totalToPay, 'garbage-payslip')
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.pay_slip', { 
            total = totalToPay, 
            deposit = payoutDeposit 
        }), 'success')

        Routes[CitizenId] = nil
        SaveGarbageRoute(CitizenId)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.never_clocked_on'), 'error')
    end
end)

TMGCore.Commands.Add('cleargarbroutes', 'Removes garbo routes for user (admin only)', { 
    { name = 'id', help = 'Player ID' } 
}, false, function(source, args)
    local targetId = tonumber(args[1])
    local Player = TMGCore.Functions.GetPlayer(targetId)
    if not Player then return end
    
    local CitizenId = Player.PlayerData.citizenid
    local count = Routes[CitizenId] and 1 or 0

    
    Routes[CitizenId] = nil
    SaveGarbageRoute(CitizenId)

    TriggerClientEvent('TMGCore:Notify', source, Lang:t('success.clear_routes', { value = count }), 'success')
end, 'admin')
