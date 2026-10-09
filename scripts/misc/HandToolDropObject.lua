--
-- HandToolDropObject
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

-- Collision boxes share one mesh; dimensions are configured in XML
-- Scaled compound collisions in GIANTS Engine have shown visible contact gaps
-- No per-shape contact/rest offset control was found in the available Lua API
-- I have not found a better solution yet and am investigating alternatives

HandToolDropObject = {}

local HandToolDropObject_mt = Class(HandToolDropObject, PhysicsObject)
InitObjectClass(HandToolDropObject, "HandToolDropObject")

---Creates a new HandToolDropObject instance
-- @param boolean isServer Indicates server context
-- @param boolean isClient Indicates client context
-- @param table customMt Custom metatable
-- @return HandToolDropObject New instance
-- @includeCode
function HandToolDropObject.new(isServer, isClient, customMt)
  local self = HandToolDropObject:superClass().new(isServer, isClient, customMt or HandToolDropObject_mt)

  registerObjectClassName(self, "HandToolDropObject")

  self.forcedClipDistance = 100

  self.hiddenNodeVisibility = {}
  self.tensionBeltMeshes = {}
  self.sharedLoadRequestId = nil

  return self
end

---Configures the collision shape for a given node
-- @param any node The node to configure collision for
-- @includeCode
function HandToolDropObject:configureCollisionShape(node)
  setRigidBodyType(node, RigidBodyType.STATIC)
  removeFromPhysics(node)

  if getIsCompound(node) then
    setIsCompound(node, false)
  end

  setHasCollision(node, true)
  setCollisionFilterGroup(node, CollisionPreset.DYNAMIC_OBJECT.group)
  setCollisionFilterMask(node, CollisionPreset.DYNAMIC_OBJECT.mask)
  setClipDistance(node, self.forcedClipDistance)
  setIsNonRenderable(node, true)
end

---Releases the collider I3D file if loaded
-- @includeCode
function HandToolDropObject:releaseColliderI3DFile()
  if self.sharedLoadRequestId ~= nil then
    g_i3DManager:releaseSharedI3DFile(self.sharedLoadRequestId)
    self.sharedLoadRequestId = nil
  end
end

---Creates collision shapes from source node
-- @param any parentNode Parent node for shapes
-- @param any sourceNode Source node for cloning
-- @includeCode
function HandToolDropObject:createCollisionShapes(parentNode, sourceNode)
  local center = self.bounds.center
  local templateSize = HandToolDropUtil.getCollisionTemplateSize()

  for i, box in ipairs(self.bounds.boxes) do
    local shape = clone(sourceNode, false, false, false)

    setName(shape, "handToolDropCollision" .. i)
    self:configureCollisionShape(shape)

    setScale(shape, math.sqrt(box.size[1] / templateSize), math.sqrt(box.size[2] / templateSize), math.sqrt(box.size[3] / templateSize))
    setTranslation(shape, box.center[1] - center[1], box.center[2] - center[2], box.center[3] - center[3])
    setRotation(shape, unpack(box.rotation))
    setIsCompoundChild(shape, true)
    link(parentNode, shape)
  end
end

---Sets mass properties for the object
-- @includeCode
function HandToolDropObject:setMassProperties()
  setMass(self.nodeId, self:getTotalMass())

  local volume, centerX, centerY, centerZ = 0, 0, 0, 0

  for _, box in ipairs(self.bounds.boxes) do
    local boxVolume = box.size[1] * box.size[2] * box.size[3]
    volume = volume + boxVolume
    centerX = centerX + box.center[1] * boxVolume
    centerY = centerY + box.center[2] * boxVolume
    centerZ = centerZ + box.center[3] * boxVolume
  end

  if volume > 0 then
    local center = self.bounds.center
    centerX, centerY, centerZ = centerX / volume - center[1], centerY / volume - center[2], centerZ / volume - center[3]
  end

  setCenterOfMass(self.nodeId, centerX, centerY, centerZ)
