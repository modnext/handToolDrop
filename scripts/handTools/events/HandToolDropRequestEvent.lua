--
-- HandToolDropRequestEvent
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

HandToolDropRequestEvent = {}

local HandToolDropRequestEvent_mt = Class(HandToolDropRequestEvent, Event)
InitEventClass(HandToolDropRequestEvent, "HandToolDropRequestEvent")

---Creates a new empty HandToolDropRequestEvent
-- @return HandToolDropRequestEvent New event instance
-- @includeCode
function HandToolDropRequestEvent.emptyNew()
  return Event.new(HandToolDropRequestEvent_mt)
end

---Creates a HandToolDropRequestEvent with player and tool
-- @param Player player The player dropping the tool
-- @param HandTool handTool The tool to drop
-- @return HandToolDropRequestEvent New event instance
-- @includeCode
function HandToolDropRequestEvent.new(player, handTool)
  local self = HandToolDropRequestEvent.emptyNew()

  self.player = player
  self.handTool = handTool

  return self
end

---Called on client side when the object is synced to the client
-- @param integer streamId stream ID
-- @param Connection connection Connection object
-- @includeCode
function HandToolDropRequestEvent:readStream(streamId, connection)
  self.player = NetworkUtil.readNodeObject(streamId)
  self.handTool = NetworkUtil.readNodeObject(streamId)
  self:run(connection)
end

---Called on server side when the object is synced to the client
-- @param integer streamId stream ID
-- @param nil _ Unused parameter
-- @includeCode
function HandToolDropRequestEvent:writeStream(streamId, _)
  NetworkUtil.writeNodeObject(streamId, self.player)
  NetworkUtil.writeNodeObject(streamId, self.handTool)
end

---Run event
-- @param Connection connection Connection object
-- @includeCode
function HandToolDropRequestEvent:run(connection)
  if connection:getIsServer() then
    HandToolDrop.showDropWarning(self.player)
  else
    local isRequestingPlayer = self.player ~= nil and self.player:isa(Player) and self.player.connection == connection
    local isValidHandTool = self.handTool ~= nil and self.handTool:isa(HandTool)

    if isRequestingPlayer and isValidHandTool then
      local _, isBlocked = self.handTool:dropHandTool(self.player)

      if isBlocked then
        connection:sendEvent(self)
      end
    end
  end
end

---Sends a request to drop a hand tool
-- @param any player The player instance
-- @param any handTool The hand tool to drop
-- @includeCode
function HandToolDropRequestEvent.sendEvent(player, handTool)
  g_client:getServerConnection():sendEvent(HandToolDropRequestEvent.new(player, handTool))
end
