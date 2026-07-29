# Script to add icon_asset_id fields to BuildingsData.luau

$filePath = "c:\Users\point\Documents\repos\temp\Sovereign_V2\Sovereign\src\shared\GameData\BuildingsData.luau"
$content = Get-Content $filePath -Raw

# Define the replacements (building name pattern -> icon asset ID)
$replacements = @{
    'BuildingsData\["Weaponsmith"\] = \{\s+model_asset_name = "Weapon_Smith",' = 'BuildingsData["Weaponsmith"] = {
	model_asset_name = "Weapon_Smith",
	icon_asset_id = "rbxassetid://131338540215149",'

    'BuildingsData\["Siege Workshop"\] = \{\s+model_asset_name = "Carpenter",' = 'BuildingsData["Siege Workshop"] = {
	model_asset_name = "Carpenter",
	icon_asset_id = "rbxassetid://73332606434180",'

    'BuildingsData\["Stables"\] = \{\s+model_asset_name = "Storehouse",' = 'BuildingsData["Stables"] = {
	model_asset_name = "Storehouse",
	icon_asset_id = "rbxassetid://110188781053984",'

    'BuildingsData\["Archery Range"\] = \{\s+model_asset_name = "Watch_Tower",' = 'BuildingsData["Archery Range"] = {
	model_asset_name = "Watch_Tower",
	icon_asset_id = "rbxassetid://86272485851338",'

    'BuildingsData\["Woodcutters Post"\] = \{\s+model_asset_name = "Lumberjack",' = 'BuildingsData["Woodcutters Post"] = {
	model_asset_name = "Lumberjack",
	icon_asset_id = "rbxassetid://107651048062977",'

    'BuildingsData\["Stone Quarry"\] = \{\s+model_asset_name = nil,' = 'BuildingsData["Stone Quarry"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://98679684747169",'

    'BuildingsData\["Iron Mine"\] = \{\s+model_asset_name = nil,' = 'BuildingsData["Iron Mine"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://139798646970990",'

    'BuildingsData\["Coal Mine"\] = \{\s+model_asset_name = nil,' = 'BuildingsData["Coal Mine"] = {
	model_asset_name = nil,
	icon_asset_id = "rbxassetid://133760178879723",'
}

# Apply replacements
foreach ($pattern in $replacements.Keys) {
    $content = $content -replace $pattern, $replacements[$pattern]
}

# Write back to file
$content | Set-Content $filePath -NoNewline

Write-Host "Icon asset IDs added successfully!"