end

---Creates a node for the HandToolDropObject
-- @param table position Position of the node
-- @param table rotation Rotation of the node
-- @return boolean True if node creation is successful
-- @includeCode
function HandToolDropObject:createNode(position, rotation)
  local filename = g_handToolDropSystem.defaultColliderFilename
  local scene
  scene, self.sharedLoadRequestId = g_i3DManager:loadSharedI3DFile(filename, false, false)

  if scene == nil or scene == 0 then
    Logging.error("HandTool Drop: unable to load collider '%s'", filename)
    self:releaseColliderI3DFile()
    return false
  end

  removeFromPhysics(scene)

  local nodeId, sourceNode

  if getNumOfChildren(scene) >= 2 then
    nodeId = getChildAt(scene, 0)
    sourceNode = getChildAt(scene, 1)
  end

  local isValidRoot = nodeId ~= nil and getHasClassId(nodeId, ClassIds.SHAPE) and getIsCompound(nodeId) and not getIsCompoundChild(nodeId) and getRigidBodyType(nodeId) ~= RigidBodyType.NONE
  local isValidTemplate = isValidRoot and getHasClassId(sourceNode, ClassIds.SHAPE) and not getIsCompoundChild(sourceNode) and getRigidBodyType(sourceNode) == RigidBodyType.STATIC

  if not isValidTemplate then
    Logging.error("HandTool Drop: collider must contain a compound Shape root and a separate static box: %s", filename)
    delete(scene)
    self:releaseColliderI3DFile()
    return false
  end

  setHasCollision(nodeId, false)
  setCollisionFilterGroup(nodeId, CollisionPreset.DYNAMIC_OBJECT.group)
  setCollisionFilterMask(nodeId, CollisionPreset.DYNAMIC_OBJECT.mask)
  setClipDistance(nodeId, self.forcedClipDistance)

  self:createCollisionShapes(nodeId, sourceNode)
  removeFromPhysics(nodeId)
  unlink(nodeId)
  delete(scene)

  if position ~= nil then
    setTranslation(nodeId, unpack(position))
    setRotation(nodeId, unpack(rotation))
  end

  link(getRootNode(), nodeId)
  self.rootNode = nodeId
  self:setNodeId(nodeId)

  if self.isServer then
    self:setMassProperties()
  end

  return true
end

---Sets visibility of the hand tool
-- @param boolean isVisible Visibility state
-- @includeCode
function HandToolDropObject:setHandToolVisibility(isVisible)
  local tool = self.handTool

  if tool ~= nil and tool.rootNode ~= nil and entityExists(tool.rootNode) then
    setVisibility(tool.rootNode, isVisible)
  end
end

---Updates the visual representation of the tool
-- @includeCode
function HandToolDropObject:updateVisual()
  if self.visualRootNode == nil or self.nodeId == 0 then
    return
  end

  setWorldTranslation(self.visualRootNode, getWorldTranslation(self.nodeId))
  setWorldQuaternion(self.visualRootNode, getWorldQuaternion(self.nodeId))
end

