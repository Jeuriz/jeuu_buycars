local QBCore = exports['qb-core']:GetCoreObject()
local testDriveData = {}

-- Sistema global de vehículos spawneados (sincronizado)
local globalSpawnedVehicles = {}
local playersNearShowroom = {}
local lastDistanceCheck = 0

-- HOTFIX: Asegurar que ox_lib esté cargado
if not lib then
    print('^1[Vehicle Showroom] ERROR: ox_lib no está disponible')
    return
end

-- Función para obtener un routing bucket libre
local function GetFreeRoutingBucket()
    if not GetPlayerRoutingBucket or not SetPlayerRoutingBucket then
        return 0
    end
    
    local bucket = math.random(1000, 9999)
    
    for _, data in pairs(testDriveData) do
        if data.bucket == bucket then
            return GetFreeRoutingBucket()
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

-- Función para verificar si algún jugador está cerca del showroom
local function CheckPlayersNearShowroom()
    local currentTime = GetGameTimer()
    
    -- Solo verificar cada 2 segundos para optimización
    if currentTime - lastDistanceCheck < 2000 then
        return
    end
    
    lastDistanceCheck = currentTime
    local previousPlayersNear = {}
    
    -- Copiar estado anterior
    for src, _ in pairs(playersNearShowroom) do
        previousPlayersNear[src] = true
    end
    
    -- Limpiar lista actual
    playersNearShowroom = {}
    
    -- Verificar cada jugador conectado
    local players = QBCore.Functions.GetPlayers()
    
    for _, src in ipairs(players) do
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                
                -- Verificar distancia a cualquier vehículo del showroom
                for i, vehicleData in ipairs(Config.Vehicles) do
                    local distance = #(coords - vector3(vehicleData.coords.x, vehicleData.coords.y, vehicleData.coords.z))
                    
                    if distance <= Config.SpawnDistance then
                        playersNearShowroom[src] = true
                        break
                    end
                end
            end
        end
    end
    
    -- Verificar si hay cambios en el estado del showroom
    local hasPlayersNow = next(playersNearShowroom) ~= nil
    local hadPlayersBefore = next(previousPlayersNear) ~= nil
    
    if hasPlayersNow and not hadPlayersBefore then
        -- Primeros jugadores llegaron - spawnear vehículos
        SpawnAllShowroomVehicles()
        
        if Config.Debug then
            print('[Showroom] Players entered area - spawning vehicles')
        end
        
    elseif not hasPlayersNow and hadPlayersBefore then
        -- Todos los jugadores se fueron - despawnear vehículos
        DespawnAllShowroomVehicles()
        
        if Config.Debug then
            print('[Showroom] All players left area - despawning vehicles')
        end
    end
end

-- Función para spawnear todos los vehículos del showroom
function SpawnAllShowroomVehicles()
    if next(globalSpawnedVehicles) ~= nil then
        return -- Ya están spawneados
    end
    
    for i, vehicleData in ipairs(Config.Vehicles) do
        -- Crear el vehículo en el servidor (sin verificación de modelo - ya está en config)
        local hash = GetHashKey(vehicleData.model)
        
        local vehicle = CreateVehicle(
            hash,
            vehicleData.coords.x,
            vehicleData.coords.y,
            vehicleData.coords.z,
            vehicleData.coords.w,
            true,  -- networked
            false  -- script vehicle
        )
        
        if DoesEntityExist(vehicle) then
            -- Configurar propiedades del vehículo
            SetEntityInvincible(vehicle, true)
            FreezeEntityPosition(vehicle, true)
            SetVehicleDoorsLocked(vehicle, 2)
            SetVehicleEngineOn(vehicle, false, true, true)
            SetVehicleNumberPlateText(vehicle, 'SHOWROOM')
            
            -- Configurar modificaciones
            SetVehicleModKit(vehicle, 0)
            SetVehicleWheelType(vehicle, 7)
            SetVehicleMod(vehicle, 11, 3, false)
            SetVehicleMod(vehicle, 12, 2, false)
            SetVehicleMod(vehicle, 13, 2, false)
            SetVehicleWindowTint(vehicle, 1)
            SetVehicleColours(vehicle, 0, 0)
            
            -- Guardar referencia global
            globalSpawnedVehicles[i] = {
                entity = vehicle,
                netId = NetworkGetNetworkIdFromEntity(vehicle),
                data = vehicleData
            }
            
            if Config.Debug then
                print(('Spawned vehicle %s (NetID: %d)'):format(vehicleData.model, NetworkGetNetworkIdFromEntity(vehicle)))
            end
        else
            if Config.Debug then
                print(('Failed to spawn vehicle: %s'):format(vehicleData.model))
            end
        end
    end
    
    -- Notificar a todos los clientes que los vehículos están listos
    TriggerClientEvent('vehicleShowroom:vehiclesSpawned', -1, globalSpawnedVehicles)
