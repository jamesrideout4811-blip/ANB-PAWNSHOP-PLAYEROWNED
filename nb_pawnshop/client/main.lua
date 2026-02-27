local function spawnPed()
    local model = joaat(Config.Ped.model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local ped = CreatePed(4, model, Config.Ped.x, Config.Ped.y, Config.Ped.z, Config.Ped.h, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    -- CUSTOMER MENU (sell/buyback)
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'nb_pawnshop_open',
            label = 'Open Pawn Shop',
            icon = 'fa-solid fa-shop',
            onSelect = function()
                TriggerEvent('nb_pawnshop:openMain')
            end
        }
    })
end

local function createBlip()
    if not Config.Blip.enabled then return end

    local blip = AddBlipForCoord(Config.Ped.x, Config.Ped.y, Config.Ped.z)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipScale(blip, Config.Blip.scale)
    SetBlipColour(blip, Config.Blip.colour)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.name)
    EndTextCommandSetBlipName(blip)
end


local function _resourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function _debugPrint(msg)
    print(('[NB Pawnshop] %s'):format(msg))
end

-- NUI readiness handshake:
-- If the player clicks the target before the NUI page finishes loading,
-- SendNUIMessage can be dropped and the player ends up with focus but no UI.
-- We solve this by having the UI POST a "ready" callback on load.
local nuiReady = false

local function waitForNuiReady(timeoutMs)
    timeoutMs = timeoutMs or 2000
    local start = GetGameTimer()
    while not nuiReady and (GetGameTimer() - start) < timeoutMs do
        Wait(25)
    end
    return nuiReady
end

-- =============================
-- NUI FALLBACK INITIALIZER
-- =============================
-- If client/nui.lua fails to load for any reason, ox_target will still call the
-- management function from this file. To prevent nil-call errors and to ensure
-- the UI always works, we provide a guarded fallback initializer here.
local function ensureNuiInitialized()
    if _G.__NB_PAWNSHOP_NUI_INIT then return end
    _G.__NB_PAWNSHOP_NUI_INIT = true

    local isOpen = false
    local currentMode = nil -- 'pawn' | 'manage'

    local function _title()
        return (Config.Blip and Config.Blip.name) or 'Pawn Shop'
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
        SendNUIMessage({ action = 'updatePawn', sellables = sellables, stock = stock })
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
        SendNUIMessage({ action = 'updateManage', manage = manage })
    end

    -- Exposed functions (called from targets)
    function OpenPawnshopUI()
        currentMode = 'pawn'
        if not waitForNuiReady(2500) then
            -- Don't steal focus if the UI hasn't loaded yet
            lib.notify({ title = _title(), description = 'UI is still loading. Try again in a moment.', type = 'error' })
            return
        end
        setFocus(true)
        local sellables = lib.callback.await('nb_pawnshop:getSellables', false) or {}
        local stock = lib.callback.await('nb_pawnshop:getStock', false) or {}
        SendNUIMessage({ action = 'open', mode = 'pawn', title = _title(), sellables = sellables, stock = stock })
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

        SendNUIMessage({ action = 'open', mode = 'manage', nav = defaultNav or 'dash', title = _title(), manage = manage })
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
        refreshManage()
        cb({ ok = true })
    end)
end

-- Make sure the OpenPawnshop* functions exist before ox_target can call them.
ensureNuiInitialized()

