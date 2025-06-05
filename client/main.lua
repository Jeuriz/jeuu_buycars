local QBCore = exports['qb-core']:GetCoreObject()
local testDriveVehicle = nil
local testDriveActive = false
local testDriveThread = nil
local showroomVehicles = {} -- Vehículos recibidos del servidor
local vehicleTargets = {} -- Targets configurados
local isInShowroomArea = false

-- Cache usando ox_lib
local playerCache = {
    coords = vector3(0, 0, 0),
    ped = 0,
    vehicle = 0,
    lastUpdate = 0
}

-- Declaración forward de funciones
local ClearVehicleTargets
local SetupVehicleTargets
local WaitForVehicleSync

-- Función para actualizar cache del jugador
local function UpdatePlayerCache()
    local currentTime = GetGameTimer()
    if currentTime - playerCache.lastUpdate > 100 then -- Actualizar cada 100ms
        playerCache.ped = PlayerPedId()
        playerCache.coords = GetEntityCoords(playerCache.ped)
        playerCache.vehicle = GetVehiclePedIsIn(playerCache.ped, false)
        playerCache.lastUpdate = currentTime
    end
end

-- Función para forzar actualización inmediata del cache
local function ForceUpdatePlayerCache()
    playerCache.ped = PlayerPedId()
    playerCache.coords = GetEntityCoords(playerCache.ped)
    playerCache.vehicle = GetVehiclePedIsIn(playerCache.ped, false)
    playerCache.lastUpdate = GetGameTimer()
end

-- Función para formatear precio
local function FormatPrice(price)
    local formatted = tostring(price)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return '$' .. formatted
end

-- Función para dibujar texto 3D
local function DrawText3D(coords, text, scale, font, r, g, b, a)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    
    if onScreen then
        local dist = #(GetGameplayCamCoords() - coords)
        local fov = (1 / GetGameplayCamFov()) * 100
        local scale = (scale / dist) * (1.5) * fov * (1 / scale)
        
        SetTextScale(0.0 * scale, scale)
        SetTextFont(font)
        SetTextProportional(1)
        SetTextColour(r, g, b, a)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

-- Función para mostrar información 3D del vehículo (sincronizada)
local function ShowVehicle3DText()
    UpdatePlayerCache()
    
    for i, vehicleInfo in pairs(showroomVehicles) do
        if vehicleInfo and vehicleInfo.netId then
            -- Obtener entidad del network ID
            local entity = NetworkGetEntityFromNetworkId(vehicleInfo.netId)
            
            if DoesEntityExist(entity) then
                local vehCoords = GetEntityCoords(entity)
                local distance = #(playerCache.coords - vehCoords)
                
                if distance <= Config.Text3D.distance then
                    local textCoords = vector3(vehCoords.x, vehCoords.y, vehCoords.z + Config.Text3D.offsetZ)
                    local priceCoords = vector3(vehCoords.x, vehCoords.y, vehCoords.z + Config.Text3D.offsetZ - 0.3)
                    
                    -- Mostrar nombre del vehículo
                    DrawText3D(
                        textCoords,
                        vehicleInfo.data.label,
                        Config.Text3D.scale,
                        Config.Text3D.font,
                        Config.Text3D.nameColor.r,
                        Config.Text3D.nameColor.g,
                        Config.Text3D.nameColor.b,
                        255
                    )
                    
                    -- Mostrar precio en verde
                    DrawText3D(
                        priceCoords,
                        FormatPrice(vehicleInfo.data.price),
                        Config.Text3D.scale * 0.8,
                        Config.Text3D.font,
                        Config.Text3D.priceColor.r,
                        Config.Text3D.priceColor.g,
                        Config.Text3D.priceColor.b,
                        255
                    )
                end
            end
        end
    end
end

-- Función para crear la UI del contador
local function CreateTestDriveUI(timeLeft)
    lib.showTextUI(('[Prueba de Vehículo] Tiempo restante: %d segundos'):format(timeLeft), {
        position = "top-center",
        icon = 'car',
        style = {
            borderRadius = 10,
            backgroundColor = '#48BB78',
            color = 'white'
        }
    })
