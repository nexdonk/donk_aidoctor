-- =============================================================
-- donk_aidoctor :: client
-- Smart AI EMS dispatch with state machine, live retargeting,
-- stuck detection, and recovery ladder so the doctor never
-- gets lost or stuck on the way to a downed player.
-- =============================================================

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

-- ---------- State ----------
local STATE = {
    IDLE      = 'idle',
    DISPATCH  = 'dispatch',
    DRIVING   = 'driving',
    DEBOARD   = 'deboard',
    WALKING   = 'walking',
    TREATING  = 'treating',
    DONE      = 'done',
}

local Doctor = {
    state         = STATE.IDLE,
    vehicle       = nil,
    ped           = nil,
    blip          = nil,
    lastTargetPos = nil,   -- last position the doctor was tasked toward
    stuckTimer    = 0.0,   -- accumulated seconds of low-velocity while not arrived
    stateStarted  = 0,     -- GetGameTimer() ms when current state began
    dispatchStart = 0,     -- GetGameTimer() ms when the call was placed
    recoveryUsed  = 0,     -- how many recovery teleports already burned
}

local ProcessingCall = false

-- ---------- Helpers ----------
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

local function SetState(newState)
    if Doctor.state == newState then return end
    DebugPrint(string.format('STATE: %s -> %s', Doctor.state, newState))
    Doctor.state = newState
    Doctor.stateStarted = GetGameTimer()
    Doctor.stuckTimer = 0.0
end

local function GetSpeed(entity)
    if not entity or not DoesEntityExist(entity) then return 0.0 end
    local v = GetEntityVelocity(entity)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Validate a candidate spawn coord: must be near ground, not in water, reasonable distance.
local function ValidateSpawnPoint(coord, playerPos)
    -- Reject if too far from player vertically (probably wrong floor / inside building)
    if math.abs(coord.z - playerPos.z) > 25.0 then
        return false
    end

    -- Reject if in water
    local _, waterHeight = GetWaterHeight(coord.x, coord.y, coord.z)
    if waterHeight and waterHeight > coord.z - 0.5 then
        return false
    end

    return true
end

-- Find a road node near a target position with retries and ground correction.
local function FindGoodSpawnPoint(playerPos)
    local baseRadius = Config.SpawnDistance
    local attempts = Config.MaxSpawnAttempts or 6

    for i = 1, attempts do
        local radius = baseRadius * math.pow(Config.SpawnSearchExpansion or 1.5, i - 1)
        local angle = math.random() * 2 * math.pi
        local sx = playerPos.x + math.cos(angle) * radius
        local sy = playerPos.y + math.sin(angle) * radius

        local found, nodePos, heading = GetClosestVehicleNodeWithHeading(sx, sy, playerPos.z, 1, 3.0, 0)
        if found then
            -- Snap Z to actual ground when possible
            local hitGround, groundZ = GetGroundZFor_3dCoord(nodePos.x, nodePos.y, nodePos.z + 2.0, false)
            if hitGround then
                nodePos = vector3(nodePos.x, nodePos.y, groundZ)
            end

            if ValidateSpawnPoint(nodePos, playerPos) then
                DebugPrint(string.format('Spawn candidate %d accepted at %.1f,%.1f,%.1f', i, nodePos.x, nodePos.y, nodePos.z))
                return nodePos, heading
            else
                DebugPrint(string.format('Spawn candidate %d rejected (validation)', i))
            end
        else
            DebugPrint(string.format('Spawn candidate %d: no road node', i))
        end
    end

    -- Fallback: just plop the vehicle at player.z + offset
    DebugPrint('All spawn candidates failed - using fallback near player')
    return vector3(playerPos.x + 8.0, playerPos.y + 8.0, playerPos.z), 0.0
end

local function CleanupDoctor()
    DebugPrint('Cleaning up doctor entities')

    if Doctor.blip and DoesBlipExist(Doctor.blip) then
        RemoveBlip(Doctor.blip)
    end
    if Doctor.ped and DoesEntityExist(Doctor.ped) then
        SetEntityAsNoLongerNeeded(Doctor.ped)
        DeleteEntity(Doctor.ped)
    end
    if Doctor.vehicle and DoesEntityExist(Doctor.vehicle) then
        SetEntityAsNoLongerNeeded(Doctor.vehicle)
        DeleteEntity(Doctor.vehicle)
    end

    Doctor.vehicle = nil
    Doctor.ped = nil
    Doctor.blip = nil
    Doctor.lastTargetPos = nil
    Doctor.recoveryUsed = 0
    SetState(STATE.IDLE)