end

-- Función para despawnear todos los vehículos del showroom
function DespawnAllShowroomVehicles()
    if next(globalSpawnedVehicles) == nil then
        return -- No hay vehículos spawneados
    end
    
    -- Notificar a los clientes antes de eliminar
    TriggerClientEvent('vehicleShowroom:vehiclesDespawned', -1)
    
    -- Eliminar vehículos del servidor
    for i, vehicleInfo in pairs(globalSpawnedVehicles) do
        if DoesEntityExist(vehicleInfo.entity) then
            DeleteEntity(vehicleInfo.entity)
            
            if Config.Debug then
                print(('Despawned vehicle %s (NetID: %d)'):format(vehicleInfo.data.model, vehicleInfo.netId))
            end
        end
    end
    
    -- Limpiar lista global
    globalSpawnedVehicles = {}
end

-- HOTFIX: Registrar callbacks después de asegurar que ox_lib está disponible
CreateThread(function()
    Wait(1000) -- Esperar a que todo se cargue
    
    -- Callback para obtener estado actual de vehículos
    lib.callback.register('vehicleShowroom:getVehicleState', function(source)
        return globalSpawnedVehicles
    end)

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
        
        if GetPlayerRoutingBucket and SetPlayerRoutingBucket then
            useRoutingBucket = true
            bucket = GetFreeRoutingBucket()
            originalBucket = GetPlayerRoutingBucket(src)
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
    
    print('^2[Vehicle Showroom] ^7Callbacks registrados correctamente')
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
    
    -- Limpiar datos de prueba
    if testDriveData[src] then
        if Config.Debug then
            print(('Player %s disconnected during test drive'):format(src))
        end
        testDriveData[src] = nil
    end
    
    -- Remover de la lista de jugadores cerca del showroom
    if playersNearShowroom[src] then
        playersNearShowroom[src] = nil
        
        -- Verificar si era el último jugador y despawnear vehículos si es necesario
        CreateThread(function()
            Wait(1000) -- Esperar un poco antes de verificar
            CheckPlayersNearShowroom()
        end)
    end
end)

-- Event para refrescar showroom (admin)
RegisterNetEvent('vehicleShowroom:refreshShowroom', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player or not QBCore.Functions.HasPermission(src, 'admin') then
        return
    end
    
    -- Forzar despawn y respawn
    DespawnAllShowroomVehicles()
    Wait(1000)
    
    -- Verificar jugadores cerca y respawnear si es necesario
    CheckPlayersNearShowroom()
    
    TriggerClientEvent('QBCore:Notify', src, Config.Notifications.showroomRefresh, 'success')
end)

-- Comandos para administradores
QBCore.Commands.Add('showroom', 'Teleportar al showroom', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player.PlayerData.job.name == 'police' or QBCore.Functions.HasPermission(source, 'admin') then
        local coords = Config.Vehicles[1].coords
        TriggerClientEvent('QBCore:Command:TeleportToCoords', source, coords.x, coords.y, coords.z)
    else
        TriggerClientEvent('QBCore:Notify', source, 'No tienes permisos para usar este comando', 'error')
    end
end)

QBCore.Commands.Add('refreshshowroom', 'Refrescar vehículos del showroom', {}, false, function(source)
    TriggerEvent('vehicleShowroom:refreshShowroom', source)
end)

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

-- Thread principal para verificar jugadores cerca del showroom
CreateThread(function()
    while true do
        Wait(2000) -- Verificar cada 2 segundos
        CheckPlayersNearShowroom()
    end
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

print('^2[Vehicle Showroom] ^7Servidor cargado correctamente - HOTFIX aplicado')
print('^3[Vehicle Showroom] ^7Sistema anti-duplicación activado')
print('^3[Vehicle Showroom] ^7Vehículos configurados: ^2' .. #Config.Vehicles)