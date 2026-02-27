local pad = script.Parent
local Players = game:GetService("Players")

-- ✅ Change ce chemin selon ton organisation :
local interiorSpawn = workspace:WaitForChild("tour1"):WaitForChild("InterriorSpawn")

local COOLDOWN = 1
local lastTp = {} -- [player] = time

pad.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Lock (vague de lave)
	if pad:GetAttribute("Locked") == true then 
		return 
	end

	-- Anti-spam
	local now = os.clock()
	if lastTp[player] and (now - lastTp[player]) < COOLDOWN then
		return
	end
	lastTp[player] = now

	-- TP propre
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = interiorSpawn.CFrame + Vector3.new(0, 3, 0) -- +3 pour éviter d’être collé au sol
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastTp[player] = nil
end)

local function updateLook()
	if pad:GetAttribute("Locked") then
		pad.BrickColor = BrickColor.new("Really red")
	else
		pad.BrickColor = BrickColor.new("Lime green")
	end
end

pad:GetAttributeChangedSignal("Locked"):Connect(updateLook)
updateLook()
