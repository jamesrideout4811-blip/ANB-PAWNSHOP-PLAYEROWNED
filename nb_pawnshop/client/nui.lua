-- Guard: prevents duplicate NUI handler registration if the file is executed twice
-- or if main.lua provides a fallback initializer.
if _G.__NB_PAWNSHOP_NUI_INIT then return end
_G.__NB_PAWNSHOP_NUI_INIT = true

local isOpen = false
local currentMode = nil -- 'pawn' | 'manage'

-- NUI readiness handshake.
-- First click can happen before UI finishes loading, which can drop SendNUIMessage.
-- The UI will POST a 'ready' callback on load; we wait for it before taking focus.
local nuiReady = false

local function waitForNuiReady(timeoutMs)
    timeoutMs = timeoutMs or 2500
    local start = GetGameTimer()
    while not nuiReady and (GetGameTimer() - start) < timeoutMs do
        Wait(25)
    end
    return nuiReady
end

local function _title()
    return Config.Blip and Config.Blip.name or 'Pawn Shop'
end

local function sendToast(typ, title, desc)
    SendNUIMessage({
        action = 'toast',
        type = typ or 'info',
        title = title or '',
        desc = desc or ''
    })
end

local function setFocus(state)
    isOpen = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function refreshPawn()
    local sellables = lib.callback.await('nb_pawnshop:getSellables', false) or {}
    local stock = lib.callback.await('nb_pawnshop:getStock', false) or {}
    SendNUIMessage({
        action = 'updatePawn',
        sellables = sellables,
        stock = stock
    })
end

local function refreshManage()
    local manage = {}
    manage.isBoss = lib.callback.await('nb_pawnshop:isBoss', false) == true
    local status = lib.callback.await('nb_pawnshop:getMyStaffStatus', false) or { clockedIn = false, grade = 0 }
    manage.clockedIn = status.clockedIn == true
    manage.grade = status.grade or 0
    manage.activeStaff = lib.callback.await('nb_pawnshop:getActiveStaff', false) or {}
    manage.businessBankEnabled = (Config.BusinessBank and Config.BusinessBank.enabled) or false
    manage.staffManagementEnabled = (Config.StaffManagement and Config.StaffManagement.enabled) or false

    if manage.businessBankEnabled then
        manage.bankBalance = lib.callback.await('nb_pawnshop:getBankBalance', false) or 0
    else
        manage.bankBalance = 0
    end

    SendNUIMessage({
        action = 'updateManage',
        manage = manage
    })
end

function OpenPawnshopUI()
    currentMode = 'pawn'

    if not waitForNuiReady(2500) then
        lib.notify({ title = _title(), description = 'UI is still loading. Try again in a moment.', type = 'error' })
        return
    end

    setFocus(true)
    local sellables = lib.callback.await('nb_pawnshop:getSellables', false) or {}
    local stock = lib.callback.await('nb_pawnshop:getStock', false) or {}

    SendNUIMessage({
        action = 'open',
        mode = 'pawn',
        title = _title(),
        sellables = sellables,
        stock = stock
    })
end

function OpenPawnshopManagementUI(defaultNav)
    local ok = lib.callback.await('nb_pawnshop:isStaff', false)
    if not ok then
        lib.notify({ title = _title(), description = 'Staff only.', type = 'error' })
        return
    end

    currentMode = 'manage'

    if not waitForNuiReady(2500) then
        lib.notify({ title = _title(), description = 'UI is still loading. Try again in a moment.', type = 'error' })
        return
    end

    setFocus(true)

    local manage = {}
    manage.isBoss = lib.callback.await('nb_pawnshop:isBoss', false) == true
    local status = lib.callback.await('nb_pawnshop:getMyStaffStatus', false) or { clockedIn = false, grade = 0 }
    manage.clockedIn = status.clockedIn == true
    manage.grade = status.grade or 0
    manage.activeStaff = lib.callback.await('nb_pawnshop:getActiveStaff', false) or {}
    manage.businessBankEnabled = (Config.BusinessBank and Config.BusinessBank.enabled) or false
    manage.staffManagementEnabled = (Config.StaffManagement and Config.StaffManagement.enabled) or false
    if manage.businessBankEnabled then
        manage.bankBalance = lib.callback.await('nb_pawnshop:getBankBalance', false) or 0
    else
        manage.bankBalance = 0
    end

    SendNUIMessage({
        action = 'open',
        mode = 'manage',
        nav = defaultNav or 'dash',
        title = _title(),
        manage = manage
    })
