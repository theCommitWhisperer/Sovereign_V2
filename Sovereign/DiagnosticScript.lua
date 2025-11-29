--[[
    WALL MODEL DIAGNOSTIC SCRIPT

    Instructions:
    1. Open Roblox Studio
    2. Open the Script editor (View > Output, View > Command Bar)
    3. Paste this entire script into the Command Bar or a Script object
    4. Run it
    5. Copy the output from the Output window
    6. Share it with Claude

    This script analyzes all wall models and provides:
    - ConnectionPoint positions (world and local)
    - Walkway positions (world and local)
    - Model pivot points
    - Recommended grid alignment data
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function analyzeModel(model)
    if not model:IsA("Model") then
        return nil
    end

    local info = {
        name = model.Name,
        pivot = model:GetPivot(),
        connectionPoints = {},
        walkways = {},
    }

    -- Find all ConnectionPoints
    for _, desc in model:GetDescendants() do
        if desc:IsA("BasePart") and desc.Name:match("^ConnectionPoint") then
            local worldPos = desc.Position
            local localPos = info.pivot:PointToObjectSpace(worldPos)
            local worldRot = desc.CFrame - desc.Position
            local localRot = info.pivot:ToObjectSpace(desc.CFrame)

            table.insert(info.connectionPoints, {
                name = desc.Name,
                worldPos = worldPos,
                localPos = localPos,
                worldCFrame = desc.CFrame,
                localCFrame = localRot,
                lookVector = desc.CFrame.LookVector,
                size = desc.Size,
            })
        end

        -- Find walkways
        if desc:IsA("BasePart") and desc.Name == "Walkway" then
            local worldPos = desc.Position
            local localPos = info.pivot:PointToObjectSpace(worldPos)

            table.insert(info.walkways, {
                worldPos = worldPos,
                localPos = localPos,
                size = desc.Size,
            })
        end
    end

    -- Calculate centers
    if #info.connectionPoints > 0 then
        local total = Vector3.zero
        for _, cp in info.connectionPoints do
            total = total + cp.worldPos
        end
        info.cpCenter = total / #info.connectionPoints
        info.cpCenterLocal = info.pivot:PointToObjectSpace(info.cpCenter)
    end

    if #info.walkways > 0 then
        local total = Vector3.zero
        for _, ww in info.walkways do
            total = total + ww.worldPos
        end
        info.walkwayCenter = total / #info.walkways
        info.walkwayCenterLocal = info.pivot:PointToObjectSpace(info.walkwayCenter)
    end

    return info
end

local function vector3ToString(v)
    return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

local function printModelInfo(info)
    print("\n" .. string.rep("=", 80))
    print("MODEL: " .. info.name)
    print(string.rep("=", 80))
    print("Pivot Position: " .. vector3ToString(info.pivot.Position))
    print("Pivot Rotation: " .. vector3ToString(Vector3.new(
        math.deg(info.pivot:ToEulerAnglesXYZ())
    )))

    print("\nConnectionPoints (" .. #info.connectionPoints .. " found):")
    for i, cp in ipairs(info.connectionPoints) do
        print(string.format("  [%d] %s", i, cp.name))
        print("      World Pos:  " .. vector3ToString(cp.worldPos))
        print("      Local Pos:  " .. vector3ToString(cp.localPos))
        print("      Look Vec:   " .. vector3ToString(cp.lookVector))
        print("      Size:       " .. vector3ToString(cp.size))
    end

    if info.cpCenter then
        print("\n  CP Center (World): " .. vector3ToString(info.cpCenter))
        print("  CP Center (Local): " .. vector3ToString(info.cpCenterLocal))
    end

    print("\nWalkways (" .. #info.walkways .. " found):")
    for i, ww in ipairs(info.walkways) do
        print(string.format("  [%d]", i))
        print("      World Pos:  " .. vector3ToString(ww.worldPos))
        print("      Local Pos:  " .. vector3ToString(ww.localPos))
        print("      Size:       " .. vector3ToString(ww.size))
    end

    if info.walkwayCenter then
        print("\n  Walkway Center (World): " .. vector3ToString(info.walkwayCenter))
        print("  Walkway Center (Local): " .. vector3ToString(info.walkwayCenterLocal))
    end

    -- Calculate offset between CP and Walkway
    if info.cpCenter and info.walkwayCenter then
        local offset = info.walkwayCenter - info.cpCenter
        local offsetLocal = info.walkwayCenterLocal - info.cpCenterLocal
        print("\nOffset (Walkway - CP):")
        print("  World: " .. vector3ToString(offset))
        print("  Local: " .. vector3ToString(offsetLocal))
        print("  Vertical (Y): " .. string.format("%.2f", offset.Y))
    end

    print(string.rep("=", 80))
end

-- Main execution
print("\n\n")
print(string.rep("#", 80))
print("WALL MODEL DIAGNOSTIC REPORT")
print("Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
print(string.rep("#", 80))

local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
    print("ERROR: Could not find ReplicatedStorage.Assets")
    return
end

local buildings = assets:FindFirstChild("Buildings")
if not buildings then
    print("ERROR: Could not find ReplicatedStorage.Assets.Buildings")
    return
end

-- List of wall models to analyze
local wallModels = {
    "Wall Segment",
    "Ladder Wall Segment",
    "Wall Corner",
    "Wall Corner Reverse",
    "Tower",
    "Gatehouse",
}

local results = {}

for _, modelName in ipairs(wallModels) do
    local model = buildings:FindFirstChild(modelName)
    if model then
        local info = analyzeModel(model)
        if info then
            table.insert(results, info)
            printModelInfo(info)
        end
    else
        print("\nWARNING: Could not find model: " .. modelName)
    end
end

-- Summary
print("\n\n")
print(string.rep("#", 80))
print("SUMMARY - Grid Alignment Recommendations")
print(string.rep("#", 80))

for _, info in ipairs(results) do
    if info.cpCenterLocal then
        print(string.format("\n%s:", info.name))
        print(string.format("  - CP Local Offset: %s", vector3ToString(info.cpCenterLocal)))
        print(string.format("  - Recommended Grid Anchor: Use CP center at local %s",
            vector3ToString(info.cpCenterLocal)))
    end
end

print("\n\nDiagnostic complete! Copy all of this output and share with Claude.")
