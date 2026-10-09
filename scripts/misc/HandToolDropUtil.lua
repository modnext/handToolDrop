--
-- HandToolDropUtil
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

HandToolDropUtil = {
  MAX_COLLISION_BOXES = 4,
}

---
HandToolDropUtil.OBSTACLE_MASK = Utils.clearFlags(CollisionPreset.DYNAMIC_OBJECT.mask, CollisionFlag.TRIGGER, CollisionFlag.FILLABLE, CollisionFlag.PLAYER, CollisionFlag.WATER)

---Returns the collision template size
-- @return number Size of the collision template
-- @includeCode
function HandToolDropUtil.getCollisionTemplateSize()
  return 0.13
end

---Retrieves the default pose for a given node
-- @param any node The node to get the pose from
-- @param table pose Table to store pose data
-- @return table Table containing pose information
-- @includeCode
function HandToolDropUtil.getDefaultPose(node, pose)
  pose = pose or {}

  for i = 0, getNumOfChildren(node) - 1 do
    local child = getChildAt(node, i)

    pose[child] = {
      translation = { getTranslation(child) },
      rotation = { getRotation(child) },
    }

    HandToolDropUtil.getDefaultPose(child, pose)
  end

  return pose
end

---Uses the first timed keyframe for animated nodes in the cached model pose
-- @param HandTool handTool The hand tool being loaded
-- @param string key XML element to inspect
-- @param table pose Cached local transformations indexed by node
-- @includeCode
function HandToolDropUtil.loadAnimationStartPose(handTool, key, pose)
  local xmlFile = handTool.xmlFile
  local frameKey = key .. ".keyFrame(0)"
  local hasAnimation = xmlFile:hasProperty(key .. "#node") and xmlFile:hasProperty(frameKey .. "#time")

  if hasAnimation then
    local node = xmlFile:getNode(key .. "#node", nil, handTool.components, handTool.i3dMappings)
    local transform = pose[node]

    if transform ~= nil then
      transform.translation = xmlFile:getVector(frameKey .. "#translation", transform.translation, 3)
      transform.rotation = xmlFile:getRadiansVector(frameKey .. "#rotation", transform.rotation, 3)
    end
  end

  for _, childKey in xmlFile:iteratorChildren(key) do
    HandToolDropUtil.loadAnimationStartPose(handTool, childKey, pose)
  end
end

---Checks if a vector3 is valid
-- @param table value Vector3 to check
-- @param number limit Max allowed value
-- @return boolean True if valid, else false
-- @includeCode
function HandToolDropUtil.getIsValidVector3(value, limit)
  if type(value) ~= "table" or not MathUtil.getIsValidTransformationValue(value[1], value[2], value[3]) then
    return false
  end

  return math.max(math.abs(value[1]), math.abs(value[2]), math.abs(value[3])) <= limit
end

---Gets the configuration node from path
-- @param any visualNode Visual node to search
-- @param string path Path to the node
-- @return any The configuration node
-- @includeCode
function HandToolDropUtil.getConfigurationNode(visualNode, path)
  if path == "" then
    return visualNode
  end

  return I3DUtil.indexToObject(visualNode, path)
end

---Checks if node or one of its parents up to visualNode is hidden by configuration
-- @param any node Node to check
-- @param any visualNode Visual node reference
-- @param table hiddenNodes Set of hidden nodes
-- @return boolean True if hidden, else false
-- @includeCode
function HandToolDropUtil.getIsHiddenByConfiguration(node, visualNode, hiddenNodes)
  while node ~= nil and node ~= 0 do
    if hiddenNodes[node] then
      return true
    end

    if node == visualNode then
      return false
    end

    node = getParent(node)
  end

  return false
end

