--[[
	GenerateUnitPlaceholders.lua
	----------------------------------------------------------------------------
	Run this ONCE in Roblox Studio (paste into the Command Bar, or drop it into a
	temporary Script inside ServerScriptService and press Play, then delete it).

	What it does:
	  • Reads the real unit list from ReplicatedStorage.Shared.GameData.UnitsData
	    (so it always matches the game — no hard-coded names to drift).
	  • Creates ReplicatedStorage/Assets/Units if missing.
	  • For every unit type WITHOUT a model yet, drops a valid placeholder rig
	    named after the type (Peasant, Spearman, Archer, ...). Each placeholder is
	    a proper Humanoid + HumanoidRootPart rig (unanchored, welded) so units
	    spawn and move correctly until you swap in your own art.
	  • Prints a report of what it created vs. what already had a custom model.

	How the game picks up your models (from UnitManager.getUnitModel):
	  • A single Model named  "Peasant"                        -> always used
	  • Models "Peasant", "Peasant_A", "Peasant_2", ...        -> random variant
	  • A Folder "Peasant" holding any-named Model children     -> random variant
	  Replace a placeholder with your rig (keep the name), or delete a placeholder
	  and add a folder / "_variant" models to get random variety.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Where the game looks for unit models.
local PLACE_INTO_SERVICE = ReplicatedStorage -- (UnitManager also checks ServerStorage/Assets/Units)

-- Placeholders are tinted this colour so they're obvious in-game.
local PLACEHOLDER_COLOR = Color3.fromRGB(226, 65, 226)

-- ---------------------------------------------------------------------------
-- Resolve the unit list from the game's own data.
-- ---------------------------------------------------------------------------
local function resolveUnitTypes(): { string }
	local ok, gameData = pcall(function()
		return require(ReplicatedStorage.Shared.GameData)
	end)

	local names = {}
	if ok and gameData and gameData.Units then
		for unitType in pairs(gameData.Units) do
			table.insert(names, unitType)
		end
	else
		warn("[Placeholders] Could not require GameData.Units — using a built-in list.")
		names = {
			"Administrator","Archer","Baker","Banshee","Bard","Blacksmith","Bonnacht",
			"Brewer","Carpenter","Ceithern","Celtic_Champion","Druid","Farmer","Fianna",
			"Fisherman","Gallowglass","High_King","Hobelar","Innkeeper","Kern","King",
			"Knight","Light_Cavalry","Longbowman","Merchant","Miller","Miner","Monk",
			"Peasant","Priest","Scribe","Slinger","Smelter","Spearman","Stonemason",
			"Tanner","Trader","Viking","Wolfhound","Woodcutter",
		}
	end
	table.sort(names)
	return names
end

-- ---------------------------------------------------------------------------
-- Folder plumbing.
-- ---------------------------------------------------------------------------
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Does a usable model already exist for this type (exact, "_variant", or folder)?
local function hasModelFor(unitsFolder: Instance, unitType: string): boolean
	local exact = unitsFolder:FindFirstChild(unitType)
	if exact and exact:IsA("Folder") then
		for _, child in exact:GetChildren() do
			if child:IsA("Model") then
				return true
			end
		end
	end
	local prefix = unitType .. "_"
	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") and (child.Name == unitType or child.Name:sub(1, #prefix) == prefix) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Build one valid placeholder rig (Humanoid + HumanoidRootPart, welded).
-- ---------------------------------------------------------------------------
local function makePlaceholder(unitType: string): Model
	local model = Instance.new("Model")
	model.Name = unitType

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = true -- collides with the world for pathfinding
	hrp.Anchored = false
	hrp.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = PLACEHOLDER_COLOR
	torso.Material = Enum.Material.SmoothPlastic
	torso.CanCollide = false
	torso.Anchored = false
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(255, 204, 153)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Anchored = false
	head.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 1
	humanoid.DisplayName = unitType
	humanoid.Parent = model

	model.PrimaryPart = hrp

	-- Position parts around the root, then weld so the rig moves as one.
	torso.CFrame = hrp.CFrame
	head.CFrame = hrp.CFrame * CFrame.new(0, 1.6, 0)

	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = hrp
	w1.Part1 = torso
	w1.Parent = hrp

	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = torso
	w2.Part1 = head
	w2.Parent = torso

	-- Tag so you can find/replace all placeholders later.
	model:SetAttribute("IsPlaceholder", true)

	return model
end

-- ---------------------------------------------------------------------------
-- Run.
-- ---------------------------------------------------------------------------
local assets = ensureFolder(PLACE_INTO_SERVICE, "Assets")
local unitsFolder = ensureFolder(assets, "Units")

local unitTypes = resolveUnitTypes()
local created, skipped = {}, {}

for _, unitType in ipairs(unitTypes) do
	if hasModelFor(unitsFolder, unitType) then
		table.insert(skipped, unitType)
	else
		local placeholder = makePlaceholder(unitType)
		placeholder.Parent = unitsFolder
		table.insert(created, unitType)
	end
end

print(("=== Unit placeholders: %d types ==="):format(#unitTypes))
print(("Created %d placeholder(s) in %s/Assets/Units:"):format(#created, PLACE_INTO_SERVICE.Name))
print("  " .. (next(created) and table.concat(created, ", ") or "(none — all already had models)"))
if next(skipped) then
	print(("Skipped %d type(s) that already have a model:"):format(#skipped))
	print("  " .. table.concat(skipped, ", "))
end
print("Replace a magenta placeholder with your own rig (keep the name), or add")
print('"<Type>_A", "<Type>_B", ... / a "<Type>" folder for random variants.')
