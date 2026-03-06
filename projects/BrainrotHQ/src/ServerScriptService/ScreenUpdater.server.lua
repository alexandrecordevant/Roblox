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

    -- Utilitaire : reconstruire entièrement le billboard d'un portail
    local function rebuilderBillboard(bb, texte, couleurTexte)
        -- Taille et position
        bb.Size         = UDim2.new(5, 0, 3, 0)
        bb.StudsOffset  = Vector3.new(0, 12, 0)

        -- Supprimer les anciens enfants (Rang, Title, Score, Info, fond)
        for _, enfant in ipairs(bb:GetChildren()) do
            enfant:Destroy()
        end

        -- Fond semi-transparent arrondi
        local fond = Instance.new("Frame")
        fond.Size                  = UDim2.new(1, 0, 1, 0)
        fond.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
        fond.BackgroundTransparency = 0.4
        fond.BorderSizePixel       = 0
        fond.Parent                = bb

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.15, 0)
        corner.Parent       = fond

        -- TextLabel unique
        local txt = Instance.new("TextLabel")
        txt.Name                 = "Info"
        txt.Size                 = UDim2.new(1, -8, 1, -8)
        txt.Position             = UDim2.new(0, 4, 0, 4)
        txt.BackgroundTransparency = 1
        txt.Text                 = texte
        txt.TextColor3           = couleurTexte
        txt.Font                 = Enum.Font.GothamBold
        txt.TextScaled           = true
        txt.TextXAlignment       = Enum.TextXAlignment.Center
        txt.Parent               = fond
    end

    local COULEUR_NORMAL = Color3.fromRGB(0, 245, 160)   -- vert
    local COULEUR_VIP    = Color3.fromRGB(255, 214, 10)  -- doré

    -- Mettre à jour les billboards des portails normaux
    local portalsFolder = workspace:FindFirstChild("Portals")
    if portalsFolder then
        for i = 1, 8 do
            local portal = portalsFolder:FindFirstChild("Portal_"..i)
            if portal then
                local bb = portal:FindFirstChildOfClass("BillboardGui")
                if bb then
                    rebuilderBillboard(bb, DataFetcher.formaterPortail(i), COULEUR_NORMAL)
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
                    rebuilderBillboard(bb, DataFetcher.formaterPortail(i), COULEUR_VIP)
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