-- Target creation: try qb-target zones, then ox_target zones, then ox_target local entity fallback.
local function addDeskAndCounterTargets(openManagementFn, openCounterFn)
    local desk = Config.Management.coords
    local counter = Config.Counter.coords

    -- 1) qb-target (optional)
    if _resourceStarted('qb-target') then
        _debugPrint('Using qb-target for desk/counter.')
        local function addBox(name, coords4, label, icon, cb)
            exports['qb-target']:AddBoxZone(
                name,
                vec3(coords4.x, coords4.y, coords4.z),
                1.2, 1.2,
                {
                    name = name,
                    heading = coords4.w or 0.0,
                    debugPoly = false,
                    minZ = coords4.z - 1.0,
                    maxZ = coords4.z + 1.5,
                },
                {
                    options = {
                        { label = label, icon = icon, action = cb }
                    },
                    distance = 2.5
                }
            )
        end

        addBox('nb_pawnshop_mgmt', desk, 'Pawn Shop Management', 'fa-solid fa-user-gear', openManagementFn)
        addBox('nb_pawnshop_counter', counter, 'Employee Counter', 'fa-solid fa-cash-register', openCounterFn)
        return true
    end

    -- 2) ox_target zones (optional)
    if _resourceStarted('ox_target') then
        _debugPrint('qb-target not started. Trying ox_target zones for desk/counter.')

        local function toVec3(c) return vec3(c.x, c.y, c.z) end
        local function trySphere(zoneName, coords4, radius, options)
            local v3 = toVec3(coords4)
            local ok = pcall(function()
                exports.ox_target:addSphereZone({
                    name = zoneName,
                    coords = v3,
                    radius = radius,
                    debug = false,
                    options = options
                })
            end)
            if ok then return true end

            ok = pcall(function()
                exports.ox_target:addSphereZone(zoneName, v3, radius, {
                    name = zoneName,
                    debugPoly = false,
                    useZ = true,
                    options = options
                })
            end)
            if ok then return true end

            return false
        end

        local mgmtOk = trySphere('nb_pawnshop_mgmt_zone', desk, Config.Management.radius or 1.6, {
            { name='nb_pawnshop_mgmt', label='Pawn Shop Management', icon='fa-solid fa-user-gear', distance=2.5, onSelect=openManagementFn }
        })
        local counterOk = trySphere('nb_pawnshop_counter_zone', counter, Config.Counter.radius or 1.8, {
            { name='nb_pawnshop_employee_counter', label='Employee Counter', icon='fa-solid fa-cash-register', distance=2.5, onSelect=openCounterFn }
        })

        if mgmtOk or counterOk then
            _debugPrint('ox_target zone targets created.')
            return true
        end

        _debugPrint('ox_target zones failed. Falling back to local entity targets.')
    end

    -- 3) fallback: invisible local props + ox_target addLocalEntity
    if _resourceStarted('ox_target') then
        _debugPrint('Using ox_target local entity fallback for desk/counter.')
        local function spawnTargetProp(coords4)
            local model = joaat('prop_tool_box_04')
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(0) end
            local obj = CreateObject(model, coords4.x, coords4.y, coords4.z - 0.2, false, false, false)
            SetEntityHeading(obj, coords4.w or 0.0)
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            SetEntityCollision(obj, true, true)
            SetEntityAlpha(obj, 0, false)
            SetEntityVisible(obj, true, false)
            return obj
        end

        local deskObj = spawnTargetProp(desk)
        local counterObj = spawnTargetProp(counter)

        exports.ox_target:addLocalEntity(deskObj, {
            { name='nb_pawnshop_mgmt', label='Pawn Shop Management', icon='fa-solid fa-user-gear', distance=2.5, onSelect=openManagementFn }
        })
        exports.ox_target:addLocalEntity(counterObj, {
            { name='nb_pawnshop_employee_counter', label='Employee Counter', icon='fa-solid fa-cash-register', distance=2.5, onSelect=openCounterFn }
        })
        return true
    end

    _debugPrint('No target system started (qb-target/ox_target). Desk/counter targets cannot be created.')
    return false
end



