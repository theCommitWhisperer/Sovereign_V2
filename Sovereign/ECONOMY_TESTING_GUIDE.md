# Economy Testing Guide

## Setup Instructions

### 1. Add Your User ID to Admin List

Open [TestCommandManager.luau](src/server/Managers/TestCommandManager.luau) and add your Roblox User ID to the `ADMIN_USER_IDS` table:

```lua
local ADMIN_USER_IDS = {
    -- Add your user ID here to use test commands
    8820940408,  -- Replace with YOUR Roblox User ID
}
```

**To find your Roblox User ID:**
1. Go to your Roblox profile page
2. Look at the URL - it will be: `https://www.roblox.com/users/YOUR_ID_HERE/profile`
3. Copy that number

### 2. Create Client Command Input (Optional)

To send commands from the game, you'll need a simple TextBox in your UI. Add this to your HUD:

```lua
-- In your client-side UI code
local RemoteEvents = game.ReplicatedStorage:WaitForChild("RemoteEvents")
local GameEvent = RemoteEvents:WaitForChild("GameEvent")

local function sendCommand(commandText: string)
    if commandText:sub(1, 1) == "/" then
        GameEvent:FireServer("TestCommand", commandText:sub(2)) -- Remove leading /
    end
end

-- Connect to a TextBox's FocusLost event
yourTextBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        sendCommand(yourTextBox.Text)
        yourTextBox.Text = ""
    end
end)
```

## Available Test Commands

### Resource Management
- `/addres [resource] [amount]` - Add resources to your inventory
  - Example: `/addres Food 500`
  - Example: `/addres Gold 100`
  - Resources: Wood, Stone, Gold, Food, Iron_Ore, Iron_Bars, Weapons, Bread, Ale

### Season & Weather Control
- `/season [Spring|Summer|Autumn|Winter]` - Change the current season
  - Example: `/season Winter`

- `/weather [Clear|Rain|Drought|Storm]` - Change the current weather
  - Example: `/weather Storm`

- `/skiptime` - Advance to next season and change weather

### Population & Units
- `/spawn [count]` - Spawn peasants near your Keep
  - Example: `/spawn 10`
  - Default: 5 peasants if no count specified

### Economy Testing
- `/econinfo` - Display comprehensive economy snapshot
  - Shows: Economy Status, Population, Food Consumption, Season, Weather, Happiness

- `/tax [0-100]` - Set tax rate percentage
  - Example: `/tax 50` (sets 50% tax rate)
  - Range: 0-100

### Trade & Caravans
- `/caravan [route 1-5]` - Send a test caravan on a trade route
  - Example: `/caravan 3`
  - Routes:
    1. Dublin (60s, safe)
    2. Cork (90s, moderate)
    3. Galway (100s, moderate)
    4. Limerick (120s, risky)
    5. Waterford (70s, safe)

### Events
- `/event` - Trigger a random economic event
  - Events include: Crop Failure, Bandit Raid, Plague, Fire, Merchant Visit, Bumper Harvest, Rich Ore Vein, Wandering Peasants, Festival

### Notifications
- `/testnotify` - Test all notification types (Info, Success, Warning, Alert, Critical)

### Help
- `/help` - Show all available commands

## Testing Scenarios

### Scenario 1: Test Starvation System
1. Start game with `/addres Food 50`
2. Spawn population: `/spawn 20`
3. Wait 30 seconds - food consumption will occur
4. Monitor notifications for starvation warnings
5. Check economy: `/econinfo`
6. Add food to recover: `/addres Food 200`

### Scenario 2: Test Seasonal Effects
1. Build several Farms
2. Set season to Summer: `/season Summer`
3. Check `/econinfo` - note farm production bonus (1.3x)
4. Set season to Winter: `/season Winter`
5. Check `/econinfo` - note reduced production (0.5x) and happiness penalty

### Scenario 3: Test Tax & Happiness
1. Check baseline happiness: `/econinfo`
2. Set high tax: `/tax 80`
3. Wait a few seconds, check happiness again: `/econinfo`
4. Add luxury goods: `/addres Ale 100` and `/addres Bread 100`
5. Check happiness boost: `/econinfo`

