# Define the root directory for the source files
$srcPath = ".\src"

# Create the root source directory
New-Item -ItemType Directory -Path $srcPath -Force

# Define the folder structure based on the project configuration
$folders = @(
    "Workspace",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterPlayer/StarterPlayerScripts",
    "StarterPlayer/StarterCharacterScripts",
    "StarterGui",
    "StarterPack",
    "Lighting",
    "SoundService"
)

# Create each directory within the 'src' folder
foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path (Join-Path $srcPath $folder) -Force
}

# Define the content for the default.project.json file
$projectJsonContent = @'
{
  "name": "Sovereign_V2",
  "tree": {
    "$className": "DataModel",
    "Workspace": {
      "$path": "src/Workspace"
    },
    "ReplicatedStorage": {
      "$path": "src/ReplicatedStorage"
    },
    "ServerScriptService": {
      "$path": "src/ServerScriptService"
    },
    "ServerStorage": {
      "$path": "src/ServerStorage"
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$path": "src/StarterPlayer/StarterPlayerScripts"
      },
      "StarterCharacterScripts": {
        "$path": "src/StarterPlayer/StarterCharacterScripts"
      }
    },
    "StarterGui": {
      "$path": "src/StarterGui"
    },
    "StarterPack": {
      "$path": "src/StarterPack"
    },
    "Lighting": {
      "$path": "src/Lighting"
    },
    "SoundService": {
      "$path": "src/SoundService"
    }
  }
}
'@

# Create the default.project.json file in the root of the repository
Set-Content -Path ".\default.project.json" -Value $projectJsonContent

Write-Host "Rojo project structure for Sovereign_V2 has been created successfully!"