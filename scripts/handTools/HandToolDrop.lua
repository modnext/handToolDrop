--
-- HandToolDrop
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

HandToolDrop = {}

---
HandToolDrop.SPEC_TABLE_NAME = "spec_" .. modName .. ".handToolDrop"

---Checks if all prerequisite specializations are loaded
-- @param any _ Unused parameter
-- @return boolean hasPrerequisite true if all prerequisite specializations are present
-- @includeCode
function HandToolDrop.prerequisitesPresent(_)
  return true
end

---Registers XML paths for saving the specialization to the savegame
-- @param XMLSchema schema XML schema to register paths to
-- @param string baseKey Base key for XML paths
-- @includeCode
function HandToolDrop.registerSavegameXMLPaths(schema, baseKey)
  local key = baseKey .. "." .. modName .. ".handToolDrop"

  schema:register(XMLValueType.BOOL, key .. "#isDropped", "Tool has a physical world representation", false)
  schema:register(XMLValueType.VECTOR_3, key .. "#position", "World position of collider centre in metres")
  schema:register(XMLValueType.VECTOR_3, key .. "#rotation", "World Euler rotation in radians")
end

---Register all functions from the specialization that can be called on vehicle level
-- @param string handToolType Type of hand tool
-- @includeCode
function HandToolDrop.registerFunctions(handToolType)
  SpecializationUtil.registerFunction(handToolType, "getIsHandToolDropSupported", HandToolDrop.getIsHandToolDropSupported)
  SpecializationUtil.registerFunction(handToolType, "getCanDropHandTool", HandToolDrop.getCanDropHandTool)
  SpecializationUtil.registerFunction(handToolType, "dropHandTool", HandToolDrop.dropHandTool)
  SpecializationUtil.registerFunction(handToolType, "setIsDropped", HandToolDrop.setIsDropped)
  SpecializationUtil.registerFunction(handToolType, "handToolDropPickupOverlapCallback", HandToolDrop.handToolDropPickupOverlapCallback)
end

---Register all function overwritings
-- @param string handToolType Type of hand tool
-- @includeCode
function HandToolDrop.registerOverwrittenFunctions(handToolType)
  SpecializationUtil.registerOverwrittenFunction(handToolType, "setHolder", HandToolDrop.setHolder)
end

---Register all events that should be called for this specialization
-- @param string handToolType Type of hand tool
-- @includeCode
function HandToolDrop.registerEventListeners(handToolType)
  SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onPostLoad", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onLoadFinished", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onDelete", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onReadStream", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onWriteStream", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onReadUpdateStream", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onWriteUpdateStream", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onUpdate", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolDrop)
  SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolDrop)
end

---Called after i3d has been loaded
-- @param any _ Unused parameter
-- @includeCode
function HandToolDrop:onLoad(_)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]

  spec.configuration = g_handToolDropSystem:getHandToolConfiguration(self.configFileName)
  spec.defaultPose = nil
  spec.isDropped = false
  spec.droppedHandTool = nil
  spec.pendingDropTransform = nil
  spec.hasRestoreAttempted = false
  spec.targetingPlayer = nil
  spec.pickupTarget = nil
  spec.pickupQuery = {}
  spec.actionEventId = nil

  spec.dropText = g_i18n:getText("action_returnHandTool")
  spec.pickupText = g_i18n:getText("action_takeHandTool")

  spec.dirtyFlag = self:getNextDirtyFlag()
end

---Called after the main loading has been finished
-- @param table savegame savegame
-- @includeCode
function HandToolDrop:onPostLoad(savegame)
  if not self.isServer or savegame == nil then
    return
  end

  local key = savegame.key .. "." .. modName .. ".handToolDrop"

  if savegame.xmlFile:getValue(key .. "#isDropped", false) then
    local position = { savegame.xmlFile:getValue(key .. "#position") }
    local rotation = { savegame.xmlFile:getValue(key .. "#rotation") }

    if HandToolDropUtil.getIsValidVector3(position, 1000000) and HandToolDropUtil.getIsValidVector3(rotation, 1000) then
      local spec = self[HandToolDrop.SPEC_TABLE_NAME]

      spec.isDropped = true
      spec.pendingDropTransform = {
        position = position,
        rotation = rotation,
      }
    else
      Logging.warning("HandTool Drop: ignoring invalid saved transform for %s", self.configFileName)
    end
  end
