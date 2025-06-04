local QBCore = exports['qb-core']:GetCoreObject()
local testDriveData = {}

-- Función para obtener un routing bucket libre
local function GetFreeRoutingBucket()
    -- Si no hay soporte para routing buckets, devolver 0
    if not GetPlayerRoutingBucket or not SetPlayerRoutingBucket then
        return 0
    end
    
    local bucket = math.random(1000, 9999)
    
    -- Verificar que el bucket no esté en uso
    for _, data in pairs(testDriveData) do
        if data.bucket == bucket then
            return GetFreeRoutingBucket() -- Recursivo hasta encontrar uno libre
        end
    end
    
    return bucket
end

-- Función para verificar si el vehículo existe en la configuración
local function IsValidVehicle(vehicleModel)
    for _, veh in ipairs(Config.Vehicles) do
        if veh.model == vehicleModel then
            return true, veh
        end
    end
    return false, nil
end

-- Callback para iniciar prueba de vehículo usando ox_lib
lib.callback.register('vehicleShowroom:startTestDrive', function(source, vehicleModel)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then 
        return false, 'Error: Jugador no encontrado'
    end
    
    -- Verificar si ya está en prueba
    if testDriveData[src] then
        return false, Config.Notifications.alreadyTesting
    end
    
    -- Verificar que el vehículo sea válido
    local isValid, vehicleConfig = IsValidVehicle(vehicleModel)
    if not isValid then
        return false, Config.Notifications.invalidVehicle
    end
    
    -- Obtener coordenadas actuales
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    -- Crear nuevo routing bucket (solo si la función existe)
    local bucket = 0
    local originalBucket = 0
    local useRoutingBucket = false
    
    -- Verificar si las funciones de routing bucket están disponibles
    if GetPlayerRoutingBucket and SetPlayerRoutingBucket then
        useRoutingBucket = true
        bucket = GetFreeRoutingBucket()
        originalBucket = GetPlayerRoutingBucket(src)
        -- Cambiar routing bucket
        SetPlayerRoutingBucket(src, bucket)
    end
    
    -- Guardar datos de la prueba
    testDriveData[src] = {
        originalBucket = originalBucket,
        originalCoords = {x = coords.x, y = coords.y, z = coords.z, w = heading},
        bucket = bucket,
        vehicleModel = vehicleModel,
        startTime = os.time(),
        useRoutingBucket = useRoutingBucket
    }
    
    -- Iniciar prueba en cliente
    TriggerClientEvent('vehicleShowroom:startTestDriveClient', src, vehicleModel, bucket)
    
    if Config.Debug then
        if useRoutingBucket then
            print(('Player %s started test drive with %s in bucket %d'):format(src, vehicleModel, bucket))
        else
            print(('Player %s started test drive with %s (no routing bucket support)'):format(src, vehicleModel))
        end
    end
    
    -- Log para administradores
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshowroom', 'Test Drive Started', 'green', 
        ('**%s** started test driving **%s**'):format(Player.PlayerData.name, vehicleConfig.label))
    
    return true, 'Prueba iniciada correctamente'
end)

