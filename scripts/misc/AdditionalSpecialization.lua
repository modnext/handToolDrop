--
-- AdditionalSpecialization
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName
local oldFinalizeTypes = TypeManager.finalizeTypes

---Finalizes types for handTool specialization
-- @param any ... Additional parameters
-- @return any Result of oldFinalizeTypes call
-- @includeCode
function TypeManager:finalizeTypes(...)
  if g_modIsLoaded[modName] and self.typeName == "handTool" then
    local specializationName = modName .. ".handToolDrop"

    for typeName, typeEntry in pairs(self:getTypes()) do
      if typeEntry.specializationsByName[specializationName] == nil then
        self:addSpecialization(typeName, specializationName)
      end
    end
  end

  return oldFinalizeTypes(self, ...)
end
