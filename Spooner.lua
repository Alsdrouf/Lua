local pluginName = "Spooner"
local menuRootPath = FileMgr.GetMenuRootPath() .. "\\Lua\\" .. pluginName
local nativesPath = menuRootPath .. "\\Assets\\natives.lua"
local configPath = menuRootPath .. "\\config.xml"
local libsPath = menuRootPath .. "\\libs\\"

FileMgr.CreateDir(menuRootPath)
FileMgr.CreateDir(menuRootPath .. "\\Assets")
FileMgr.CreateDir(menuRootPath .. "\\libs")

local propListPath = menuRootPath .. "\\Assets\\PropList.xml"
local vehicleListPath = menuRootPath .. "\\Assets\\VehicleList.xml"
local pedListPath = menuRootPath .. "\\Assets\\PedList.xml"
local spoonerSavePath = menuRootPath .. "\\XML"

FileMgr.CreateDir(spoonerSavePath)

-- ============================================================================
-- Load Libraries
-- ============================================================================
local function LoadLib(name)
    local path = libsPath .. name .. ".lua"
    local status, result = pcall(dofile, path)
    if not status then
        Logger.Log(eLogColor.RED, pluginName, "Failed to load library " .. name .. ": " .. tostring(result))
        return nil
    end
    return result
end

local LoggerLib = LoadLib("Logger")
local XMLParserLib = LoadLib("XMLParser")
local EntityListsLib = LoadLib("EntityLists")
local NetworkUtilsLib = LoadLib("NetworkUtils")
local KeybindsLib = LoadLib("Keybinds")
local CameraUtilsLib = LoadLib("CameraUtils")
local MemoryUtilsLib = LoadLib("MemoryUtils")
local RaycastLib = LoadLib("Raycast")
local SpoonerUtilsLib = LoadLib("SpoonerUtils")
local RotationUtilsLib = LoadLib("RotationUtils")
local SpoonerCoreLib = LoadLib("SpoonerCore")
local SpoonerSpawnerLib = LoadLib("SpoonerSpawner")
local SpoonerDrawLib = LoadLib("SpoonerDraw")
local SpoonerUILib = LoadLib("SpoonerUI")
local SpoonerFeaturesLib = LoadLib("SpoonerFeatures")

-- ============================================================================
-- Constants
-- ============================================================================
local CONSTANTS = {
    NATIVES_URL = "https://raw.githubusercontent.com/Alsdrouf/CheraxSpooner/refs/heads/main/Spooner/Assets/natives.lua",
    PED_LIST_URL = "https://raw.githubusercontent.com/Alsdrouf/CheraxSpooner/refs/heads/main/Spooner/Assets/PedList.xml",
    PROP_LIST_URL = "https://raw.githubusercontent.com/Alsdrouf/CheraxSpooner/refs/heads/main/Spooner/Assets/PropList.xml",
    VEHICLE_LIST_URL = "https://raw.githubusercontent.com/Alsdrouf/CheraxSpooner/refs/heads/main/Spooner/Assets/VehicleList.xml",
    NETWORK_TIMEOUT = 1500,
    NETWORK_TIMEOUT_SHORT = 25,
    RAYCAST_MAX_DISTANCE = 1000.0,
    RAYCAST_INTERVAL = 3,
    RAYCAST_FLAGS = 30,
    MIN_GRAB_DISTANCE = 1.0,
    CAMERA_SPEED = 0.5,
    CAMERA_ROT_SPEED = 20.0,
    CAMERA_SPEED_BOOST = 3.0,
    ROTATION_SPEED = 2.0,
    ROTATION_SPEED_BOOST = 4.0,
    SCROLL_SPEED = 0.5,
    PITCH_CLAMP_MAX = 89.0,
    PITCH_CLAMP_MIN = -89.0,
    VELOCITY_MULTIPLIER = 30.0,
    CLIP_TO_GROUND_DISTANCE = 3,
    CLIP_TO_GROUND_RAYCAST_FLAGS = 33,
    POSITION_STEP_DEFAULT = 1.0,
}

-- ============================================================================
-- Initialize Libraries (before natives)
-- ============================================================================
local CustomLogger = LoggerLib.New(pluginName)
local MemoryUtils = MemoryUtilsLib.New()
local XMLParser = XMLParserLib.New()
local SpoonerUtils = SpoonerUtilsLib.New()
local RotationUtils = RotationUtilsLib.New()

