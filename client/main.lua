local RSGCore = exports['rsg-core']:GetCoreObject()

-- Local variables
local CreatedVendors = {}
local menuOpen = false
local createdShowEntities = {} -- Track created show entities
local activeShows = {} -- Track active shows and their viewers
local activeMovies = {} -- Track active movie screens
local displayActive = false -- Track if display is active
local stressReliefInterval = 30000 -- Interval for stress relief (30 seconds)

CreateThread(function()
    CreateTicketVendors()
    CreateCinemaBlips()
end)

function CreateCinemaBlips()
    for location, data in pairs(Config.TicketVendors) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, data.pos)
        SetBlipSprite(blip, -417940443, 1) -- Cinema blip sprite
        SetBlipScale(blip, 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, data.blipName or "Cinema")
    end
end

function CreateTicketVendors()
    for location, data in pairs(Config.TicketVendors) do
        local model = `A_M_O_SDUpperClass_01`
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(100) end
        
        local vendor = CreatePed(model, data.pos, data.heading, false, true, true, true)
        Citizen.InvokeNative(0x283978A15512B2FE, vendor, true)
        SetEntityCanBeDamaged(vendor, false)
        SetPedConfigFlag(vendor, 26, true)
        SetBlockingOfNonTemporaryEvents(vendor, true)
        
        -- Make NPC stick to ground
        PlaceObjectOnGroundProperly(vendor)
        SetEntityAsMissionEntity(vendor, true, true)
        
        -- Freeze NPC position and make invincible
        FreezeEntityPosition(vendor, true)
        SetEntityInvincible(vendor, true)
        
        CreatedVendors[location] = {
            ped = vendor,
            shows = data.shows
        }

        -- Changed from jkt_target to rsg-target
        exports['rsg-target']:AddTargetEntity(vendor, {
            options = {
                {
                    type = 'client',
                    icon = 'fas fa-film',
                    label = 'Talk to Cinema Vendor',
                    action = function()
                        if not menuOpen then
                            menuOpen = true
                            OpenMovieMenu(location, data.shows)
                        end
                    end
                }
            },
            distance = 2.0
        })
    end
end

function OpenMovieMenu(location, shows)
    local options = {}
    
    for _, show in pairs(shows) do
        local price = Config.Prices[show] or Config.Prices.default
        table.insert(options, {
            title = show:gsub("_", " "),
            description = "Price: $" .. price,
            icon = 'fas fa-film',
            onSelect = function()
                TriggerServerEvent("rsg-cinema:buyTicket", show, location)
            end
        })
    end
    
    -- Register and show the ox_lib context menu
    lib.registerContext({
        id = 'cinema_menu_' .. location,
        title = 'Cinema Shows',
        options = options
    })
    
    lib.showContext('cinema_menu_' .. location)
    menuOpen = false
end

-- Event handler for buying ticket (triggered from menu)
RegisterNetEvent('rsg-cinema:client:buyTicket')
AddEventHandler('rsg-cinema:client:buyTicket', function(data)
    TriggerServerEvent("rsg-cinema:buyTicket", data.show, data.location)
end)

function SetupMovie(projection, movie)
    local projectionData = Config.Projections[projection]
    local movieConfig = Config.Movies[movie]

    if not projectionData or not movieConfig then return nil end

    while not HasModelLoaded(projectionData.targetModel) do 
        RequestModel(projectionData.targetModel)
        Wait(10) 
    end

    local screen = CreateObjectNoOffset(projectionData.targetModel, projectionData.screenPos, false, false, false, true)
    SetEntityRotation(screen, projectionData.screenRot, 2, true)
    SetEntityVisible(screen, false)
    SetEntityDynamic(screen, false)
    SetEntityProofs(screen, 31, false)
    FreezeEntityPosition(screen, true)
    SetModelAsNoLongerNeeded(projectionData.targetModel)

    if not IsNamedRendertargetRegistered(projectionData.renderTarget) then
        RegisterNamedRendertarget(projectionData.renderTarget, false)
        LinkNamedRendertarget(projectionData.targetModel)

        if not IsNamedRendertargetLinked(projectionData.targetModel) then    
            ReleaseNamedRendertarget(projectionData.renderTarget)
            return nil
        end
    end

    return {
        screen = screen,
        renderTarget = GetNamedRendertargetRenderId(projectionData.renderTarget)
    }
end

