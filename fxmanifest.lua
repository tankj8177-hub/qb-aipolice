fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-aipolice'
author 'Custom Build'
description 'AI Police - 7 star wanted, investigations, pursuits, witnesses, arrests, jail and optional integrations'
version '3.1.37'

shared_scripts {
    'config.lua',
    'shared/utils.lua'
}

client_scripts {
    'client/main.lua',
    'client/detection.lua',
    'client/police.lua',
    'client/arrest.lua',
    'client/integrations.lua',
    'client/ui.lua',
    'client/target.lua'
}

server_scripts {
    'server/storage.lua',
    'server/main.lua',
    'server/detection.lua',
    'server/commands.lua',
    'server/integrations.lua'
}

files {
    'html/ui.html',
    'html/ui.js',
    'html/ui.css',
    'data/*.json'
}

ui_page 'html/ui.html'