-- ============================================================================
-- Utilities
-- ============================================================================
local function DownloadAndSaveFile(url, filePath)
    local curlObject = Curl.Easy()
    curlObject:Setopt(eCurlOption.CURLOPT_URL, url)
    curlObject:AddHeader("User-Agent: Lua-Curl-Client")
    curlObject:Perform()

    while not curlObject:GetFinished() do
    end

    local responseCode, responseString = curlObject:GetResponse()

    if responseCode ~= eCurlCode.CURLE_OK then
        Logger.LogError("Error downloading file. Response code: " .. responseCode)
        Logger.LogError("Response message: " .. responseString)
        return false
    end

    if responseString == "404: Not Found" then
        Logger.LogError("File not found on the internet!")
        return false
    end

    if not FileMgr.WriteFileContent(filePath, responseString) then
        Logger.LogError("Error saving file: " .. filePath)
        Logger.LogError("Content: " .. responseString)
        return false
    end

    Logger.LogInfo("Successfully downloaded and saved: " .. filePath)
    return true
end

local function LoadNatives(path)
    if not FileMgr.DoesFileExist(path) then
        Logger.LogInfo("natives.lua not found. Downloading...")
        if not DownloadAndSaveFile(CONSTANTS.NATIVES_URL, path) then
            return false
        end
    end

    local status, err = pcall(dofile, path)
    if not status then
        Logger.LogError("Failed to load natives.lua: " .. err)
        return false
    end

    return true
end

LoadNatives(nativesPath)

local function DownloadAssetLists()
    if not FileMgr.DoesFileExist(pedListPath) then
        Logger.LogInfo("PedList.xml not found. Downloading...")
        DownloadAndSaveFile(CONSTANTS.PED_LIST_URL, pedListPath)
    end

    if not FileMgr.DoesFileExist(propListPath) then
        Logger.LogInfo("PropList.xml not found. Downloading...")
        DownloadAndSaveFile(CONSTANTS.PROP_LIST_URL, propListPath)
    end

    if not FileMgr.DoesFileExist(vehicleListPath) then
        Logger.LogInfo("VehicleList.xml not found. Downloading...")
        DownloadAndSaveFile(CONSTANTS.VEHICLE_LIST_URL, vehicleListPath)
    end
end

DownloadAssetLists()

-- ============================================================================
-- Initialize Libraries (after natives)
-- ============================================================================
local EntityLists = EntityListsLib.New(XMLParser, CustomLogger)
local NetworkUtils = NetworkUtilsLib.New(CONSTANTS)
local KeybindsInstance = KeybindsLib.New(PAD)
local Keybinds = KeybindsInstance.SetupDefaultBinds()
Keybinds.EnablePassthrough = KeybindsInstance.EnablePassthroughControls
local CameraUtils = CameraUtilsLib.New(CONSTANTS)
local Raycast = RaycastLib.New("CameraHit", CONSTANTS, CustomLogger, MemoryUtils)
local RaycastForClipToGround = RaycastLib.New("ClipToGround", CONSTANTS, CustomLogger, MemoryUtils)

-- ============================================================================
-- Configuration Management
-- ============================================================================
local Config = {
    enableF9Key = false,
    throwableMode = false,
    clipToGround = false,
    lockMovementWhileMenuIsOpen = false,
    lockMovementWhileMenuIsOpenEnhanced = false,
    positionStep = CONSTANTS.POSITION_STEP_DEFAULT,
    spawnUnnetworked = false,
}

local function SaveConfig()
    local xmlContent = XMLParser.GenerateXML("SpoonerConfig", {
        enableF9Key = Config.enableF9Key,
        throwableMode = Config.throwableMode,
        clipToGround = Config.clipToGround,
        lockMovementWhileMenuIsOpen = Config.lockMovementWhileMenuIsOpen,
        lockMovementWhileMenuIsOpenEnhanced = Config.lockMovementWhileMenuIsOpenEnhanced,
        positionStep = Config.positionStep,
        spawnUnnetworked = Config.spawnUnnetworked
    })

    if FileMgr.WriteFileContent(configPath, xmlContent) then
        CustomLogger.Info("Configuration saved to XML")
        return true
    else
        CustomLogger.Error("Failed to save configuration")
        return false
    end
end

