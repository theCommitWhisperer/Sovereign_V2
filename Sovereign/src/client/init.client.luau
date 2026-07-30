local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugManager = require(ReplicatedStorage.Shared.DebugManager)
local ClientDebug = DebugManager.createChannel("Client", false) -- Corrected to be off by default

ClientDebug:info("Hello world, from client!")

-- NOTE: UnitAnimator existed but was never required, so no unit has ever been
-- animated. Keep this line — without it units slide instead of walking.
require(script.UnitAnimator)

require(script.Selection.SelectionManager)
require(script.Movement.MovementManager)
require(script.Combat.HealthBarManager)
require(script.Combat.DamageNumberManager)
require(script.Combat.FogOfWarClient)
require(script.Combat.ResourceCarryIndicator)
require(script.Combat.CombatEffectsClient)

-- Hero combat input + feedback (third-person combo/block/parry/dodge). Replaces
-- the old FirstPersonCombat.client.luau, which gated on
-- `player.CameraMode == LockFirstPerson` — a check that is permanently false now
-- that hero view is third person, so it would have refused every swing.
require(script.Combat.HeroCombatController)
