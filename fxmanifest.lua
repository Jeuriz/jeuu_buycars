fx_version 'cerulean'
game 'gta5'

author 'TuNombre'
description 'Sistema de concesionario con prueba de vehículos'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'qb-core',
    'ox_target',
    'ox_lib'
}

lua54 'yes'
