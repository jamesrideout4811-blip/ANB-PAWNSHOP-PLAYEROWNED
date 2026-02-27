local function detectFramework()
    local preferred = string.lower(tostring(Config.Framework or 'auto'))
    if preferred ~= 'auto' then
        return preferred
    end

    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function getFrameworkPlayer(src)
    local framework = detectFramework()

    -- QBOX / QBX variants
    if framework == 'qbx' then
        -- Some builds expose GetPlayer directly
        local ok1, p1 = pcall(function()
            if exports.qbx_core and exports.qbx_core.GetPlayer then
                return exports.qbx_core:GetPlayer(src)
            end
            return nil
        end)
        if ok1 and p1 then
            return p1, 'qbx'
        end

        -- Some builds use a CoreObject
        local ok2, core = pcall(function()
            if exports.qbx_core and exports.qbx_core.GetCoreObject then
                return exports.qbx_core:GetCoreObject()
            end
            return nil
        end)
        if ok2 and core and core.GetPlayer then
            local p2 = core:GetPlayer(src)
            if p2 then return p2, 'qbx' end
        end
    elseif framework == 'qb' then
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore then
            return QBCore.Functions.GetPlayer(src), 'qb'
        end
    elseif framework == 'esx' then
        local ok, ESX = pcall(function() return exports.es_extended:getSharedObject() end)
        if ok and ESX and ESX.GetPlayerFromId then
            return ESX.GetPlayerFromId(src), 'esx'
        end
    end
    return nil, 'standalone'
end

local function getJobInfo(player)
    if not player then
        return nil, 0
    end

    local pd = player.PlayerData or player.playerData or player.data
    local job = pd and (pd.job or pd.Job)

    if not job and player.getJob then
        local ok, j = pcall(function() return player.getJob(player) end)
        if ok and j then job = j end
    end

    if not job then return nil, 0 end

    local name = job.name or job.id
    local grade = tonumber(job.grade_level) or tonumber(job.gradeLevel) or 0

    if type(job.grade) == 'table' then
        grade = tonumber(job.grade.level or job.grade.grade or job.grade.value) or 0
    elseif job.grade ~= nil then
        grade = tonumber(job.grade) or 0
    end

    if grade == 0 and type(job.grade_name) == 'number' then
        grade = tonumber(job.grade_name) or 0
    end

    return name, grade
end

