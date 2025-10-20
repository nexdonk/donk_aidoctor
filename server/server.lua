-- Initialize framework
Framework.Init()

if not Framework.Object then
    print('[donk_aidoctor] ERROR: Failed to initialize framework! Script will not work.')
    return
end

-- Debug print helper
local function DebugPrint(...)
    if Config.Debug then
        print('[donk_aidoctor]', ...)
    end
end

-- Cooldown tracking
local PlayerCooldowns = {}

-- Check if player is on cooldown
local function IsOnCooldown(source)
    if not Config.Cooldown or Config.Cooldown <= 0 then
        return false
    end

    local playerId = tostring(source)
    if PlayerCooldowns[playerId] then
        local timeLeft = PlayerCooldowns[playerId] - os.time()
        if timeLeft > 0 then
            return true, timeLeft
        else
            PlayerCooldowns[playerId] = nil
        end
    end
    return false, 0
end

-- Set player cooldown
local function SetCooldown(source)
    if Config.Cooldown and Config.Cooldown > 0 then
        PlayerCooldowns[tostring(source)] = os.time() + Config.Cooldown
    end
end

-- Callback to check if doctor is available
Framework.RegisterCallback('donk_aidoctor:docOnline', function(source, cb)
    local src = source
    local player = Framework.GetPlayer(src)

    if not player then
        DebugPrint('Player object not found for source:', src)
        cb(false, false, 'Player not found')
        return
    end

    -- Check cooldown
    local onCooldown, timeLeft = IsOnCooldown(src)
    if onCooldown then
        DebugPrint('Player on cooldown:', timeLeft, 'seconds remaining')
        cb(false, false, 'cooldown', timeLeft)
        return
    end

    -- Count online EMS/doctors
    local emsCount = Framework.GetJobCount(Config.EMSJob)
    DebugPrint('EMS online:', emsCount, '| Required minimum:', Config.MinEMS)

    -- Check if enough EMS are online (if MinEMS > 0, require that many or fewer EMS)
    -- Logic: If MinEMS = 2, we want AI doctor available when 2 or MORE EMS are online
    -- Actually, reading the original: it seems backward - let's fix the logic
    -- Config.MinEMS should mean "AI doctor available when EMS count is this or lower"
    -- So if MinEMS = 0, AI doctor always available
    -- If MinEMS = 2, AI doctor available when 2 or fewer EMS online
    local emsAvailable = emsCount > Config.MinEMS
    if emsAvailable then
        DebugPrint('Too many EMS online - AI doctor not available')
        cb(false, false, 'ems_available')
        return
    end

    -- Check if player can afford the service
    local canPay = false
    local cashAmount = Framework.GetPlayerMoney(player, 'cash')
    local bankAmount = Framework.GetPlayerMoney(player, 'bank')

    DebugPrint('Player money - Cash:', cashAmount, 'Bank:', bankAmount, 'Required:', Config.Price)

    if Config.PaymentAccount == 'cash' then
        canPay = cashAmount >= Config.Price
    elseif Config.PaymentAccount == 'bank' then
        canPay = bankAmount >= Config.Price
    elseif Config.PaymentAccount == 'both' then
        canPay = (cashAmount >= Config.Price) or (bankAmount >= Config.Price)
    end

    if not canPay then
        DebugPrint('Player cannot afford service')
        cb(false, false, 'no_money')
        return
    end

    -- All checks passed
    DebugPrint('All checks passed - AI doctor available')
    cb(true, true, 'success')
end)

-- Event to charge player for service
RegisterNetEvent('donk_aidoctor:charge', function()
    local src = source
    local player = Framework.GetPlayer(src)

    if not player then
        DebugPrint('Cannot charge - player not found')
        return
    end

    local cashAmount = Framework.GetPlayerMoney(player, 'cash')
    local bankAmount = Framework.GetPlayerMoney(player, 'bank')
    local charged = false
    local accountUsed = nil

    -- Determine which account to charge
    if Config.PaymentAccount == 'cash' then
        if cashAmount >= Config.Price then
            Framework.RemovePlayerMoney(player, Config.Price, 'cash', 'AI Doctor Service')
            charged = true
            accountUsed = 'cash'
        end
    elseif Config.PaymentAccount == 'bank' then
        if bankAmount >= Config.Price then
            Framework.RemovePlayerMoney(player, Config.Price, 'bank', 'AI Doctor Service')
            charged = true
            accountUsed = 'bank'
        end
    elseif Config.PaymentAccount == 'both' then
        -- Try cash first, then bank
        if cashAmount >= Config.Price then
            Framework.RemovePlayerMoney(player, Config.Price, 'cash', 'AI Doctor Service')
            charged = true
            accountUsed = 'cash'
        elseif bankAmount >= Config.Price then
            Framework.RemovePlayerMoney(player, Config.Price, 'bank', 'AI Doctor Service')
            charged = true
            accountUsed = 'bank'
        end
    end

    if charged then
        DebugPrint('Player charged', Config.Price, 'from', accountUsed)

        -- Set cooldown
        SetCooldown(src)

        -- Send money to society if configured
        if Config.SendToSociety then
            Framework.AddSocietyMoney(Config.SocietyAccount, Config.Price)
            DebugPrint('Payment sent to society:', Config.SocietyAccount)
        end
    else
        DebugPrint('Failed to charge player - insufficient funds')
    end
end)

-- Event to revive player
RegisterNetEvent('donk_aidoctor:revivePlayer', function()
    local src = source
    DebugPrint('Reviving player:', src)

    Framework.RevivePlayer(src)

    -- Additional cleanup - remove death status
    if Framework.Type == 'qbcore' then
        local player = Framework.GetPlayer(src)
        if player then
            player.Functions.SetMetaData("isdead", false)
            player.Functions.SetMetaData("inlaststand", false)
        end
    end
end)

-- Cleanup cooldowns on player drop
AddEventHandler('playerDropped', function()
    local src = source
    local playerId = tostring(src)
    if PlayerCooldowns[playerId] then
        PlayerCooldowns[playerId] = nil
        DebugPrint('Cleared cooldown for disconnected player:', src)
    end
end)

DebugPrint('Server script loaded successfully')