local function openBusinessBank()
    local bal = lib.callback.await('nb_pawnshop:getBankBalance', false) or 0
    local options = {
        {
            title = ('Current Balance: $%s'):format(bal),
            description = 'Business account balance (all earnings go here when enabled).',
            icon = 'fa-solid fa-wallet',
            disabled = true
        },
        {
            title = 'Deposit',
            description = 'Move cash from your pocket into the business account',
            icon = 'fa-solid fa-circle-arrow-up',
            onSelect = function()
                local input = lib.inputDialog('Business Banking • Deposit', {
                    { type = 'number', label = 'Amount', description = 'Cash to deposit', required = true, min = 1 }
                })
                if not input or not input[1] then return end
                local resp = lib.callback.await('nb_pawnshop:bankDeposit', false, tonumber(input[1]))
                if resp and resp.ok then
                    lib.notify({ title = 'Business Banking', description = ('Deposited $%s. New balance: $%s'):format(input[1], resp.balance or 0), type = 'success' })
                else
                    lib.notify({ title = 'Business Banking', description = (resp and resp.message) or 'Deposit failed.', type = 'error' })
                end
                openBusinessBank()
            end
        },
        {
            title = 'Withdraw',
            description = 'Move money from the business account into your pocket',
            icon = 'fa-solid fa-circle-arrow-down',
            onSelect = function()
                local input = lib.inputDialog('Business Banking • Withdraw', {
                    { type = 'number', label = 'Amount', description = 'Cash to withdraw', required = true, min = 1 }
                })
                if not input or not input[1] then return end
                local resp = lib.callback.await('nb_pawnshop:bankWithdraw', false, tonumber(input[1]))
                if resp and resp.ok then
                    lib.notify({ title = 'Business Banking', description = ('Withdrew $%s. New balance: $%s'):format(input[1], resp.balance or 0), type = 'success' })
                else
                    lib.notify({ title = 'Business Banking', description = (resp and resp.message) or 'Withdraw failed.', type = 'error' })
                end
                openBusinessBank()
            end
        }
    }

    lib.registerContext({
        id = 'nb_pawnshop_bank',
        title = (Config.Blip.name or 'Pawn Shop') .. ' • Business Banking',
        options = options
    })

    lib.showContext('nb_pawnshop_bank')
end

local function openStaffManagement()
    local options = {
        {
            title = 'Hire / Set Grade',
            description = 'Set a player to pawnshop job by Server ID',
            icon = 'fa-solid fa-user-plus',
            onSelect = function()
                local input = lib.inputDialog('Staff Management • Hire / Set Grade', {
                    { type = 'number', label = 'Server ID', required = true, min = 1 },
                    { type = 'number', label = 'Grade (0-4)', required = true, min = 0, max = 10 }
                })
                if not input or not input[1] or input[2] == nil then return end
                local resp = lib.callback.await('nb_pawnshop:setStaffJob', false, tonumber(input[1]), tonumber(input[2]))
                if resp and resp.ok then
                    lib.notify({ title = 'Staff Management', description = resp.message or 'Updated staff.', type = 'success' })
                else
                    lib.notify({ title = 'Staff Management', description = (resp and resp.message) or 'Failed.', type = 'error' })
                end
                openStaffManagement()
            end
        },
        {
            title = 'Fire',
            description = 'Remove a player from the pawnshop job by Server ID',
            icon = 'fa-solid fa-user-xmark',
            onSelect = function()
                local input = lib.inputDialog('Staff Management • Fire', {
                    { type = 'number', label = 'Server ID', required = true, min = 1 }
                })
                if not input or not input[1] then return end
                local resp = lib.callback.await('nb_pawnshop:fireStaff', false, tonumber(input[1]))
                if resp and resp.ok then
                    lib.notify({ title = 'Staff Management', description = resp.message or 'Fired.', type = 'success' })
                else
                    lib.notify({ title = 'Staff Management', description = (resp and resp.message) or 'Failed.', type = 'error' })
                end
                openStaffManagement()
            end
        }
    }

    lib.registerContext({
        id = 'nb_pawnshop_staff',
        title = (Config.Blip.name or 'Pawn Shop') .. ' • Staff Management',
        options = options
    })

    lib.showContext('nb_pawnshop_staff')
end


local function openManagement()
    OpenPawnshopManagementUI('dash')
end


local function createManagementZone()
    createCounterZone()
    local c = Config.Management.coords
    exports.ox_target:addSphereZone({
        coords = vec3(c.x, c.y, c.z),
        radius = Config.Management.radius or 0.9,
        debug = false,
        drawSprite = true,
        options = {
            {
                name = 'nb_pawnshop_mgmt',
                label = 'Pawn Shop Management',
                icon = 'fa-solid fa-user-gear',
                onSelect = openManagement,
                distance = 2.5,
            }
        }
    })