---Attaches a hand tool to the drop object
-- @return boolean Indicates success of the attachment
-- @includeCode
function HandToolDropObject:attachHandTool()
  local tool = self.handTool

  if tool.rootNode == nil or not entityExists(tool.rootNode) then
    return false
  end

  if self.visualRootNode == nil then
    self.visualRootNode = createTransformGroup("handToolDropObjectVisual")

    link(getRootNode(), self.visualRootNode)
  end

  link(self.visualRootNode, tool.rootNode)

  local center = self.bounds.center

  setTranslation(tool.rootNode, -center[1], -center[2], -center[3])
  setRotation(tool.rootNode, 0, 0, 0)

  local graphicalNode = tool.graphicalNode

  if graphicalNode ~= tool.rootNode then
    if self.graphicalTransform == nil then
      self.graphicalTransform = {
        translation = { getTranslation(graphicalNode) },
        rotation = { getRotation(graphicalNode) },
      }
    end

    setTranslation(graphicalNode, 0, 0, 0)
    setRotation(graphicalNode, 0, 0, 0)
  end

  local defaultPose = tool[HandToolDrop.SPEC_TABLE_NAME].defaultPose

  if defaultPose ~= nil then
    for node, transform in pairs(defaultPose) do
      if entityExists(node) then
        setTranslation(node, unpack(transform.translation))
        setRotation(node, unpack(transform.rotation))
      end
    end
  end

  for _, entry in ipairs(self.configuration.nodes) do
    local node = HandToolDropUtil.getConfigurationNode(graphicalNode, entry.path)

    if node ~= nil and node ~= 0 and self.hiddenNodeVisibility[node] == nil then
      self.hiddenNodeVisibility[node] = getVisibility(node)
      setVisibility(node, false)
    end
  end

  self:updateVisual()
  setVisibility(tool.rootNode, true)

  return true
end

---Detaches the hand tool and cleans up associated nodes
-- @includeCode
function HandToolDropObject:detachHandTool()
  for node, visibility in pairs(self.hiddenNodeVisibility) do
    if entityExists(node) then
      setVisibility(node, visibility)
    end
  end

  table.clear(self.hiddenNodeVisibility)

  local tool = self.handTool
  local graphicalTransform = self.graphicalTransform

  if graphicalTransform ~= nil and entityExists(tool.graphicalNode) then
    setTranslation(tool.graphicalNode, unpack(graphicalTransform.translation))
    setRotation(tool.graphicalNode, unpack(graphicalTransform.rotation))
  end

  self.graphicalTransform = nil

  local visualRootNode = self.visualRootNode
  if visualRootNode == nil then
    return
  end

  local rootNode = tool.rootNode

  if rootNode ~= nil and entityExists(rootNode) and getParent(rootNode) == visualRootNode then
    tool:detachTool()
  end

  if entityExists(visualRootNode) then
    delete(visualRootNode)
  end

  self.visualRootNode = nil
end

---Creates a HandToolDropObject from a given hand tool
-- @param table tool The hand tool to create from
-- @return HandToolDropObject The created HandToolDropObject or nil
-- @includeCode
function HandToolDropObject.createFromHandTool(tool)
  local configuration = tool[HandToolDrop.SPEC_TABLE_NAME].configuration
  local bounds = HandToolDropUtil.getHandToolBounds(tool, configuration)

  if bounds == nil then
    Logging.warning("HandTool Drop: no usable collision definition for %s", tool.configFileName)
    return nil
  end

  local self = HandToolDropObject.new(tool.isServer, tool.isClient)

  self.configuration = configuration
  self.handTool = tool
  self.bounds = bounds

  if configuration.mass ~= nil then
    self.massKg = configuration.mass
  elseif MathUtil.isFinite(tool.mass) and tool.mass > 0 then
    self.massKg = tool.mass
  else
    self.massKg = 1
  end

  self:setOwnerFarmId(tool:getOwnerFarmId(), true)

  return self
end

---Spawns the drop object at a position
-- @param table position Position to spawn the object
-- @param table rotation Rotation of the spawned object
-- @return boolean True if spawned successfully
-- @includeCode
function HandToolDropObject:spawn(position, rotation)
  if not self:createNode(position, rotation) or not self:attachHandTool() then
    self:delete()
    return false
  end

  self.handTool[HandToolDrop.SPEC_TABLE_NAME].droppedHandTool = self
  self:register()

  return true
end

