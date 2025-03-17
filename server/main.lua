local RSGCore = exports['rsg-core']:GetCoreObject()

-- Track active movies and shows
local activeMovies = {}
local activeShows = {}

-- Register usable item (cinema ticket)
RSGCore.Functions.CreateUseableItem("cinema_ticket", function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check ticket metadata
    if item.info and item.info.show and item.info.location then
        if Config.Movies[item.info.show] and Config.Projections[item.info.location] then
            -- Check if movie is already playing
            if activeMovies[item.info.location] then
                TriggerClientEvent('RSGCore:Notify', src, "A movie is already playing at this location", 'error')
                return
            end
            
            -- Mark movie as active
            activeMovies[item.info.location] = {
                show = item.info.show,
                startTime = os.time(),
                displayActive = true -- Add display state tracking
            }
            
            -- Remove ticket from inventory
            Player.Functions.RemoveItem('cinema_ticket', 1, item.slot)
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['cinema_ticket'], "remove")
            
            -- Sync movie start and display state to all players
            TriggerClientEvent("rsg-cinema:startMovie", -1, item.info.show, item.info.location)
            TriggerClientEvent("rsg-cinema:syncMovieState", -1, item.info.location, item.info.show, true)
            TriggerClientEvent("rsg-cinema:syncDisplayState", -1, item.info.location, true) -- Sync display state
        elseif Config.Shows[item.info.show] then
            -- Check if show is already playing
            if activeShows[item.info.show] then
                TriggerClientEvent('RSGCore:Notify', src, "This show is already playing", 'error')
                return
            end
            
            -- Mark show as active
            activeShows[item.info.show] = {
                startTime = os.time(),
                displayActive = true -- Add display state tracking
            }
            
            -- Remove ticket from inventory
            Player.Functions.RemoveItem('cinema_ticket', 1, item.slot)
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['cinema_ticket'], "remove")
            
            -- Sync show start and display state to all players
            TriggerClientEvent("rsg-cinema:startMovie", -1, item.info.show)  
            TriggerClientEvent("rsg-cinema:syncShowState", -1, item.info.show, true)
            TriggerClientEvent("rsg-cinema:syncDisplayState", -1, item.info.show, true) -- Sync display state
        end
    else
        TriggerClientEvent('RSGCore:Notify', src, "This ticket is invalid", 'error')
    end
end)

-- Buy ticket event
RegisterServerEvent('rsg-cinema:buyTicket')
AddEventHandler('rsg-cinema:buyTicket', function(show, location)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local price = Config.Prices[show] or Config.Prices.default -- Get price from config

    if Player.Functions.GetMoney('cash') >= price then
        -- Remove money
        Player.Functions.RemoveMoney('cash', price, "cinema-ticket-purchase")
        
        -- Create ticket info (metadata)
        local info = {
            show = show,
            location = location,
            description = "Movie ticket for " .. show,
            expiry = os.time() + (24 * 60 * 60)
        }
        
        -- Add ticket to inventory
        Player.Functions.AddItem('cinema_ticket', 1, nil, info)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['cinema_ticket'], "add")
        TriggerClientEvent('RSGCore:Notify', src, "Ticket purchased for " .. show .. " ($" .. price .. ")", 'success')
    else
        TriggerClientEvent('RSGCore:Notify', src, "Not enough money", 'error')
    end
end)

-- Events to sync movie/show state between players
RegisterServerEvent("rsg-cinema:syncMovieState") 
AddEventHandler("rsg-cinema:syncMovieState", function(projection, movie, isStarting)
    if isStarting then
        activeMovies[projection] = {
            show = movie,
            startTime = os.time(),
            displayActive = true -- Add display state tracking
        }
    else
        activeMovies[projection] = nil
    end
    TriggerClientEvent("rsg-cinema:syncMovieState", -1, projection, movie, isStarting)
    TriggerClientEvent("rsg-cinema:syncDisplayState", -1, projection, isStarting) -- Sync display state
end)

RegisterServerEvent("rsg-cinema:syncShowState")
AddEventHandler("rsg-cinema:syncShowState", function(show, isStarting)
    if isStarting then
        activeShows[show] = {
            startTime = os.time(),
            displayActive = true -- Add display state tracking
        }
    else
        activeShows[show] = nil
    end
    TriggerClientEvent("rsg-cinema:syncShowState", -1, show, isStarting)
    TriggerClientEvent("rsg-cinema:syncDisplayState", -1, show, isStarting) -- Sync display state
end)