local function addCash(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local player, fw = getFrameworkPlayer(src)
    if player and (fw == 'qb' or fw == 'qbx') and player.Functions and player.Functions.AddMoney then
        player.Functions.AddMoney('cash', amount, 'nb-pawnshop')
        return true
    end

    if player and fw == 'esx' then
        if player.addMoney then
            player.addMoney(player, amount)
            return true
        end
        if player.addAccountMoney then
            player.addAccountMoney(player, 'money', amount)
            return true
        end
    end

    return exports.ox_inventory:AddItem(src, Config.MoneyItem or 'money', amount) == true
end

local function removeCash(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local player, fw = getFrameworkPlayer(src)
    if player and (fw == 'qb' or fw == 'qbx') and player.Functions and player.Functions.RemoveMoney then
        return player.Functions.RemoveMoney('cash', amount, 'nb-pawnshop') == true
    end

    if player and fw == 'esx' then
        if player.removeMoney then
            player.removeMoney(player, amount)
            return true
        end
        if player.removeAccountMoney then
            player.removeAccountMoney(player, 'money', amount)
            return true
        end
    end

    return exports.ox_inventory:RemoveItem(src, Config.MoneyItem or 'money', amount)
end

local function getCash(src)
    local player, fw = getFrameworkPlayer(src)
    if player and (fw == 'qb' or fw == 'qbx') and player.Functions and player.Functions.GetMoney then
        local money = player.Functions.GetMoney('cash')
        return tonumber(money) or 0
    end
    if player and fw == 'esx' then
        if player.getMoney then
            return tonumber(player.getMoney(player)) or 0
        end
        if player.getAccount then
            local acc = player.getAccount(player, 'money')
            return tonumber(acc and acc.money) or 0
        end
    end
    return exports.ox_inventory:GetItemCount(src, Config.MoneyItem or 'money') or 0
end


-- =========================
-- Business Banking (optional)
-- =========================
local Bank = {
    balance = 0,
    storage = 'kvp', -- resolved on start
    kvpKey = (Config.BusinessBank and Config.BusinessBank.kvpKey) or 'nb_pawnshop_bank_sandy',
    accountId = (Config.BusinessBank and Config.BusinessBank.accountId) or 'sandy',
    tableName = (Config.BusinessBank and Config.BusinessBank.mysqlTable) or 'nb_pawnshop_business_accounts',
}

local function _hasMySQL()
    if not Config.BusinessBank then return false end
    if Config.BusinessBank.storage == 'kvp' then return false end
    if GetResourceState('oxmysql') ~= 'started' then return false end
    -- oxmysql typically exposes global MySQL.*.await helpers
    return type(MySQL) == 'table' and type(MySQL.scalar) == 'function'
end

local function _mysqlInit()
    local tn = Bank.tableName
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `account_id` VARCHAR(64) NOT NULL,
            `balance` BIGINT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`account_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(tn))
end

local function _mysqlLoad()
    local tn = Bank.tableName
    local bal = MySQL.scalar.await(('SELECT balance FROM `%s` WHERE account_id = ? LIMIT 1'):format(tn), { Bank.accountId })
    if bal == nil then return nil end
    return tonumber(bal) or 0
end

local function _mysqlSave()
    local tn = Bank.tableName
    MySQL.update.await(
        ('INSERT INTO `%s` (account_id, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = VALUES(balance)'):format(tn),
        { Bank.accountId, Bank.balance }
    )
end

local function _kvpLoad()
    local v = GetResourceKvpInt(Bank.kvpKey)
    if v == nil or v == 0 then
        -- Some servers return 0 when unset; use string check to disambiguate
        local s = GetResourceKvpString(Bank.kvpKey)
        if s == nil then return nil end
        return tonumber(s) or 0
    end
    return tonumber(v) or 0
end

local function _kvpSave()
    SetResourceKvpInt(Bank.kvpKey, math.floor(Bank.balance))
end

local function _bankEnabled()
    return Config.BusinessBank and Config.BusinessBank.enabled == true
end

local function _bankGet()
    return math.floor(tonumber(Bank.balance) or 0)
end

local function _bankSet(v)
    Bank.balance = math.floor(tonumber(v) or 0)
    if Bank.storage == 'mysql' then
        local ok = pcall(_mysqlSave)
        if not ok then Bank.storage = 'kvp'; _kvpSave() end
    else
        _kvpSave()
    end
end

local function _bankAdd(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return _bankGet() end
    _bankSet(_bankGet() + amount)
    return _bankGet()
end

local function _bankSub(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true, _bankGet() end
    local cur = _bankGet()
    if cur < amount then return false, cur end
    _bankSet(cur - amount)
    return true, _bankGet()
end

local function _bankInit()
    if not _bankEnabled() then return end
    -- Resolve storage mode
    local mode = tostring(Config.BusinessBank.storage or 'auto'):lower()
    if mode == 'mysql' or (mode == 'auto' and _hasMySQL()) then
        Bank.storage = 'mysql'
        local ok = pcall(function()
            _mysqlInit()
            local loaded = _mysqlLoad()
            if loaded == nil then
                Bank.balance = math.floor(tonumber(Config.BusinessBank.startingBalance) or 0)
                _mysqlSave()
            else
                Bank.balance = loaded
            end
        end)
        if not ok then
            Bank.storage = 'kvp'
        end
    end

    if Bank.storage ~= 'mysql' then
        Bank.storage = 'kvp'
        local loaded = _kvpLoad()
        if loaded == nil then
            Bank.balance = math.floor(tonumber(Config.BusinessBank.startingBalance) or 0)
            _kvpSave()
        else
            Bank.balance = loaded
        end
    end
end

CreateThread(function()
    _bankInit()
end)

local function isJewelry(name, data)
    local n = (name or ''):lower()
    local label = ((data and data.label) or ''):lower()
    local patterns = { 'rolex','watch','chain','gold','diamond','ring','necklace','bracelet','earring','jewelry','jewellery' }
    for _, p in ipairs(patterns) do
        if n:find(p, 1, true) or label:find(p, 1, true) then return true end
    end
    return false
end

local function weaponCategory(name)
    local n = (name or ''):lower()
    if not n:find('weapon_', 1, true) then return nil end
    if n:find('knife', 1, true) or n:find('bat', 1, true) or n:find('machete', 1, true) or n:find('crowbar', 1, true) then return 'weapon_melee' end
    if n:find('sniper', 1, true) or n:find('marksman', 1, true) then return 'weapon_sniper' end
    if n:find('shotgun', 1, true) then return 'weapon_shotgun' end
    if n:find('smg', 1, true) or n:find('microsmg', 1, true) then return 'weapon_smg' end
    if n:find('rifle', 1, true) or n:find('carbine', 1, true) or n:find('assaultrifle', 1, true) or n:find('specialcarbine', 1, true) then return 'weapon_rifle' end
    if n:find('pistol', 1, true) or n:find('revolver', 1, true) then return 'weapon_pistol' end
    return 'weapon_other'
end

local function resolveSellPrice(itemName, itemData)
    if Config.SellPrices and Config.SellPrices[itemName] then
        return tonumber(Config.SellPrices[itemName])
    end
    if not Config.AutoSell or not Config.AutoSell.enabled then return nil end
    if Config.AutoSell.jewelry and isJewelry(itemName, itemData) then
        return tonumber(Config.DefaultPrices.jewelry) or 200
    end
    if Config.AutoSell.weapons then
        local cat = weaponCategory(itemName)
        if cat then return tonumber(Config.DefaultPrices[cat] or Config.DefaultPrices.weapon_other) or 9000 end
    end
    return nil
end

local function resolveBuyBackPrice(itemName, itemData)
    local sell = resolveSellPrice(itemName, itemData)
    local mult = tonumber(Config.BuyBackMultiplier) or 1.35
    if sell then return math.floor(sell * mult) end
    return 500
end


-- In-memory staff clock-in tracking (resets on server restart)
local StaffClock = {}

local function ensureStockStash()
    exports.ox_inventory:RegisterStash(
        Config.StockStash.id,
        Config.StockStash.label,
        Config.StockStash.slots,
        Config.StockStash.maxWeight
    )
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    ensureStockStash()
end)

lib.callback.register('nb_pawnshop:isStaff', function(source)
    local player = select(1, getFrameworkPlayer(source))
    if not player or not Config.Owner or not Config.Owner.job then
        TriggerClientEvent('nb_pawnshop:notify', source, 'Staff only. (No player object found)', 'error')
        return false
    end

    local required = string.lower(tostring(Config.Owner.job))
    local rawJobName, grade = getJobInfo(player)
    local jobName = rawJobName and string.lower(tostring(rawJobName)) or ''

    local minGrade = tonumber(Config.Owner.minGrade) or 1

    if jobName ~= required then
        TriggerClientEvent('nb_pawnshop:notify', source,
            ('Staff only. Detected job: "%s" (need "%s").'):format(jobName ~= '' and jobName or 'none', required),
            'error'
        )
        return false
    end

    if grade < minGrade then
        TriggerClientEvent('nb_pawnshop:notify', source,
            ('Staff only. Detected grade: %s (need %s+).'):format(grade, minGrade),
            'error'
        )
        return false
    end

    return true
end)






-- Boss check (owner grade)
local function _isBoss(src)
    local player = select(1, getFrameworkPlayer(src))
    if not player or not Config.Owner or not Config.Owner.job then
        return false, 'No player object'
    end

    local required = string.lower(tostring(Config.Owner.job))
    local bossGrade = tonumber(Config.Owner.bossGrade) or 4
    local rawJobName, grade = getJobInfo(player)
    local jobName = rawJobName and string.lower(tostring(rawJobName)) or ''

    if jobName ~= required then return false, 'Wrong job' end
    if grade < bossGrade then return false, 'Insufficient grade' end
    return true
end

lib.callback.register('nb_pawnshop:isBoss', function(source)
    local ok = _isBoss(source)
    if not ok then
        TriggerClientEvent('nb_pawnshop:notify', source, 'Boss only.', 'error')
        return false
    end
    return true
end)

-- Banking callbacks (boss-only)
lib.callback.register('nb_pawnshop:getBankBalance', function(source)
    if not _bankEnabled() then return 0 end
    local ok = _isBoss(source)
    if not ok then return 0 end
    return _bankGet()
end)

lib.callback.register('nb_pawnshop:bankDeposit', function(source, amount)
    if not _bankEnabled() then return { ok = false, message = 'Business banking is disabled.' } end
    local ok = _isBoss(source)
    if not ok then return { ok = false, message = 'Boss only.' } end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return { ok = false, message = 'Invalid amount.' } end
    if getCash(source) < amount then return { ok = false, message = 'Not enough cash.' } end
    if not removeCash(source, amount) then return { ok = false, message = 'Could not take cash.' } end

    return { ok = true, balance = _bankAdd(amount) }
end)

lib.callback.register('nb_pawnshop:bankWithdraw', function(source, amount)
    if not _bankEnabled() then return { ok = false, message = 'Business banking is disabled.' } end
    local ok = _isBoss(source)
    if not ok then return { ok = false, message = 'Boss only.' } end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return { ok = false, message = 'Invalid amount.' } end

    local okSub, bal = _bankSub(amount)
    if not okSub then return { ok = false, message = 'Business account has insufficient funds.', balance = bal } end
    if not addCash(source, amount) then
        _bankAdd(amount)
        return { ok = false, message = 'Could not give cash.' }
    end

    return { ok = true, balance = bal }
end)

-- Hire / Fire (boss-only)
lib.callback.register('nb_pawnshop:setStaffJob', function(source, targetId, grade)
    if not (Config.StaffManagement and Config.StaffManagement.enabled) then
        return { ok = false, message = 'Staff management disabled.' }
    end
    local ok = _isBoss(source)
    if not ok then return { ok = false, message = 'Boss only.' } end

    targetId = tonumber(targetId)
    grade = math.floor(tonumber(grade) or 0)
    if not targetId or targetId <= 0 then return { ok = false, message = 'Invalid Server ID.' } end
    if grade < 0 then grade = 0 end

    local targetPlayer = select(1, getFrameworkPlayer(targetId))
    if not targetPlayer then return { ok = false, message = 'Player not online.' } end

    local jobName = tostring(Config.Owner.job)

    if targetPlayer.Functions and targetPlayer.Functions.SetJob then
        targetPlayer.Functions.SetJob(jobName, grade)
        return { ok = true, message = ('Set %s to %s grade %s'):format(GetPlayerName(targetId) or ('ID '..targetId), jobName, grade) }
    end

    if targetPlayer.setJob then
        local ok2 = pcall(function() targetPlayer.setJob(targetPlayer, jobName, grade) end)
        if ok2 then
            return { ok = true, message = ('Set %s to %s grade %s'):format(GetPlayerName(targetId) or ('ID '..targetId), jobName, grade) }
        end
    end

    if targetPlayer.setJob then
        local ok2 = pcall(function() targetPlayer:setJob(jobName, grade) end)
        if ok2 then
            return { ok = true, message = ('Set %s to %s grade %s'):format(GetPlayerName(targetId) or ('ID '..targetId), jobName, grade) }
        end
    end

    return { ok = false, message = 'Could not set job (framework mismatch).' }
end)

lib.callback.register('nb_pawnshop:fireStaff', function(source, targetId)
    if not (Config.StaffManagement and Config.StaffManagement.enabled) then
        return { ok = false, message = 'Staff management disabled.' }
    end
    local ok = _isBoss(source)
    if not ok then return { ok = false, message = 'Boss only.' } end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return { ok = false, message = 'Invalid Server ID.' } end

    local targetPlayer = select(1, getFrameworkPlayer(targetId))
    if not targetPlayer then return { ok = false, message = 'Player not online.' } end

    local fireJob = (Config.StaffManagement.fireJob or 'unemployed')
    local fireGrade = math.floor(tonumber(Config.StaffManagement.fireGrade) or 0)

    if targetPlayer.Functions and targetPlayer.Functions.SetJob then
        targetPlayer.Functions.SetJob(fireJob, fireGrade)
        return { ok = true, message = ('Fired %s'):format(GetPlayerName(targetId) or ('ID '..targetId)) }
    end

    if targetPlayer.setJob then
        local ok2 = pcall(function() targetPlayer.setJob(targetPlayer, fireJob, fireGrade) end)
        if ok2 then
            return { ok = true, message = ('Fired %s'):format(GetPlayerName(targetId) or ('ID '..targetId)) }
        end
    end

    if targetPlayer.setJob then
        local ok2 = pcall(function() targetPlayer:setJob(fireJob, fireGrade) end)
        if ok2 then
            return { ok = true, message = ('Fired %s'):format(GetPlayerName(targetId) or ('ID '..targetId)) }
        end
    end

    return { ok = false, message = 'Could not set job (framework mismatch).' }
end)



lib.callback.register('nb_pawnshop:getSellables', function(source)
    local items = exports.ox_inventory:GetInventoryItems(source)
    local result = {}
    if not items then return result end

    for _, slot in pairs(items) do
        if slot and slot.name and slot.count and slot.count > 0 then
            local itemData = exports.ox_inventory:Items(slot.name)
            local price = resolveSellPrice(slot.name, itemData)
            if price then
                result[#result+1] = {
                    name = slot.name,
                    label = (itemData and itemData.label) or slot.name,
                    count = slot.count,
                    price = price
                }
            end
        end
    end

    table.sort(result, function(a,b) return (a.label or a.name) < (b.label or b.name) end)
    return result
end)

lib.callback.register('nb_pawnshop:getStock', function(source)
    local items = exports.ox_inventory:GetInventoryItems(Config.StockStash.id)
    local result = {}
    if not items then return result end

    for _, slot in pairs(items) do
        if slot and slot.name and slot.count and slot.count > 0 then
            local itemData = exports.ox_inventory:Items(slot.name)
            result[#result+1] = {
                name = slot.name,
                label = (itemData and itemData.label) or slot.name,
                count = slot.count,
                price = resolveBuyBackPrice(slot.name, itemData)
            }
        end
    end

    table.sort(result, function(a,b) return (a.label or a.name) < (b.label or b.name) end)
    return result
end)

RegisterNetEvent('nb_pawnshop:sellItem', function(itemName, qty)
    local src = source
    if type(itemName) ~= 'string' then return end
    qty = tonumber(qty) or 0
    if qty <= 0 then return end

    ensureStockStash()

    local itemData = exports.ox_inventory:Items(itemName)
    local price = resolveSellPrice(itemName, itemData)
    if not price then
        TriggerClientEvent('nb_pawnshop:notify', src, 'This item is not sellable at the pawn shop.', 'error')
        return
    end

    local slotsData = exports.ox_inventory:GetSlotsWithItem(src, itemName)
    if not slotsData or #slotsData == 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'You do not have that item.', 'error')
        return
    end

    local remaining = qty
    local moved = 0

    for _, slot in ipairs(slotsData) do
        if remaining <= 0 then break end
        local take = math.min(remaining, slot.count)
        local ok = exports.ox_inventory:RemoveItem(src, itemName, take, slot.metadata, slot.slot)
        if ok then
            exports.ox_inventory:AddItem(Config.StockStash.id, itemName, take, slot.metadata)
            remaining = remaining - take
            moved = moved + take
        end
    end

    if moved <= 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Sale failed.', 'error')
        return
    end

    local payout = math.floor(price * moved)

    if _bankEnabled() then
        local okSub = _bankSub(payout)
        if not okSub then
            exports.ox_inventory:AddItem(src, itemName, moved)
            exports.ox_inventory:RemoveItem(Config.StockStash.id, itemName, moved)
            TriggerClientEvent('nb_pawnshop:notify', src, 'Pawnshop business account has insufficient funds. Sale cancelled.', 'error')
            return
        end
    end

    if not addCash(src, payout) then
        -- Refund items back and refund business bank if used
        exports.ox_inventory:AddItem(src, itemName, moved)
        exports.ox_inventory:RemoveItem(Config.StockStash.id, itemName, moved)
        if _bankEnabled() then _bankAdd(payout) end
        TriggerClientEvent('nb_pawnshop:notify', src, 'Could not pay you. Sale cancelled.', 'error')
        return
    end

    TriggerClientEvent('nb_pawnshop:notify', src, ('Sold %sx %s for $%s'):format(moved, itemName, payout), 'success')
end)

RegisterNetEvent('nb_pawnshop:buyFromStock', function(itemName, qty)
    local src = source
    if type(itemName) ~= 'string' then return end
    qty = tonumber(qty) or 0
    if qty <= 0 then return end

    ensureStockStash()

    local itemData = exports.ox_inventory:Items(itemName)
    local priceEach = resolveBuyBackPrice(itemName, itemData)
    local total = math.floor(priceEach * qty)

    if getCash(src) < total then
        TriggerClientEvent('nb_pawnshop:notify', src, ('Not enough cash. Need $%s.'):format(total), 'error')
        return
    end

    if not exports.ox_inventory:CanCarryItem(src, itemName, qty) then
        TriggerClientEvent('nb_pawnshop:notify', src, 'You cannot carry that.', 'error')
        return
    end

    local slotsData = exports.ox_inventory:GetSlotsWithItem(Config.StockStash.id, itemName)
    if not slotsData or #slotsData == 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Item is no longer in stock.', 'error')
        return
    end

    local remaining = qty
    local given = 0

    for _, slot in ipairs(slotsData) do
        if remaining <= 0 then break end
        local take = math.min(remaining, slot.count)
        local ok = exports.ox_inventory:RemoveItem(Config.StockStash.id, itemName, take, slot.metadata, slot.slot)
        if ok then
            local ok2 = exports.ox_inventory:AddItem(src, itemName, take, slot.metadata)
            if ok2 then
                remaining = remaining - take
                given = given + take
            else
                exports.ox_inventory:AddItem(Config.StockStash.id, itemName, take, slot.metadata)
            end
        end
    end

    if given <= 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Purchase failed.', 'error')
        return
    end

    local finalTotal = math.floor(priceEach * given)
    if not removeCash(src, finalTotal) then
        -- Refund items back to stock
        exports.ox_inventory:RemoveItem(src, itemName, given)
        exports.ox_inventory:AddItem(Config.StockStash.id, itemName, given)
        TriggerClientEvent('nb_pawnshop:notify', src, 'Could not take cash. Purchase cancelled.', 'error')
        return
    end

    if _bankEnabled() then
        _bankAdd(finalTotal)
    end

    TriggerClientEvent('nb_pawnshop:notify', src, ('Bought %sx %s for $%s'):format(given, itemName, finalTotal), 'success')
end)


local function getPlayerName(src, player)
    if player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        local fn = ci.firstname or ''
        local ln = ci.lastname or ''
        local full = (fn .. ' ' .. ln):gsub('^%s*(.-)%s*$', '%1')
        if full ~= '' then return full end
    end
    return GetPlayerName(src) or ('ID ' .. tostring(src))
end

local function clockKey(player)
    -- Prefer citizenid if available, else fallback to license
    if player and player.PlayerData and player.PlayerData.citizenid then
        return 'cid:' .. tostring(player.PlayerData.citizenid)
    end
    local ids = GetPlayerIdentifiers(source)
    for _, id in ipairs(ids) do
        if id:find('license:', 1, true) then
            return id
        end
    end
    return 'src:' .. tostring(source)
end


RegisterNetEvent('nb_pawnshop:toggleClock', function()
    local src = source
    local player = select(1, getFrameworkPlayer(src))
    if not player or not Config.Owner or not Config.Owner.job then return end

    local rawJobName, grade = getJobInfo(player)
    local jobName = rawJobName and string.lower(tostring(rawJobName)) or ''
    if jobName ~= string.lower(tostring(Config.Owner.job)) then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Staff only.', 'error')
        return
    end
    if grade < (tonumber(Config.Owner.minGrade) or 1) then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Staff only.', 'error')
        return
    end

    local key = (player.PlayerData and player.PlayerData.citizenid) and ('cid:'..tostring(player.PlayerData.citizenid)) or ('src:'..tostring(src))
    local entry = StaffClock[key]
    if entry and entry.clockedIn then
        StaffClock[key] = nil
        TriggerClientEvent('nb_pawnshop:notify', src, 'Clocked out.', 'success')
    else
        StaffClock[key] = {
            src = src,
            name = getPlayerName(src, player),
            grade = grade,
            since = os.date('%Y-%m-%d %H:%M:%S')
        }
        TriggerClientEvent('nb_pawnshop:notify', src, 'Clocked in.', 'success')
    end
end)

lib.callback.register('nb_pawnshop:getMyStaffStatus', function(source)
    local player = select(1, getFrameworkPlayer(source))
    local status = { clockedIn = false, grade = 0 }
    if not player then return status end

    local _, grade = getJobInfo(player)
    status.grade = grade

    local key = (player.PlayerData and player.PlayerData.citizenid) and ('cid:'..tostring(player.PlayerData.citizenid)) or ('src:'..tostring(source))
    status.clockedIn = StaffClock[key] ~= nil
    return status
end)

lib.callback.register('nb_pawnshop:getActiveStaff', function(source)
    local list = {}
    for _, v in pairs(StaffClock) do
        if v and v.src and GetPlayerPing(v.src) ~= 0 then
            list[#list+1] = { name = v.name, grade = v.grade, since = v.since }
        end
    end
    table.sort(list, function(a,b) return (a.name or '') < (b.name or '') end)
    return list
end)


lib.callback.register('nb_pawnshop:getCustomerSellables', function(source, targetId)
    local staff = select(1, getFrameworkPlayer(source))
    if not staff or not Config.Owner or not Config.Owner.job then return {} end

    local rawJobName = select(1, getJobInfo(staff))
    local jobName = rawJobName and string.lower(tostring(rawJobName)) or ''
    if jobName ~= string.lower(tostring(Config.Owner.job)) then return {} end

    -- Optional: require clocked in
    if Config.ClockIn and Config.ClockIn.enabled and Config.ClockIn.requireClockedInForCounter then
        local key = (staff.PlayerData and staff.PlayerData.citizenid) and ('cid:'..tostring(staff.PlayerData.citizenid)) or ('src:'..tostring(source))
        if not StaffClock[key] then
            return {}
        end
    end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return {} end

    local items = exports.ox_inventory:GetInventoryItems(targetId)
    local result = {}
    if not items then return result end

    for _, slot in pairs(items) do
        if slot and slot.name and slot.count and slot.count > 0 then
            local itemData = exports.ox_inventory:Items(slot.name)
            local price = resolveSellPrice(slot.name, itemData)
            if price then
                result[#result+1] = {
                    name = slot.name,
                    label = (itemData and itemData.label) or slot.name,
                    count = slot.count,
                    price = price
                }
            end
        end
    end

    table.sort(result, function(a,b) return (a.label or a.name) < (b.label or b.name) end)
    return result
end)

RegisterNetEvent('nb_pawnshop:staffBuyFromCustomer', function(targetId, itemName, qty)
    local src = source
    local staff = select(1, getFrameworkPlayer(src))
    if not staff or not Config.Owner or not Config.Owner.job then return end

    local rawJobName, grade = getJobInfo(staff)
    local jobName = rawJobName and string.lower(tostring(rawJobName)) or ''
    if jobName ~= string.lower(tostring(Config.Owner.job)) then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Staff only.', 'error')
        return
    end

    if grade < (tonumber(Config.Owner.minGrade) or 1) then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Staff only.', 'error')
        return
    end

    if Config.ClockIn and Config.ClockIn.enabled and Config.ClockIn.requireClockedInForCounter then
        local key = (staff.PlayerData and staff.PlayerData.citizenid) and ('cid:'..tostring(staff.PlayerData.citizenid)) or ('src:'..tostring(src))
        if not StaffClock[key] then
            TriggerClientEvent('nb_pawnshop:notify', src, 'You must be clocked in to use the counter.', 'error')
            return
        end
    end

    targetId = tonumber(targetId)
    qty = tonumber(qty) or 0
    if not targetId or targetId <= 0 or qty <= 0 then return end
    if type(itemName) ~= 'string' then return end

    ensureStockStash()

    local itemData = exports.ox_inventory:Items(itemName)
    local price = resolveSellPrice(itemName, itemData)
    if not price then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Item not buyable by pawnshop.', 'error')
        return
    end

    local targetPing = GetPlayerPing(targetId)
    if not targetPing or targetPing == 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Customer is not online.', 'error')
        return
    end

    local count = exports.ox_inventory:GetItemCount(targetId, itemName)
    if not count or count < qty then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Customer does not have enough of that item.', 'error')
        return
    end

    -- Move per-slot to preserve metadata (important for weapons)
    local slotsData = exports.ox_inventory:GetSlotsWithItem(targetId, itemName)
    if not slotsData or #slotsData == 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Could not find item slots.', 'error')
        return
    end

    local remaining = qty
    local moved = 0
    for _, slot in ipairs(slotsData) do
        if remaining <= 0 then break end
        local take = math.min(remaining, slot.count)
        local ok = exports.ox_inventory:RemoveItem(targetId, itemName, take, slot.metadata, slot.slot)
        if ok then
            exports.ox_inventory:AddItem(Config.StockStash.id, itemName, take, slot.metadata)
            remaining = remaining - take
            moved = moved + take
        end
    end

    if moved <= 0 then
        TriggerClientEvent('nb_pawnshop:notify', src, 'Transaction failed.', 'error')
        return
    end

    local payout = math.floor(price * moved)

    if _bankEnabled() then
        local okSub = _bankSub(payout)
        if not okSub then
            -- Return items back to customer (undo move to stock)
            exports.ox_inventory:AddItem(targetId, itemName, moved)
            exports.ox_inventory:RemoveItem(Config.StockStash.id, itemName, moved)
            TriggerClientEvent('nb_pawnshop:notify', src, 'Business account has insufficient funds. Cancelled.', 'error')
            TriggerClientEvent('nb_pawnshop:notify', targetId, 'Pawnshop cannot pay you right now. Sale cancelled.', 'error')
            return
        end
    end

    if not addCash(targetId, payout) then
        -- Refund customer and remove from stock if payout fails
        exports.ox_inventory:AddItem(targetId, itemName, moved)
        exports.ox_inventory:RemoveItem(Config.StockStash.id, itemName, moved)
        if _bankEnabled() then _bankAdd(payout) end
        TriggerClientEvent('nb_pawnshop:notify', src, 'Could not pay customer. Cancelled.', 'error')
        TriggerClientEvent('nb_pawnshop:notify', targetId, 'Pawnshop could not pay you. Sale cancelled.', 'error')
        return
    end

    TriggerClientEvent('nb_pawnshop:notify', src, ('Purchased %sx %s from ID %s for $%s'):format(moved, itemName, targetId, payout), 'success')
    TriggerClientEvent('nb_pawnshop:notify', targetId, ('Sold %sx %s to pawnshop for $%s'):format(moved, itemName, payout), 'success')
end)