-- Callback para comprar vehículo usando ox_lib
lib.callback.register('vehicleShowroom:buyVehicle', function(source, vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then 
        return false, 'Error: Jugador no encontrado'
    end
    
    -- Verificar que el vehículo existe en la configuración
    local vehicleExists = false
    local vehicleConfig = nil
    
    for _, veh in ipairs(Config.Vehicles) do
        if veh.model == vehicleData.model then
            vehicleExists = true
            vehicleConfig = veh
            break
        end
    end
    
    if not vehicleExists then
        return false, Config.Notifications.invalidVehicle
    end
    
    -- Verificar dinero en efectivo
    local cash = Player.PlayerData.money['cash']
    
    if cash < vehicleData.price then
        return false, Config.Notifications.notEnoughMoney
    end
    
    -- Verificar que el ítem existe en qb-core
    local itemData = QBCore.Shared.Items[vehicleConfig.item]
    if not itemData then
        if Config.Debug then
            print(('Item %s not found in QBCore.Shared.Items'):format(vehicleConfig.item))
        end
        return false, 'Error: Ítem del vehículo no configurado correctamente'
    end
    
    -- Verificar si ya tiene este vehículo
    local hasItem = Player.Functions.GetItemByName(vehicleConfig.item)
    if hasItem then
        return false, 'Ya tienes este vehículo en tu inventario'
    end
    
    -- Verificar espacio en inventario
    local totalWeight = 0
    for _, item in pairs(Player.PlayerData.items) do
        if item then
            totalWeight = totalWeight + (item.weight * item.amount)
        end
    end
    
    if totalWeight + itemData.weight > Player.PlayerData.maxweight then
        return false, 'No tienes espacio suficiente en el inventario'
    end
    
    -- Remover dinero
    Player.Functions.RemoveMoney('cash', vehicleData.price, 'vehicle-showroom-purchase')
    
    -- Generar metadata para el ítem del vehículo
    local metadata = {
        vehicle = vehicleData.model,
        label = vehicleData.label,
        category = vehicleData.category,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S'),
        buyer = Player.PlayerData.name,
        citizenid = Player.PlayerData.citizenid,
        price = vehicleData.price
    }
    
    -- Añadir ítem del vehículo al inventario
    local itemAdded = Player.Functions.AddItem(vehicleConfig.item, 1, false, metadata)
    
    if itemAdded then
        if Config.Debug then
            print(('Player %s bought %s for $%d (Item: %s)'):format(src, vehicleData.model, vehicleData.price, vehicleConfig.item))
        end
        
        -- Log para administradores
        TriggerEvent('qb-log:server:CreateLog', 'vehicleshowroom', 'Vehicle Purchase', 'blue', 
            ('**%s** purchased **%s** for **$%d**'):format(Player.PlayerData.name, vehicleData.label, vehicleData.price))
        
        local successMessage = ('Has comprado un %s por $%d. Revisa tu inventario para encontrar el ítem: %s'):format(
            vehicleData.label, vehicleData.price, vehicleConfig.item
        )
        
        return true, successMessage, vehicleConfig.item
    else
        -- Si falla al añadir el ítem, devolver el dinero
        Player.Functions.AddMoney('cash', vehicleData.price, 'vehicle-showroom-refund')
        
        if Config.Debug then
            print(('Failed to add item %s to player %s'):format(vehicleConfig.item, src))
        end
        
        return false, 'Error al procesar la compra. Dinero devuelto.'
    end
end)

-- Event para iniciar prueba de vehículo
RegisterNetEvent('vehicleShowroom:startTestDrive', function(vehicleModel)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Verificar si ya está en prueba
    if testDriveData[src] then
        TriggerClientEvent('QBCore:Notify', src, Config.Notifications.alreadyTesting, 'error')
        return
    end
    
    -- Verificar que el vehículo sea válido
    local isValid, vehicleConfig = IsValidVehicle(vehicleModel)
    if not isValid then
        TriggerClientEvent('QBCore:Notify', src, Config.Notifications.invalidVehicle, 'error')
        return
    end
    
    -- Obtener coordenadas actuales
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    -- Crear nuevo routing bucket (solo si la función existe)
    local bucket = 0
    local originalBucket = 0
    local useRoutingBucket = false
    
    -- Verificar si las funciones de routing bucket están disponibles
    if GetPlayerRoutingBucket and SetPlayerRoutingBucket then
        useRoutingBucket = true
        bucket = GetFreeRoutingBucket()
        originalBucket = GetPlayerRoutingBucket(src)
        -- Cambiar routing bucket
        SetPlayerRoutingBucket(src, bucket)
    end
    
    -- Guardar datos de la prueba
    testDriveData[src] = {
        originalBucket = originalBucket,
        originalCoords = {x = coords.x, y = coords.y, z = coords.z, w = heading},
        bucket = bucket,
        vehicleModel = vehicleModel,
        startTime = os.time(),
        useRoutingBucket = useRoutingBucket
    }
    
    -- Iniciar prueba en cliente
    TriggerClientEvent('vehicleShowroom:startTestDriveClient', src, vehicleModel, bucket)
    
    if Config.Debug then
        if useRoutingBucket then
            print(('Player %s started test drive with %s in bucket %d'):format(src, vehicleModel, bucket))
        else
            print(('Player %s started test drive with %s (no routing bucket support)'):format(src, vehicleModel))
        end
    end
    
    -- Log para administradores
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshowroom', 'Test Drive Started', 'green', 
        ('**%s** started test driving **%s**'):format(Player.PlayerData.name, vehicleConfig.label))
end)

