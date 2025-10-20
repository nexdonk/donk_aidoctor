-- Initialize framework with retry logic
Citizen.CreateThread(function()
    local maxRetries = 10
    local retries = 0

    while not Framework.Object and retries < maxRetries do
        Framework.Init()
        if Framework.Object then
            print('[donk_aidoctor] Framework initialized: ' .. (Framework.Type or 'unknown'))
            break
        end
        retries = retries + 1
        Citizen.Wait(1000)
    end

    if not Framework.Object then
        print('[donk_aidoctor] ERROR: Failed to initialize framework after ' .. maxRetries .. ' attempts! Script will not work.')
    end
end)

-- State variables
local Active = false
local DoctorVehicle = nil
local DoctorPed = nil
local DoctorBlip = nil
local ProcessingCall = false

-- Debug print helper
local function DebugPrint(...)
    if Config.Debug then
        print('[donk_aidoctor]', ...)
    end
end

-- Helper function to format time
local function FormatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Register command to call AI doctor
RegisterCommand(Config.Command, function(source, args, raw)
    -- Check if framework is initialized
    if not Framework or not Framework.Type or not Framework.Object then
        print('[donk_aidoctor] Framework not initialized yet!')
        return
    end

    -- Check if player is loaded
    if Framework.IsPlayerLoaded and not Framework.IsPlayerLoaded() then
        lib.notify({
            title = 'AI Doctor',
            description = 'Please wait for your character to load',
            type = 'error'
        })
        return
    end

    -- Prevent spam
    if ProcessingCall then
        Framework.Notify(Config.Locale['doctor_called'], 'info')
        return
    end

    -- Check if player is dead
    if not Framework.IsPlayerDead() then
        Framework.Notify(Config.Locale['not_dead'], 'error')
        return
    end

    ProcessingCall = true
    DebugPrint('Player calling AI doctor...')

    -- Check with server if doctor is available
    Framework.TriggerCallback('donk_aidoctor:docOnline', function(canCall, hasEnoughMoney, reason, extraData)
        if canCall and hasEnoughMoney and reason == 'success' then
            -- All checks passed - spawn doctor
            DebugPrint('All checks passed - spawning doctor')
            SpawnDoctor(GetEntityCoords(PlayerPedId()))
            TriggerServerEvent('donk_aidoctor:charge')
            Framework.Notify(Config.Locale['doctor_called'], 'success')
        else
            -- Handle different failure reasons
            if reason == 'cooldown' then
                local timeLeft = extraData or 0
                local message = string.format(Config.Locale['on_cooldown'], FormatTime(timeLeft))
                Framework.Notify(message, 'error')
            elseif reason == 'ems_available' then
                Framework.Notify(Config.Locale['ems_available'], 'error')
            elseif reason == 'no_money' then
                local message = string.format(Config.Locale['not_enough_money'], Config.Price)
                Framework.Notify(message, 'error')
            else
                Framework.Notify('AI Doctor is not available at this time.', 'error')
            end
            ProcessingCall = false
        end
    end)
end)

-- Spawn doctor vehicle and NPC
function SpawnDoctor(playerPos)
    DebugPrint('Spawning doctor vehicle and NPC...')

    -- Request vehicle model
    local vehicleHash = GetHashKey(Config.VehicleModel)
    RequestModel(vehicleHash)
    while not HasModelLoaded(vehicleHash) do
        Wait(10)
    end

    -- Request ped model
    local pedHash = GetHashKey(Config.DoctorPed)
    RequestModel(pedHash)
    while not HasModelLoaded(pedHash) do
        Wait(10)
    end

    -- Find spawn position
    local spawnRadius = Config.SpawnDistance
    local found, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(
        playerPos.x + math.random(-spawnRadius, spawnRadius),
        playerPos.y + math.random(-spawnRadius, spawnRadius),
        playerPos.z,
        0, 3, 0
    )

    if not found then
        DebugPrint('Warning: Could not find vehicle node, using random position')
        spawnPos = vector3(
            playerPos.x + math.random(-spawnRadius, spawnRadius),
            playerPos.y + math.random(-spawnRadius, spawnRadius),
            playerPos.z
        )
        spawnHeading = math.random(0, 359)
    end

    -- Ensure vehicle doesn't already exist (cleanup old one if it does)
    if DoctorVehicle and DoesEntityExist(DoctorVehicle) then
        DeleteEntity(DoctorVehicle)
    end
    if DoctorPed and DoesEntityExist(DoctorPed) then
        DeleteEntity(DoctorPed)
    end

    -- Create vehicle
    DoctorVehicle = CreateVehicle(vehicleHash, spawnPos.x, spawnPos.y, spawnPos.z + Config.SpawnOffset, spawnHeading, true, false)
    ClearAreaOfVehicles(GetEntityCoords(DoctorVehicle), 5.0, false, false, false, false, false)
    SetVehicleOnGroundProperly(DoctorVehicle)
    SetVehicleNumberPlateText(DoctorVehicle, Config.VehiclePlate)
    SetEntityAsMissionEntity(DoctorVehicle, true, true)
    SetVehicleEngineOn(DoctorVehicle, true, true, false)

    DebugPrint('Doctor vehicle spawned at', spawnPos)

    -- Create doctor NPC in vehicle
    DoctorPed = CreatePedInsideVehicle(DoctorVehicle, 26, pedHash, -1, true, false)
    SetEntityAsMissionEntity(DoctorPed, true, true)
    SetBlockingOfNonTemporaryEvents(DoctorPed, true)
    SetPedFleeAttributes(DoctorPed, 0, false)

    DebugPrint('Doctor NPC created')

    -- Create blip if configured
    if Config.ShowBlip then
        DoctorBlip = AddBlipForEntity(DoctorVehicle)
        SetBlipSprite(DoctorBlip, Config.BlipSprite)
        SetBlipColour(DoctorBlip, Config.BlipColor)
        if Config.BlipFlash then
            SetBlipFlashes(DoctorBlip, true)
        end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("AI Doctor")
        EndTextCommandSetBlipName(DoctorBlip)
    end

    -- Play arrival sound if configured
    if Config.PlayArrivalSound then
        PlaySoundFrontend(-1, Config.ArrivalSound.name, Config.ArrivalSound.set, 1)
    end

    -- Wait a moment before driving
    Wait(2000)

    -- Task doctor to drive to player
    TaskVehicleDriveToCoord(
        DoctorPed,
        DoctorVehicle,
        playerPos.x,
        playerPos.y,
        playerPos.z,
        Config.DoctorSpeed,
        0,
        GetEntityModel(DoctorVehicle),
        Config.DoctorDrivingStyle,
        2.0
    )

    DebugPrint('Doctor driving to player location')

    -- Set active state
    Active = true
    ProcessingCall = false
