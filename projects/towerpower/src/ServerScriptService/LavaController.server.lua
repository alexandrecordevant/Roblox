local Players = game:GetService("Players")

local tower = workspace:WaitForChild("tour1")
local lava = tower:WaitForChild("Lava")
local startZone = tower:WaitForChild("Triggers"):WaitForChild("StartZone")
local entrancePad = workspace:WaitForChild("tour1"):WaitForChild("Triggers"):WaitForChild("StartZone")

-- ⚙️ Réglages
local START_DELAY = 5
local MAX_HEIGHT = 550
local BASE_SPEED = 0.3        -- vitesse de départ
local ACCELERATION = 0.003     -- accélération par tick
local TICK = 0.04

local running = false
local resetting = false
local startY = lava.Position.Y

-- Vérifie s'il reste un joueur vivant dans la tour
local function playersAliveInTower()
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			if player.Character.Humanoid.Health > 0 then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp.Position.Y > startY then
					return true
				end
			end
		end
	end
	return false
end

local function resetLava()
	if resetting then return end
	resetting = true

	running = false

	lava.Position = Vector3.new(lava.Position.X, startY, lava.Position.Z)
	lava.Transparency = 1
	entrancePad:SetAttribute("Locked", false)

	task.wait(1) -- petite pause sécurité

	resetting = false
end

local function startLava()
	if running or resetting then return end
	running = true

	entrancePad:SetAttribute("Locked", true)

	task.wait(START_DELAY)

	if not playersAliveInTower() then
		resetLava()
		return
	end

	lava.Transparency = 0

	local currentSpeed = BASE_SPEED

	while running and lava.Position.Y < startY + MAX_HEIGHT do
		task.wait(TICK)

		lava.Position += Vector3.new(0, currentSpeed, 0)

		-- 🔥 Accélération progressive
		currentSpeed += ACCELERATION

		if not playersAliveInTower() then
			break
		end
	end

	resetLava()
end

startZone.Touched:Connect(function(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player then
		startLava()
	end
end)

lava.Touched:Connect(function(hit)
	local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end)