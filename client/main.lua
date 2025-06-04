local QBCore = exports['qb-core']:GetCoreObject()
local spawnedVehicles = {}
local testDriveVehicle = nil
local testDriveActive = false
local testDriveThread = nil
local vehicleStates = {} -- Estado de cada vehículo (spawneado/no spawneado)
local isInShowroomArea = false

-- Cache usando ox_lib
local playerCache = {
    coords = vector3(0, 0, 0),
    ped = 0,
    vehicle = 0,
    lastUpdate = 0
}

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

-- Función para mostrar información 3D del vehículo
local function ShowVehicle3DText()
    UpdatePlayerCache()
    
    for i, state in pairs(vehicleStates) do
        if state.spawned and state.entity and DoesEntityExist(state.entity) then
            local vehCoords = GetEntityCoords(state.entity)
            local distance = #(playerCache.coords - vehCoords)
            
            if distance <= Config.Text3D.distance then
                local textCoords = vector3(vehCoords.x, vehCoords.y, vehCoords.z + Config.Text3D.offsetZ)
                local priceCoords = vector3(vehCoords.x, vehCoords.y, vehCoords.z + Config.Text3D.offsetZ - 0.3)
                
                -- Mostrar nombre del vehículo
                DrawText3D(
                    textCoords,
                    state.data.label,
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
                    FormatPrice(state.data.price),
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

-- Función para spawnar un vehículo específico con cache
local function SpawnVehicle(index, vehicleData)
    if vehicleStates[index] and vehicleStates[index].spawned then
        return -- Ya está spawneado
    end
    
    if Config.Debug then
        print(('Spawning vehicle: %s at %s'):format(vehicleData.model, vehicleData.coords))
    end
    
    -- Usar RequestModel para optimizar carga
    local hash = GetHashKey(vehicleData.model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        if Config.Debug then
            print(('Invalid vehicle model: %s'):format(vehicleData.model))
        end
        return
    end
    
    lib.requestModel(hash, 10000) -- 10 segundos timeout
    
    QBCore.Functions.SpawnVehicle(vehicleData.model, function(veh)
        if not DoesEntityExist(veh) then
            SetModelAsNoLongerNeeded(hash)
            return
        end
        
        -- Configurar posición y propiedades básicas
        SetEntityCoords(veh, vehicleData.coords.x, vehicleData.coords.y, vehicleData.coords.z)
        SetEntityHeading(veh, vehicleData.coords.w)
        FreezeEntityPosition(veh, true)
        SetEntityInvincible(veh, true)
        SetVehicleDoorsLocked(veh, 2)
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleNumberPlateText(veh, 'SHOWROOM')
        
        -- Configurar modificaciones del vehículo
        SetVehicleModKit(veh, 0)
        SetVehicleWheelType(veh, 7) -- Sport wheels
        SetVehicleMod(veh, 11, 3, false) -- Engine
        SetVehicleMod(veh, 12, 2, false) -- Brakes
        SetVehicleMod(veh, 13, 2, false) -- Transmission
        
        -- Configurar propiedades visuales
        SetVehicleWindowTint(veh, 1) -- Tintado ligero
        SetVehicleColours(veh, 0, 0) -- Negro metálico
        
        -- Añadir target options optimizadas
        exports.ox_target:addLocalEntity(veh, {
            {
                name = 'test_drive_' .. index,
                icon = 'fas fa-car',
                label = ('🚗 Probar %s'):format(vehicleData.label),
                distance = 3.0,
                onSelect = function()
                    StartTestDrive(vehicleData.model)
                end
            },
            {
                name = 'buy_vehicle_' .. index,
                icon = 'fas fa-dollar-sign',
                label = ('💰 Comprar %s'):format(FormatPrice(vehicleData.price)),
                distance = 3.0,
                onSelect = function()
                    OpenPurchaseShop(vehicleData)
                end
            }
        })
        
        -- Guardar referencia del vehículo con cache
        vehicleStates[index] = {
            spawned = true,
            entity = veh,
            data = vehicleData,
            lastHealthCheck = GetGameTimer()
        }
        
        spawnedVehicles[#spawnedVehicles + 1] = veh
        
        -- Liberar modelo de la memoria
        SetModelAsNoLongerNeeded(hash)
        
    end, vehicleData.coords, true)
end

-- Función para despawnar un vehículo específico
local function DespawnVehicle(index)
    if not vehicleStates[index] or not vehicleStates[index].spawned then
        return -- No está spawneado
    end
    
    local veh = vehicleStates[index].entity
    
    if DoesEntityExist(veh) then
        exports.ox_target:removeLocalEntity(veh)
        DeleteEntity(veh)
        
        -- Remover de la lista de vehículos spawneados
        for i, spawnedVeh in ipairs(spawnedVehicles) do
            if spawnedVeh == veh then
                table.remove(spawnedVehicles, i)
                break
            end
        end
        
        if Config.Debug then
            print(('Despawned vehicle: %s'):format(vehicleStates[index].data.model))
        end
    end
    
    vehicleStates[index] = {
        spawned = false,
        entity = nil,
        data = vehicleStates[index].data
    }
end

-- Función para verificar si el jugador está cerca del showroom con cache
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

-- Función para manejar spawning por distancia optimizada
local function HandleDistanceSpawning()
    UpdatePlayerCache()
    
    for i, vehicleData in ipairs(Config.Vehicles) do
        local distance = #(playerCache.coords - vector3(vehicleData.coords.x, vehicleData.coords.y, vehicleData.coords.z))
        
        if distance <= Config.SpawnDistance then
            -- Spawnar si no está spawneado
            if not vehicleStates[i] or not vehicleStates[i].spawned then
                SpawnVehicle(i, vehicleData)
            end
        elseif distance >= Config.DespawnDistance then
            -- Despawnar si está spawneado
            if vehicleStates[i] and vehicleStates[i].spawned then
                DespawnVehicle(i)
            end
        end
    end
end

-- Función para limpiar todos los vehículos spawneados
local function CleanupAllVehicles()
    for i = 1, #Config.Vehicles do
        DespawnVehicle(i)
    end
    spawnedVehicles = {}
    vehicleStates = {}
end

-- Función para spawnar todos los vehículos (para comando de admin)
local function SpawnAllVehicles()
    for i, vehicleData in ipairs(Config.Vehicles) do
        SpawnVehicle(i, vehicleData)
    end
end

-- Función para refrescar el showroom después de regresar de prueba
local function RefreshShowroomAfterTestDrive()
    if Config.Debug then
        print('Refreshing showroom after test drive...')
    end
    
    -- Forzar actualización del cache
    ForceUpdatePlayerCache()
    
    -- Esperar un momento para que el teletransporte se complete
    CreateThread(function()
        Wait(1000) -- Esperar 1 segundo
        
        -- Actualizar estado del área del showroom
        isInShowroomArea = IsPlayerNearShowroom()
        
        if Config.Debug then
            print(('Player is near showroom: %s'):format(tostring(isInShowroomArea)))
        end
        
        -- Si está en el área del showroom, forzar spawning
        if isInShowroomArea then
            HandleDistanceSpawning()
            
            -- Notificación de debug
            if Config.Debug then
                lib.notify({
                    title = 'Showroom',
                    description = 'Vehículos recargados después de la prueba',
                    type = 'inform'
                })
            end
        end
    end)
end

-- Events del cliente
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
    
    -- Refrescar el showroom después del teletransporte
    RefreshShowroomAfterTestDrive()
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
    
    -- Inicializar estados de vehículos
    for i, vehicleData in ipairs(Config.Vehicles) do
        vehicleStates[i] = {
            spawned = false,
            entity = nil,
            data = vehicleData
        }
    end
    
    if Config.Debug then
        print('^2[Vehicle Showroom] ^7Cliente cargado correctamente')
        print('^3[Vehicle Showroom] ^7Sistema de spawning por distancia activado')
        print('^3[Vehicle Showroom] ^7Distancia de spawn: ^2' .. Config.SpawnDistance .. 'm')
        print('^3[Vehicle Showroom] ^7Distancia de despawn: ^2' .. Config.DespawnDistance .. 'm')
    end
end)

-- Cleanup al salir del juego
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        EndTestDrive()
        CleanupAllVehicles()
        lib.hideTextUI()
        
        -- Limpiar thread si existe
        if testDriveThread then
            testDriveActive = false
            testDriveThread = nil
        end
    end
end)

-- Thread principal para monitoreo de distancia optimizado
CreateThread(function()
    while true do
        Wait(Config.CheckInterval)
        
        if not testDriveActive then -- Solo verificar si no está en prueba de vehículo
            local wasInArea = isInShowroomArea
            isInShowroomArea = IsPlayerNearShowroom()
            
            -- Notificar entrada/salida del área del showroom
            if isInShowroomArea and not wasInArea then
                if Config.Debug then
                    lib.notify({
                        title = 'Showroom',
                        description = Config.Notifications.showroomEntered,
                        type = 'inform'
                    })
                end
            elseif not isInShowroomArea and wasInArea then
                if Config.Debug then
                    lib.notify({
                        title = 'Showroom',
                        description = Config.Notifications.showroomExited,
                        type = 'inform'
                    })
                end
            end
            
            -- Manejar spawning por distancia
            HandleDistanceSpawning()
        end
    end
end)

-- Thread para 3D Text optimizado
CreateThread(function()
    while true do
        Wait(0) -- Ejecutar cada frame para texto suave
        
        if isInShowroomArea and not testDriveActive then
            ShowVehicle3DText()
        else
            Wait(500) -- Reducir frecuencia cuando no está en el área
        end
    end
end)

-- Thread para mantenimiento de vehículos optimizado
CreateThread(function()
    while true do
        Wait(5000) -- Verificar cada 5 segundos
        
        local currentTime = GetGameTimer()
        
        for i, state in pairs(vehicleStates) do
            if state.spawned and state.entity and DoesEntityExist(state.entity) then
                -- Solo verificar salud cada 5 segundos por vehículo
                if currentTime - state.lastHealthCheck > 5000 then
                    local veh = state.entity
                    SetEntityHealth(veh, 1000)
                    SetVehicleEngineHealth(veh, 1000.0)
                    SetVehicleBodyHealth(veh, 1000.0)
                    SetVehiclePetrolTankHealth(veh, 1000.0)
                    
                    state.lastHealthCheck = currentTime
                end
            end
        end
    end
end)

-- Thread adicional para monitorear prueba de vehículo optimizado
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