end

---Called when the loading has been completed
-- @param any _
-- @includeCode
function HandToolDrop:onLoadFinished(_)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  local resetPose = spec.configuration and spec.configuration.resetPose

  if resetPose then
    spec.defaultPose = HandToolDropUtil.getDefaultPose(self.graphicalNode)

    if spec.configuration.resetPoseMode == "animation" then
      HandToolDropUtil.loadAnimationStartPose(self, "handTool", spec.defaultPose)
    end
  end
end

---Cleans up HandToolDrop on deletion
-- @includeCode
function HandToolDrop:onDelete()
  HandToolDrop.onHeldEnd(self)

  local spec = self[HandToolDrop.SPEC_TABLE_NAME]

  if spec.droppedHandTool ~= nil then
    spec.droppedHandTool:delete()
  end
end

---Used to save object attributes to the savegame xml file
-- @param XMLFile xmlFile The savegame xml file to save to
-- @param string key The base object key
-- @param any _ Unused parameter
-- @includeCode
function HandToolDrop:saveToXMLFile(xmlFile, key, _)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  if not spec.isDropped then
    return
  end

  local droppedHandTool = spec.droppedHandTool
  local position, rotation

  if droppedHandTool ~= nil then
    position = { getWorldTranslation(droppedHandTool.nodeId) }
    rotation = { getWorldRotation(droppedHandTool.nodeId) }
  elseif spec.pendingDropTransform ~= nil then
    position = spec.pendingDropTransform.position
    rotation = spec.pendingDropTransform.rotation
  end

  if position ~= nil then
    xmlFile:setValue(key .. "#isDropped", true)
    xmlFile:setValue(key .. "#position", unpack(position))
    xmlFile:setValue(key .. "#rotation", unpack(rotation))
  end
end

---Sets the dropped state of HandToolDrop
-- @param boolean isDropped New dropped state
-- @includeCode
function HandToolDrop:setIsDropped(isDropped)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]

  if spec.isDropped ~= isDropped then
    spec.isDropped = isDropped
    self:raiseDirtyFlags(spec.dirtyFlag)
    self:raiseActive()
  end
end

---Called on client side when the object is synced to the client
-- @param integer streamId streamId
-- @param Connection connection Connection object
-- @includeCode
function HandToolDrop:onReadStream(streamId, connection)
  if connection:getIsServer() then
    self[HandToolDrop.SPEC_TABLE_NAME].isDropped = streamReadBool(streamId)
    self:raiseActive()
  end
end

---Called on server side when the object is synced to the client
-- @param integer streamId streamId
-- @param Connection connection Connection object
-- @includeCode
function HandToolDrop:onWriteStream(streamId, connection)
  if not connection:getIsServer() then
    streamWriteBool(streamId, self[HandToolDrop.SPEC_TABLE_NAME].isDropped)
  end
end

---Called on update to sync data between server and client
-- @param integer streamId stream ID
-- @param any _ Unused parameter
-- @param Connection connection Connection object
-- @includeCode
function HandToolDrop:onReadUpdateStream(streamId, _, connection)
  if connection:getIsServer() and streamReadBool(streamId) then
    self[HandToolDrop.SPEC_TABLE_NAME].isDropped = streamReadBool(streamId)
  end
end

---Called on update to sync data between server and client
-- @param integer streamId stream ID
-- @param Connection connection Connection object
-- @param integer dirtyMask dirty mask
-- @includeCode
function HandToolDrop:onWriteUpdateStream(streamId, connection, dirtyMask)
  if not connection:getIsServer() then
    local spec = self[HandToolDrop.SPEC_TABLE_NAME]

    if streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
      streamWriteBool(streamId, spec.isDropped)
    end
  end
