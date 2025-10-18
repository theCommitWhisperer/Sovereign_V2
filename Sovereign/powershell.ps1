# --- IMPORTANT: UPDATE THIS PATH! ---
$projectRoot = "C:\Users\point\Documents\repos\temp\Sovereign_V2\Sovereign\"

# --- Define Paths ---
$componentsDir = Join-Path $projectRoot "src\ui\components"
$sliderFile = Join-Path $componentsDir "Slider.luau"
$settingsFile = Join-Path $projectRoot "src\ui\screens\Settings\Settings.luau"

# --- 1. Create the new Slider.luau component ---
Set-Content -Path $sliderFile -Value @"
-- A reusable slider component for things like volume control.
local React = require(game.ReplicatedStorage.Packages.react)
local UIConfig = require(script.Parent.Parent.UIConfig)

local Slider = React.Component:extend("Slider")

function Slider:init()
    self.state = {
        value = self.props.value or 50,
    }
    self.frameRef = React.createRef()
    self.isDragging = false

    self.onDrag = function(input)
        if self.isDragging and self.frameRef.current then
            local frame = self.frameRef.current
            local relativeX = input.Position.X - frame.AbsolutePosition.X
            local percentage = math.clamp(relativeX / frame.AbsoluteSize.X, 0, 1)
            local newValue = math.floor(self.props.min + (self.props.max - self.props.min) * percentage)

            self:setState({ value = newValue })
            if self.props.onValueChanged then
                self.props.onValueChanged(newValue)
            end
        end
    end

    self.onRelease = function()
        self.isDragging = false
    end
end

function Slider:render()
    local value = self.state.value
    local min = self.props.min
    local max = self.props.max
    local percentage = (value - min) / (max - min)

    return React.createElement("Frame", {
        Name = "Slider",
        Size = self.props.Size or UDim2.new(1, 0, 0, 20),
        Position = self.props.Position,
        AnchorPoint = self.props.AnchorPoint,
        LayoutOrder = self.props.LayoutOrder,
        BackgroundTransparency = self.props.BackgroundTransparency or 0,
        BackgroundColor3 = self.props.BackgroundColor3 or UIConfig.Color.Secondary,
        [React.Ref] = self.frameRef,
        [React.Event.MouseMoved] = self.onDrag,
        [React.Event.MouseButton1Up] = self.onRelease,
    }, {
        Progress = React.createElement("Frame", {
            Name = "Progress",
            Size = UDim2.new(percentage, 0, 1, 0),
            BackgroundColor3 = UIConfig.Color.PrimaryButton,
            BorderSizePixel = 0,
        }),
        Handle = React.createElement("TextButton", {
            Name = "Handle",
            Size = UDim2.new(0, 20, 1, 10),
            Position = UDim2.new(percentage, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Text = "",
            BackgroundColor3 = UIConfig.Color.Primary,
            [React.Event.MouseButton1Down] = function()
                self.isDragging = true
            end,
        }),
        ValueLabel = React.createElement("TextLabel", {
            Name = "ValueLabel",
            Size = UDim2.new(0, 50, 1, 0),
            Position = UDim2.new(1, 10, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            Text = tostring(value),
            TextColor3 = UIConfig.Color.Primary,
            TextXAlignment = Enum.TextXAlignment.Left,
            FontFace = UIConfig.Font.Default,
            TextSize = 24,
        }),
    })
end

return Slider
"@

# --- 2. Update Settings.luau to use the new Slider component ---
$settingsContent = Get-Content -Raw -Path $settingsFile

# Add the Slider component to the list of required components
$settingsContent = $settingsContent -replace 'local Textbox = require\(components.Textbox\)', "local Textbox = require(components.Textbox)`nlocal Slider = require(components.Slider)"

# Replace the Music Volume Textbox with the Slider
$settingsContent = $settingsContent -replace 'Input = React.createElement\(Textbox, {\s*Size = UDim2.new\(0.3, 0, 1, 0\),\s*Position = UDim2.fromScale\(1, 0.5\),\s*AnchorPoint = Vector2.new\(1, 0.5\),\s*Text = self.state.musicVolume,\s*onTextChanged = function\(newText\)\s*self:setState\({ musicVolume = newText }\)\s*end,\s*}\)', "Input = React.createElement(Slider, {`n                        Size = UDim2.new(0.3, 0, 1, 0),`n                        Position = UDim2.fromScale(1, 0.5),`n                        AnchorPoint = Vector2.new(1, 0.5),`n                        min = 0,`n                        max = 100,`n                        value = self.state.musicVolume,`n                        onValueChanged = function(newValue)`n                            self:setState({ musicVolume = newValue })`n                        end,`n                    })"

# Replace the Sound Effects Volume Textbox with the Slider
$settingsContent = $settingsContent -replace 'Input = React.createElement\(Textbox, {\s*Size = UDim2.new\(0.3, 0, 1, 0\),\s*Position = UDim2.fromScale\(1, 0.5\),\s*AnchorPoint = Vector2.new\(1, 0.5\),\s*Text = self.state.soundEffectsVolume,\s*onTextChanged = function\(newText\)\s*self:setState\({ soundEffectsVolume = newText }\)\s*end,\s*}\)', "Input = React.createElement(Slider, {`n                        Size = UDim2.new(0.3, 0, 1, 0),`n                        Position = UDim2.fromScale(1, 0.5),`n                        AnchorPoint = Vector2.new(1, 0.5),`n                        min = 0,`n                        max = 100,`n                        value = self.state.soundEffectsVolume,`n                        onValueChanged = function(newValue)`n                            self:setState({ soundEffectsVolume = newValue })`n                        end,`n                    })"

# Also, update the initial state to use numbers instead of strings for the volumes
$settingsContent = $settingsContent -replace 'self:setState\({ musicVolume = "100", soundEffectsVolume = "100", isFullScreen = true, showSubtitles = false }\)', "self:setState({ musicVolume = 100, soundEffectsVolume = 100, isFullScreen = true, showSubtitles = false })"

Set-Content -Path $settingsFile -Value $settingsContent

Write-Host "Successfully created the Slider component and updated the Settings screen!"