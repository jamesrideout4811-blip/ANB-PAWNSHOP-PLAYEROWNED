# ANB-PAWNSHOP-PLAYEROWNED

Player-owned pawnshop with UI, stock buyback, staff tools, and optional business banking.

## Framework support
This resource now supports:
- **ESX** (`es_extended`)
- **QBCore** (`qb-core`)
- **Qbox** (`qbx_core`)
- **Standalone** cash fallback (money item via `ox_inventory`)

Set your framework in `nb_pawnshop/shared/config.lua`:

```lua
Config.Framework = 'auto' -- auto | esx | qb | qbx | standalone
```

`auto` detects in this order: `qbx_core` -> `qb-core` -> `es_extended` -> standalone.

If you have any issues, check config first and make sure your framework resource is started.