---Called on server side when the object is synced to the client
-- @param integer streamId stream ID
-- @param Connection connection Connection object
-- @includeCode
function HandToolDropObject:writeStream(streamId, connection)
  NetworkUtil.writeNodeObject(streamId, self.handTool)
  streamWriteString(streamId, self.configuration.filename)

  for i = 1, 3 do
    streamWriteFloat32(streamId, self.bounds.center[i])
  end

  streamWriteUInt8(streamId, #self.bounds.boxes)

  for _, box in ipairs(self.bounds.boxes) do
    for i = 1, 3 do
      streamWriteFloat32(streamId, box.size[i])
      streamWriteFloat32(streamId, box.center[i])
      streamWriteFloat32(streamId, box.rotation[i])
    end
  end

  streamWriteFloat32(streamId, self.massKg)

  HandToolDropObject:superClass().writeStream(self, streamId, connection)
end

---Called on client side when the object is synced to the client
-- @param integer streamId stream ID
-- @param Connection connection Connection object
-- @param integer objectId ID of the object
-- @includeCode
function HandToolDropObject:readStream(streamId, connection, objectId)
  self.handToolId = NetworkUtil.readNodeObjectId(streamId)
  self.configuration = g_handToolDropSystem:getHandToolConfiguration(streamReadString(streamId))
  self.bounds = { center = {}, boxes = {} }

  for i = 1, 3 do
    self.bounds.center[i] = streamReadFloat32(streamId)
  end

  local numBoxes = streamReadUInt8(streamId)

  assert(numBoxes > 0 and numBoxes <= HandToolDropUtil.MAX_COLLISION_BOXES, "HandTool Drop: invalid network collision box count")

  for boxIndex = 1, numBoxes do
    local box = { size = {}, center = {}, rotation = {} }

    for i = 1, 3 do
      box.size[i] = streamReadFloat32(streamId)
      box.center[i] = streamReadFloat32(streamId)
      box.rotation[i] = streamReadFloat32(streamId)
    end

    self.bounds.boxes[boxIndex] = box
  end

  self.massKg = streamReadFloat32(streamId)

  assert(self.configuration ~= nil, "HandTool Drop: client configuration is missing")

  if self.nodeId == 0 then
    assert(self:createNode(), "HandTool Drop: client collider is missing")
  end

  HandToolDropObject:superClass().readStream(self, streamId, connection, objectId)

  self:tryResolveHandTool()
end

---Attempts to resolve and attach a hand tool if available
-- @includeCode
function HandToolDropObject:tryResolveHandTool()
  local tool = NetworkUtil.getObject(self.handToolId)
  local isSynchronized = tool ~= nil and not tool.isDeleted and tool:getIsSynchronized()

  if isSynchronized and tool:getHolder() == nil and not tool:getIsCarried() then
    local spec = tool[HandToolDrop.SPEC_TABLE_NAME]

    if spec.isDropped then
      self.handTool = tool

      if self:attachHandTool() then
        spec.droppedHandTool = self
      else
        self.handTool = nil
      end
    end
  end

  if self.handTool == nil then
    self:raiseActive()
  end
end

---Updates the hand tool drop object state
-- @param number dt Delta time in seconds
-- @includeCode
function HandToolDropObject:update(dt)
  if self.isDeleted or self.nodeId == 0 then
    return
  end

  HandToolDropObject:superClass().update(self, dt)

  if not self.isServer and self.handTool == nil then
    self:tryResolveHandTool()
  end

  self:updateVisual()
end

---Handles removal of ghost object
-- @includeCode
function HandToolDropObject:onGhostRemove()
  self:setHandToolVisibility(false)
  HandToolDropObject:superClass().onGhostRemove(self)
end

---Handles addition of ghost object
-- @includeCode
function HandToolDropObject:onGhostAdd()
  HandToolDropObject:superClass().onGhostAdd(self)
  self:updateVisual()
  self:setHandToolVisibility(true)
  self:raiseActive()
end

---Returns the hands of the player holding the tool
-- @return table The player's hands holding the item or nil
-- @includeCode
function HandToolDropObject:getHoldingHands()
  for _, player in pairs(g_currentMission.players) do
    local hands = player.hands

    if hands ~= nil and hands:getHeldItem() == self.nodeId then
      return hands
    end
  end

  return nil
end

---Releases the object from player's hands
-- @param boolean noEventSend Suppress event sending
-- @includeCode
function HandToolDropObject:releaseFromHands(noEventSend)
  local hands = self:getHoldingHands()

  if hands ~= nil then
    hands:dropHeldItem(noEventSend)
  end
end

---Checks if the hand tool supports tension belts
-- @return boolean True if tension belts are supported
-- @includeCode
function HandToolDropObject:getSupportsTensionBelts()
  return self:getHoldingHands() == nil
end

---Gets the tension belt node ID
-- @return number the node ID
-- @includeCode
function HandToolDropObject:getTensionBeltNodeId()
  return self.nodeId
end

---Retrieves mesh nodes for tension belts
-- @return table list of mesh nodes
-- @includeCode
function HandToolDropObject:getMeshNodes()
  return self.tensionBeltMeshes
end

---Checks if a player can pick up the hand tool
-- @param Player player The player attempting to pick up the tool
-- @return boolean True if the tool can be picked up, false otherwise
-- @includeCode
function HandToolDropObject:getCanPickupHandTool(player)
  local tool = self.handTool

  if tool == nil or self.tensionMountObject ~= nil or not HandToolDrop.getIsPlayerOnFoot(player) then
    return false
  end

  local spec = tool[HandToolDrop.SPEC_TABLE_NAME]

  if not spec.isDropped or spec.droppedHandTool ~= self or tool:getHolder() ~= nil then
    return false
  end

  local playerX, playerY, playerZ = player:getPosition()
  local objectX, objectY, objectZ = getWorldTranslation(self.nodeId)
  local distanceSq = MathUtil.vector3LengthSq(playerX - objectX, playerY + 0.5 - objectY, playerZ - objectZ)

  if distanceSq > HandToolHands.PICKUP_DISTANCE ^ 2 then
    return false
  end

  local heldHandTool = player:getHeldHandTool()
  local canEquipTool = (heldHandTool == nil or not heldHandTool.mustBeHeld) and player:getCanPickupHandTool(tool)

  if not canEquipTool then
    return false
  end

  local hands = player.hands
  local isHeldByPlayer = hands ~= nil and hands:getHeldItem() == self.nodeId
  local areHandsFree = not player:getAreHandsHoldingObject() and self:getHoldingHands() == nil

  return (isHeldByPlayer or areHandsFree) and HandToolDropUtil.getHasLineOfSight(player, self)
end

---Allows player to pick up hand tool
-- @param Player player the player
-- @return boolean true if picked up
-- @includeCode
function HandToolDropObject:pickupHandTool(player)
  if not self.isServer or not self:getCanPickupHandTool(player) then
    return false
  end

  local tool = self.handTool
  tool:setHolder(player)

  if tool:getHolder() == player then
    player:setCurrentHandTool(tool)
    return true
  else
    return false
  end
end

---Checks if the hand tool can be picked up
-- @param any _ Unused parameter
-- @return boolean True if can be picked up, false otherwise
-- @includeCode
function HandToolDropObject:getCanBePickedUp(_)
  return self.handTool ~= nil and self:getHoldingHands() == nil
end

---Gets the total mass of the object in tons
-- @return number Total mass in tons
-- @includeCode
function HandToolDropObject:getTotalMass()
  return self.massKg / 1000
end

---Deletes the hand tool drop object
-- @includeCode
function HandToolDropObject:delete()
  if self.isDeleted then
    return
  end

  local tool = self.handTool

  if tool ~= nil and tool[HandToolDrop.SPEC_TABLE_NAME].droppedHandTool == self then
    tool[HandToolDrop.SPEC_TABLE_NAME].droppedHandTool = nil
  end

  self:releaseFromHands(true)
  self:detachHandTool()

  unregisterObjectClassName(self)
  HandToolDropObject:superClass().delete(self)
  self.rootNode = nil

  self:releaseColliderI3DFile()

  self.handTool = nil
end
