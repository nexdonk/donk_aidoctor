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

local Active = false
local DoctorVehicle = nil
local DoctorPed = nil
local DoctorBlip = nil
local ProcessingCall = false

local function DebugPrint(...)
    if Config.Debug then
        print('[donk_aidoctor]', ...)
    end
end

local function FormatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

RegisterCommand(Config.Command, function(source, args, raw)
    if not Framework or not Framework.Type or not Framework.Object then
        print('[donk_aidoctor] Framework not initialized yet!')
        return
    end

    if ProcessingCall then
        Framework.Notify(Config.Locale['doctor_called'], 'info')
        return
    end

    if not Framework.IsPlayerDead() then
        Framework.Notify(Config.Locale['not_dead'], 'error')
        return
    end

    ProcessingCall = true
    DebugPrint('Player calling AI doctor...')

    Framework.TriggerCallback('donk_aidoctor:docOnline', function(canCall, hasEnoughMoney, reason, extraData)
        if canCall and hasEnoughMoney and reason == 'success' then
            DebugPrint('All checks passed - spawning doctor')
            SpawnDoctor(GetEntityCoords(PlayerPedId()))
            TriggerServerEvent('donk_aidoctor:charge')
            Framework.Notify(Config.Locale['doctor_called'], 'success')
        else
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

function SpawnDoctor(playerPos)
    DebugPrint('Spawning doctor vehicle and NPC...')

    local vehicleHash = GetHashKey(Config.VehicleModel)
    RequestModel(vehicleHash)
    while not HasModelLoaded(vehicleHash) do
        Wait(10)
    end

    local pedHash = GetHashKey(Config.DoctorPed)
    RequestModel(pedHash)
    while not HasModelLoaded(pedHash) do
        Wait(10)
    end

    local spawnRadius = Config.SpawnDistance
    local found, spawnPos, spawnHeading = GetClosestVehicleNodeWithHeading(
        playerPos.x + math.random(-spawnRadius, spawnRadius),
        playerPos.y + math.random(-spawnRadius, spawnRadius),
        playerPos.z,
        0, 3, 0
    )

    if not found then
        DebugPrint('Could not find vehicle node, using random position')
        spawnPos = vector3(
            playerPos.x + math.random(-spawnRadius, spawnRadius),
            playerPos.y + math.random(-spawnRadius, spawnRadius),
            playerPos.z
        )
        spawnHeading = math.random(0, 359)
    end

    if DoctorVehicle and DoesEntityExist(DoctorVehicle) then
        DeleteEntity(DoctorVehicle)
    end
    if DoctorPed and DoesEntityExist(DoctorPed) then
        DeleteEntity(DoctorPed)
    end

    DoctorVehicle = CreateVehicle(vehicleHash, spawnPos.x, spawnPos.y, spawnPos.z + Config.SpawnOffset, spawnHeading, true, false)
    ClearAreaOfVehicles(GetEntityCoords(DoctorVehicle), 5.0, false, false, false, false, false)
    SetVehicleOnGroundProperly(DoctorVehicle)
    SetVehicleNumberPlateText(DoctorVehicle, Config.VehiclePlate)
    SetEntityAsMissionEntity(DoctorVehicle, true, true)
    SetVehicleEngineOn(DoctorVehicle, true, true, false)

    DebugPrint('Doctor vehicle spawned at', spawnPos)

    DoctorPed = CreatePedInsideVehicle(DoctorVehicle, 26, pedHash, -1, true, false)
    SetEntityAsMissionEntity(DoctorPed, true, true)
    SetBlockingOfNonTemporaryEvents(DoctorPed, true)
    SetPedFleeAttributes(DoctorPed, 0, false)

    DebugPrint('Doctor NPC created')

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

    if Config.PlayArrivalSound then
        PlaySoundFrontend(-1, Config.ArrivalSound.name, Config.ArrivalSound.set, 1)
    end

    Wait(2000)

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

    Active = true
    ProcessingCall = false
end

Citizen.CreateThread(function()
    local hasExitedVehicle = false

    while true do
        Citizen.Wait(500)

        if Active and DoctorVehicle and DoctorPed then
            if not DoesEntityExist(DoctorVehicle) or not DoesEntityExist(DoctorPed) then
                DebugPrint('Doctor entities no longer exist - resetting state')
                CleanupDoctor()
                Active = false
                hasExitedVehicle = false
            else
                local playerPos = GetEntityCoords(PlayerPedId())
                local vehiclePos = GetEntityCoords(DoctorVehicle)
                local pedPos = GetEntityCoords(DoctorPed)

                local distToVehicle = #(playerPos - vehiclePos)
                local distToPed = #(playerPos - pedPos)

                if Config.Debug then
                    print(string.format('[donk_aidoctor] Dist to vehicle: %.2f | Dist to ped: %.2f', distToVehicle, distToPed))
                end

                if distToPed <= Config.TreatmentDistance then
                    DebugPrint('Doctor close enough - starting treatment')
                    Active = false
                    hasExitedVehicle = false
                    ClearPedTasksImmediately(DoctorPed)
                    StartTreatment()
                elseif distToVehicle <= Config.ApproachDistance then
                    if not hasExitedVehicle then
                        DebugPrint('Doctor within approach distance')

                        if IsPedInVehicle(DoctorPed, DoctorVehicle, false) then
                            TaskLeaveVehicle(DoctorPed, DoctorVehicle, 0)
                            DebugPrint('Doctor exiting vehicle')
                            hasExitedVehicle = true
                            Citizen.Wait(3000)
                        else
                            hasExitedVehicle = true
                        end
                    end

                    if hasExitedVehicle then
                        TaskGoToCoordAnyMeans(
                            DoctorPed,
                            playerPos.x,
                            playerPos.y,
                            playerPos.z,
                            1.0, 0, 0,
                            786603,
                            0xbf800000
                        )
                    end
                end
            end
        else
            hasExitedVehicle = false
        end
    end
end)

function StartTreatment()
    DebugPrint('Starting treatment sequence')

    local animDict = Config.DoctorAnimation.dict
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Citizen.Wait(100)
    end

    TaskPlayAnim(
        DoctorPed,
        animDict,
        Config.DoctorAnimation.anim,
        1.0, 1.0, -1, 9, 1.0, 0, 0, 0
    )

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

                ClearPedTasks(DoctorPed)
                Wait(500)

                TriggerServerEvent("donk_aidoctor:revivePlayer")

                StopScreenEffect('DeathFailOut')

                local message = string.format("%s ($%s)", Config.Locale['treatment_complete'], Config.Price)
                Framework.Notify(message, 'success')

                CleanupDoctor()

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

function CleanupDoctor()
    DebugPrint('Cleaning up doctor entities')

    if DoctorBlip and DoesBlipExist(DoctorBlip) then
        RemoveBlip(DoctorBlip)
        DoctorBlip = nil
    end

    if DoctorPed and DoesEntityExist(DoctorPed) then
        SetEntityAsNoLongerNeeded(DoctorPed)
        DeleteEntity(DoctorPed)
        DoctorPed = nil
    end

    if DoctorVehicle and DoesEntityExist(DoctorVehicle) then
        SetEntityAsNoLongerNeeded(DoctorVehicle)
        DeleteEntity(DoctorVehicle)
        DoctorVehicle = nil
    end

    Active = false
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupDoctor()
    end
end)

DebugPrint('Client script loaded successfully')
