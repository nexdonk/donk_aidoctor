Framework.Init()

if not Framework.Object then
    print('[donk_aidoctor] ERROR: Failed to initialize framework! Script will not work.')
    return
end

local function DebugPrint(...)
    if Config.Debug then
        print('[donk_aidoctor]', ...)
    end
end

local PlayerCooldowns = {}
local PlayerLastCharge = {} -- src -> { amount = N, account = 'cash'|'bank' } for refund on dispatch failure

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

local function SetCooldown(source)
    if Config.Cooldown and Config.Cooldown > 0 then
        PlayerCooldowns[tostring(source)] = os.time() + Config.Cooldown
    end
end

Framework.RegisterCallback('donk_aidoctor:docOnline', function(source, cb)
    local src = source
    local player = Framework.GetPlayer(src)

    if not player then
        DebugPrint('Player object not found for source:', src)
        cb(false, false, 'Player not found')
        return
    end

    local onCooldown, timeLeft = IsOnCooldown(src)
    if onCooldown then
        DebugPrint('Player on cooldown:', timeLeft, 'seconds remaining')
        cb(false, false, 'cooldown', timeLeft)
        return
    end

    local emsCount = Framework.GetJobCount(Config.EMSJob)
    DebugPrint('EMS online:', emsCount, '| Required minimum:', Config.MinEMS)

    local emsAvailable = emsCount > Config.MinEMS
    if emsAvailable then
        DebugPrint('Too many EMS online - AI doctor not available')
        cb(false, false, 'ems_available')
        return
    end

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

    DebugPrint('All checks passed - AI doctor available')
    cb(true, true, 'success')
end)

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

        SetCooldown(src)
        PlayerLastCharge[tostring(src)] = { amount = Config.Price, account = accountUsed }

        if Config.SendToSociety then
            Framework.AddSocietyMoney(Config.SocietyAccount, Config.Price)
            DebugPrint('Payment sent to society:', Config.SocietyAccount)
        end
    else
        DebugPrint('Failed to charge player - insufficient funds')
    end
end)

-- Called when the client-side dispatch fails (vehicle stuck unrecoverably,
-- spawn failed, player cancelled). Refund the charge and clear cooldown
-- so the player isn't punished for the AI being dumb.
RegisterNetEvent('donk_aidoctor:dispatchFailed', function()
    local src = source
    local key = tostring(src)
    local last = PlayerLastCharge[key]

    if not last then
        DebugPrint('dispatchFailed but no charge on record for', src)
        PlayerCooldowns[key] = nil
        return
    end

    local player = Framework.GetPlayer(src)
    if player then
        if Framework.Type == 'qbcore' then
            player.Functions.AddMoney(last.account or 'cash', last.amount, 'AI Doctor refund')
        elseif Framework.Type == 'esx' then
            if (last.account or 'cash') == 'bank' then
                player.addAccountMoney('bank', last.amount)
            else
                player.addMoney(last.amount)
            end
        end
        DebugPrint('Refunded', last.amount, 'to', src, 'from', last.account)
    end

    -- Pull society money back if we sent it there
    if Config.SendToSociety and Framework.RemoveSocietyMoney then
        Framework.RemoveSocietyMoney(Config.SocietyAccount, last.amount)
    end

    PlayerLastCharge[key] = nil
    PlayerCooldowns[key] = nil
end)

RegisterNetEvent('donk_aidoctor:revivePlayer', function()
    local src = source
    DebugPrint('Reviving player:', src)

    Framework.RevivePlayer(src)

    if Framework.Type == 'qbcore' then
        local player = Framework.GetPlayer(src)
        if player then
            player.Functions.SetMetaData("isdead", false)
            player.Functions.SetMetaData("inlaststand", false)
        end
    end

    -- Successful treatment - clear the refund record so a later dispatchFailed can't double-refund
    PlayerLastCharge[tostring(src)] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    local playerId = tostring(src)
    if PlayerCooldowns[playerId] then
        PlayerCooldowns[playerId] = nil
        DebugPrint('Cleared cooldown for disconnected player:', src)
    end
    PlayerLastCharge[playerId] = nil
end)

DebugPrint('Server script loaded successfully')
