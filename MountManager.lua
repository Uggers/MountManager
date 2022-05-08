MountManager = LibStub("AceAddon-3.0"):NewAddon("MountManager", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MountManager")

------------------------------------------------------------------
-- Local Settings
------------------------------------------------------------------
local state = {}
local options = {
    name = "MountManager",
    handler = MountManager,
    type = "group",
    args = {
        desc = {
            type = "description",
            name = L["Description"],
            order = 0,
        },
        showInChat = {
            type = "toggle",
            name = L["Show in Chat"],
            desc = L["Toggles the display of the mount name in the chat window."],
            get = "GetShowInChat",
            set = "SetShowInChat",
            width = "full",
        },
        alwaysDifferent = {
            type = "toggle",
            name = L["Always Different"],
            desc = L["Always select a different mount than the previous one."],
            get = "GetAlwaysDifferent",
            set = "SetAlwaysDifferent",
            width = "full",
        },
        safeFlying = {
            type = "toggle",
            name = L["Safe Flying"],
            desc = L["Toggles the ability to dismount when flying"],
            get = "GetSafeFlying",
            set = "SetSafeFlying",
            width = "full",
        },
        oneClick = {
            type = "toggle",
            name = L["One Click"],
            desc = L["One click will dismount you and summon the next available mount."],
            get = "GetOneClick",
            set = "SetOneClick",
            width = "full",
        },
        autoNextMount = {
            type = "toggle",
            name = L["Automatic Next Mount"],
            desc = L["Automatically determine the next available random mount after summoning the currently selected one."],
            get = "GetAutoNextMount",
            set = "SetAutoNextMount",
            width = "full",
        },
    },
}
local defaults = {
    char = {
        level = level,
        race = race,
        class = class,
		faction = faction,
		prof = {},
        mount_skill = 0,
		serpent = false,
        mounts = {
			skill = {},
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        }
    },
    profile = {
        showInChat = false,
        alwaysDifferent = true,
        safeFlying = true,
        oneClick = true,
        autoNextMount = true
    },
}

-- This variable is used for determining the ability to fly in the old world
local flightTest = 60025
-- Worgen racial
local worgenRacial = 87840
-- Druid travel forms
local druidForms = {
    travel = 783,
    aquatic = 1066,
    flight = 33943,
    swiftflight = 40120
}
-- Shaman ghost wolf form
local ghostWolf = 2645
-- Monk zen flight
local zenFlight = 125883

-- A list of all the Vashj'ir zones for reference
local vashj = { 
	[613] = true, -- Vashj'ir
	[610] = true, -- Kelp'thar Forest
	[615] = true, -- Shimmering Expanse
	[614] = true  -- Abyssal Depths
}
-- Chauffeured
local chauffeured = {
	[678] = 179244, -- Chauffeured Mechano-Hog
	[679] = 179245, -- Chauffeured Mekgineer's Chopper
}
local SetMapToCurrentZone = SetMapToCurrentZone;

------------------------------------------------------------------
-- Property Accessors
------------------------------------------------------------------
function MountManager:GetShowInChat(info)
    return self.db.profile.showInChat
end
function MountManager:SetShowInChat(info, value)
    self.db.profile.showInChat = value
end

function MountManager:GetAlwaysDifferent(info)
    return self.db.profile.alwaysDifferent
end
function MountManager:SetAlwaysDifferent(info, value)
    self.db.profile.alwaysDifferent = value
end

function MountManager:GetSafeFlying(info)
    return self.db.profile.safeFlying
end
function MountManager:SetSafeFlying(info, value)
    self.db.profile.safeFlying = value
end

function MountManager:GetOneClick(info)
    return self.db.profile.oneClick
end
function MountManager:SetOneClick(info, value)
    self.db.profile.oneClick = value
end

function MountManager:GetAutoNextMount(info)
    return self.db.profile.autoNextMount
end
function MountManager:SetAutoNextMount(info, value)
    self.db.profile.autoNextMount = value
end

------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------
function MountManager:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("MountManagerDB", defaults, "Default")

    LibStub("AceConfig-3.0"):RegisterOptionsTable("MountManager", options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MountManager", "MountManager")
    self:RegisterChatCommand("mountmanager", "ChatCommand")
    self:RegisterChatCommand("mm", "ChatCommand")
end

function MountManager:OnEnable()
    -- Setup current character values
    self.db.char.level = UnitLevel("player")
    self.db.char.race = select(2, UnitRace("player"))
    self.db.char.class = UnitClass("player")
    self.db.char.faction = UnitFactionGroup("player")
	local prof1, prof2 = GetProfessions()
	if prof1 ~= nil then
		local name1, _, rank1 = GetProfessionInfo(prof1)
		local name2, _, rank2 = GetProfessionInfo(prof2)
		self.db.char.prof = {
			[name1] = rank1,
			[name2] = rank2
		}
	end
    self:LEARNED_SPELL_IN_TAB()
	
    -- Track the current combat state for summoning
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateCombatState")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateCombatState")
    self:RegisterEvent("PET_BATTLE_OPENING_START", "UpdatePetBattleState")
    self:RegisterEvent("PET_BATTLE_OPENING_DONE", "UpdatePetBattleState")
    self:RegisterEvent("PET_BATTLE_CLOSE", "UpdatePetBattleState")
    
    -- Track the current zone and player state for summoning restrictions
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")						-- new world zone
    self:RegisterEvent("ZONE_CHANGED", "UpdateZoneStatus")			-- new sub-zone
    self:RegisterEvent("ZONE_CHANGED_INDOORS", "UpdateZoneStatus")	-- new city sub-zone
    self:RegisterEvent("UPDATE_WORLD_STATES", "UpdateZoneStatus")	-- world pvp objectives updated
    self:RegisterEvent("SPELL_UPDATE_USABLE", "UpdateZoneStatus")	-- self-explanatory
	
	--[[-- Handle entering and exiting water
	local f = CreateFrame("Frame", "MyStateWatcher", UIParent, "SecureHandlerStateTemplate")
	f:SetScript("OnShow", function() self:UpdateZoneStatus() end)
	f:SetScript("OnHide", function() self:UpdateZoneStatus() end)
	RegisterStateDriver(f, "visibility", "[swimming] show; hide")]]
    
    -- Track riding skill to determine what mounts can be used
    if self.db.char.mount_skill ~= 5 or not self.db.char.serpent then
        self:RegisterEvent("LEARNED_SPELL_IN_TAB")
    end
    
    -- Learned a new mount
    self:RegisterEvent("COMPANION_LEARNED")
    
    -- Perform an initial scan
    self:ScanForNewMounts()
	self:ScanForRaceClass()
    self:ZONE_CHANGED_NEW_AREA()
    
    -- Track spell cast, to generate a new mount after the current has been cast
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	
    self:RegisterEvent("ADDON_LOADED")
end

------------------------------------------------------------------
-- Event Handling
------------------------------------------------------------------
function MountManager:ChatCommand(input)
    if input == "rescan" then
        self:Print(L["Beginning rescan..."])

        self.db.char.mounts = {
			skill = {},
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        }
        
        self:ScanForNewMounts()
		self:ScanForRaceClass()

        self:Print(L["Rescan complete"])
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

function MountManager:UpdateCombatState()
    state.inCombat = UnitAffectingCombat("player") == 1
end
function MountManager:UpdatePetBattleState(event)
    state.inPetBattle = C_PetBattles.IsInBattle() == true
end

function MountManager:ZONE_CHANGED_NEW_AREA()
	if not InCombatLockdown() then
		SetMapToCurrentZone();
		state.zone = GetCurrentMapAreaID()
	end
	
	self:UpdateZoneStatus()
end
function MountManager:UpdateZoneStatus(event)
    if InCombatLockdown() or state.inCombat or state.inPetBattle then return end
    
    local prevSwimming = state.isSwimming
    local prevFlyable = state.isFlyable
    
    state.isSwimming = IsSwimming() or IsSubmerged()
    
	local usable, _ = IsUsableSpell(flightTest)
    if IsFlyableArea() and self.db.char.mount_skill > 2 and usable == true then
        state.isFlyable = true
    else
        state.isFlyable = false
    end
    
    if (prevSwimming ~= state.isSwimming) or (prevFlyable ~= state.isFlyable) then
        self:GenerateMacro()
    end
end

function MountManager:LEARNED_SPELL_IN_TAB()
    if IsSpellKnown(90265) then -- Master (310 flight)
        self.db.char.mount_skill = 5
    elseif IsSpellKnown(34091) then -- Artisan (280 flight)
        self.db.char.mount_skill = 4
    elseif IsSpellKnown(34090) then -- Expert (150 flight)
        self.db.char.mount_skill = 3
    elseif IsSpellKnown(33391) then -- Journeyman (100 ground)
        self.db.char.mount_skill = 2
    elseif IsSpellKnown(33388) then -- Apprentice (60 ground)
        self.db.char.mount_skill = 1
    end
	
	--if IsSpellKnown(130487) then -- Cloud Serpent Riding
		self.db.char.serpent = true
	--end
	
	--[[if self.db.char.class == "Monk" then
		self.db.char.mounts["flying"][zenFlight] = IsSpellKnown(zenFlight);
	end]]
end

function MountManager:COMPANION_LEARNED()
    self:ScanForNewMounts()
end

function MountManager:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName)
    if self.db.profile.autoNextMount and unit == "player" and spellName == GetSpellInfo(state.mount) then
        self:GenerateMacro()
    end