-- Event para finalizar prueba de vehículo
RegisterNetEvent('vehicleShowroom:endTestDrive', function()
    local src = source
    local data = testDriveData[src]
    
    if not data then return end
    
    -- Restaurar routing bucket original (solo si se usó)
    if data.useRoutingBucket and SetPlayerRoutingBucket then
        SetPlayerRoutingBucket(src, data.originalBucket)
    end
    
    -- Teletransportar de vuelta
    TriggerClientEvent('vehicleShowroom:endTestDriveClient', src, data.originalCoords)
    
    if Config.Debug then
        local testDuration = os.time() - data.startTime
        print(('Player %s ended test drive after %d seconds'):format(src, testDuration))
    end
    
    -- Limpiar datos
    testDriveData[src] = nil
end)

-- Event para comprar vehículo (ahora entrega ítem)
RegisterNetEvent('vehicleShowroom:buyVehicle', function(vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Verificar que el vehículo existe en la configuración
    local vehicleExists = false
    local vehicleConfig = nil
    
    for _, veh in ipairs(Config.Vehicles) do
        if veh.model == vehicleData.model then
            vehicleExists = true
            vehicleConfig = veh
            break
        end
    end
    
    if not vehicleExists then
        TriggerClientEvent('QBCore:Notify', src, Config.Notifications.invalidVehicle, 'error')
        return
    end
    
    -- Verificar dinero en efectivo
    local cash = Player.PlayerData.money['cash']
    
    if cash < vehicleData.price then
        TriggerClientEvent('QBCore:Notify', src, Config.Notifications.notEnoughMoney, 'error')
        return
    end
    
    -- Verificar que el ítem existe en qb-core
    local itemData = QBCore.Shared.Items[vehicleConfig.item]
    if not itemData then
        if Config.Debug then
            print(('Item %s not found in QBCore.Shared.Items'):format(vehicleConfig.item))
        end
        TriggerClientEvent('QBCore:Notify', src, 'Error: Ítem del vehículo no configurado correctamente', 'error')
        return
    end
    
    -- Verificar espacio en inventario
    local hasSpace = Player.Functions.GetItemByName(vehicleConfig.item)
    if hasSpace then
        TriggerClientEvent('QBCore:Notify', src, 'Ya tienes este vehículo en tu inventario', 'error')
        return
    end
    
    -- Verificar si el inventario tiene espacio
    local totalWeight = 0
    for _, item in pairs(Player.PlayerData.items) do
        if item then
            totalWeight = totalWeight + (item.weight * item.amount)
        end
    end
    
    if totalWeight + itemData.weight > Player.PlayerData.maxweight then
        TriggerClientEvent('QBCore:Notify', src, 'No tienes espacio suficiente en el inventario', 'error')
        return
    end
    
    -- Remover dinero
    Player.Functions.RemoveMoney('cash', vehicleData.price, 'vehicle-showroom-purchase')
    
    -- Generar metadata para el ítem del vehículo
    local metadata = {
        vehicle = vehicleData.model,
        label = vehicleData.label,
        category = vehicleData.category,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S'),
        buyer = Player.PlayerData.name,
        citizenid = Player.PlayerData.citizenid
    }
    
    -- Añadir ítem del vehículo al inventario
    local itemAdded = Player.Functions.AddItem(vehicleConfig.item, 1, false, metadata)
    
    if itemAdded then
        -- Notificar al cliente sobre la compra exitosa
        TriggerClientEvent('vehicleShowroom:purchaseSuccess', src, vehicleData.label, vehicleData.price, vehicleConfig.item)
        
        if Config.Debug then
            print(('Player %s bought %s for $%d (Item: %s)'):format(src, vehicleData.model, vehicleData.price, vehicleConfig.item))
        end
        
        -- Log para administradores
        TriggerEvent('qb-log:server:CreateLog', 'vehicleshowroom', 'Vehicle Purchase', 'blue', 
            ('**%s** purchased **%s** for **$%d**'):format(Player.PlayerData.name, vehicleData.label, vehicleData.price))
    else
        -- Si falla al añadir el ítem, devolver el dinero
        Player.Functions.AddMoney('cash', vehicleData.price, 'vehicle-showroom-refund')
        TriggerClientEvent('QBCore:Notify', src, 'Error al procesar la compra. Dinero devuelto.', 'error')
        
        if Config.Debug then
            print(('Failed to add item %s to player %s'):format(vehicleConfig.item, src))
        end
    end
end)

-- Event para forzar finalización de prueba (admin)
RegisterNetEvent('vehicleShowroom:forceEndTestDrive', function(targetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player or not QBCore.Functions.HasPermission(src, 'admin') then
        return
    end
    
    if testDriveData[targetId] then
        -- Restaurar routing bucket (solo si se usó)
        if testDriveData[targetId].useRoutingBucket and SetPlayerRoutingBucket then
            SetPlayerRoutingBucket(targetId, testDriveData[targetId].originalBucket)
        end
        
        -- Notificar al jugador
        TriggerClientEvent('vehicleShowroom:endTestDriveClient', targetId, testDriveData[targetId].originalCoords)
        TriggerClientEvent('QBCore:Notify', targetId, 'Tu prueba de vehículo fue finalizada por un administrador', 'error')
        
        -- Limpiar datos
        testDriveData[targetId] = nil
        
        TriggerClientEvent('QBCore:Notify', src, ('Prueba de vehículo finalizada para el jugador %d'):format(targetId), 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, 'El jugador no está en una prueba de vehículo', 'error')
    end
end)

-- Cleanup al desconectar jugador
AddEventHandler('playerDropped', function(reason)
    local src = source
    if testDriveData[src] then
        if Config.Debug then
            print(('Player %s disconnected during test drive'):format(src))
        end
        testDriveData[src] = nil
    end
end)

-- Comando para administradores: teleportar a showroom
QBCore.Commands.Add('showroom', 'Teleportar al showroom', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player.PlayerData.job.name == 'police' or QBCore.Functions.HasPermission(source, 'admin') then
        -- Usar las coordenadas del primer vehículo del showroom
        local coords = Config.Vehicles[1].coords
        TriggerClientEvent('QBCore:Command:TeleportToCoords', source, coords.x, coords.y, coords.z)
    else
        TriggerClientEvent('QBCore:Notify', source, 'No tienes permisos para usar este comando', 'error')
    end
end)

-- Comando para ver quién está en prueba de vehículo
QBCore.Commands.Add('testdrives', 'Ver jugadores en prueba de vehículo', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not QBCore.Functions.HasPermission(source, 'admin') then
        TriggerClientEvent('QBCore:Notify', source, 'No tienes permisos para usar este comando', 'error')
        return
    end
    
    local count = 0
    for playerId, data in pairs(testDriveData) do
        local targetPlayer = QBCore.Functions.GetPlayer(playerId)
        if targetPlayer then
            count = count + 1
            TriggerClientEvent('QBCore:Notify', source, 
                ('Jugador: %s (%d) - Vehículo: %s - Bucket: %d'):format(
                    targetPlayer.PlayerData.name, playerId, data.vehicleModel, data.bucket
                ), 'primary')
        end
    end
    
    if count == 0 then
        TriggerClientEvent('QBCore:Notify', source, 'No hay jugadores en prueba de vehículo', 'primary')
    else
        TriggerClientEvent('QBCore:Notify', source, ('Total de jugadores en prueba: %d'):format(count), 'success')
    end
end)

-- Comando para finalizar prueba de un jugador específico
QBCore.Commands.Add('endtestdrive', 'Finalizar prueba de vehículo de un jugador', {{name = 'id', help = 'ID del jugador'}}, true, function(source, args)
    local Player = QBCore.Functions.GetPlayer(source)
    if not QBCore.Functions.HasPermission(source, 'admin') then
        TriggerClientEvent('QBCore:Notify', source, 'No tienes permisos para usar este comando', 'error')
        return
    end
    
    local targetId = tonumber(args[1])
    if not targetId then
        TriggerClientEvent('QBCore:Notify', source, 'ID de jugador inválido', 'error')
        return
    end
    
    TriggerEvent('vehicleShowroom:forceEndTestDrive', source, targetId)
end)

-- Función para limpiar pruebas colgadas (cada 10 minutos)
CreateThread(function()
    while true do
        Wait(600000) -- 10 minutos
        
        local currentTime = os.time()
        for playerId, data in pairs(testDriveData) do
            if currentTime - data.startTime > (Config.TestDriveTime + 120) then -- 2 minutos de gracia
                if Config.Debug then
                    print(('Cleaning up stuck test drive for player %d'):format(playerId))
                end
                
                -- Restaurar routing bucket (solo si se usó)
                if data.useRoutingBucket and SetPlayerRoutingBucket then
                    SetPlayerRoutingBucket(playerId, data.originalBucket)
                end
                
                -- Limpiar datos
                testDriveData[playerId] = nil
            end
        end
    end
end)

print('^2[Vehicle Showroom] ^7Servidor cargado correctamente')
print('^3[Vehicle Showroom] ^7Vehículos configurados: ^2' .. #Config.Vehicles)
