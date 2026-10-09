--
-- HandToolDropSystem
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

HandToolDropSystem = {}

source(g_currentModDirectory .. "scripts/misc/HandToolDropUtil.lua")
source(g_currentModDirectory .. "scripts/misc/AdditionalSpecialization.lua")
source(g_currentModDirectory .. "scripts/misc/HandToolDropObject.lua")
source(g_currentModDirectory .. "scripts/hud/HandToolDropHud.lua")
source(g_currentModDirectory .. "scripts/handTools/events/HandToolDropRequestEvent.lua")
source(g_currentModDirectory .. "scripts/extensions/HandToolExtension.lua")
source(g_currentModDirectory .. "scripts/extensions/InGameMenuStatisticsFrameExtension.lua")
source(g_currentModDirectory .. "scripts/extensions/PlayerHUDUpdaterExtension.lua")

local HandToolDropSystem_mt = Class(HandToolDropSystem)

---Creates a new HandToolDropSystem instance
-- @param string modName Name of the mod
-- @param string modDirectory Directory of the mod
-- @return HandToolDropSystem New instance of HandToolDropSystem
-- @includeCode
function HandToolDropSystem.new(modName, modDirectory)
  local self = setmetatable({}, HandToolDropSystem_mt)

  self.modName = modName
  self.configurationFilename = modDirectory .. "handToolDrop.xml"
  self.defaultColliderFilename = modDirectory .. "objects/handToolCollider.i3d"

  self.handTools = {}
  self.isInitialized = false
  self.hud = HandToolDropHud.new()

  return self
end

---Initializes the HandToolDropSystem
-- @includeCode
function HandToolDropSystem:initialize()
  if self.isInitialized then
    return
  end

  HandToolExtension.overwriteGameFunctions(self)
  InGameMenuStatisticsFrameExtension.overwriteGameFunctions(self)
  PlayerHUDUpdaterExtension.overwriteGameFunctions()

  self.isInitialized = true
end

---Loads the map configuration if mod is loaded
-- @includeCode
function HandToolDropSystem:loadMap()
  if g_modIsLoaded[self.modName] then
    self:loadConfiguration()
  end
end

---Cleans up the HandToolDropSystem resources
-- @includeCode
function HandToolDropSystem:deleteMap()
  self.handTools = {}

  if self.hud ~= nil then
    self.hud:delete()
    self.hud = nil
  end
end

---Draws the HUD for the HandToolDropSystem
-- @includeCode
function HandToolDropSystem:draw()
  if self.hud ~= nil then
    self.hud:draw()
  end
end