---Calculates the collision box for a hand tool
-- @param any node The node to calculate from
-- @param any referenceNode The reference node for transformation
-- @param table size Dimensions of the collision box
-- @param table translation Translation vector for positioning
-- @param table rotation Rotation vector in radians
-- @return table Collision box properties or nil
-- @includeCode
function HandToolDropUtil.getCollisionBox(node, referenceNode, size, translation, rotation)
  local cx, cy, cz = localToLocal(node, referenceNode, unpack(translation))
  local rx, ry, rz = unpack(rotation)
  local axes, scaledSize = {}, {}

  for i = 1, 3 do
    local x, y, z = mathEulerRotateVector(rx, ry, rz, i == 1 and size[1] or 0, i == 2 and size[2] or 0, i == 3 and size[3] or 0)
    x, y, z = localDirectionToLocal(node, referenceNode, x, y, z)
    local length = MathUtil.vector3Length(x, y, z)

    if not MathUtil.isFinite(length) or length <= 0 or length > 5 then
      return nil
    end

    axes[i] = { x / length, y / length, z / length }
    scaledSize[i] = length
  end

  for i = 1, 2 do
    for j = i + 1, 3 do
      local a, b = axes[i], axes[j]

      if math.abs(MathUtil.dotProduct(a[1], a[2], a[3], b[1], b[2], b[3])) > 0.001 then
        return nil
      end
    end
  end

  local measureNode = createTransformGroup("handToolDropMeasure")
  setDirection(measureNode, axes[3][1], axes[3][2], axes[3][3], axes[2][1], axes[2][2], axes[2][3])
  local boxRotation = { getRotation(measureNode) }
  delete(measureNode)

  return { size = scaledSize, center = { cx, cy, cz }, rotation = boxRotation }
end

---Calculates the collision bounds for given boxes
-- @param table boxes Array of box definitions
-- @return table Bounds with size and center info
-- @includeCode
function HandToolDropUtil.getCollisionBounds(boxes)
  if #boxes == 0 then
    return nil
  end

  local minBounds = { math.huge, math.huge, math.huge }
  local maxBounds = { -math.huge, -math.huge, -math.huge }

  for _, box in ipairs(boxes) do
    local rx, ry, rz = unpack(box.rotation)
    local xx, xy, xz = mathEulerRotateVector(rx, ry, rz, box.size[1], 0, 0)
    local yx, yy, yz = mathEulerRotateVector(rx, ry, rz, 0, box.size[2], 0)
    local zx, zy, zz = mathEulerRotateVector(rx, ry, rz, 0, 0, box.size[3])
    local halfX = (math.abs(xx) + math.abs(yx) + math.abs(zx)) * 0.5
    local halfY = (math.abs(xy) + math.abs(yy) + math.abs(zy)) * 0.5
    local halfZ = (math.abs(xz) + math.abs(yz) + math.abs(zz)) * 0.5

    minBounds[1] = math.min(minBounds[1], box.center[1] - halfX)
    minBounds[2] = math.min(minBounds[2], box.center[2] - halfY)
    minBounds[3] = math.min(minBounds[3], box.center[3] - halfZ)
    maxBounds[1] = math.max(maxBounds[1], box.center[1] + halfX)
    maxBounds[2] = math.max(maxBounds[2], box.center[2] + halfY)
    maxBounds[3] = math.max(maxBounds[3], box.center[3] + halfZ)
  end

  local bounds = { size = {}, center = {}, boxes = boxes }

  for i = 1, 3 do
    bounds.size[i] = maxBounds[i] - minBounds[i]
    bounds.center[i] = (minBounds[i] + maxBounds[i]) * 0.5
  end

  if HandToolDropUtil.getIsValidVector3(bounds.size, 5) and HandToolDropUtil.getIsValidVector3(bounds.center, 5) then
    return bounds
  end
end

