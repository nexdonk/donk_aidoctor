Framework = {}
Framework.Type = nil
Framework.Object = nil

-- Detect and initialize framework
function Framework.Init()
    -- Try QBCore first
    local success, qbcore = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if success and qbcore then
        Framework.Type = 'qbcore'
        Framework.Object = qbcore
        print('[donk_aidoctor] QBCore framework detected')
        return true
    end

    -- Try ESX
    success, esx = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)

    if success and esx then
        Framework.Type = 'esx'
        Framework.Object = esx
        print('[donk_aidoctor] ESX framework detected')
        return true
    end

    -- Try legacy ESX trigger
    TriggerEvent('esx:getSharedObject', function(obj)
        Framework.Type = 'esx'
        Framework.Object = obj
        print('[donk_aidoctor] ESX framework detected (legacy)')
    end)

    if Framework.Object then
        return true
    end

    print('[donk_aidoctor] ERROR: No supported framework detected!')
    return false
end

-- Client-side functions
if IsDuplicityVersion() == 0 then

    -- Get player data
    function Framework.GetPlayerData()
        if Framework.Type == 'qbcore' then
            return Framework.Object.Functions.GetPlayerData()
        elseif Framework.Type == 'esx' then
            return Framework.Object.GetPlayerData()
        end
        return nil
    end

    -- Check if player is dead
    function Framework.IsPlayerDead()
        if Framework.Type == 'qbcore' then
            local playerData = Framework.Object.Functions.GetPlayerData()
            return playerData.metadata and (playerData.metadata["isdead"] or playerData.metadata["inlaststand"])
        elseif Framework.Type == 'esx' then
            local playerData = Framework.Object.GetPlayerData()
            return playerData.dead or false
        end
        return false
    end

    -- Trigger server callback
    function Framework.TriggerCallback(name, cb, ...)
        if Framework.Type == 'qbcore' then
            Framework.Object.Functions.TriggerCallback(name, cb, ...)
        elseif Framework.Type == 'esx' then
            Framework.Object.TriggerServerCallback(name, cb, ...)
        end
    end

    -- Show notification
    function Framework.Notify(message, type, duration)
        duration = duration or 5000

        -- Try ox_lib first
        if GetResourceState('ox_lib') == 'started' then
            lib.notify({
                title = 'AI Doctor',
                description = message,
                type = type or 'info',
                duration = duration
            })
            return
        end

        -- Fallback to framework notifications
        if Framework.Type == 'qbcore' then
            Framework.Object.Functions.Notify(message, type, duration)
        elseif Framework.Type == 'esx' then
            Framework.Object.ShowNotification(message)
        else
            -- Final fallback to basic notification
            BeginTextCommandThefeedPost("STRING")
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandThefeedPostTicker(false, true)
        end
    end

    -- Show progress bar
    function Framework.ShowProgress(label, duration, options, onFinish)
        options = options or {}

        -- Try ox_lib first
        if GetResourceState('ox_lib') == 'started' then
            if lib.progressBar({
                duration = duration,
                label = label,
                useWhileDead = options.useWhileDead or false,
                canCancel = options.canCancel or false,
                disable = {
                    move = options.disableMovement or false,
                    car = options.disableCarMovement or false,
                    combat = options.disableCombat or false,
                    mouse = options.disableMouse or false
                },
                anim = options.anim,
                prop = options.prop
            }) then
                if onFinish then onFinish(true) end
            else
                if onFinish then onFinish(false) end
            end
            return
        end

        -- Fallback to framework progress
        if Framework.Type == 'qbcore' then
            Framework.Object.Functions.Progressbar(
                options.name or "progress",
                label,
                duration,
                false,
                true,
                {
                    disableMovement = options.disableMovement or false,
                    disableCarMovement = options.disableCarMovement or false,
                    disableMouse = options.disableMouse or false,
                    disableCombat = options.disableCombat or false,
                },
                options.anim or {},
                options.prop or {},
                {},
                function() -- on finish
                    if onFinish then onFinish(true) end
                end,
                function() -- on cancel
                    if onFinish then onFinish(false) end
                end
            )
        elseif Framework.Type == 'esx' then
            -- ESX doesn't have built-in progress, use basic timer
            Citizen.CreateThread(function()
                Citizen.Wait(duration)
                if onFinish then onFinish(true) end
            end)
        end
    end
end

