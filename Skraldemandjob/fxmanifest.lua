fx_version 'cerulean'
game 'gta5'

author 'Tony'
description 'Skraldemandjob ESX'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependency {
    'es_extended',
    'ox_lib'
}

lua54 'yes' 