end

-- Función para finalizar prueba de vehículo
local function EndTestDrive()
    if not testDriveActive then return end
    
    testDriveActive = false
    
    -- Ocultar UI
    lib.hideTextUI()
    
    -- Eliminar vehículo de prueba
    if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
        DeleteEntity(testDriveVehicle)
        testDriveVehicle = nil
    end
    
    -- El thread se detendrá automáticamente al cambiar testDriveActive a false
    testDriveThread = nil
    
    -- Notificar al servidor para finalizar la prueba
    TriggerServerEvent('vehicleShowroom:endTestDrive')
    
    QBCore.Functions.Notify(Config.Notifications.testDriveEnd, 'primary')
end

-- Función para iniciar prueba de vehículo usando ox_lib callback
local function StartTestDrive(vehicleModel)
    if testDriveActive then
        QBCore.Functions.Notify(Config.Notifications.alreadyTesting, 'error')
        return
    end
    
    testDriveActive = true
    
    -- Usar ox_lib callback para mayor eficiencia
    lib.callback('vehicleShowroom:startTestDrive', false, function(success, message)
        if not success then
            testDriveActive = false
            if message then
                QBCore.Functions.Notify(message, 'error')
            end
        end
    end, vehicleModel)
end

-- Función para abrir tienda de compra con mejor UX
local function OpenPurchaseShop(vehicleData)
    local formattedPrice = FormatPrice(vehicleData.price)
    
    lib.registerContext({
        id = 'vehicle_purchase',
        title = '🚗 ' .. vehicleData.label,
        description = 'Información del vehículo y opciones de compra',
        options = {
            {
                title = '📊 Información',
                description = ('Categoría: %s | Modelo: %s'):format(vehicleData.category:upper(), vehicleData.model:upper()),
                icon = 'info-circle',
                iconColor = '#3B82F6',
                disabled = true
            },
            {
                title = '💰 Comprar Vehículo',
                description = ('Precio: %s (Efectivo)'):format(formattedPrice),
                icon = 'dollar-sign',
                iconColor = '#10B981',
                onSelect = function()
                    -- Usar callback para la compra
                    lib.callback('vehicleShowroom:buyVehicle', false, function(success, message, itemName)
                        if success then
                            lib.notify({
                                title = '✅ Compra Exitosa',
                                description = message,
                                type = 'success',
                                duration = 7000
                            })
                        else
                            QBCore.Functions.Notify(message, 'error')
                        end
                    end, vehicleData)
                end
            },
            {
                title = '🚗 Probar Primero',
                description = 'Haz una prueba de manejo antes de comprar',
                icon = 'car',
                iconColor = '#F59E0B',
                onSelect = function()
                    StartTestDrive(vehicleData.model)
                end
            },
            {
                title = '❌ Cancelar',
                description = 'Cerrar menú de compra',
                icon = 'times',
                iconColor = '#EF4444'
            }
        }
    })
    
    lib.showContext('vehicle_purchase')
end

-- NUEVA: Función para esperar a que el vehículo se sincronice completamente
WaitForVehicleSync = function(netId, maxAttempts)
    maxAttempts = maxAttempts or 50 -- 10 segundos máximo (50 * 200ms)
    local attempts = 0
    
    return CreateThread(function()
        while attempts < maxAttempts do
            local entity = NetworkGetEntityFromNetworkId(netId)
            
            -- Verificar que la entidad existe Y está completamente sincronizada
            if DoesEntityExist(entity) and NetworkHasControlOfEntity(entity) then
                if Config.Debug then
                    print(('Vehicle synced after %d attempts (NetID: %d)'):format(attempts, netId))
                end
                return entity
            end
            
            attempts = attempts + 1
            Wait(200) -- Esperar 200ms entre intentos
        end
        
        if Config.Debug then
            print(('Failed to sync vehicle after %d attempts (NetID: %d)'):format(maxAttempts, netId))
        end
        return nil
    end)
