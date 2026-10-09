--
-- PlayerHUDUpdaterExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

PlayerHUDUpdaterExtension = {}

---Overwrites game functions for HUD updates
-- PlayerHUDUpdater drops deleted objects through a delete listener and HandToolDropObject clears handTool on delete
-- @includeCode
function PlayerHUDUpdaterExtension.overwriteGameFunctions()
  PlayerHUDUpdater.update = Utils.appendedFunction(PlayerHUDUpdater.update, function(updater)
    local object = updater.object
    local handTool = object ~= nil and object:isa(HandToolDropObject) and object.handTool or nil

    if Platform.playerInfo.showVehicleInfo and handTool ~= nil then
      local box = updater.objectBox
      box:clear()
      box:setTitle(handTool:getName())

      local farm = g_farmManager:getFarmById(handTool:getOwnerFarmId())

      if farm ~= nil then
        box:addLine(g_i18n:getText("fieldInfo_ownedBy"), updater:convertFarmToName(farm))
      end

      if handTool.age > 0 then
        box:addLine(g_i18n:getText("infohud_age"), g_i18n:formatNumMonth(handTool.age))
      end

      box:showNextFrame()
    end
  end)
end
