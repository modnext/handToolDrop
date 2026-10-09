--
-- InGameMenuStatisticsFrameExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

InGameMenuStatisticsFrameExtension = {}

---Overwrites game functions for the menu
-- @param any system Game system to modify
-- @return nil No return value
-- @includeCode
function InGameMenuStatisticsFrameExtension.overwriteGameFunctions(system)
  InGameMenuStatisticsFrame.updateViewHandTools = Utils.overwrittenFunction(InGameMenuStatisticsFrame.updateViewHandTools, function(frame, superFunc)
    local holderText = g_i18n:getText("ui_map")

    for _, item in ipairs(frame.handTools) do
      if item.handTool:getHolder() == nil and system:getIsDroppedHandTool(item.handTool) then
        local column = item.columns[InGameMenuStatisticsFrame.COLUMN_HOLDER]
        column.text = holderText
        column.value = holderText
      end
    end

    return superFunc(frame)
  end)
end
