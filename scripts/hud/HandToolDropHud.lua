--
-- HandToolDropHud
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

HandToolDropHud = {}

local HandToolDropHud_mt = Class(HandToolDropHud, HUDDisplay)

---Creates a new HandToolDropHud instance
-- @return HandToolDropHud New instance of HandToolDropHud
-- @includeCode
function HandToolDropHud.new()
  local self = HandToolDropHud:superClass().new(HandToolDropHud_mt)

  self.pickupTarget = nil
  self.pickupTargetChangeTime = 0

  self.markerOverlay = g_overlayManager:createOverlay("gui.whiteCircleFat", 0, 0, 0, 0)

  if self.markerOverlay ~= nil then
    self.markerOverlay:setAlignment(Overlay.ALIGN_VERTICAL_MIDDLE, Overlay.ALIGN_HORIZONTAL_CENTER)
  end

  self:setScale(g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE))
  g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.UI_SCALE], self.setScale, self)

  return self
end

---Deletes the HandToolDropHud instance
-- @includeCode
function HandToolDropHud:delete()
  g_messageCenter:unsubscribeAll(self)

  if self.markerOverlay ~= nil then
    self.markerOverlay:delete()
    self.markerOverlay = nil
  end

  HandToolDropHud:superClass().delete(self)
end

---Stores scaled values for the marker overlay
-- @includeCode
function HandToolDropHud:storeScaledValues()
  if self.markerOverlay ~= nil then
    self.markerOverlay:setDimension(self:scalePixelValuesToScreenVector(16, 16))
  end
end

---Draws the HUD for dropped hand tools
-- @includeCode
function HandToolDropHud:draw()
  local canDraw = self.markerOverlay ~= nil and self:getVisible() and g_localPlayer ~= nil
  local isMarkerEnabled = canDraw and g_gameSettings:getValue(GameSettings.SETTING.SHOW_TRIGGER_MARKER) and g_currentMission.hud:getIsVisible()
  local cameraNode = isMarkerEnabled and g_cameraManager:getActiveCamera() or nil
  local hasCamera = cameraNode ~= nil and cameraNode ~= 0 and entityExists(cameraNode)

  if hasCamera then
    local playerX, playerY, playerZ = g_localPlayer:getPosition()
    local heldHandTool = g_localPlayer:getHeldHandTool(true)
    local heldSpec = heldHandTool ~= nil and heldHandTool[HandToolDrop.SPEC_TABLE_NAME] or nil
    local pickupTarget = heldSpec ~= nil and heldSpec.pickupTarget or nil

    if pickupTarget ~= self.pickupTarget then
      self.pickupTarget = pickupTarget
      self.pickupTargetChangeTime = g_time
    end

    if g_time - self.pickupTargetChangeTime < 100 then
      pickupTarget = nil
    end

    new2DLayer()

    for _, handTool in ipairs(g_currentMission.handToolSystem.handTools) do
      local spec = handTool[HandToolDrop.SPEC_TABLE_NAME]

      if spec ~= nil and spec.isDropped and spec.droppedHandTool ~= nil then
        self:drawMarker(spec.droppedHandTool, cameraNode, playerX, playerY, playerZ, spec.droppedHandTool == pickupTarget)
      end
    end
  end
end

---Draws a marker for a dropped hand tool
-- @param table droppedHandTool Dropped hand tool data
-- @param number cameraNode Active camera node ID
-- @param number playerX Player's X position
-- @param number playerY Player's Y position
-- @param number playerZ Player's Z position
-- @param boolean isPickupTarget Is this the pickup target
-- @includeCode
function HandToolDropHud:drawMarker(droppedHandTool, cameraNode, playerX, playerY, playerZ, isPickupTarget)
  local tool = droppedHandTool.handTool
  local isAttached = droppedHandTool.visualRootNode ~= nil and not tool.isDeleted

  if isAttached and getVisibility(tool.rootNode) then
    local x, y, z = getWorldTranslation(droppedHandTool.nodeId)
    local isInRange = MathUtil.vector3LengthSq(x - playerX, y - playerY, z - playerZ) <= 5 ^ 2

    if isInRange then
      local _, _, cameraZ = worldToLocal(cameraNode, x, y, z)

      if cameraZ < -getNearClip(cameraNode) then
        local screenX, screenY, screenZ = project(x, y, z)
        local isOnScreen = screenX >= 0 and screenX <= 1 and screenY >= 0 and screenY <= 1 and screenZ <= 1

        if isOnScreen then
          local color = isPickupTarget and HUD.COLOR.ACTIVE or HUD.COLOR.INACTIVE

          self.markerOverlay:setColor(unpack(color))
          self.markerOverlay:setPosition(screenX, screenY)
          self.markerOverlay:render()
        end
      end
    end
  end
end
