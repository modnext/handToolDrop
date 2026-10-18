--
-- ForestryPhysicsRopeExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

ForestryPhysicsRopeExtension = {}

---Overwrites game functions for forestry ropes
-- @param HandToolDropSystem system Game system reference
-- @includeCode
function ForestryPhysicsRopeExtension.overwriteGameFunctions(system)
  system:overwriteGameFunction(ForestryPhysicsRope, "create", function(superFunc, rope, ...)
    local hasDefaultCollisionFilter = rope.collisionGroup == ForestryPhysicsRope.COLLISION_GROUP and rope.collisionMask == ForestryPhysicsRope.COLLISION_MASK

    if hasDefaultCollisionFilter then
      local collisionGroup = HandToolDropUtil.COLLISION_GROUP
      local collisionMask = Utils.clearFlags(rope.collisionMask, collisionGroup)

      if bit32.btest(rope.collisionMask, rope.collisionGroup) then
        collisionMask = bit32.bor(collisionMask, collisionGroup)
      end

      rope.collisionGroup = collisionGroup
      rope.collisionMask = collisionMask
    end

    return superFunc(rope, ...)
  end)
end