---Gets the configuration key for a hand tool
-- @param string filename The filename of the hand tool
-- @return string The processed configuration key
-- @includeCode
function HandToolDropSystem:getHandToolConfigurationKey(filename)
  if string.isNilOrWhitespace(filename) then
    return nil
  else
    local gameBasePath = string.lower((string.gsub(g_gameBasePath, "\\", "/")))
    local normalizedFilename = string.lower(NetworkUtil.convertToNetworkFilename((string.gsub(filename, "\\", "/"))))

    if gameBasePath ~= "" and string.startsWith(normalizedFilename, gameBasePath) then
      return string.sub(normalizedFilename, #gameBasePath + 1)
    else
      return normalizedFilename
    end
  end
end

---Loads the collision box from XML
-- @param XMLFile xmlFile The XML file containing data
-- @param string key The key for the collision box
-- @return table Collision box data or nil
-- @includeCode
function HandToolDropSystem:loadCollisionBox(xmlFile, key)
  local size = xmlFile:getVector(key .. "#size", nil, 3)
  local translation = xmlFile:getVector(key .. "#translation", nil, 3)
  local rotation = xmlFile:getRadiansVector(key .. "#rotation", { 0, 0, 0 }, 3)
  local templateSize = HandToolDropUtil.getCollisionTemplateSize()
  local isValidSize = HandToolDropUtil.getIsValidVector3(size, 5 / templateSize) and size[1] > 0 and size[2] > 0 and size[3] > 0
  local isValidTranslation = HandToolDropUtil.getIsValidVector3(translation, 5)
  local isValidRotation = HandToolDropUtil.getIsValidVector3(rotation, math.huge)

  if isValidSize and isValidTranslation and isValidRotation then
    for i = 1, 3 do
      size[i] = size[i] * templateSize
    end

    return {
      path = xmlFile:getString(key .. "#path", ""),
      size = size,
      translation = translation,
      rotation = rotation,
    }
  else
    Logging.xmlWarning(xmlFile, "Invalid collision size, translation or rotation at '%s'", key)
  end
end

---Loads collision definitions from XML
-- @param XMLFile xmlFile The XML file containing data
-- @param string key The key for collision definitions
-- @return table List of collision boxes or nil
-- @includeCode
function HandToolDropSystem:loadCollisionDefinitions(xmlFile, key)
  local collisions = {}

  for _, collisionKey in xmlFile:iterator(key .. ".collision") do
    local collision = self:loadCollisionBox(xmlFile, collisionKey)

    if collision ~= nil then
      collisions[#collisions + 1] = collision
    else
      return nil
    end
  end

  if #collisions > HandToolDropUtil.MAX_COLLISION_BOXES then
    Logging.xmlWarning(xmlFile, "Too many collision boxes at '%s' (maximum %d)", key, HandToolDropUtil.MAX_COLLISION_BOXES)
  elseif #collisions == 0 then
    Logging.xmlWarning(xmlFile, "Expected at least one collision box at '%s'", key)
  else
    return collisions
  end
end

---Loads node definitions from an XML file
-- @param XMLFile xmlFile The XML file to read from
-- @param string key The key to access nodes
-- @return table A table of node definitions or nil
-- @includeCode
function HandToolDropSystem:loadNodeDefinitions(xmlFile, key)
  local nodes = {}

  for _, nodeKey in xmlFile:iterator(key .. ".node") do
    local path = xmlFile:getString(nodeKey .. "#path")
    local hide = xmlFile:getBool(nodeKey .. "#hide", false)

    if path ~= nil and hide then
      nodes[#nodes + 1] = { path = path }
    else
      Logging.xmlWarning(xmlFile, "Expected a node path and hide='true' at '%s'", nodeKey)
      return nil
    end
  end

  return nodes
end

---Loads hand tool configuration from XML
-- @param XMLFile xmlFile The XML file containing data
-- @param string key The key for the hand tool
-- @return table Hand tool configuration or nil
-- @includeCode
function HandToolDropSystem:loadHandToolConfiguration(xmlFile, key)
  local filename = xmlFile:getString(key .. "#filename")
  local mass = xmlFile:getFloat(key .. "#mass")
  local resetPoseMode = xmlFile:getString(key .. "#resetPoseMode", "model")

  if string.isNilOrWhitespace(filename) then
    Logging.xmlWarning(xmlFile, "Missing hand tool XML filename at '%s'", key)
  elseif mass ~= nil and (not MathUtil.isFinite(mass) or mass <= 0) then
    Logging.xmlWarning(xmlFile, "Hand tool mass must be a positive finite value in kilograms at '%s'", key)
  elseif resetPoseMode ~= "model" and resetPoseMode ~= "animation" then
    Logging.xmlWarning(xmlFile, "Reset pose mode must be 'model' or 'animation' at '%s'", key)
  else
    local collisions = self:loadCollisionDefinitions(xmlFile, key)
    local nodes = collisions ~= nil and self:loadNodeDefinitions(xmlFile, key) or nil

    if nodes ~= nil then
      return {
        filename = self:getHandToolConfigurationKey(filename),
        mass = mass,
        resetPose = xmlFile:getBool(key .. "#resetPose", false),
        resetPoseMode = resetPoseMode,
        collisions = collisions,
        nodes = nodes,
      }
    end
  end
end

---Loads the hand tool configuration file
-- @includeCode
function HandToolDropSystem:loadConfiguration()
  self.handTools = {}

  local xmlFile = XMLFile.load("HandToolDropXML", self.configurationFilename)

  if xmlFile == nil then
    Logging.error("HandTool Drop: unable to load configuration '%s'", self.configurationFilename)
  else
    if xmlFile:hasProperty("handToolDrop") then
      local numConfigurations = 0

      for _, key in xmlFile:iterator("handToolDrop.handTool") do
        local configuration = self:loadHandToolConfiguration(xmlFile, key)

        if configuration ~= nil then
          if self.handTools[configuration.filename] == nil then
            self.handTools[configuration.filename] = configuration
            numConfigurations = numConfigurations + 1
          else
            Logging.xmlWarning(xmlFile, "Duplicate hand tool configuration at '%s': %s", key, configuration.filename)
          end
        end
      end

      Logging.info("HandTool Drop: loaded %d hand tool configurations", numConfigurations)
    else
      Logging.xmlError(xmlFile, "Missing handToolDrop root element")
    end

    xmlFile:delete()
  end
end

---Gets configuration for a hand tool
-- @param string filename File name of the hand tool
-- @return table Configuration table of the hand tool
-- @includeCode
function HandToolDropSystem:getHandToolConfiguration(filename)
  local key = self:getHandToolConfigurationKey(filename)

  return self.handTools[key]
end

---Checks if the hand tool is dropped
-- @param table handTool Hand tool object
-- @return boolean True if dropped, else false
-- @includeCode
function HandToolDropSystem:getIsDroppedHandTool(handTool)
  local spec = handTool ~= nil and handTool[HandToolDrop.SPEC_TABLE_NAME] or nil

  return spec ~= nil and spec.isDropped
end

---Global instance of HandToolDropSystem
g_handToolDropSystem = HandToolDropSystem.new(g_currentModName, g_currentModDirectory)
addModEventListener(g_handToolDropSystem)

---
TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, function(typeManager)
  if typeManager.typeName == "handTool" and g_modIsLoaded[g_handToolDropSystem.modName] then
    g_handToolDropSystem:initialize()
  end
end)
