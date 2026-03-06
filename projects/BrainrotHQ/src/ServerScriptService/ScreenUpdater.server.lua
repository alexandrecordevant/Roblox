-- ============================================================
-- ScreenUpdater.lua — BrainRot HQ
-- Branche DataFetcher aux SurfaceGui des écrans physiques
-- Script → ServerScriptService
-- ============================================================

local DataFetcher = require(script.Parent.DataFetcher)

-- ------------------------------------------------------------
-- RÉFÉRENCES ÉCRANS
-- ------------------------------------------------------------
local areneFolder = workspace:WaitForChild("ArenaHQ", 10)
local boardFolder = areneFolder and areneFolder:WaitForChild("BoardCentral", 10)

if not boardFolder then
    warn("[ScreenUpdater] BoardCentral introuvable")
    return
end

local boardNormal = boardFolder:WaitForChild("Board_Normal", 10)
local boardVIP    = boardFolder:WaitForChild("Board_VIP", 10)

-- Récupérer les TextLabel Contenu dans chaque SurfaceGui
local function getContenu(board, face)
    local sg = board and board:FindFirstChildOfClass("SurfaceGui")
    if not sg then return nil end
    return sg:FindFirstChild("Contenu")
end

local contenuNormal = getContenu(boardNormal, "Back")
local contenuVIP    = getContenu(boardVIP, "Front")

-- ------------------------------------------------------------
-- MISE À JOUR DES ÉCRANS
-- ------------------------------------------------------------
local function mettreAJourEcrans()
    -- Board Normal → classement top 8
    if contenuNormal then
        local ok, texte = pcall(function()
            return DataFetcher.formaterClassement(8)
        end)
        if ok and texte then
            contenuNormal.Text = texte
        else
            contenuNormal.Text = "⚠️ Données indisponibles"
        end
    end

    -- Board VIP → stats détaillées #1
    if contenuVIP then
        local ok, texte = pcall(function()
            return DataFetcher.formaterStatsVIP()
        end)
        if ok and texte then
            contenuVIP.Text = texte
        else
            contenuVIP.Text = "⚠️ Données indisponibles"
        end
    end

    -- Utilitaire : récupère ou crée un TextLabel "Info" dans un BillboardGui
    local function getOrCreateInfo(bb)
        local info = bb:FindFirstChild("Info")
        if not info then
            info = Instance.new("TextLabel")
            info.Name                = "Info"
            info.Size                = UDim2.new(1, 0, 1, 0)
            info.BackgroundTransparency = 1
            info.TextScaled          = true
            info.Font                = Enum.Font.GothamBold
            info.TextColor3          = Color3.new(1, 1, 1)
            info.TextXAlignment      = Enum.TextXAlignment.Center
            info.Parent              = bb
        end
        return info
    end

    -- Mettre à jour les billboards des portails normaux
    local portalsFolder = workspace:FindFirstChild("Portals")
    if portalsFolder then
        for i = 1, 8 do
            local portal = portalsFolder:FindFirstChild("Portal_"..i)
            if portal then
                local bb = portal:FindFirstChildOfClass("BillboardGui")
                if bb then
                    local info = getOrCreateInfo(bb)
                    info.Text = DataFetcher.formaterPortail(i)
                end
            end
        end
    end

    -- Mettre à jour les billboards des portails VIP
    local vipFolder  = areneFolder:FindFirstChild("ZoneVIP")
    local vipPortals = vipFolder and vipFolder:FindFirstChild("PortailsVIP")
    if vipPortals then
        for i = 1, 8 do
            local portal = vipPortals:FindFirstChild("PortalVIP_"..i)
            if portal then
                local bb = portal:FindFirstChildOfClass("BillboardGui")
                if bb then
                    local info = getOrCreateInfo(bb)
                    info.Text = DataFetcher.formaterPortail(i)
                end
            end
        end
    end

    print("[ScreenUpdater] ✅ Écrans mis à jour")
end

-- ------------------------------------------------------------
-- DÉMARRAGE + LOOP
-- ------------------------------------------------------------
task.spawn(function()
    task.wait(5)  -- laisser DataFetcher faire son premier fetch
    mettreAJourEcrans()

    while true do
        task.wait(300)  -- toutes les 5 minutes
        mettreAJourEcrans()
    end
end)

-- Écouter les mises à jour forcées depuis DataFetcher
local remotes = game.ReplicatedStorage:WaitForChild("RadarEvents", 10)
if remotes then
    local dataUpdate = remotes:FindFirstChild("DataUpdate")
    if dataUpdate then
        -- DataUpdate est FireAllClients (client) — côté serveur on écoute via OnServerEvent si besoin
        -- Ici on re-fetch directement depuis le cache déjà mis à jour
        task.spawn(function()
            while true do
                task.wait(300)
                mettreAJourEcrans()
            end
        end)
    end
end

print("[ScreenUpdater] ✅ Initialisé")
