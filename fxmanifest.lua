fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'JKT Cinema'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    '@jo_libs/init.lua'
}

jo_libs {
    'menu',
  }

ui_page "nui://jo_libs/nui/menu/index.html"

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'rsg-core'
}