end

function MountManager:UPDATE_SHAPESHIFT_FORMS()
    if IsSpellKnown(druidForms.travel) then
        self.db.char.mounts["skill"][druidForms.travel] = true
    end
    if IsSpellKnown(druidForms.aquatic) then
        self.db.char.mounts["water"][druidForms.aquatic] = true
    end
    if IsSpellKnown(druidForms.flight) then
        self.db.char.mounts["flying"][druidForms.flight] = true
    end
    if IsSpellKnown(druidForms.swiftflight) then
        self.db.char.mounts["flying"][druidForms.swiftflight] = true
    end
end

function MountManager:ADDON_LOADED(event, addon)
	if (addon == "Blizzard_PetJournal") then
		self:HijackMountFrame()
	end
end

------------------------------------------------------------------
-- Mount Methods
------------------------------------------------------------------
function MountManager:ScanForNewMounts()
    local newMounts = 0
	for _, id in pairs(C_MountJournal.GetMountIDs()) do
		local name, spellID, _, _, _, _, _, isFactionSpecific, faction, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        --make sure its valid and not already found
		local correctFaction = not isFactionSpecific or (self.db.char.faction == "Horde" and faction == 0) or (self.db.char.faction == "Alliance" and faction == 1)
		if correctFaction == true and isCollected == true and not self:MountExists(spellID) then
            newMounts = newMounts + 1
			
			local _, _, _, _, mountType = C_MountJournal.GetMountInfoExtraByID(id)

			
			-- 269 for 2 Water Striders (Azure and Crimson)
			-- 254 for 1 Subdued Seahorse (Vashj'ir and water)
			-- 248 for 163 "typical" flying mounts, including those that change based on level
			-- 247 for 1 Red Flying Cloud (flying mount)
			-- 242 for 1 Swift Spectral Gryphon (the one we fly while dead)
			-- 241 for 4 Qiraji Battle Tanks (AQ only)
			-- 232 for 1 Abyssal Seahorse (Vashj'ir only)
			-- 231 for 2 Turtles (Riding and Sea)
			-- 230 for 298 land mounts
			if mountType == 241 then
				self.db.char.mounts["aq"] = self.db.char.mounts["aq"] or {}
				self.db.char.mounts["aq"][spellID] = true
			end
			if mountType == 232 or mountType == 254 then
				self.db.char.mounts["vashj"] = self.db.char.mounts["vashj"] or {}
				self.db.char.mounts["vashj"][spellID] = true
			end
			if mountType == 247 or mountType == 248 then
				self.db.char.mounts["flying"] = self.db.char.mounts["flying"] or {}
				self.db.char.mounts["flying"][spellID] = true
			end
			if mountType == 231 or mountType == 254 or mountType == 269 then
				self.db.char.mounts["water"] = self.db.char.mounts["water"] or {}
				self.db.char.mounts["water"][spellID] = true
			end
			if mountType == 230 or mountType == 231 or mountType == 269 or mountType == 284 then
				self.db.char.mounts["ground"] = self.db.char.mounts["ground"] or {}
				self.db.char.mounts["ground"][spellID] = true
			end
        end
end
    
    if newMounts > 0 then
        self:Print(string.format("|cff20ff20%s|r %s", newMounts, L["new mount(s) found!"]))
		self:UpdateMountChecks()
    end
end
function MountManager:ScanForRaceClass()
	if self.db.char.race == "Worgen" and self.db.char.mount_skill > 0 then
		self.db.char.mounts["ground"][worgenRacial] = true;
	end
	if self.db.char.class == "Druid" then
		self:UPDATE_SHAPESHIFT_FORMS()
	end
	if self.db.char.class == "Monk" then
		self.db.char.mounts["flying"][zenFlight] = IsSpellKnown(zenFlight);
	end
	if self.db.char.class == "Shaman" and self.db.char.level > 14 then
		self.db.char.mounts["skill"][ghostWolf] = true;
	end
end
function MountManager:MountExists(spellID)
    for mountType, typeTable in pairs(self.db.char.mounts) do
        if typeTable[spellID] ~= nil then
            return true
        end
    end
    return false
end
function MountManager:SummonMount(mount)
	for _, id in pairs(C_MountJournal.GetMountIDs()) do
		local _, spellID = C_MountJournal.GetMountInfoByID(id)
        if spellID == mount then
			C_MountJournal.SummonByID(id)
			return
        end
    end
end
------------------------------------------------------------------
-- Mount Configuration
------------------------------------------------------------------
function MountManager:HijackMountFrame()
    self.companionButtons = {}

	local numMounts = (C_MountJournal.GetMountIDs())
	local scrollFrame = MountJournal.ListScrollFrame
	local buttons = scrollFrame.buttons

	-- build out check buttons
	for idx = 1, #buttons do
		local parent = buttons[idx];
		if idx <= numMounts then
			local button = CreateFrame("CheckButton", "MountCheckButton" .. idx, parent, "UICheckButtonTemplate")
			button:SetEnabled(false)
			button:SetPoint("TOPRIGHT", 0, 0)
			button:HookScript("OnClick", function(self)
				MountManager:MountCheckButton_OnClick(self)
			end)

			self.companionButtons[idx] = button
		end
	end

	-- hook up events to update check state on scrolling
	scrollFrame:HookScript("OnMouseWheel", function(self)
		MountManager:UpdateMountChecks()
	end)
	scrollFrame:HookScript("OnVerticalScroll", function(self)
		MountManager:UpdateMountChecks()
	end)
	
	---- hook up events to update check state on search or filter change
	hooksecurefunc("MountJournal_UpdateMountList", function(self)
		MountManager:UpdateMountChecks()
	end);

	-- force an initial update on the journal, as it's coded to only do it upon scroll or selection
	MountJournal_UpdateMountList()
end

function MountManager:UpdateMountChecks()
    if self.companionButtons then
		local offset = HybridScrollFrame_GetOffset(MountJournal.ListScrollFrame);
	
		for idx, button in ipairs(self.companionButtons) do
			local parent = button:GetParent()
			
			-- Get information about the currently selected mount
			local spellID = parent.spellID
			local id = self:FindSelectedID(spellID)
			local _, _, _, _, _, _, _, isFactionSpecific, faction, _, isCollected = C_MountJournal.GetMountInfoByID(id)
			local correctFaction = (not isFactionSpecific or (self.db.char.faction == "Horde" and faction == 0) or (self.db.char.faction == "Alliance" and faction == 1))
			
			if correctFaction == true and isCollected == true and parent:IsEnabled() == true then
					
			-- Set the checked state based on the currently saved value
				local checked = false;
				for mountType, typeTable in pairs(self.db.char.mounts) do
					if typeTable[spellID] ~= nil then
						checked = typeTable[spellID]
					end
				end

				button:SetEnabled(true)
				button:SetChecked(checked)
				button:SetAlpha(1.0);
			else
				button:SetEnabled(false)
				button:SetChecked(false)
				button:SetAlpha(0.25);
			end
		end
	end
end

function MountManager:MountCheckButton_OnClick(button)
    local spellID = button:GetParent().spellID
    
    -- Toggle the saved value for the selected mount
    for mountType, typeTable in pairs(self.db.char.mounts) do
        if typeTable[spellID] ~= nil then
            if typeTable[spellID] == true then
                typeTable[spellID] = false
            else
                typeTable[spellID] = true
            end
        end
    end
end
function MountManager:FindSelectedID(selectedSpellID)
	for _, id in pairs(C_MountJournal.GetMountIDs()) do
		local _, spellID = MountJournal_GetMountInfoByID(id);
		if spellID == selectedSpellID then
			return id;
		end
	end

	return nil;
end

function MountManager:MountManagerButton_OnClick(button)
    if button == "LeftButton" then
        if IsIndoors() then return end
        
        if IsFlying() then
            if self.db.profile.safeFlying == false then
                Dismount()
            end
        else
            local speed = GetUnitSpeed("player")
            
            if IsMounted() then
                Dismount()
                if speed == 0 and self.db.profile.oneClick then
                    self:SummonMount(state.mount)
                end
            else 
                if speed == 0 then
                    self:SummonMount(state.mount)
                end    
            end
        end
    else
        self:GenerateMacro()
    end
end

------------------------------------------------------------------
-- Macro Setup
------------------------------------------------------------------
function MountManager:GenerateMacro()
    if InCombatLockdown() or state.inCombat or state.inPetBattle then return end
    
    -- Create base macro for mount selection
    local index = GetMacroIndexByName("MountManager")
    if index == 0 then
        index = CreateMacro("MountManager", 1, "", 1, nil)
    end
    
	if self.db.char.level < 20 then
		local id = (UnitFactionGroup("player") == "Horde") and 678 or 679
		state.mount = select(5, C_MountJournal.GetMountInfoByID(id)) and chauffeured[id]
	else
		state.mount = self:GetRandomMount()
	end
	
	if state.mount then
		local name, rank, icon = GetSpellInfo(state.mount)
		--icon = string.sub(icon, 17)
		
		if self.db.profile.showInChat then
			self:Print(string.format("%s |cff20ff20%s|r", L["The next selected mount is"], name))
		end
		
		EditMacro(index, "MountManager", icon, string.format("/script MountManagerButton:Click(GetMouseButtonClicked());\n#showtooltip %s", name))
	else
		self:Print(L["There is no mount available for the current character."])
	end
end

function MountManager:GetRandomMount()
    if self.db.char.mount_skill == 0 then
		return nil
	end
	
	-- Determine state order for looking for a mount
    local typeList = {}
	local keyDown = IsModifierKeyDown()
	if vashj[state.zone] then -- in Vashj'ir
		if state.isSwimming == true and not keyDown then
			typeList = { "vashj", "water", "ground" }
		elseif state.isFlyable == true then
			typeList = { "flying", "vashj", "water", "ground" }
		else
			typeList = { "ground" }
		end
	elseif state.zone == 766 then -- in AQ
		if keyDown then
			typeList = { "ground" }
		elseif state.isSwimming == true then
			typeList = { "water", "aq", "ground" }
		else
			typeList = { "aq", "ground" }
		end
	elseif state.isSwimming == true then
		if state.isFlyable == true and not keyDown then
			typeList = { "flying", "water", "ground" }
		else
			typeList = { "water", "ground" }
		end
	elseif state.isFlyable == true and not keyDown then
		typeList = { "flying", "ground" }
	else
		typeList = { "ground" }
	end
	
	-- Cycle through the type list
	for i, type in pairs(typeList) do
		-- Make a sublist of any valid mounts of the selected type
		local mounts = {}
		for mount, active in pairs(self.db.char.mounts[type]) do
			if self.db.char.mounts[type][mount] == true and self:CheckProfession(mount) and self:CheckSerpent(mount) then
				mounts[#mounts + 1] = mount
			end
		end
		
		-- If there were any matching mounts of the current type, then proceed, otherwise move to the next type
		if #mounts > 0 then
			-- Grab a random mount from the narrowed list
			local rand = random(1, #mounts)
			local mount = mounts[rand]
			if state.mount == mount and self.db.profile.alwaysDifferent and #mounts > 1 then
				while state.mount == mount do
					rand = random(1, #mounts)
					mount = mounts[rand]
				end
			end
			return mount
		end
	end
	
	-- If this point has been reached, then no matching mount was found
	return nil
end

-- Class Mounts
local DeathKnight = Death Knight
local DemonHunter = Demon Hunter
local Hunter = Hunter
local Mage = Mage
local Monk = Monk
local Paladin = Paladin
local Priest = Priest
local Rogue = Rogue
local Shaman = Shaman
local Warlock = Warlock
local Warrior = Warrior
local classmounts =  {	
[229387] = { Death Knight }, --Deathlord's Vilebrood Vanquisher

[229417] = { Demon Hunter }, --Slayer's Felbroken Shrieker

[229386] = { Hunter }, --Huntmaster's Loyal Wolfhawk
[229438] = { Hunter }, --Huntmaster's Fierce Wolfhawk
[229439] = { Hunter }, --Huntmaster's Dire Wolfhawk

[229376] = { Mage }, --Archmage's Prismatic Disc

[229385] = { Monk }, --Ban-Lu, Grandmaster's Companion

[231435] = { Paladin }, --Highlord's Golden Charger
[231589] = { Paladin }, --Highlord's Valorous Charge
[231588] = { Paladin }, --Highlord's Vigilant Charger
[231587] = { Paladin }, --Highlord's Vengeful Charger

[229377] = { Priest }, --High Priest's Lightsworn Seeker

[231434] = { Rogue }, --Shadowblade's Murderous Omen
[231523] = { Rogue }, --Shadowblade's Lethal Omen
[231524] = { Rogue }, --Shadowblade's Baneful Omen
[231525] = { Rogue }, --Shadowblade's Crimson Omen

[231442] = { Shaman }, --Farseer's Raging Tempest

[238452] = { Warlock }, --Netherlord's Brimstone Wrathsteed
[238454] = { Warlock }, --Netherlord's Accursed Wrathsteed
[232412] = { Warlock }, --Netherlord's Chaotic Wrathsteed

[229388] = { Warrior }, --Battlelord's Bloodthirsty War Wyrm
}
function MountManager:CheckClass(spell)
	if classmounts[spell] then
		return self.db.char.classmounts
	end
	return true
end

-- Profession restricted mounts
local TAILORING_ID = 110426
local ENGINEERING_ID = 110403
local profMounts =  {
	[61451] = { TAILORING_ID, 300 }, --Flying Carpet
	[61309] = { TAILORING_ID, 300 }, --Magnificent Flying Carpet
	[75596] = { TAILORING_ID, 300 }, --Frosty Flying Carpet
	[169952] = { TAILORING_ID, 300 }, --Creeping Carpet
	
	[44153] = { ENGINEERING_ID, 300 }, --Flying Machine
	[44151] = { ENGINEERING_ID, 300 }, --Turbo-Charged Flying Machine
}
function MountManager:CheckProfession(spell)
	if profMounts[spell] then
		local skill = GetSpellInfo(profMounts[spell][1])
		local req = profMounts[spell][2]
		if self.db.char.prof[skill] then
			return self.db.char.prof[skill] >= req
		else
			return false
		end
	end
	return true
end

-- Cloud Serpents
local serpents = {
	[113199] = true, --Jade Cloud Serpent
	[123992] = true, --Azure Cloud Serpent
	[123993] = true, --Golden Cloud Serpent
	[127154] = true, --Onyx Cloud Serpent
	[127156] = true, --Crimson Cloud Serpent
	[127170] = true, --Astral Cloud Serpent
	
	[127158] = true, --Heavenly Onyx Cloud Serpent
	[127161] = true, --Heavenly Crimson Cloud Serpent
	[127164] = true, --Heavenly Golden Cloud Serpent
	[127165] = true, --Heavenly Jade Cloud Serpent
	[127169] = true, --Heavenly Azure Cloud Serpent
	
	[124408] = true, --Thundering Jade Cloud Serpent
	[129918] = true, --Thundering August Cloud Serpent
	[132036] = true, --Thundering Ruby Cloud Serpent
}
function MountManager:CheckSerpent(spell)
	if serpents[spell] then
		return self.db.char.serpent
	end
	return true
end