end

-- Main thread to monitor doctor proximity
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        if Active and DoctorVehicle and DoctorPed then
            if not DoesEntityExist(DoctorVehicle) or not DoesEntityExist(DoctorPed) then
                DebugPrint('Doctor entities no longer exist - resetting state')
                CleanupDoctor()
                Active = false
            else
                local playerPos = GetEntityCoords(PlayerPedId())
                local vehiclePos = GetEntityCoords(DoctorVehicle)
                local pedPos = GetEntityCoords(DoctorPed)

                local distToVehicle = #(playerPos - vehiclePos)
                local distToPed = #(playerPos - pedPos)

                -- When vehicle is within approach distance, make doctor walk to player
                if distToVehicle <= Config.ApproachDistance then
                    TaskGoToCoordAnyMeans(
                        DoctorPed,
                        playerPos.x,
                        playerPos.y,
                        playerPos.z,
                        1.0, 0, 0,
                        Config.DoctorDrivingStyle,
                        0xbf800000
                    )

                    -- When doctor is close enough, start treatment
                    if distToPed <= Config.TreatmentDistance then
                        Active = false
                        ClearPedTasksImmediately(DoctorPed)
                        StartTreatment()
                    end
                end
            end
        end
    end
end)

-- Start treatment sequence
function StartTreatment()
    DebugPrint('Starting treatment sequence')

    -- Load animation dictionary
    local animDict = Config.DoctorAnimation.dict
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Citizen.Wait(100)
    end

    -- Play CPR animation on doctor
    TaskPlayAnim(
        DoctorPed,
        animDict,
        Config.DoctorAnimation.anim,
        1.0, 1.0, -1, 9, 1.0, 0, 0, 0
    )

    -- Show progress bar
    Framework.ShowProgress(
        Config.Locale['treatment_progress'],
        Config.ReviveTime,
        {
            name = "revive_doc",
            disableMovement = false,
            disableCarMovement = false,
            disableMouse = false,
            disableCombat = true,
            useWhileDead = true,
            canCancel = false,
            anim = {}
        },
        function(completed)
            if completed then
                DebugPrint('Treatment completed')

                -- Clear doctor animation
                ClearPedTasks(DoctorPed)
                Wait(500)

                -- Trigger revive on server
                TriggerServerEvent("donk_aidoctor:revivePlayer")

                -- Stop death effects
                StopScreenEffect('DeathFailOut')

                -- Notify player
                local message = string.format("%s ($%s)", Config.Locale['treatment_complete'], Config.Price)
                Framework.Notify(message, 'success')

                -- Cleanup
                CleanupDoctor()

                -- Reset spam protection after delay
                Wait(5000)
                ProcessingCall = false
            else
                DebugPrint('Treatment cancelled')
                CleanupDoctor()
                ProcessingCall = false
            end
        end
    )
end

-- Cleanup doctor entities
function CleanupDoctor()
    DebugPrint('Cleaning up doctor entities')

    -- Remove blip
    if DoctorBlip and DoesBlipExist(DoctorBlip) then
        RemoveBlip(DoctorBlip)
        DoctorBlip = nil
    end

    -- Delete ped gracefully
    if DoctorPed and DoesEntityExist(DoctorPed) then
        SetEntityAsNoLongerNeeded(DoctorPed)
        DeleteEntity(DoctorPed)
        DoctorPed = nil
    end

    -- Delete vehicle
    if DoctorVehicle and DoesEntityExist(DoctorVehicle) then
        SetEntityAsNoLongerNeeded(DoctorVehicle)
        DeleteEntity(DoctorVehicle)
        DoctorVehicle = nil
    end

    Active = false
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupDoctor()
    end
end)

DebugPrint('Client script loaded successfully')
