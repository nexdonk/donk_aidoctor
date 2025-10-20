fx_version 'cerulean'
game 'gta5'

author 'donk'
description 'AI Doctor - Multi-framework emergency medical service with ox_lib support'
version '2.0.0'

-- Lua 5.4 support
lua54 'yes'

-- Dependencies
dependencies {
    '/server:5848', -- Minimum server version
    '/onesync',     -- OneSync required for proper entity handling
}

-- Optional dependencies (will be used if available)
-- ox_lib for better UI/UX
-- qb-core or es_extended for framework support

-- Shared scripts (loaded on both client and server)
shared_scripts {
    '@ox_lib/init.lua', -- Load ox_lib if available
    'config.lua',
    'shared/framework.lua'
}

-- Client scripts
client_scripts {
    'client/client.lua'
}

-- Server scripts
server_scripts {
    'server/server.lua'
}

-- Files to include in the resource
files {
    -- Add any additional files here if needed
}

-- Escrow (if using encryption - currently not needed)
-- escrow_ignore {
--     'config.lua',
--     'shared/framework.lua'
-- }
