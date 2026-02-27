local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local BASE = workspace:WaitForChild("Base")
local FLOOR_TEMPLATE = ServerStorage:WaitForChild("FloorTemplate") -- Model

-- ---------- Réglages ----------
local FLOOR_HEIGHT = 22            -- hauteur entre étages (ajuste si besoin)
local BASE_FLOOR_COST = 100        -- coût étage 5, etc
local COST_MULT = 1.35             -- inflation du coût
local MAX_FLOORS = 50
local COLLECT_COOLDOWN = 0.25
local BUY_COOLDOWN = 0.25

-- ---------- Utils ----------
local function getCash(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Cash")
end

local function isFloorModel(m)
	return m:IsA("Model") and string.match(m.Name, "^Floor")
end

local function getExistingFloors()
	local floors = {}
	for _, child in ipairs(BASE:GetChildren()) do
		if isFloorModel(child) then
			table.insert(floors, child)
		end
	end
	table.sort(floors, function(a,b)
		local ai = tonumber((a.Name:gsub("%D",""))) or 0
		local bi = tonumber((b.Name:gsub("%D",""))) or 0
		return ai < bi
	end)
	return floors
end

local function nextFloorIndex()
	local floors = getExistingFloors()
	local last = floors[#floors]
	if not last then return 1 end
	local idx = tonumber((last.Name:gsub("%D",""))) or #floors
	return idx + 1
end

local function getReferenceCFrame()
	-- On se base sur "Floor  1" si présent, sinon un BasePart quelconque
	local floors = getExistingFloors()
	for _, f in ipairs(floors) do
		if f.Name:find("1") then
			-- cherche un Part interne pour positionner
			local p = f:FindFirstChildWhichIsA("BasePart", true)
			if p then return p.CFrame end
		end
	end
	local anyPart = BASE:FindFirstChildWhichIsA("BasePart", true)
	assert(anyPart, "Impossible de trouver une BasePart dans Base")
	return anyPart.CFrame
end

local function pivotModel(model, cf)
	if model.PrimaryPart then
		model:PivotTo(cf)
	else
		-- essaye de définir une PrimaryPart automatiquement
		local p = model:FindFirstChildWhichIsA("BasePart", true)
		assert(p, "Model sans BasePart: "..model:GetFullName())
		model.PrimaryPart = p
		model:PivotTo(cf)
	end
end

-- ---------- Ajout étage ----------
local function computeCost(floorIndex)
	-- ex: Floor 5 coûte BASE_FLOOR_COST * (COST_MULT^(floorIndex-1))
	return math.floor(BASE_FLOOR_COST * (COST_MULT ^ math.max(0, floorIndex - 1)))
end

local function addNewFloor()
	local idx = nextFloorIndex()
	if idx > MAX_FLOORS then return nil end

	local ref = getReferenceCFrame()
	local newFloor = FLOOR_TEMPLATE:Clone()
	newFloor.Name = "Floor " .. tostring(idx)

	-- Position: au-dessus de la référence (Floor 1)
	local target = ref * CFrame.new(0, FLOOR_HEIGHT * (idx - 1), 0)
	newFloor.Parent = BASE
	pivotModel(newFloor, target)

	return newFloor
end

-- ---------- Détection brainrot sur spot ----------
local function findBrainrotOnSpot(spotModel)
	-- spotModel = Workspace.Base.Floor X.spot (Model)
	-- On cherche un descendant qui est brainrot
	for _, d in ipairs(spotModel:GetDescendants()) do
		if CollectionService:HasTag(d, "Brainrot") or d:GetAttribute("IsBrainrot") == true then
			local v = d:GetAttribute("Value")
			if typeof(v) == "number" and v > 0 then
				return d, v
			end
		end
	end
	return nil, nil
end

-- ---------- Bind: boutons et collecte ----------
local buyDebounce = {}
local collectDebounce = {}

local function bindFloor(floorModel)
	-- 1) Bouton d'achat (si présent)
	-- Chemin: Floor X.spot.Button.TouchPart
	for _, spot in ipairs(floorModel:GetChildren()) do
		if spot:IsA("Model") and spot.Name == "spot" then
			local button = spot:FindFirstChild("Button")
			local touchBuy = button and button:FindFirstChild("TouchPart")
			local touchCollect = spot:FindFirstChild("TouchPart")

			-- Achat étage
			if touchBuy and touchBuy:IsA("BasePart") then
				touchBuy.Touched:Connect(function(hit)
					local player = Players:GetPlayerFromCharacter(hit.Parent)
					if not player then return end
					if buyDebounce[player] then return end
					buyDebounce[player] = true

					local cash = getCash(player)
					if not cash then buyDebounce[player] = nil return end

					local idx = nextFloorIndex()
					local cost = computeCost(idx)

					if idx <= MAX_FLOORS and cash.Value >= cost then
						cash.Value -= cost
						addNewFloor()
					end

					task.delay(BUY_COOLDOWN, function()
						buyDebounce[player] = nil
					end)
				end)
			end

			-- 2) Collecte sur le spot (si présent)
			-- Chemin: Floor X.spot.TouchPart (ça ressemble à ta "plateforme verte")
			if touchCollect and touchCollect:IsA("BasePart") then
				touchCollect.Touched:Connect(function(hit)
					local player = Players:GetPlayerFromCharacter(hit.Parent)
					if not player then return end

					collectDebounce[player] = collectDebounce[player] or {}
					if collectDebounce[player][touchCollect] then return end
					collectDebounce[player][touchCollect] = true

					local cash = getCash(player)
					if not cash then
						collectDebounce[player][touchCollect] = nil
						return
					end

					local brainrot, value = findBrainrotOnSpot(spot)
					if brainrot and value then
						cash.Value += math.floor(value)
						-- Consomme le brainrot
						brainrot:Destroy()
					end

					task.delay(COLLECT_COOLDOWN, function()
						collectDebounce[player][touchCollect] = nil
					end)
				end)
			end
		end
	end
end

-- Bind existants
for _, floor in ipairs(getExistingFloors()) do
	bindFloor(floor)
end

-- Bind nouveaux étages ajoutés
BASE.ChildAdded:Connect(function(child)
	if isFloorModel(child) then
		task.defer(function()
			bindFloor(child)
		end)
	end
end)