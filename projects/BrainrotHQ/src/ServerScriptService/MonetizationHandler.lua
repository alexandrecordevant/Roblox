-- ============================================================
-- MonetizationHandler.lua — BrainRot Radar Hub
-- ModuleScript → ServerScriptService
-- Rôle : Game Pass Analyst Pro + Developer Product Boost
-- ProcessReceipt TOUJOURS ici, jamais ailleurs
-- ============================================================

local MonetizationHandler = {}

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local Config             = require(game.ReplicatedStorage.Modules.Config)
local DataFetcher        -- Chargé en lazy pour éviter les dépendances circulaires

-- DataStore pour les achats traités (anti-double-achat)
local receiptStore = DataStoreService:GetDataStore("BrainRotRadar_Receipts_v1")

-- Cache Game Pass en mémoire : { [userId] = bool }
local analyistProCache = {}

-- ------------------------------------------------------------
-- VÉRIFIER GAME PASS ANALYST PRO
-- ------------------------------------------------------------
function MonetizationHandler.aAnalystPro(player)
    local userId = player.UserId

    if analyistProCache[userId] ~= nil then
        return analyistProCache[userId]
    end

    if Config.GamePass.AnalystPro.Id == 0 then
        return false -- non configuré
    end

    local ok, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, Config.GamePass.AnalystPro.Id)
    end)

    local owns = ok and result or false
    analyistProCache[userId] = owns
    return owns
end

-- ------------------------------------------------------------
-- APPLIQUER LES AVANTAGES ANALYST PRO
-- ------------------------------------------------------------
local function appliquerAnalystPro(player)
    analyistProCache[player.UserId] = true

    -- Notifier le client pour débloquer l'UI stats avancées
    local remote = game.ReplicatedStorage:FindFirstChild("RadarEvents")
    if remote then
        local applyEvent = remote:FindFirstChild("AppliquerAnalystPro")
        if applyEvent then
            applyEvent:FireClient(player)
        end
    end
end

-- ------------------------------------------------------------
-- TRAITER UN BOOST (Developer Product)
-- Le joueur spécifie le nom de son jeu via un TextBox dans le shop
-- Stocké en session : { [userId] = nomJeu }
-- ------------------------------------------------------------
local nomJeuBoostSession = {}

function MonetizationHandler.setNomJeuBoost(player, nomJeu)
    nomJeuBoostSession[player.UserId] = nomJeu
end

local function appliquerBoost(player)
    -- Lazy load DataFetcher
    if not DataFetcher then
        DataFetcher = require(script.Parent.DataFetcher)
    end

    local nomJeu = nomJeuBoostSession[player.UserId]

    if not nomJeu or nomJeu == "" then
        -- Notifier l'erreur au client
        local remote = game.ReplicatedStorage:FindFirstChild("RadarEvents")
        if remote then
            local notif = remote:FindFirstChild("Notification")
            if notif then
                notif:FireClient(player, {
                    type    = "erreur",
                    message = "⚠️ Entre le nom de ton jeu avant d'acheter le Boost !",
                })
            end
        end
        return
    end

    -- Enregistrer le boost
    DataFetcher.enregistrerBoost(nomJeu, Config.Produits.Boost.DureeHeures)

    -- Notifier le joueur
    local remote = game.ReplicatedStorage:FindFirstChild("RadarEvents")
    if remote then
        local notif = remote:FindFirstChild("Notification")
        if notif then
            notif:FireClient(player, {
                type    = "boost",
                message = string.format("🚀 '%s' boosté pour %dh ! Score +%.1f",
                    nomJeu,
                    Config.Produits.Boost.DureeHeures,
                    Config.Produits.Boost.BonusScore
                ),
            })
        end
    end

    -- Nettoyer session
    nomJeuBoostSession[player.UserId] = nil
end

-- ------------------------------------------------------------
-- PROCESS RECEIPT — obligatoire pour Developer Products
-- Roblox appelle cette fonction après chaque achat
-- DOIT retourner Enum.ProductPurchaseDecision.PurchaseGranted
-- ou NotProcessedYet en cas d'erreur
-- ------------------------------------------------------------
local function processReceipt(receiptInfo)
    local userId    = receiptInfo.PlayerId
    local productId = receiptInfo.ProductId
    local receiptId = receiptInfo.PurchaseId

    -- Vérifier si déjà traité (anti-double)
    local okCheck, alreadyProcessed = pcall(function()
        return receiptStore:GetAsync(receiptId)
    end)

    if okCheck and alreadyProcessed then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local player = Players:GetPlayerByUserId(userId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Traiter selon le produit
    local success = false

    if productId == Config.Produits.Boost.Id and Config.Produits.Boost.Id ~= 0 then
        local okBoost, err = pcall(appliquerBoost, player)
        success = okBoost
        if not okBoost then
            warn("[MonetizationHandler] Erreur Boost :", err)
        end
    end

    if not success then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Marquer comme traité
    pcall(function()
        receiptStore:SetAsync(receiptId, true)
    end)

    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Assigner le handler — une seule fois au démarrage
MarketplaceService.ProcessReceipt = processReceipt

-- ------------------------------------------------------------
-- GAME PASS PROMPT
-- ------------------------------------------------------------
function MonetizationHandler.promptAnalystPro(player)
    if Config.GamePass.AnalystPro.Id == 0 then
        warn("[MonetizationHandler] Game Pass ID non configuré")
        return
    end
    MarketplaceService:PromptGamePassPurchase(player, Config.GamePass.AnalystPro.Id)
end

function MonetizationHandler.promptBoost(player)
    if Config.Produits.Boost.Id == 0 then
        warn("[MonetizationHandler] Produit Boost ID non configuré")
        return
    end
    MarketplaceService:PromptProductPurchase(player, Config.Produits.Boost.Id)
end

-- ------------------------------------------------------------
-- GAME PASS PURCHASED EVENT
-- Appelé quand un joueur achète un Game Pass dans la session
-- ------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
    if purchased and passId == Config.GamePass.AnalystPro.Id then
        appliquerAnalystPro(player)
    end
end)

-- ------------------------------------------------------------
-- NETTOYAGE SESSION À LA DÉCONNEXION
-- ------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    analyistProCache[player.UserId] = nil
    nomJeuBoostSession[player.UserId] = nil
end)

return MonetizationHandler
