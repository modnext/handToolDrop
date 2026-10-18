--
-- HandToolExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

HandToolExtension = {}

---Overwrites game functions for hand tools
-- @param any system Game system reference
-- @return nil No return value
-- @includeCode
function HandToolExtension.overwriteGameFunctions(system)
  system:overwriteGameFunction(HandToolSetHolderEvent, "run", function(superFunc, event, connection)
    if not connection:getIsServer() and system:getIsDroppedHandTool(event.handTool) then
      local player = event.holder
      local droppedHandTool = event.handTool[HandToolDrop.SPEC_TABLE_NAME].droppedHandTool
      local isRequestingPlayer = player ~= nil and player:isa(Player) and player.connection == connection

      if isRequestingPlayer and event.handTool:getIsSynchronized() and droppedHandTool ~= nil and droppedHandTool:pickupHandTool(player) then
        g_messageCenter:publish(HandToolSetHolderEvent)
      end
    else
      return superFunc(event, connection)
    end
  end)

  system:overwriteGameFunction(PlayerHoldHandToolEvent, "run", function(superFunc, event, connection)
    local isDroppedRequest = not connection:getIsServer() and event.handToolId ~= nil and system:getIsDroppedHandTool(NetworkUtil.getObject(event.handToolId))

    if not isDroppedRequest then
      return superFunc(event, connection)
    end
  end)
end