end

---Sets the holder for the hand tool, managing its state
-- @param function superFunc The original function to call
-- @param any holder The entity holding the tool
-- @param boolean noEventSend Flag to skip event sending
-- @return nil No return value
-- @includeCode
function HandToolDrop:setHolder(superFunc, holder, noEventSend)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]

  if not spec.isDropped or holder == nil then
    return superFunc(self, holder, noEventSend)
  end

  local droppedHandTool = spec.droppedHandTool

  if not self.isServer and noEventSend then
    if droppedHandTool ~= nil then
      droppedHandTool:detachHandTool()
    end

    return superFunc(self, holder, noEventSend)
  end

  local isTensionMounted = droppedHandTool ~= nil and droppedHandTool.tensionMountObject ~= nil
  if isTensionMounted or not holder:getCanPickupHandTool(self) then
    return
  end

  if not self.isServer then
    if holder == g_localPlayer then
      HandToolSetHolderEvent.sendEvent(self, holder)
    end

    return
  end

  if self:getHolder() ~= nil then
    return
  end

  if droppedHandTool ~= nil then
    droppedHandTool:releaseFromHands()
    droppedHandTool:detachHandTool()
  end

  superFunc(self, holder, noEventSend)

  if self:getHolder() == holder then
    self:setIsDropped(false)
    spec.pendingDropTransform = nil

    if droppedHandTool ~= nil then
      droppedHandTool:delete()
    end
  elseif droppedHandTool ~= nil then
    droppedHandTool:attachHandTool()
  end
end

---Checks if player is on foot
-- @param Player player The player object
-- @return boolean True if player is on foot
-- @includeCode
function HandToolDrop.getIsPlayerOnFoot(player)
  return player ~= nil and player:isa(Player) and player:getIsControlled(true) and not player:getIsInVehicle()
end

---Checks if the hand tool can be dropped
-- @return boolean Indicates if drop is supported
-- @includeCode
function HandToolDrop:getIsHandToolDropSupported()
  local isAvailable = not self.isDeleted and self:getIsSynchronized() and self[HandToolDrop.SPEC_TABLE_NAME].configuration ~= nil
  local canBeDropped = self:getNeedsSaving() and self:getCanBeDropped() and not self.mustBeHeld

  if not isAvailable or not canBeDropped then
    return false
  end

  local rootNode = self.rootNode
  local graphicalNode = self.graphicalNode

  return rootNode ~= nil and graphicalNode ~= nil and entityExists(rootNode) and entityExists(graphicalNode)
end

---Gets the closest pickup target for the player
-- @param Player player The player object
-- @return any The closest pickup target or nil
-- @includeCode
function HandToolDrop.getPickupTarget(self, player)
  local node = player.targeter:getClosestTargetedNodeFromType(HandToolDrop)
  local target = node ~= nil and g_currentMission:getNodeObject(node) or nil

  if target ~= nil and target:getCanPickupHandTool(player) then
    return target
  end

  local _, _, _, directionX, _, directionZ = player.targeter:getLastLookRay()

  if directionX == nil or directionZ == nil or MathUtil.vector2LengthSq(directionX, directionZ) < 0.000001 then
    return nil
  end

  directionX, directionZ = MathUtil.vector2Normalize(directionX, directionZ)

  local query = self[HandToolDrop.SPEC_TABLE_NAME].pickupQuery
  local playerX, playerY, playerZ = player:getPosition()

  query.player = player
  query.playerX, query.playerZ = playerX, playerZ
  query.directionX, query.directionZ = directionX, directionZ
  query.closestTarget = nil
  query.closestDistanceSq = math.huge

  overlapSphere(playerX, playerY + 0.5, playerZ, HandToolHands.PICKUP_DISTANCE, "handToolDropPickupOverlapCallback", self, CollisionFlag.DYNAMIC_OBJECT, true, true, false, true)

  return query.closestTarget
end