end

local function AbortCall(reason, notifyPlayer, refund)
    DebugPrint('Aborting call:', reason)
    if notifyPlayer then
        Framework.Notify(Config.Locale['doctor_failed'], 'error')
    end
    CleanupDoctor()
    if refund then
        TriggerServerEvent('donk_aidoctor:dispatchFailed')
    end
    ProcessingCall = false
end

-- ---------- Models ----------
local function LoadModel(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end
    return HasModelLoaded(hash)
end

-- ---------- Spawning ----------
local function SpawnDoctor(playerPos)
    DebugPrint('Spawning doctor vehicle and NPC...')
    SetState(STATE.DISPATCH)

    local vehicleHash = GetHashKey(Config.VehicleModel)
    local pedHash = GetHashKey(Config.DoctorPed)

    if not LoadModel(vehicleHash) or not LoadModel(pedHash) then
        DebugPrint('ERROR: Failed to load required models')
        AbortCall('model load failed', true, true)
        return false
    end

    local spawnPos, spawnHeading = FindGoodSpawnPoint(playerPos)

    -- Clear traffic from spawn point BEFORE creating our vehicle (the original code did this after, which can delete the doctor's car)
    ClearAreaOfVehicles(spawnPos.x, spawnPos.y, spawnPos.z, 8.0, false, false, false, false, false)

    Doctor.vehicle = CreateVehicle(vehicleHash, spawnPos.x, spawnPos.y, spawnPos.z + (Config.SpawnOffset or 0.0), spawnHeading, true, false)
    if not DoesEntityExist(Doctor.vehicle) then
        DebugPrint('ERROR: vehicle did not spawn')
        AbortCall('vehicle spawn failed', true, true)
        return false
    end

    SetVehicleOnGroundProperly(Doctor.vehicle)
    SetVehicleNumberPlateText(Doctor.vehicle, Config.VehiclePlate)
    SetEntityAsMissionEntity(Doctor.vehicle, true, true)
    SetVehicleEngineOn(Doctor.vehicle, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(Doctor.vehicle, false)
    SetVehicleSiren(Doctor.vehicle, true)

    Doctor.ped = CreatePedInsideVehicle(Doctor.vehicle, 26, pedHash, -1, true, false)
    if not DoesEntityExist(Doctor.ped) then
        DebugPrint('ERROR: ped did not spawn')
        AbortCall('ped spawn failed', true, true)
        return false
    end

    SetEntityAsMissionEntity(Doctor.ped, true, true)
    SetBlockingOfNonTemporaryEvents(Doctor.ped, true)
    SetPedFleeAttributes(Doctor.ped, 0, false)
    SetPedCombatAttributes(Doctor.ped, 17, true)        -- always flee from threat... by not engaging
    SetPedCanRagdoll(Doctor.ped, false)                  -- don't trip on stairs
    SetPedCanBeKnockedOffVehicle(Doctor.ped, 1)
    SetDriverAbility(Doctor.ped, 1.0)
    SetDriverAggressiveness(Doctor.ped, 0.0)

    if Config.ShowBlip then
        Doctor.blip = AddBlipForEntity(Doctor.vehicle)
        SetBlipSprite(Doctor.blip, Config.BlipSprite)
        SetBlipColour(Doctor.blip, Config.BlipColor)
        if Config.BlipFlash then SetBlipFlashes(Doctor.blip, true) end
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("AI Doctor")
        EndTextCommandSetBlipName(Doctor.blip)
    end

    if Config.PlayArrivalSound then
        PlaySoundFrontend(-1, Config.ArrivalSound.name, Config.ArrivalSound.set, 1)
    end

    SetModelAsNoLongerNeeded(vehicleHash)
    SetModelAsNoLongerNeeded(pedHash)

    Doctor.dispatchStart = GetGameTimer()
    Doctor.recoveryUsed = 0

    -- Issue initial drive task toward the player.
    Doctor.lastTargetPos = playerPos
    TaskVehicleDriveToCoordLongrange(
        Doctor.ped,
        Doctor.vehicle,
        playerPos.x, playerPos.y, playerPos.z,
        Config.DoctorSpeed,
        Config.DoctorDrivingStyle,
        5.0
    )

    SetState(STATE.DRIVING)
    Framework.Notify(Config.Locale['doctor_arriving'], 'info')
    return true
end

-- ---------- Recovery actions ----------
-- Re-route: just refresh the drive task using the *current* player position.
local function ReissueDriveTask(playerPos)
    if not (Doctor.ped and Doctor.vehicle and DoesEntityExist(Doctor.ped) and DoesEntityExist(Doctor.vehicle)) then return end

    if not IsPedInVehicle(Doctor.ped, Doctor.vehicle, false) then
        -- Ped got out somehow - put them back in
        TaskWarpPedIntoVehicle(Doctor.ped, Doctor.vehicle, -1)
    end

    ClearPedTasks(Doctor.ped)
    Wait(50)
    TaskVehicleDriveToCoordLongrange(
        Doctor.ped,
        Doctor.vehicle,
        playerPos.x, playerPos.y, playerPos.z,
        Config.DoctorSpeed,
        Config.DoctorDrivingStyle,
        5.0
    )
    Doctor.lastTargetPos = playerPos
end

-- Teleport vehicle to a safe road node near the player (used when stuck driving).
local function TeleportVehicleNearPlayer(playerPos)
    if not Config.TeleportRecovery then return false end
    if not (Doctor.vehicle and DoesEntityExist(Doctor.vehicle)) then return false end

    local found, nodePos, heading = GetClosestVehicleNodeWithHeading(
        playerPos.x + math.random(-25, 25),
        playerPos.y + math.random(-25, 25),
        playerPos.z, 1, 3.0, 0
    )
    if not found then
        nodePos = vector3(playerPos.x + 10.0, playerPos.y + 10.0, playerPos.z)
        heading = 0.0
    end

    DebugPrint(string.format('RECOVERY: teleporting vehicle to %.1f,%.1f,%.1f', nodePos.x, nodePos.y, nodePos.z))
    SetEntityCoords(Doctor.vehicle, nodePos.x, nodePos.y, nodePos.z, false, false, false, false)
    SetEntityHeading(Doctor.vehicle, heading)
    SetVehicleOnGroundProperly(Doctor.vehicle)
    if Doctor.ped and not IsPedInVehicle(Doctor.ped, Doctor.vehicle, false) then
        TaskWarpPedIntoVehicle(Doctor.ped, Doctor.vehicle, -1)
    end
    Doctor.recoveryUsed = Doctor.recoveryUsed + 1
    Framework.Notify(Config.Locale['doctor_stuck'], 'info')
    return true
end

-- Teleport ped directly to player (final fallback for walking phase).
local function TeleportPedNearPlayer(playerPos)
    if not Config.TeleportRecovery then return false end
    if not (Doctor.ped and DoesEntityExist(Doctor.ped)) then return false end

    local angle = math.random() * 2 * math.pi
    local px = playerPos.x + math.cos(angle) * 2.5
    local py = playerPos.y + math.sin(angle) * 2.5
    local pz = playerPos.z

    local hit, gz = GetGroundZFor_3dCoord(px, py, pz + 2.0, false)
    if hit then pz = gz end

    DebugPrint('RECOVERY: teleporting ped near player')
    SetEntityCoords(Doctor.ped, px, py, pz, false, false, false, false)
    Doctor.recoveryUsed = Doctor.recoveryUsed + 1
    return true
end

-- ---------- State Machine Tick ----------
-- Forward declaration so TickWalking can call into the treatment routine.
local StartTreatment

local function TickDriving(playerPos, dt)
    if not (Doctor.vehicle and DoesEntityExist(Doctor.vehicle) and Doctor.ped and DoesEntityExist(Doctor.ped)) then
        AbortCall('vehicle/ped lost mid-drive', true, true)
        return
    end

    local vehiclePos = GetEntityCoords(Doctor.vehicle)
    local distToPlayer = #(playerPos - vehiclePos)

    -- Player moved enough to warrant a re-route
    if Doctor.lastTargetPos and #(playerPos - Doctor.lastTargetPos) > Config.RetargetThreshold then
        DebugPrint(string.format('Player moved %.1fm - rerouting', #(playerPos - Doctor.lastTargetPos)))
        ReissueDriveTask(playerPos)
    end

    -- Reached approach distance: switch to deboard
    if distToPlayer <= Config.ApproachDistance then
        SetState(STATE.DEBOARD)
        return
    end

    -- Stuck detection
    local speed = GetSpeed(Doctor.vehicle)
    if speed < Config.StuckSpeedThreshold then
        Doctor.stuckTimer = Doctor.stuckTimer + dt
    else
        Doctor.stuckTimer = 0.0
    end

    if Doctor.stuckTimer >= Config.StuckTimeVehicle then
        DebugPrint(string.format('Vehicle stuck for %.1fs - recovery', Doctor.stuckTimer))
        Doctor.stuckTimer = 0.0

        if Doctor.recoveryUsed == 0 then
            -- First recovery: just re-route
            ReissueDriveTask(playerPos)
            Doctor.recoveryUsed = 1
            Framework.Notify(Config.Locale['doctor_rerouting'], 'info')
        else
            -- Subsequent: teleport vehicle closer
            if TeleportVehicleNearPlayer(playerPos) then
                ReissueDriveTask(playerPos)
            end
        end
    end
end

local function TickDeboard(playerPos, dt)
    if not (Doctor.ped and DoesEntityExist(Doctor.ped)) then
        AbortCall('ped lost during deboard', true, true)
        return
    end

    -- If player ran far away again, get back in vehicle and drive
    if Doctor.vehicle and DoesEntityExist(Doctor.vehicle) then
        if #(playerPos - GetEntityCoords(Doctor.vehicle)) > Config.ApproachDistance + 10.0 then
            DebugPrint('Player moved away - returning to vehicle')
            TaskWarpPedIntoVehicle(Doctor.ped, Doctor.vehicle, -1)
            ReissueDriveTask(playerPos)
            SetState(STATE.DRIVING)
            return
        end
    end

    if IsPedInVehicle(Doctor.ped, Doctor.vehicle, false) then
        -- Issue exit task once (state-entry guarantees we only do this on transition)
        if (GetGameTimer() - Doctor.stateStarted) < 250 then
            TaskLeaveVehicle(Doctor.ped, Doctor.vehicle, 256) -- 256 = don't close door, exit immediately
        end
        -- Timeout: if still in vehicle after 6s, force them out
        if (GetGameTimer() - Doctor.stateStarted) > 6000 then
            DebugPrint('Forcing ped out of vehicle')
            ClearPedTasksImmediately(Doctor.ped)
            local p = GetEntityCoords(Doctor.vehicle)
            SetEntityCoords(Doctor.ped, p.x + 1.5, p.y, p.z, false, false, false, false)
        end
    else
        SetState(STATE.WALKING)
    end
end

local function TickWalking(playerPos, dt)
    if not (Doctor.ped and DoesEntityExist(Doctor.ped)) then
        AbortCall('ped lost during walk', true, true)
        return
    end

    local pedPos = GetEntityCoords(Doctor.ped)
    local distToPlayer = #(playerPos - pedPos)

    if distToPlayer <= Config.TreatmentDistance then
        ClearPedTasks(Doctor.ped)
        SetState(STATE.TREATING)
        StartTreatment()
        return
    end

    -- Re-issue task only when player moved (or first entry, or task was cleared)
    local needRetask = false
    if not Doctor.lastTargetPos then
        needRetask = true
    elseif #(playerPos - Doctor.lastTargetPos) > Config.RetargetThreshold then
        needRetask = true
    elseif (GetGameTimer() - Doctor.stateStarted) < 250 then
        needRetask = true
    end

    if needRetask then
        TaskGoToCoordAnyMeans(Doctor.ped, playerPos.x, playerPos.y, playerPos.z, 2.0, 0, false, 786603, 0xbf800000)
        Doctor.lastTargetPos = playerPos
    end

    -- Stuck detection on foot
    local speed = GetSpeed(Doctor.ped)
    if speed < Config.StuckSpeedThreshold then
        Doctor.stuckTimer = Doctor.stuckTimer + dt
    else
        Doctor.stuckTimer = 0.0
    end

    if Doctor.stuckTimer >= Config.StuckTimeWalking then
        DebugPrint(string.format('Ped stuck on foot for %.1fs - teleporting', Doctor.stuckTimer))
        Doctor.stuckTimer = 0.0
        TeleportPedNearPlayer(playerPos)
        ClearPedTasks(Doctor.ped)
        Doctor.lastTargetPos = nil -- force retask next tick
    end
end

-- ---------- Treatment ----------
StartTreatment = function()
    DebugPrint('Starting treatment sequence')

    if not (Doctor.ped and DoesEntityExist(Doctor.ped)) then
        AbortCall('ped lost before treatment', true, true)
        return
    end

    local animDict = Config.DoctorAnimation.dict
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do
        Citizen.Wait(50)
    end

    -- Face the player
    local playerPos = GetEntityCoords(PlayerPedId())
    TaskTurnPedToFaceCoord(Doctor.ped, playerPos.x, playerPos.y, playerPos.z, 1000)
    Wait(800)

    TaskPlayAnim(Doctor.ped, animDict, Config.DoctorAnimation.anim, 1.0, 1.0, -1, 9, 1.0, 0, 0, 0)

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
                if Doctor.ped and DoesEntityExist(Doctor.ped) then
                    ClearPedTasks(Doctor.ped)
                end
                Wait(500)
                TriggerServerEvent("donk_aidoctor:revivePlayer")
                StopScreenEffect('DeathFailOut')
                local message = string.format("%s ($%s)", Config.Locale['treatment_complete'], Config.Price)
                Framework.Notify(message, 'success')
                CleanupDoctor()
                ProcessingCall = false
            else
                DebugPrint('Treatment cancelled')
                CleanupDoctor()
                ProcessingCall = false
            end
        end
    )
end

-- ---------- Main loop ----------
Citizen.CreateThread(function()
    local lastTick = GetGameTimer()
    while true do
        Citizen.Wait(250)
        local now = GetGameTimer()
        local dt = (now - lastTick) / 1000.0
        lastTick = now

        if Doctor.state == STATE.IDLE then
            -- nothing to do
        else
            local playerPos = GetEntityCoords(PlayerPedId())

            -- Overall dispatch timeout (safety net)
            if Config.OverallTimeout and Config.OverallTimeout > 0 then
                local elapsed = (now - Doctor.dispatchStart) / 1000.0
                if elapsed > Config.OverallTimeout and Doctor.state ~= STATE.TREATING then
                    DebugPrint(string.format('Overall timeout %.1fs reached - forced recovery', elapsed))
                    -- Skip to walking by warping ped near player
                    if Doctor.ped and DoesEntityExist(Doctor.ped) then
                        TeleportPedNearPlayer(playerPos)
                        ClearPedTasks(Doctor.ped)
                        Doctor.lastTargetPos = nil
                        Doctor.dispatchStart = now -- reset so we don't spam
                        SetState(STATE.WALKING)
                    else
                        AbortCall('overall timeout, no ped', true, true)
                    end
                end
            end

            if Doctor.state == STATE.DRIVING then
                TickDriving(playerPos, dt)
            elseif Doctor.state == STATE.DEBOARD then
                TickDeboard(playerPos, dt)
            elseif Doctor.state == STATE.WALKING then
                TickWalking(playerPos, dt)
            elseif Doctor.state == STATE.TREATING then
                -- treatment is driven by ShowProgress callback; nothing to do here
            end

            if Config.Debug and Doctor.state ~= STATE.IDLE and Doctor.state ~= STATE.TREATING then
                if Doctor.vehicle and DoesEntityExist(Doctor.vehicle) then
                    local vp = GetEntityCoords(Doctor.vehicle)
                    print(string.format('[donk_aidoctor] state=%s veh_dist=%.1f stuck=%.1fs',
                        Doctor.state, #(playerPos - vp), Doctor.stuckTimer))
                end
            end
        end
    end
end)

-- ---------- Commands ----------
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
            local ok = SpawnDoctor(GetEntityCoords(PlayerPedId()))
            if ok then
                TriggerServerEvent('donk_aidoctor:charge')
                Framework.Notify(Config.Locale['doctor_called'], 'success')
            end
            -- if not ok, SpawnDoctor already aborted and reset ProcessingCall
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

if Config.AllowCancelCommand then
    RegisterCommand(Config.CancelCommand, function()
        if not ProcessingCall and Doctor.state == STATE.IDLE then
            Framework.Notify(Config.Locale['no_active_call'], 'error')
            return
        end
        Framework.Notify(Config.Locale['call_cancelled'], 'info')
        AbortCall('player cancelled', false, true)
    end)
end

-- ---------- Cleanup ----------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupDoctor()
    end
end)

DebugPrint('Client script loaded successfully')
