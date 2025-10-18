local UIConfig = {
    Font = {
        Default = Font.new("rbxasset://fonts/families/IndieFlower.json"),
        Title = Font.new("rbxasset://fonts/families/IndieFlower.json"), -- Custom 'Kings' font: rbxassetid://12187371622
        Button = {
            Default = Font.new("rbxasset://fonts/families/IndieFlower.json"),
        }
    },
    Color = {
        Primary = Color3.fromRGB(255, 255, 255),
        Secondary = Color3.fromRGB(170, 170, 170),
        Background = Color3.fromRGB(0, 0, 0),
        PrimaryButton = Color3.fromRGB(0, 122, 255),
        SecondaryButton = Color3.fromRGB(100, 100, 100),
    },
    Size = {
        Button = UDim2.new(0, 200, 0, 50),
        Title = UDim2.new(1, 0, 0, 100),
    }
}

function UIConfig.getFont(...)
    local args = {...}
    for _, font in ipairs(args) do
        if font then
            return font
        end
    end
    return UIConfig.Font.Default
end

return UIConfig