end


local function openEmployeeCounter()
    local ok = lib.callback.await('nb_pawnshop:isStaff', false)
    if not ok then
        lib.notify({ title = Config.Blip.name or 'Pawn Shop', description = 'Staff only.', type = 'error' })
        return
    end

    local status = lib.callback.await('nb_pawnshop:getMyStaffStatus', false) or { clockedIn = false }
    if Config.ClockIn and Config.ClockIn.enabled and Config.ClockIn.requireClockedInForCounter and not status.clockedIn then
        lib.notify({ title = Config.Blip.name or 'Pawn Shop', description = 'You must be clocked in to use the counter.', type = 'error' })
        return
    end

    OpenPawnshopManagementUI('counter')
end

local function createCounterZone()
    if not Config.Counter or not Config.Counter.coords then return end
    exports.ox_target:addSphereZone({
        coords = vec3(Config.Counter.coords.x, Config.Counter.coords.y, Config.Counter.coords.z),
        radius = Config.Counter.radius or 1.2,
        debug = false,
        drawSprite = true,
        options = {
            {
                name = 'nb_pawnshop_employee_counter',
                label = 'Employee Counter',
                icon = 'fa-solid fa-cash-register',
                onSelect = openEmployeeCounter,
                distance = 2.5,
            }
        }
    })
end

CreateThread(function()
    Wait(2000)
    _debugPrint('Client starting...')
    spawnPed()
    createBlip()
    addDeskAndCounterTargets(openManagement, openEmployeeCounter)
end)

local function sellMenu()
    local list = lib.callback.await('nb_pawnshop:getSellables', false)
    local options = {}

    if list and #list > 0 then
        for _, entry in ipairs(list) do
            options[#options+1] = {
                title = ('%s'):format(entry.label or entry.name),
                description = ('You have %s • Sell for $%s each'):format(entry.count, entry.price),
                icon = 'fa-solid fa-hand-holding-dollar',
                onSelect = function()
                    local input = lib.inputDialog('Sell Item', {
                        { type = 'number', label = 'Quantity', required = true, min = 1, max = entry.count, default = 1 },
                    })
                    if not input then return end
                    local qty = tonumber(input[1]) or 1
                    TriggerServerEvent('nb_pawnshop:sellItem', entry.name, qty)
                end
            }
        end
    else
        options[#options+1] = { title = 'Nothing to sell', description = 'No jewelry/weapons detected, or SellPrices not set.', disabled = true }
    end

    lib.registerContext({ id = 'nb_pawnshop_sell', title = 'Sell to Pawn Shop', options = options })
    lib.showContext('nb_pawnshop_sell')
end

local function buyBackMenu()
    local stock = lib.callback.await('nb_pawnshop:getStock', false)
    local options = {}

    if stock and #stock > 0 then
        for _, entry in ipairs(stock) do
            options[#options+1] = {
                title = ('%s'):format(entry.label or entry.name),
                description = ('In stock: %s • Price: $%s each'):format(entry.count, entry.price),
                icon = 'fa-solid fa-cart-shopping',
                onSelect = function()
                    local input = lib.inputDialog('Buy Item', {
                        { type = 'number', label = 'Quantity', required = true, min = 1, max = entry.count, default = 1 },
                    })
                    if not input then return end
                    local qty = tonumber(input[1]) or 1
                    TriggerServerEvent('nb_pawnshop:buyFromStock', entry.name, qty)
                end
            }
        end
    else
        options[#options+1] = { title = 'No stock yet', description = 'Nobody has sold anything yet.', disabled = true }
    end

    lib.registerContext({ id = 'nb_pawnshop_buyback', title = 'Buy Back Stock', options = options })
    lib.showContext('nb_pawnshop_buyback')
end

RegisterNetEvent('nb_pawnshop:openMain', function()
    OpenPawnshopUI()
end)

RegisterNetEvent('nb_pawnshop:notify', function(msg, typ)
    lib.notify({ title = Config.Blip.name or 'Pawn Shop', description = msg, type = typ or 'inform' })
end)