-- Server-side functions
if IsDuplicityVersion() == 1 then

    -- Get player object
    function Framework.GetPlayer(source)
        if Framework.Type == 'qbcore' then
            return Framework.Object.Functions.GetPlayer(source)
        elseif Framework.Type == 'esx' then
            return Framework.Object.GetPlayerFromId(source)
        end
        return nil
    end

    -- Get all players
    function Framework.GetPlayers()
        if Framework.Type == 'qbcore' then
            return Framework.Object.Functions.GetPlayers()
        elseif Framework.Type == 'esx' then
            return Framework.Object.GetPlayers()
        end
        return {}
    end

    -- Register server callback
    function Framework.RegisterCallback(name, cb)
        if Framework.Type == 'qbcore' then
            Framework.Object.Functions.CreateCallback(name, cb)
        elseif Framework.Type == 'esx' then
            Framework.Object.RegisterServerCallback(name, cb)
        end
    end

    -- Get player money
    function Framework.GetPlayerMoney(player, moneyType)
        if not player then return 0 end

        if Framework.Type == 'qbcore' then
            moneyType = moneyType or 'cash'
            return player.PlayerData.money[moneyType] or 0
        elseif Framework.Type == 'esx' then
            if moneyType == 'bank' then
                return player.getAccount('bank').money or 0
            else
                return player.getMoney() or 0
            end
        end
        return 0
    end

    -- Remove player money
    function Framework.RemovePlayerMoney(player, amount, moneyType, reason)
        if not player then return false end

        if Framework.Type == 'qbcore' then
            moneyType = moneyType or 'cash'
            return player.Functions.RemoveMoney(moneyType, amount, reason)
        elseif Framework.Type == 'esx' then
            if moneyType == 'bank' then
                player.removeAccountMoney('bank', amount)
            else
                player.removeMoney(amount)
            end
            return true
        end
        return false
    end

    -- Get player job
    function Framework.GetPlayerJob(player)
        if not player then return nil end

        if Framework.Type == 'qbcore' then
            return player.PlayerData.job
        elseif Framework.Type == 'esx' then
            return player.getJob()
        end
        return nil
    end

    -- Count players with specific job
    function Framework.GetJobCount(jobName)
        local count = 0
        local players = Framework.GetPlayers()

        for _, playerId in pairs(players) do
            local player = Framework.GetPlayer(playerId)
            if player then
                local job = Framework.GetPlayerJob(player)
                if job and job.name == jobName then
                    count = count + 1
                end
            end
        end

        return count
    end

    -- Add money to society/job account
    function Framework.AddSocietyMoney(jobName, amount)
        if Framework.Type == 'qbcore' then
            -- Try qb-bossmenu
            if GetResourceState('qb-management') == 'started' or GetResourceState('qb-bossmenu') == 'started' then
                exports['qb-management']:AddMoney(jobName, amount)
            end
        elseif Framework.Type == 'esx' then
            -- Try esx_society or esx_addonaccount
            TriggerEvent('esx_addonaccount:getSharedAccount', 'society_'..jobName, function(account)
                if account then
                    account.addMoney(amount)
                end
            end)

            -- Also try esx_society
            TriggerEvent('esx_society:getSociety', jobName, function(society)
                if society then
                    society.addMoney(amount)
                end
            end)
        end
    end

    -- Revive player
    function Framework.RevivePlayer(source)
        local reviveSystem = Config.ReviveSystem or 'auto'

        if reviveSystem == 'auto' then
            -- Auto-detect revive system
            if GetResourceState('wasabi_ambulance') == 'started' then
                exports.wasabi_ambulance:RevivePlayer(source)
            elseif Framework.Type == 'qbcore' then
                TriggerClientEvent('hospital:client:Revive', source)
            elseif Framework.Type == 'esx' then
                TriggerClientEvent('esx_ambulancejob:revive', source)
            end
        elseif reviveSystem == 'wasabi' then
            exports.wasabi_ambulance:RevivePlayer(source)
        elseif reviveSystem == 'qbcore' then
            TriggerClientEvent('hospital:client:Revive', source)
        elseif reviveSystem == 'esx' then
            TriggerClientEvent('esx_ambulancejob:revive', source)
        elseif reviveSystem == 'custom' then
            -- Trigger custom event defined in config
            if Config.CustomReviveEvent then
                TriggerClientEvent(Config.CustomReviveEvent, source)
            end
        end
    end
end

return Framework