### Scenario 4: Test Maintenance System
1. Build several production buildings (Farms, Mines, etc.)
2. Remove all gold: `/addres Gold -1000` (this won't work - add negative carefully!)
3. Wait 60 seconds for maintenance cycle
4. Buildings will fall into disrepair
5. Production will be penalized
6. Add gold and wait for next cycle to restore

### Scenario 5: Test Trade System
1. Add starting resources: `/addres Food 200` `/addres Ale 100`
2. Build a Market
3. Build a Trading Post
4. Check economy: `/econinfo` for trade prices
5. Send caravan: `/caravan 3` (Galway route)
6. Wait for caravan to complete
7. Check resources after trade

### Scenario 6: Test Weather Impact
1. Build Mines (for testing)
2. Set Clear weather: `/weather Clear`
3. Note production rates
4. Set Storm: `/weather Storm`
5. Mining production reduced by 30%
6. Check with `/econinfo`

### Scenario 7: Test Random Events
1. Trigger event: `/event`
2. Read notification for event type
3. Check resource changes
4. Try multiple times to see different events

### Scenario 8: Test Victory/Loss Conditions
1. Win condition - Gold: `/addres Gold 1000`
2. System should detect victory within 10 seconds
3. Win condition - Weapons: `/addres Weapons 100` `/addres Iron_Bars 100`
4. Loss condition - Starvation: Remove all food and wait 5 minutes

## System Update Intervals

Understanding the timing helps with testing:

- **Food Consumption**: Every 30 seconds
- **Maintenance Payments**: Every 60 seconds
- **Population Growth**: Every 10 seconds (if conditions met)
- **Dashboard Updates**: Every 5 seconds
- **Season Changes**: Every 180 seconds (3 minutes)
- **Weather Changes**: 60-120 seconds (1-2 minutes)
- **Trade Price Updates**: Every 30 seconds
- **Caravan Progress**: Every 5 seconds
- **Event Checks**: Every 45 seconds
- **Victory/Loss Checks**: Every 10 seconds
- **Random Events**: 8-20% chance every 45 seconds

## Monitoring Tips

1. **Watch the Output Console** - All systems log to DebugManager channels
2. **Check Notifications** - Critical issues trigger alerts
3. **Use /econinfo frequently** - Best way to monitor economy health
4. **Test edge cases** - Zero resources, maximum population, etc.
5. **Combine systems** - Test starvation + winter + high taxes for worst case

## Common Issues

**Commands not working?**
- Make sure your User ID is in `ADMIN_USER_IDS`
- Check that TestCommandManager.init() is called in GameManager
- Verify the RemoteEvent listener is set up correctly

**Systems not updating?**
- All systems initialize automatically when game starts
- Check server output for initialization messages
- Systems only run for players with `GameState == "InGame"`

**Numbers seem off?**
- Remember modifiers multiply: season × weather × happiness × maintenance
- Check all active modifiers with `/econinfo`
- Some effects have minimum values (e.g., 50% max production penalty)

## Advanced Testing

### Test Production Chains
1. Build Iron_Mine, add workers
2. Wait for Iron_Ore production
3. Build Smithy with Iron_Ore
4. Check Iron_Bars production
5. Build Weaponsmith with Iron_Bars
6. Check Weapons production

### Test Combined Systems
1. Set Winter + Storm: `/season Winter` `/weather Storm`
2. Set high taxes: `/tax 70`
3. Spawn large population: `/spawn 30`
4. Remove food: Start with low food
5. Monitor the cascade of negative effects
6. Use `/econinfo` to see economy health drop

### Stress Test
1. Spawn maximum peasants: `/spawn 50`
2. Build 20+ production buildings
3. Send multiple caravans
4. Trigger events repeatedly
5. Monitor server performance and economy calculations

## Victory Conditions to Test

Test each win condition:
1. **Economic Prosperity**: `/addres Gold 1000`
2. **Population Victory**: Spawn and house 50+ peasants
3. **Trade Dominance**: Send 20 successful caravans (takes time!)
4. **Resource Abundance**: `/addres Food 300` `/addres Wood 200` (500+ total resources)
5. **Military-Industrial Complex**: `/addres Weapons 100` `/addres Iron_Bars 100`

## Notes

- All commands require admin privileges (User ID in ADMIN_USER_IDS)
- Commands are processed server-side for security
- Most systems have debug logging enabled by default
- You can adjust update intervals in the respective System files
- Balance numbers in Manager files if systems feel too harsh/easy

Happy Testing! 🎮