---Callback for pickup overlap detection
-- @param number node The node ID of the object
-- @return boolean True to continue overlap checks
-- @includeCode
function HandToolDrop:handToolDropPickupOverlapCallback(node)
  local droppedHandTool = g_currentMission:getNodeObject(node)

  if droppedHandTool == nil or not droppedHandTool:isa(HandToolDropObject) or droppedHandTool.isDeleted then
    return true
  end

  local query = self[HandToolDrop.SPEC_TABLE_NAME].pickupQuery
  local objectX, _, objectZ = getWorldTranslation(droppedHandTool.nodeId)
  local offsetX, offsetZ = objectX - query.playerX, objectZ - query.playerZ
  local forwardDistance = offsetX * query.directionX + offsetZ * query.directionZ
  local sideDistance = math.abs(offsetX * query.directionZ - offsetZ * query.directionX)

  if forwardDistance < -0.15 or forwardDistance > HandToolHands.PICKUP_DISTANCE or sideDistance > math.max(0.6, forwardDistance * 0.5) then
    return true
  end

  local distanceSq = MathUtil.vector2LengthSq(offsetX, offsetZ)

  if distanceSq < query.closestDistanceSq and droppedHandTool:getCanPickupHandTool(query.player) then
    query.closestTarget = droppedHandTool
    query.closestDistanceSq = distanceSq
  end

  return true
end

---Checks if player can drop hand tool
-- @param Player player The player object
-- @return boolean True if can drop hand tool
-- @includeCode
function HandToolDrop:getCanDropHandTool(player)
  if self[HandToolDrop.SPEC_TABLE_NAME].isDropped or not HandToolDrop.getIsPlayerOnFoot(player) then
    return false
  end

  local isHeldByPlayer = player:getHeldHandTool() == self and self:getHolder() == player

  return self.isRegistered and isHeldByPlayer and not player:getAreHandsHoldingObject() and self:getIsHandToolDropSupported()
end

---Drops the hand tool for the specified player if allowed
-- @param any player The player dropping the hand tool
-- @return boolean Indicates success of the drop operation
-- @return boolean Indicates if a warning was shown
-- @includeCode
function HandToolDrop:dropHandTool(player)
  if not self.isServer or not self:getCanDropHandTool(player) then
    return false
  end

  local droppedHandTool = HandToolDropObject.createFromHandTool(self)
  if droppedHandTool == nil then
    return false
  end

  local position, rotation = HandToolDropUtil.getDropTransform(player, droppedHandTool.bounds.size)

  if position == nil then
    droppedHandTool:delete()
    HandToolDrop.showDropWarning(player)
    return false, true
  end

  self:setHolder(nil)
  self:setIsDropped(true)

  if droppedHandTool:spawn(position, rotation) then
    return true, false
  end

  self:setIsDropped(false)
  self:setHolder(player)
  player:setCurrentHandTool(self)

  return false, false
end

---Shows a warning if drop is not allowed
-- @param Player player The player to show warning to
-- @includeCode
function HandToolDrop.showDropWarning(player)
  if player ~= nil and player.isOwner then
    g_currentMission:showBlinkingWarning(g_i18n:getText("warning_actionNotAllowedHere"), 2000)
  end
end

---Restores the hand tool drop object from a saved state
-- @includeCode
function HandToolDrop.restoreHandToolDropObject(self)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  spec.hasRestoreAttempted = true

  self.pendingHolder = nil
  self.pendingHolderUniqueId = nil

  if spec.configuration == nil then
    Logging.error("HandTool Drop: no configuration for '%s' (normalized: '%s')", self.configFileName, tostring(g_handToolDropSystem:getHandToolConfigurationKey(self.configFileName)))
    return
  end

  if self:getHolder() ~= nil then
    self:setHolder(nil)
  end

  local droppedHandTool = self:getIsHandToolDropSupported() and HandToolDropObject.createFromHandTool(self) or nil
  local transform = spec.pendingDropTransform

  if droppedHandTool ~= nil and droppedHandTool:spawn(transform.position, transform.rotation) then
    spec.pendingDropTransform = nil
  else
    Logging.error("HandTool Drop: could not restore %s (%s); world position retained in savegame", self:getUniqueId(), self.configFileName)
  end
