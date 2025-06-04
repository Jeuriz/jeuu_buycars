Config = {}

-- Configuración general
Config.Debug = false
Config.TestDriveTime = 60 -- Tiempo en segundos para prueba
Config.TestDriveLocation = vector4(-1000.0, -3000.0, 13.94, 0.0) -- Coordenadas de prueba

-- Configuración de optimización
Config.SpawnDistance = 50.0 -- Distancia para spawnar vehículos (metros)
Config.DespawnDistance = 75.0 -- Distancia para despawnar vehículos (metros)
Config.CheckInterval = 2000 -- Intervalo de verificación de distancia (ms)

-- Configuración de 3D Text
Config.Text3D = {
    distance = 3.0, -- Distancia para mostrar texto (metros)
    scale = 0.6, -- Escala del texto
    font = 4, -- Fuente del texto
    offsetZ = 1.5, -- Altura del texto sobre el vehículo
    priceColor = {r = 46, g = 204, b = 113}, -- Color verde para precio
    nameColor = {r = 255, g = 255, b = 255}, -- Color blanco para nombre
}

-- Configuración de vehículos del showroom
Config.Vehicles = {
    {
        model = 'adder',
        coords = vector4(1899.59, 2721.44, 45.25, 297.66),
        price = 50000,
        label = 'Truffade Adder',
        category = 'supercar',
        item = 'vehicle_adder' -- Ítem que se entregará al comprar
    },
    {
        model = 'zentorno',
        coords = vector4(-45.12, -1097.34, 25.44, 69.85),
        price = 75000,
        label = 'Pegassi Zentorno',
        category = 'supercar',
        item = 'vehicle_zentorno'
    },
    {
        model = 'sultanrs',
        coords = vector4(-33.89, -1095.24, 25.44, 115.0),
        price = 25000,
        label = 'Karin Sultan RS',
        category = 'sports',
        item = 'vehicle_sultanrs'
    },
    {
        model = 'elegy2',
        coords = vector4(-27.88, -1083.24, 25.44, 160.0),
        price = 20000,
        label = 'Annis Elegy RH8',
        category = 'sports',
        item = 'vehicle_elegy2'
    },
    {
        model = 'infernus',
        coords = vector4(-40.22, -1108.44, 25.44, 340.0),
        price = 45000,
        label = 'Pegassi Infernus',
        category = 'supercar',
        item = 'vehicle_infernus'
    }
}

-- Configuración de notificaciones
Config.Notifications = {
    testDriveStart = '¡Disfruta tu prueba de manejo!',
    testDriveEnd = 'Prueba de vehículo finalizada',
    alreadyTesting = 'Ya estás en una prueba de vehículo',
    purchaseSuccess = '¡Has comprado un %s por $%d!',
    notEnoughMoney = 'No tienes suficiente dinero en efectivo',
    invalidVehicle = 'Vehículo no válido',
    showroomRefresh = 'Showroom reiniciado',
    showroomEntered = 'Has entrado al showroom - Vehículos cargándose...',
    showroomExited = 'Has salido del showroom - Vehículos guardados para optimización'
}
