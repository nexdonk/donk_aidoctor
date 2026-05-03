-------------------
-- CONFIG --
-------------------
Config = {}

-- Framework Settings
Config.Framework = 'auto' -- Options: 'auto', 'qbcore', 'esx' (auto will detect automatically)

-- Command Settings
Config.Command = 'aidoctor' -- Command to call AI doctor (changed from 'help' for clarity)

-- EMS Availability Settings
Config.MinEMS = 0 -- Minimum number of online EMS required before AI doctor is available (0 = always available)
Config.EMSJob = 'ambulance' -- Job name for EMS/Ambulance personnel

-- Payment Settings
Config.Price = 2000 -- Price for AI doctor service
Config.PaymentAccount = 'cash' -- Options: 'cash', 'bank', 'both' (both will try cash first, then bank)
Config.SendToSociety = true -- If true, payment goes to ambulance society account
Config.SocietyAccount = 'ambulance' -- Society/job account name to receive payment

-- Doctor Vehicle Settings
Config.VehicleModel = 'ambulance' -- Vehicle model to spawn
Config.VehiclePlate = 'DOCTOR' -- License plate for doctor vehicle
Config.SpawnDistance = 75.0 -- Distance from player to spawn vehicle when no hospital is configured/available (in GTA units)
Config.SpawnOffset = 5.0 -- Height offset for vehicle spawn to avoid spawning in ground
Config.SpawnZThreshold = 8.0 -- Max vertical (Z) difference between player and chosen road node when falling back to nearby spawn. Prevents the doctor spawning on a bridge above/below the player.

-- Hospital Spawn Settings
Config.UseHospitalSpawn = true -- If true, ambulance spawns at the closest configured hospital and drives to the player. If false, falls back to spawning near the player.
Config.HospitalSpawns = {
    -- vec4(x, y, z, heading) — add as many as you like; the closest one to the player is used.
    vec4(355.516479, -546.092285, 28.740601, 266.456696),    -- Pillbox Hill
    vec4(-478.483521, -341.261536, 34.368530, 170.078735),   -- Mount Zonah
    vec4(1811.459351, 3684.619873, 34.199951, 300.472443),   -- Sandy Shores
    vec4(-258.989014, 6300.777832, 31.672485, 226.771667),   -- Paleto Bay
}

-- Doctor NPC Settings
Config.DoctorPed = 's_m_m_doctor_01' -- Ped model for the doctor
Config.DoctorSpeed = 30.0 -- Driving speed for doctor (in m/s) -- bumped for emergency response
Config.DoctorDrivingStyle = 786470 -- Driving style flags. 786470 = emergency: weaves around cars, ignores red lights, still stops for peds. Use 786603 for "normal cautious" if you'd rather have a polite ambulance.
Config.DoctorAbility = 1.0 -- Driver skill (0.0 - 1.0). 1.0 = professional, takes corners well.
Config.DoctorAggressiveness = 1.0 -- Driver aggressiveness (0.0 - 1.0). 1.0 = will push past traffic instead of waiting.
Config.UseSiren = true -- Run lights and sirens while driving to the player (turns off when the doctor arrives)

-- Proximity Settings
Config.ApproachDistance = 15.0 -- Distance at which doctor starts walking to player
Config.TreatmentDistance = 1.0 -- Distance at which treatment begins

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
    ['doctor_arriving'] = 'The AI Doctor is on their way to your location.'
}