end

---Called on update
-- @includeCode
function HandToolDrop:onUpdate(_)
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  local isRestorePending = spec.pendingDropTransform ~= nil and not spec.hasRestoreAttempted

  if isRestorePending and self.isRegistered then
    HandToolDrop.restoreHandToolDropObject(self)
  end

  if not self:getIsActiveForInput(true) or spec.actionEventId == nil then
    return
  end

  local player = self:getCarryingPlayer()
  local canDrop = self:getCanDropHandTool(player)
  local pickupTarget

  if not canDrop then
    pickupTarget = HandToolDrop.getPickupTarget(self, player)
  end

  g_inputBinding:setActionEventActive(spec.actionEventId, canDrop or pickupTarget ~= nil)

  if pickupTarget ~= spec.pickupTarget then
    spec.pickupTarget = pickupTarget
    local text

    if pickupTarget ~= nil then
      text = string.format(spec.pickupText, pickupTarget.handTool:getName())
    else
      text = string.format(spec.dropText, self:getName())
    end

    g_inputBinding:setActionEventText(spec.actionEventId, text)
  end
end

---Handles the start of holding the tool
-- @includeCode
function HandToolDrop:onHeldStart()
  local player = self:getCarryingPlayer()
  if player == nil or not player.isOwner then
    return
  end

  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  spec.targetingPlayer = player

  local targeter = player.targeter
  targeter:addTargetType(HandToolDrop, CollisionFlag.DYNAMIC_OBJECT, 0.1, HandToolHands.PICKUP_DISTANCE)
  targeter:addFilterToTargetType(HandToolDrop, HandToolDrop.pickupTargetFilter)
end

---Filters valid pickup targets for hand tools
-- @param number node Node ID of the target
-- @return boolean True if valid target, else false
-- @includeCode
function HandToolDrop.pickupTargetFilter(node)
  local droppedHandTool = g_currentMission:getNodeObject(node)
  return droppedHandTool ~= nil and droppedHandTool:isa(HandToolDropObject) and not droppedHandTool.isDeleted
end

---Handles the end of holding a hand tool
-- @includeCode
function HandToolDrop:onHeldEnd()
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]

  local targetingPlayer = spec.targetingPlayer
  if targetingPlayer ~= nil then
    targetingPlayer.targeter:removeTargetType(HandToolDrop)
    spec.targetingPlayer = nil
  end

  spec.pickupTarget = nil
  if spec.pickupQuery ~= nil then
    spec.pickupQuery.player = nil
    spec.pickupQuery.closestTarget = nil
  end
end

---Register action events
-- @includeCode
function HandToolDrop:onRegisterActionEvents()
  local spec = self[HandToolDrop.SPEC_TABLE_NAME]
  spec.actionEventId = nil
  spec.pickupTarget = nil

  if not self:getIsActiveForInput(true) then
    return
  end

  local _, actionEventId = self:addActionEvent(InputAction.HANDTOOL_DROP_PICKUP, self, HandToolDrop.onHandToolDropPickupAction, false, true, false, false)
  spec.actionEventId = actionEventId

  if actionEventId ~= nil then
    g_inputBinding:setActionEventText(actionEventId, string.format(spec.dropText, self:getName()))
    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
  end
end

---Handles the action of dropping or picking up a hand tool
-- @includeCode
function HandToolDrop:onHandToolDropPickupAction(_, _)
  local player = self:getCarryingPlayer()
  local pickupTarget = self[HandToolDrop.SPEC_TABLE_NAME].pickupTarget

  if self:getCanDropHandTool(player) then
    if self.isServer then
      self:dropHandTool(player)
    else
      HandToolDropRequestEvent.sendEvent(player, self)
    end
  elseif pickupTarget ~= nil and pickupTarget:getCanPickupHandTool(player) then
    if self.isServer then
      pickupTarget:pickupHandTool(player)
    else
      HandToolSetHolderEvent.sendEvent(pickupTarget.handTool, player)
    end
  end
end
