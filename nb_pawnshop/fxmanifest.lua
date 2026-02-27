

fx_version 'cerulean'
game 'gta5'

author 'NB Scripts'
description 'NB Pawn Shop - Sandy Shores (sell/buyback + player-owned management zone)'
version '1.3.9-release'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

client_scripts {
    -- NUI helpers must load first (exports/handlers used by main.lua)
    'client/nui.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependency 'ox_lib'
dependency 'ox_target'
dependency 'ox_inventory'