end

-- Función para limpiar targets de vehículos
ClearVehicleTargets = function()
    for i, entity in pairs(vehicleTargets) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
        end
    end
    vehicleTargets = {}
    
    if Config.Debug then
        print('Cleared all vehicle targets')
    end
end

-- MEJORADA: Función para configurar targets de vehículos con mejor sincronización
SetupVehicleTargets = function()
    -- Limpiar targets existentes
    ClearVehicleTargets()
    
    if Config.Debug then
        print(('Setting up targets for %d vehicles'):format(#showroomVehicles))
    end
    
    for i, vehicleInfo in pairs(showroomVehicles) do
        if vehicleInfo and vehicleInfo.netId then
            -- Usar la nueva función de sincronización
            CreateThread(function()
                local entity = nil
                local attempts = 0
                local maxAttempts = 25 -- 5 segundos máximo
                
                -- Bucle para esperar sincronización
                while attempts < maxAttempts do
                    entity = NetworkGetEntityFromNetworkId(vehicleInfo.netId)
                    
                    -- Verificar múltiples condiciones para asegurar sincronización completa
                    if DoesEntityExist(entity) and 
                       NetworkDoesEntityExistWithNetworkId(vehicleInfo.netId) and
                       GetEntityModel(entity) ~= 0 then
                        
                        -- Esperar un frame adicional para asegurar
                        Wait(100)
                        break
                    end
                    
                    attempts = attempts + 1
                    Wait(200)
                end
                
                -- Si la entidad existe y está sincronizada, configurar targets
                if entity and DoesEntityExist(entity) then
                    -- Configurar targets para este vehículo
                    exports.ox_target:addLocalEntity(entity, {
                        {
                            name = 'test_drive_' .. i,
                            icon = 'fas fa-car',
                            label = ('🚗 Probar %s'):format(vehicleInfo.data.label),
                            distance = 3.0,
                            onSelect = function()
                                StartTestDrive(vehicleInfo.data.model)
                            end
                        },
                        {
                            name = 'buy_vehicle_' .. i,
                            icon = 'fas fa-dollar-sign',
                            label = ('💰 Comprar %s'):format(FormatPrice(vehicleInfo.data.price)),
                            distance = 3.0,
                            onSelect = function()
                                OpenPurchaseShop(vehicleInfo.data)
                            end
                        }
                    })
                    
                    -- Guardar referencia del target
                    vehicleTargets[i] = entity
                    
                    if Config.Debug then
                        print(('✅ Target configured for %s (NetID: %d, Entity: %d) after %d attempts'):format(
                            vehicleInfo.data.model, vehicleInfo.netId, entity, attempts))
                    end
                else
                    if Config.Debug then
                        print(('❌ Failed to sync vehicle %s (NetID: %d) after %d attempts'):format(
                            vehicleInfo.data.model, vehicleInfo.netId, maxAttempts))
                    end
                end
            end)
        end
    end
end

-- Función para verificar si el jugador está cerca del showroom
local function IsPlayerNearShowroom()
    UpdatePlayerCache()
    
    for i, vehicleData in ipairs(Config.Vehicles) do
        local distance = #(playerCache.coords - vector3(vehicleData.coords.x, vehicleData.coords.y, vehicleData.coords.z))
        if distance <= Config.SpawnDistance then
            return true
        end
    end
    
    return false
end

-- MEJORADA: Función para sincronizar estado con el servidor al entrar
local function SyncWithServer()
    lib.callback('vehicleShowroom:getVehicleState', false, function(serverVehicles)
        if serverVehicles and next(serverVehicles) ~= nil then
            showroomVehicles = serverVehicles
            
            if Config.Debug then
                print(('Received %d vehicles from server, setting up targets...'):format(#serverVehicles))
            end
            
            -- Configurar targets inmediatamente (la función ahora maneja la sincronización internamente)
            SetupVehicleTargets()
        else
            showroomVehicles = {}
            ClearVehicleTargets()
            
            if Config.Debug then
                print('No vehicles received from server')
            end
        end
    end)
end

-- Events del cliente
RegisterNetEvent('vehicleShowroom:vehiclesSpawned', function(serverVehicles)
    showroomVehicles = serverVehicles
    
    if Config.Debug then
        print(('Vehicles spawned event received - %d vehicles'):format(#serverVehicles))
    end
    
    -- Configurar targets (la función ahora maneja la sincronización internamente)
    SetupVehicleTargets()
    
    if Config.Debug then
        lib.notify({
            title = 'Showroom',
            description = Config.Notifications.showroomEntered,
            type = 'inform'
        })
    end
end)

RegisterNetEvent('vehicleShowroom:vehiclesDespawned', function()
    ClearVehicleTargets()
    showroomVehicles = {}
    
    if Config.Debug then
        print('Vehicles despawned - targets cleared')
        lib.notify({
            title = 'Showroom',
            description = Config.Notifications.showroomExited,
            type = 'inform'
        })
    end
end)

RegisterNetEvent('vehicleShowroom:startTestDriveClient', function(vehicleModel, routingBucket)
    -- Crear efecto de fade
    DoScreenFadeOut(1000)
    Wait(1000)
    
    -- Teletransportar a ubicación de prueba
    SetEntityCoords(PlayerPedId(), Config.TestDriveLocation.x, Config.TestDriveLocation.y, Config.TestDriveLocation.z)
    SetEntityHeading(PlayerPedId(), Config.TestDriveLocation.w)
    
    -- Spawnar vehículo de prueba
    QBCore.Functions.SpawnVehicle(vehicleModel, function(veh)
        SetEntityCoords(veh, Config.TestDriveLocation.x + 3.0, Config.TestDriveLocation.y, Config.TestDriveLocation.z)
        SetEntityHeading(veh, Config.TestDriveLocation.w)
        
        -- Configurar vehículo para prueba
        SetVehicleFuelLevel(veh, 100.0)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleNumberPlateText(veh, 'PRUEBA')
        
        -- Entrar al vehículo
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        
        testDriveVehicle = veh
        
        -- Dar llaves del vehículo
        TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
        
        -- Fade in
        DoScreenFadeIn(1000)
        
        QBCore.Functions.Notify(Config.Notifications.testDriveStart, 'success')
        
    end, Config.TestDriveLocation, true)
    
    -- Iniciar contador y thread de monitoreo
    local timeLeft = Config.TestDriveTime
    CreateTestDriveUI(timeLeft)
    
    -- Thread para el contador y monitoreo
    testDriveThread = CreateThread(function()
        while testDriveActive and timeLeft > 0 do
            Wait(1000)
            timeLeft = timeLeft - 1
            
            -- Verificar si el jugador está en el vehículo
            if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
                local playerPed = PlayerPedId()
                local vehicleOfPlayer = GetVehiclePedIsIn(playerPed, false)
                
                -- Si el jugador no está en el vehículo de prueba, finalizar
                if vehicleOfPlayer ~= testDriveVehicle then
                    QBCore.Functions.Notify('Te has bajado del vehículo. Prueba finalizada.', 'error')
                    EndTestDrive()
                    return
                end
            end
            
            -- Actualizar UI
            if testDriveActive then
                CreateTestDriveUI(timeLeft)
                
                -- Avisos de tiempo
                if timeLeft <= 10 and timeLeft > 0 then
                    QBCore.Functions.Notify(('Prueba terminará en %d segundos'):format(timeLeft), 'warning')
                end
            end
        end
        
        -- Si se agotó el tiempo, finalizar prueba
        if testDriveActive and timeLeft <= 0 then
            EndTestDrive()
        end
    end)
end)

RegisterNetEvent('vehicleShowroom:endTestDriveClient', function(originalCoords)
    -- Crear efecto de fade
    DoScreenFadeOut(1000)
    Wait(1000)
    
    if originalCoords then
        SetEntityCoords(PlayerPedId(), originalCoords.x, originalCoords.y, originalCoords.z)
        SetEntityHeading(PlayerPedId(), originalCoords.w or 0.0)
    end
    
    -- Fade in
    DoScreenFadeIn(1000)
    
    -- Sincronizar estado con el servidor después del teletransporte
    CreateThread(function()
        Wait(2000) -- Esperar a que el teletransporte se complete
        SyncWithServer()
    end)
end)

-- Evento para mostrar confirmación de compra
RegisterNetEvent('vehicleShowroom:purchaseSuccess', function(vehicleLabel, price, itemName)
    lib.notify({
        title = '✅ Compra Exitosa',
        description = ('Has comprado un %s por %s. Revisa tu inventario para encontrar el ítem: %s'):format(vehicleLabel, FormatPrice(price), itemName),
        type = 'success',
        duration = 7000
    })
end)

-- Inicialización
CreateThread(function()
    Wait(2500) -- Esperar a que cargue todo
    
    if Config.Debug then
        print('^2[Vehicle Showroom] ^7Cliente cargado correctamente')
        print('^3[Vehicle Showroom] ^7Sistema sincronizado con servidor activado')
    end
end)

-- Cleanup al salir del juego
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        EndTestDrive()
        ClearVehicleTargets()
        lib.hideTextUI()
        
        -- Limpiar thread si existe
        if testDriveThread then
            testDriveActive = false
            testDriveThread = nil
        end
    end
end)

-- Thread para verificar si el jugador está en el área del showroom
CreateThread(function()
    while true do
        Wait(3000) -- Verificar cada 3 segundos
        
        if not testDriveActive then
            local wasInArea = isInShowroomArea
            isInShowroomArea = IsPlayerNearShowroom()
            
            -- Si entró al área, sincronizar con el servidor
            if isInShowroomArea and not wasInArea then
                SyncWithServer()
            end
        end
    end
end)

-- Thread para 3D Text optimizado
CreateThread(function()
    while true do
        Wait(0) -- Ejecutar cada frame para texto suave
        
        if isInShowroomArea and not testDriveActive and next(showroomVehicles) ~= nil then
            ShowVehicle3DText()
        else
            Wait(500) -- Reducir frecuencia cuando no está en el área
        end
    end
end)

-- Thread para monitorear prueba de vehículo optimizado
CreateThread(function()
    while true do
        Wait(500) -- Verificar cada medio segundo
        
        if testDriveActive and testDriveVehicle and DoesEntityExist(testDriveVehicle) then
            UpdatePlayerCache()
            
            -- Verificar si el jugador no está en el vehículo de prueba
            if playerCache.vehicle == 0 or playerCache.vehicle ~= testDriveVehicle then
                -- Dar una oportunidad de 3 segundos para volver al vehículo
                local timeOutOfVehicle = 0
                local maxTimeOut = 3000 -- 3 segundos
                
                while timeOutOfVehicle < maxTimeOut and testDriveActive do
                    Wait(100)
                    timeOutOfVehicle = timeOutOfVehicle + 100
                    
                    UpdatePlayerCache()
                    
                    -- Si volvió al vehículo, salir del bucle
                    if playerCache.vehicle == testDriveVehicle then
                        break
                    end
                end
                
                -- Si pasó el tiempo y sigue fuera del vehículo, finalizar prueba
                if timeOutOfVehicle >= maxTimeOut and testDriveActive then
                    UpdatePlayerCache()
                    if playerCache.vehicle ~= testDriveVehicle then
                        lib.notify({
                            title = 'Prueba Finalizada',
                            description = 'Has abandonado el vehículo. Prueba finalizada.',
                            type = 'error'
                        })
                        EndTestDrive()
                    end
                end
            end
        else
            Wait(2000) -- Reducir frecuencia cuando no hay prueba activa
        end
    end
end)