end

-- NUI callbacks
RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    setFocus(false)
    currentMode = nil
    SendNUIMessage({ action = 'hide' })
    cb({ ok = true })
end)

RegisterNUICallback('refreshPawn', function(_, cb)
    refreshPawn()
    cb({ ok = true })
end)

RegisterNUICallback('sell', function(data, cb)
    local item = data and data.item
    local qty = tonumber(data and data.qty) or 1
    if type(item) ~= 'string' then cb({ ok = false }); return end
    TriggerServerEvent('nb_pawnshop:sellItem', item, qty)
    Wait(250)
    refreshPawn()
    cb({ ok = true })
end)

RegisterNUICallback('buyback', function(data, cb)
    local item = data and data.item
    local qty = tonumber(data and data.qty) or 1
    if type(item) ~= 'string' then cb({ ok = false }); return end
    TriggerServerEvent('nb_pawnshop:buyFromStock', item, qty)
    Wait(250)
    refreshPawn()
    cb({ ok = true })
end)

RegisterNUICallback('openStock', function(_, cb)
    local okOpen = pcall(function()
        exports.ox_inventory:openInventory('stash', Config.StockStash.id)
    end)
    if not okOpen then
        exports.ox_inventory:openInventory('stash', { id = Config.StockStash.id })
    end
    cb({ ok = true })
end)

RegisterNUICallback('toggleClock', function(_, cb)
    TriggerServerEvent('nb_pawnshop:toggleClock')
    Wait(250)
    refreshManage()
    cb({ ok = true })
end)

RegisterNUICallback('bankDeposit', function(data, cb)
    local amount = tonumber(data and data.amount) or 0
    local res = lib.callback.await('nb_pawnshop:bankDeposit', false, amount)
    if res and res.ok then
        sendToast('success', 'Bank', res.message or 'Deposit successful.')
    else
        sendToast('error', 'Bank', (res and res.message) or 'Deposit failed.')
    end
    refreshManage()
    cb(res or { ok = false })
end)

RegisterNUICallback('bankWithdraw', function(data, cb)
    local amount = tonumber(data and data.amount) or 0
    local res = lib.callback.await('nb_pawnshop:bankWithdraw', false, amount)
    if res and res.ok then
        sendToast('success', 'Bank', res.message or 'Withdraw successful.')
    else
        sendToast('error', 'Bank', (res and res.message) or 'Withdraw failed.')
    end
    refreshManage()
    cb(res or { ok = false })
end)

RegisterNUICallback('staffSetJob', function(data, cb)
    local targetId = tonumber(data and data.targetId) or 0
    local grade = tonumber(data and data.grade) or 0
    local res = lib.callback.await('nb_pawnshop:setStaffJob', false, targetId, grade)
    if res and res.ok then
        sendToast('success', 'Staff', res.message or 'Updated staff.')
    else
        sendToast('error', 'Staff', (res and res.message) or 'Action failed.')
    end
    refreshManage()
    cb(res or { ok = false })
end)

RegisterNUICallback('staffFire', function(data, cb)
    local targetId = tonumber(data and data.targetId) or 0
    local res = lib.callback.await('nb_pawnshop:fireStaff', false, targetId)
    if res and res.ok then
        sendToast('success', 'Staff', res.message or 'Fired staff.')
    else
        sendToast('error', 'Staff', (res and res.message) or 'Action failed.')
    end
    refreshManage()
    cb(res or { ok = false })
end)

RegisterNUICallback('customerLookup', function(data, cb)
    local customerId = tonumber(data and data.customerId) or 0
    if customerId <= 0 then
        cb({ ok = false, message = 'Invalid customer ID.' })
        return
    end
    local items = lib.callback.await('nb_pawnshop:getCustomerSellables', false, customerId) or {}
    cb({ ok = true, items = items })
end)

RegisterNUICallback('staffBuyFromCustomer', function(data, cb)
    local customerId = tonumber(data and data.customerId) or 0
    local item = data and data.item
    local qty = tonumber(data and data.qty) or 1
    if customerId <= 0 or type(item) ~= 'string' then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('nb_pawnshop:staffBuyFromCustomer', customerId, item, qty)
    Wait(250)
    -- refresh bank + active staff, customer list will be refreshed client-side by UI (button) or user can hit refresh
    refreshManage()
    cb({ ok = true })
end)
