Config = {}

-- 'auto' (detect running framework), 'esx', 'qbx' (qbx_core), 'qb' (qb-core), 'standalone' (ox_inventory money item)
Config.Framework = 'auto'
Config.MoneyItem = 'money' -- only used for standalone

-- Staff / Owner permissions (QBOX jobs)
Config.Owner = {
    job = 'pawnshop',
    minGrade = 1,   -- employees
    bossGrade = 4   -- owner
}



-- Business Banking (optional)
-- When enabled:
--  - Customer BUYBACK purchases add money to business bank
--  - Pawnshop purchases from customers are paid out from business bank (must have funds)
--  - Boss can deposit/withdraw via Management menu
Config.BusinessBank = {
    enabled = true,
    storage = 'auto',          -- 'auto' | 'mysql' | 'kvp'
    accountId = 'sandy',       -- used for MySQL row key
    startingBalance = 0,       -- used when no stored balance exists yet
    kvpKey = 'nb_pawnshop_bank_sandy',
    mysqlTable = 'nb_pawnshop_business_accounts'
}

-- Staff management (boss-only menu)
Config.StaffManagement = {
    enabled = true,
    fireJob = 'unemployed',    -- job to set when firing
    fireGrade = 0
}
-- Customer interaction point (NO PED). Set enabled=false to disable spawning a ped.
Config.Ped = {
    enabled = false,
    model = 'a_m_m_skater_01',
    vec4(-374.45, -117.25, 38.7, 174.29)
}

-- Management desk target (NO PED here) - your desk coords
Config.Management = {
    coords = vec4(-328.34, -91.43, 47.87, 253.46),
    radius = 1.6,
}



-- Employee counter interaction (NO extra PED; just a target zone near the front counter)
Config.Counter = {
    coords = vec4(-302.95, -107.15, 47.05, 300.87),
    radius = 1.8
}

-- Staff clock-in system (used for active employee status + optional restrictions)
Config.ClockIn = {
    enabled = true,
    requireClockedInForCounter = true
}

Config.Blip = {
    enabled = true,
    coords = vec3(-328.34, -91.45, 47.87), -- Legion Square area
    sprite = 431,
    scale = 0.9,
    colour = 5,
    name = 'Pawn Shop'
}

-- Pawnshop "stock" inventory (everything players sell goes here, and can be bought back)
Config.StockStash = {
    id = 'nb_pawnshop_stock_sandy',
    label = 'Pawn Shop Stock',
    slots = 200,
    maxWeight = 2000000, -- 2000kg (grams)
}

-- BUY BACK pricing: how much players pay to buy items from stock.
Config.BuyBackMultiplier = 1.35

-- Manual overrides (exact prices). If an item is listed here, it can be sold.
Config.SellPrices = {
    -- ['goldchain'] = 120,
    -- ['rolex'] = 350,
    -- ['diamondring'] = 500,
}

-- Auto sell categories: jewelry + weapons
Config.AutoSell = {
    enabled = true,
    jewelry = true,
    weapons = true,
}

-- Default prices used when AutoSell detects an item but you haven't manually set a price.
Config.DefaultPrices = {
    -- Heist / hacking tools
    lockpick = 150,
    advancedlockpick = 500,
    screwdriverset = 250,
    electronickit = 500,
    pliers = 250,
    laptop = 2000,
    laptop_card = 750,
    drill = 2500,
    fleeca_drill = 2500,
    thermite = 2500,
    gatecrack = 1000,
    cryptostick = 3000,
    trojan_usb = 1500,

    -- USBs
    usb_black = 500,
    usb_green = 500,
    usb_blue = 500,
    usb_red = 500,
    usb_purple = 500,

    -- Security cards
    security_card_01 = 1500,
    security_card_02 = 2000,

    -- Smash n Grab loot
    stolen_bag = 2500,
    stolen_weapon_case = 5000,
    expensive_bag = 2000,
    expensive_sneakers = 1500,

    -- Bobcat heist
    bag = 500,
    bobcatcard = 2000,
    bobcatcard2 = 3500,
    x_device = 5000,
    x_phone = 1500,
    x_stethoscope = 1000,
}

-- Optional: staff tablet item (if you have a matching ox_inventory item)