local function LoadConfig()
    if not FileMgr.DoesFileExist(configPath) then
        CustomLogger.Info("No config file found, using defaults")
        return
    end

    local configData = FileMgr.ReadFileContent(configPath)
    if not configData or configData == "" then
        CustomLogger.Warn("Config file is empty")
        return
    end

    local loadedConfig = XMLParser.ParseConfig(configData)

    CustomLogger.Info("Configuration loaded from XML")

    return loadedConfig
end

-- ============================================================================
-- Initialize Modules
-- ============================================================================
local Spooner = SpoonerCoreLib.New({
    CONSTANTS = CONSTANTS,
    NetworkUtils = NetworkUtils,
    CameraUtils = CameraUtils,
    MemoryUtils = MemoryUtils,
    Raycast = Raycast,
    RaycastForClipToGround = RaycastForClipToGround,
    XMLParser = XMLParser,
    Keybinds = Keybinds,
    CustomLogger = CustomLogger,
    spoonerSavePath = spoonerSavePath,
    SpoonerUtils = SpoonerUtils,
    RotationUtils = RotationUtils,
})

local Spawner = SpoonerSpawnerLib.New({
    Spooner = Spooner,
    CONSTANTS = CONSTANTS,
    MemoryUtils = MemoryUtils,
    CustomLogger = CustomLogger,
    Keybinds = Keybinds,
    NetworkUtils = NetworkUtils,
})

local DrawManager = SpoonerDrawLib.New({
    Spooner = Spooner,
    CONSTANTS = CONSTANTS,
    Raycast = Raycast,
    Keybinds = Keybinds,
    EntityLists = EntityLists,
})

local SpoonerUI = SpoonerUILib.New({
    Spooner = Spooner,
    Spawner = Spawner,
    DrawManager = DrawManager,
    EntityLists = EntityLists,
    SpoonerUtils = SpoonerUtils,
    spoonerSavePath = spoonerSavePath,
    pluginName = pluginName,
    Config = Config,
})

local SpoonerFeatures = SpoonerFeaturesLib.New({
    Spooner = Spooner,
    Config = Config,
    SaveConfig = SaveConfig,
    NetworkUtils = NetworkUtils,
    CameraUtils = CameraUtils,
    CustomLogger = CustomLogger,
    CONSTANTS = CONSTANTS,
})

-- ============================================================================
-- Initialization
-- ============================================================================
Script.QueueJob(function()
    -- Load entities
    EntityLists.LoadAll(propListPath, vehicleListPath, pedListPath)

    -- Init GUI
    SpoonerUI.Init()

    -- Load configuration and restore settings
    local loadedConfig = LoadConfig()
    SpoonerFeatures.ApplyLoadedConfig(loadedConfig)
end)

-- ============================================================================
-- Main Loops
-- ============================================================================

-- Thread for movement and action
Script.RegisterLooped(function()
    Script.QueueJob(function()
        Spooner.UpdateFreecam()
        Spooner.HandleInput()
        Spawner.HandleInput()
    end)
end)

-- Thread just for entity preview update
Script.RegisterLooped(function()
    Script.QueueJob(function()
        Spawner.UpdatePreview()
    end)
end)

-- Thread for on screen display
Script.RegisterLooped(function()
    Script.QueueJob(function()
        DrawManager.DrawCrosshair()
        DrawManager.DrawInstructionalButtons()
        DrawManager.DrawSelectedEntityMarker()
    end)
end)

Script.RegisterLooped(function()
    if Spooner.inSpoonerMode then
        Script.QueueJob(function()
            Spooner.HandleEntityGrabbing()
            DrawManager.DrawTargetedEntityBox()
        end)
    end
end)

Script.RegisterLooped(function()
    if Spooner.grabbedEntity then
        Script.QueueJob(function()
            Spooner.TakeControlOfEntity(Spooner.targetedEntity)
        end)
    elseif Spooner.targetedEntity then
        Script.QueueJob(function()
            Spooner.TakeControlOfEntity(Spooner.targetedEntity)
        end)
    end
end)

-- ============================================================================
-- Cleanup
-- ============================================================================
EventMgr.RegisterHandler(eLuaEvent.ON_UNLOAD, function()
    Script.QueueJob(function()
        if Spooner.inSpoonerMode then
            SpoonerFeatures.toggleSpoonerModeFeature:Toggle()
        end
        Spooner.selectedEntityIndex = 0
        Spooner.quickEditEntity = nil
        Spooner.UpdateSelectedEntityBlip()
        -- Free all cached memory allocations
        MemoryUtils.FreeAll()
    end)
end)