---Retrieves collision boxes for a given tool configuration
-- @param table tool The tool object with graphical data
-- @param table configuration Configuration data for the tool
-- @return table Array of collision boxes or nil
-- @includeCode
function HandToolDropUtil.getConfigurationBoxes(tool, configuration)
  local visualNode, rootNode = tool.graphicalNode, tool.rootNode
  local hiddenNodes = {}

  for _, entry in ipairs(configuration.nodes) do
    local node = HandToolDropUtil.getConfigurationNode(visualNode, entry.path)

    if node ~= nil and node ~= 0 then
      hiddenNodes[node] = true
    end
  end

  local boxes = {}

  for _, entry in ipairs(configuration.collisions) do
    local node = HandToolDropUtil.getConfigurationNode(visualNode, entry.path)

    if node == nil or node == 0 then
      return nil
    end

    if not HandToolDropUtil.getIsHiddenByConfiguration(node, visualNode, hiddenNodes) then
      local box = HandToolDropUtil.getCollisionBox(node, rootNode, entry.size, entry.translation, entry.rotation)

      if box == nil then
        return nil
      end

      boxes[#boxes + 1] = box
    end
  end

  return boxes
end

---Calculates the bounding box for a hand tool
-- @param table tool The hand tool object
-- @param string configuration Configuration name
-- @return table Bounding box dimensions or nil
-- @includeCode
function HandToolDropUtil.getHandToolBounds(tool, configuration)
  local visualNode = tool.graphicalNode
  local translation, rotation

  if visualNode ~= tool.rootNode then
    translation, rotation = { getTranslation(visualNode) }, { getRotation(visualNode) }
    setTranslation(visualNode, 0, 0, 0)
    setRotation(visualNode, 0, 0, 0)
  end

  local boxes = HandToolDropUtil.getConfigurationBoxes(tool, configuration)

  if translation ~= nil then
    setTranslation(visualNode, unpack(translation))
    setRotation(visualNode, unpack(rotation))
  end

  if boxes == nil then
    Logging.warning("HandTool Drop: invalid collision path or scaled/rotated hierarchy in %s", tool.configFileName)
    return nil
  end

  return HandToolDropUtil.getCollisionBounds(boxes)
end

---Checks line of sight to dropped tool
-- @param table player Player object
-- @param table droppedHandTool Dropped tool object
-- @return boolean True if line of sight exists
-- @includeCode
function HandToolDropUtil.getHasLineOfSight(player, droppedHandTool)
  local x, y, z = player:getPosition()
  y = y + 1.2
  local ox, oy, oz = getWorldTranslation(droppedHandTool.nodeId)
  local dx, dy, dz = ox - x, oy - y, oz - z
  local distance = MathUtil.vector3Length(dx, dy, dz)

  if distance < 0.001 then
    return true
  end

  local hit = RaycastUtil.raycastClosest(x, y, z, dx / distance, dy / distance, dz / distance, distance, HandToolDropUtil.OBSTACLE_MASK)

  return hit == nil or hit == 0 or g_currentMission:getNodeObject(hit) == droppedHandTool
end

---Handles overlap checks for dropping hand tools
-- @param table check Object to store check results
-- @param number node Node identifier to check
-- @return boolean True if drop is allowed
-- @includeCode
function HandToolDropUtil.dropOverlapCallback(check, node)
  if node == nil or node == 0 then
    return true
  end

  check.blocked = true

  return false
end

---Calculates the drop position and rotation for a hand tool
-- @param Player player The player object
-- @param table size Dimensions of the tool
-- @return table Position and rotation for dropping the tool
-- @includeCode
function HandToolDropUtil.getDropTransform(player, size)
  local x, y, z = player:getPosition()
  local dx, dz = player:getCurrentFacingDirection()
  local _, _, _, lookX, _, lookZ = player:getLookRay()

  if lookX == nil or lookZ == nil or MathUtil.vector2LengthSq(lookX, lookZ) < 0.000001 then
    lookX, lookZ = dx, dz
  end

  local quarterTurn = math.pi * 0.5
  local yaw = MathUtil.roundToStep(MathUtil.getYRotationFromDirection(lookX, lookZ), quarterTurn)
  local distance = 0.8 + math.max(size[1], size[3]) * 0.5
  local px, pz = x + dx * distance, z + dz * distance
  local dropY = y + 0.85 + size[2] * 0.5
  local mask = HandToolDropUtil.OBSTACLE_MASK

  local hit = RaycastUtil.raycastClosest(x, dropY, z, dx, 0, dz, distance, mask)

  if hit ~= nil and hit ~= 0 then
    return nil
  end

  local _, _, groundY = RaycastUtil.raycastClosest(px, y + 2, pz, 0, -1, 0, 5, mask)

  if groundY == nil then
    groundY = getTerrainHeightAtWorldPos(g_terrainNode, px, y, pz)
  end

  if not MathUtil.isFinite(groundY) then
    return nil
  end

  local py = groundY + size[2] * 0.5 + 0.05
  local check = { blocked = false, dropOverlapCallback = HandToolDropUtil.dropOverlapCallback }
  local halfX, halfY, halfZ = size[1] * 0.5 + 0.02, size[2] * 0.5, size[3] * 0.5 + 0.02

  overlapBox(px, py, pz, 0, yaw, 0, halfX, halfY, halfZ, "dropOverlapCallback", check, mask, true, true, true, true)

  if check.blocked then
    return nil
  end

  return { px, py, pz }, { 0, yaw, 0 }
end