function _LoadStream(soundSet)
    local timeout = 0
    while not LoadStream("Audience", soundSet) do
        if timeout > 4 then break end
        timeout = timeout + 1
        Wait(25)
    end
end

function StartShow(show, projection, movie)
    if show == "MOVIE" then
        if IsMovieValid(projection, movie) then
            local movieData = SetupMovie(projection, movie)
            local projectionData = Config.Projections[projection]
            local movieConfig = Config.Movies[movie]

            if movieData and projectionData and movieConfig then
                -- Add show to active shows and movies
                activeShows[projection] = {
                    type = "MOVIE",
                    movie = movie,
                    startTime = GetGameTimer(),
                    viewers = {}
                }
                
                activeMovies[projection] = movieData
                displayActive = true

                SetTvAudioFrontend(false)
                SetTvVolume(projectionData.volume)
                AttachTvAudioToEntity(movieData.screen)
                N_0xf49574e2332a8f06(movieData.screen, 5.0)
                N_0x04d1d4e411ce52d0(movieData.screen, movieData.renderTarget)

                SetTvChannel(-1)
                SetTvChannelPlaylist(0, movieConfig.clip, true)
                SetTvChannel(0)

                _LoadStream(movieConfig.audio)
                local stream = N_0x0556c784fa056628("Audience", movieConfig.audio)
                PlayStreamFromPosition(projectionData.audiencePos, stream)

                Wait(100)
                SetEntityVisible(movieData.screen, true)

                -- Create render loop thread
                CreateThread(function()
                    while activeMovies[projection] and displayActive do
                        if not projectionData.radius or (Vdist(GetEntityCoords(PlayerPedId()), projectionData.audiencePos) <= projectionData.radius) then
                            SetTextRenderId(movieData.renderTarget)
                            DrawTvChannel(projectionData.renderX, projectionData.renderY, projectionData.renderScaleX, projectionData.renderScaleY, 0.0, 255, 255, 255, 128)
                            SetTextRenderId(0)
                        end
                        Wait(0)
                    end
                end)

                -- Create stress relief thread
                CreateThread(function()
                    while activeMovies[projection] and displayActive do
                        if not projectionData.radius or (Vdist(GetEntityCoords(PlayerPedId()), projectionData.audiencePos) <= projectionData.radius) then
                            -- Changed from fx-hud to RSG-Core stress system
                            exports['fx-hud']:setStatus("stress",-3)
                        end
                        Wait(stressReliefInterval)
                    end
                end)

                -- Sync movie state to other players
                TriggerServerEvent("rsg-cinema:syncMovieState", projection, movie, true)

                while IsStreamPlaying(stream) do
                    Wait(1000)
                end

                -- Remove show from active shows and movies
                activeShows[projection] = nil
                activeMovies[projection] = nil
                displayActive = false
                
                -- Sync movie end to other players
                TriggerServerEvent("rsg-cinema:syncMovieState", projection, movie, false)

                CleanupMovie(movieData, stream, projectionData.renderTarget)
            end
        end
    else
        if Config.Shows[show] then
            local showData = Config.Shows[show]

            -- Add show to active shows
            activeShows[show] = {
                type = "SHOW",
                startTime = GetGameTimer(),
                viewers = {}
            }

            -- Create stress relief thread for shows
            CreateThread(function()
                while activeShows[show] do
                    local playerPos = GetEntityCoords(PlayerPedId())
                    for location, curtainPos in pairs(Config.Curtains) do
                        local dist = Vdist(playerPos, curtainPos)
                        if dist <= 15.0 then
                            -- Changed from fx-hud to RSG-Core stress system
                            TriggerEvent('rsg-stress:client:reduceStress', 4)
                            break -- Exit loop after first curtain in range
                        end
                    end
                    Wait(stressReliefInterval)
                end
            end)

            -- Sync show start to other players
            TriggerServerEvent("rsg-cinema:syncShowState", show, true)

            local animscene = Citizen.InvokeNative(0x1FCA98E33C1437B3, 
                showData.animscene[1], 
                showData.animscene[2], 
                showData.animscene[3], 
                showData.animscene[4], 
                showData.animscene[5]
            )

            if animscene then
                if showData.position then
                    SetAnimSceneOrigin(animscene, showData.position, showData.rotation, 2)
                end

                local showEntities = {}
                for _, entity in pairs(showData.entities) do
                    if IsModelInCdimage(entity.model) or type(entity.model) == "string" then
                        if IsModelInCdimage(entity.model) then
                            while not HasModelLoaded(entity.model) do 
                                RequestModel(entity.model)
                                Wait(10) 
                            end
                        end

                        local handle
                        if IsModelAPed(entity.model) then
                            handle = CreatePed(entity.model, vector3(0.0, 0.0, -500.0), 0.0, false, false, true, true)
                            Citizen.InvokeNative(0x283978A15512B2FE, handle, true)
                            
                            if entity.flags then
                                for _, flag in pairs(entity.flags) do
                                    SetPedConfigFlag(handle, flag, true)
                                end
                            end
                            
                            if entity.ragdoll ~= nil then
                                SetPedCanRagdoll(handle, false)
                            end
                            
                            if entity.ragdollFlag then
                                SetRagdollBlockingFlags(handle, entity.ragdollFlag)
                            end
                            
                        elseif type(entity.model) == "string" then
                            if IsWeaponValid(GetHashKey(entity.model)) then
                                handle = Citizen.InvokeNative(0x9888652B8BA77F73, GetHashKey(entity.model), 0, vector3(0.0, 0.0, 0.0), true, 1.0)
                            end
                        else
                            handle = CreateObject(entity.model, vector3(0.0, 0.0, -500.0), false, false, false, true, true)
                        end

                        SetAnimSceneEntity(animscene, entity.fields[1], handle, entity.fields[2])
                        SetModelAsNoLongerNeeded(entity.model)
                        table.insert(showEntities, handle)
                    end
                end

                LoadAnimScene(animscene)
                while not Citizen.InvokeNative(0x477122B8D05E7968, animscene, 1, 0) do Wait(10) end
                StartAnimScene(animscene)

                if showData.curtain then
                    local curtain = Config.Curtains[showData.curtain]
                    if curtain then
                        -- Add curtain logic here
                    end
                end

                if showData.endAtProgress then
                    while Citizen.InvokeNative(0x3FBC3F51BF12DFBF, animscene, Citizen.ResultAsFloat()) < showData.endAtProgress do
                        Wait(100)
                    end
                end

                -- Remove show from active shows
                activeShows[show] = nil
                -- Sync show end to other players
                TriggerServerEvent("rsg-cinema:syncShowState", show, false)

                for _, entity in ipairs(showEntities) do
                    if DoesEntityExist(entity) then
                        DeleteEntity(entity)
                    end
                end

                if animscene then
                    DeleteAnimScene(animscene)
                end
            end
        end
    end
