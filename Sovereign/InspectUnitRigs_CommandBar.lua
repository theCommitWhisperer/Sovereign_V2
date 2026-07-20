-- Paste into the Studio COMMAND BAR (View -> Command Bar) and press Enter.
-- Prints every Model it finds in your unit-model locations, and whether each one
-- is an animatable rig (Humanoid + Motor6D joints) or a static model that can't
-- walk. Use it to check the models you added under Assets/Units.

local RS, SS, WS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage"), workspace

local function scan(root, label)
	if not root then return end
	print(("──── %s ────"):format(label))
	local found = false
	for _, m in ipairs(root:GetDescendants()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			found = true
			local hum = m:FindFirstChildOfClass("Humanoid")
			local rig = hum.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
			local motors, names = 0, {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("Motor6D") then motors += 1; table.insert(names, d.Name) end
			end
			local primary = m.PrimaryPart and "PrimaryPart OK" or "NO PrimaryPart"
			if motors == 0 then
				warn(('  ✗ %s  [%s]  %s  — NO Motor6D joints (static, cannot walk)'):format(m.Name, rig, primary))
			else
				print(('  ✓ %s  [%s]  %s  — %d joints: %s'):format(m.Name, rig, primary, motors, table.concat(names, ", ")))
			end
		end
	end
	if not found then print("  (no Humanoid models here)") end
end

local assetsRS = RS:FindFirstChild("Assets")
local assetsSS = SS:FindFirstChild("Assets")
scan(assetsRS and assetsRS:FindFirstChild("Units"), "ReplicatedStorage/Assets/Units")
scan(assetsSS and assetsSS:FindFirstChild("Units"), "ServerStorage/Assets/Units")
scan(SS:FindFirstChild("Dummy") and SS or nil, "ServerStorage (Dummy)")
scan(WS:FindFirstChild("Units"), "workspace/Units (spawned units)")
print("──── done ────  ✓ = animatable rig,  ✗ = static model (needs a real rig)")
