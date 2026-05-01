-------------------
-- CONFIG --
-------------------
Config = {}

-- Framework Settings
Config.Framework = 'auto' -- Options: 'auto', 'qbcore', 'esx' (auto will detect automatically)

-- Command Settings
Config.Command = 'callems' -- Command to call AI doctor (changed from 'help' for clarity)

-- EMS Availability Settings
Config.MinEMS = 1 -- Minimum number of online EMS required before AI doctor is available (0 = always available)
Config.EMSJob = 'ambulance' -- Job name for EMS/Ambulance personnel

-- Payment Settings
Config.Price = 2000 -- Price for AI doctor service
Config.PaymentAccount = 'cash' -- Options: 'cash', 'bank', 'both' (both will try cash first, then bank)
Config.SendToSociety = true -- If true, payment goes to ambulance society account
Config.SocietyAccount = 'ambulance' -- Society/job account name to receive payment

-- Doctor Vehicle Settings
Config.VehicleModel = 'ambulance' -- Vehicle model to spawn
Config.VehiclePlate = 'DOCTOR' -- License plate for doctor vehicle
Config.SpawnDistance = 40.0 -- Distance from player to spawn vehicle (in GTA units)
Config.SpawnOffset = 5.0 -- Height offset for vehicle spawn to avoid spawning in ground

-- Doctor NPC Settings
Config.DoctorPed = 's_m_m_doctor_01' -- Ped model for the doctor
Config.DoctorSpeed = 20.0 -- Driving speed for doctor (in m/s)
Config.DoctorDrivingStyle = 786603 -- Driving style flags (786603 = normal, cautious)

-- Proximity Settings
Config.ApproachDistance = 15.0 -- Distance at which doctor starts walking to player
Config.TreatmentDistance = 1.8 -- Distance at which treatment begins

-- Smart Navigation Settings (anti-stuck system)
Config.RetargetThreshold = 3.0    -- Refresh doctor's destination if player moves more than this many meters
Config.StuckSpeedThreshold = 0.5  -- Velocity (m/s) below this counts as "not moving" for stuck detection
Config.StuckTimeVehicle = 6.0     -- Seconds vehicle must be stationary (and not at target) before recovery
Config.StuckTimeWalking = 4.0     -- Seconds ped must be stationary (and not at target) before recovery
Config.OverallTimeout = 90.0      -- Max seconds for the entire dispatch before forced teleport (0 = disabled)
Config.MaxSpawnAttempts = 6       -- How many spawn-point candidates to try before giving up
Config.SpawnSearchExpansion = 1.5 -- Multiplier applied to spawn radius after each failed attempt
Config.TeleportRecovery = true    -- If true, teleport ped/vehicle near player when stuck instead of giving up
Config.AllowCancelCommand = true  -- Allow /cancelems to abort a stuck dispatch
Config.CancelCommand = 'cancelems'

-- Treatment Settings
Config.ReviveTime = 20000 -- Time for revival process in milliseconds
Config.ReviveSystem = 'auto' -- Options: 'auto', 'wasabi', 'qbcore', 'esx', 'custom'
Config.CustomReviveEvent = nil -- Custom client event name for revival (only used if ReviveSystem = 'custom')

-- Animation Settings
Config.DoctorAnimation = {
    dict = 'mini@cpr@char_a@cpr_str',
    anim = 'cpr_pumpchest'
}

-- Blip Settings
Config.ShowBlip = true -- Show blip for doctor vehicle
Config.BlipSprite = 50 -- Blip sprite ID (50 = waypoint)
Config.BlipColor = 5 -- Blip color (5 = yellow)
Config.BlipFlash = true -- Make blip flash

-- Sound Settings
Config.PlayArrivalSound = true -- Play sound when doctor arrives
Config.ArrivalSound = {
    name = 'Text_Arrive_Tone',
    set = 'Phone_SoundSet_Default'
}

-- Notification Settings
Config.UseOxLib = true -- Try to use ox_lib for notifications/progress (falls back to framework if not available)

-- Cooldown Settings
Config.Cooldown = 300 -- Cooldown in seconds between AI doctor calls (300 = 5 minutes)

-- Debug Settings
Config.Debug = true -- Enable debug prints

-- Locale/Messages
Config.Locale = {
    ['not_dead'] = 'You are not dead or injured!',
    ['ems_available'] = 'There are EMS personnel available! Call them first.',
    ['not_enough_money'] = 'You don\'t have enough money for the AI doctor service ($%s required)',
    ['doctor_called'] = 'AI Doctor has been called! Please wait...',
    ['treatment_progress'] = 'The doctor is giving you medical aid...',
    ['treatment_complete'] = 'Treatment completed! You have been revived.',
    ['on_cooldown'] = 'AI Doctor is busy! Please wait %s seconds before calling again.',
    ['doctor_arriving'] = 'The AI Doctor is on their way to your location.',
    ['doctor_rerouting'] = 'The AI Doctor is rerouting to your new location...',
    ['doctor_stuck']    = 'The AI Doctor is having trouble reaching you - finding another way...',
    ['doctor_failed']   = 'The AI Doctor could not reach your location. Cooldown waived.',
    ['call_cancelled']  = 'AI Doctor dispatch cancelled.',
    ['no_active_call']  = 'You don\'t have an active AI Doctor call.'
}