end

function CleanupMovie(movieData, stream, renderTarget)
    SetTvChannel(-1)
    SetTextRenderId(0)
    if DoesEntityExist(movieData.screen) then
        DeleteEntity(movieData.screen)
    end
    if IsStreamPlaying(stream) then
        StopStream(stream)
    end
    if IsNamedRendertargetRegistered(renderTarget) then
        ReleaseNamedRendertarget(renderTarget)
    end
end

function IsMovieValid(projection, movie)
    return Config.Projections[projection] and Config.Movies[movie]
end

-- Event to sync movie state between players
RegisterNetEvent("rsg-cinema:syncMovieState")
AddEventHandler("rsg-cinema:syncMovieState", function(projection, movie, isStarting)
    if isStarting then
        if not activeShows[projection] and not activeMovies[projection] then
            StartShow("MOVIE", projection, movie)
            displayActive = true
        end
    else
        displayActive = false
    end
end)

-- Event to sync display state between players
RegisterNetEvent("rsg-cinema:syncDisplayState")
AddEventHandler("rsg-cinema:syncDisplayState", function(projection, isActive)
    displayActive = isActive
end)

-- Event to sync show state between players
RegisterNetEvent("rsg-cinema:syncShowState")
AddEventHandler("rsg-cinema:syncShowState", function(show, isStarting)
    if isStarting then
        if not activeShows[show] then
            StartShow(show)
        end
    end
end)

RegisterNetEvent("rsg-cinema:startMovie")
AddEventHandler("rsg-cinema:startMovie", function(show, location)
    if Config.Movies[show] and Config.Projections[location] then
        StartShow("MOVIE", location, show)
    elseif Config.Shows[show] then
        StartShow(show)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    for location, data in pairs(CreatedVendors) do
        if DoesEntityExist(data.ped) then
            DeleteEntity(data.ped)
        end
    end
end)