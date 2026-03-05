-- ============================================================
-- Main.server.lua — BrainRot Radar Hub
-- Script → ServerScriptService
-- Rôle : boot, création RemoteEvents, boucle principale
-- ============================================================

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")

-- ------------------------------------------------------------
-- CRÉATION DES REMOTE EVENTS
-- Tous créés ici au démarrage — jamais dans les modules
-- ------------------------------------------------------------
local function creerRemoteEvents()
    local dossier = ReplicatedStorage:FindFirstChild("RadarEvents")
    if not dossier then
        dossier = Instance.new("Folder")
        dossier.Name = "RadarEvents"
        dossier.Parent = ReplicatedStorage
    end

    local events = {
        "MiseAJourClassement",  -- Serveur → Clients : nouvelles données
        "MiseAJourLeaderboard", -- Serveur → Clients : nouveau top 10
        "Notification",         -- Serveur → Client : toast notification
        "AppliquerAnalystPro",  -- Serveur → Client : débloquer UI pro
        "DemandeVote",          -- Client → Serveur : voter pour un jeu
        "DemandeStats",         -- Client → Serveur : mes stats
        "DemandeLeaderboard",   -- Client → Serveur : top 10
        "DemandeBoostNom",      -- Client → Serveur : nom jeu pour boost
        "DemandeTeleport",      -- Client → Serveur : téléporter (backup)
    }

    for _, nom in ipairs(events) do
        if not dossier:FindFirstChild(nom) then
            local re = Instance.new("RemoteEvent")
            re.Name = nom
            re.Parent = dossier
        end
    end

    -- RemoteFunctions (retour de valeur)
    local functions = {
        "GetStatsJoueur",   -- Client demande ses stats
        "GetLeaderboard",   -- Client demande le top 10
        "GetClassement",    -- Client demande les données radar
    }

    for _, nom in ipairs(functions) do
        if not dossier:FindFirstChild(nom) then
            local rf = Instance.new("RemoteFunction")
            rf.Name = nom
            rf.Parent = dossier
        end
    end

    print("[Main] RemoteEvents créés ✅")
    return dossier
end

-- ------------------------------------------------------------
-- BOOT
-- ------------------------------------------------------------
print("[Main] BrainRot Radar Hub démarrage...")

-- Attendre que ReplicatedStorage/Modules soit prêt
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
if not Modules then
    error("[Main] Dossier ReplicatedStorage/Modules introuvable !")
end

-- Créer les RemoteEvents AVANT de charger les modules
local remotes = creerRemoteEvents()

-- Charger les modules (après création des events)
task.wait(0.1)

local Config              = require(Modules:WaitForChild("Config"))
local DataFetcher         = require(script.Parent:WaitForChild("DataFetcher"))
local VoteManager         = require(script.Parent:WaitForChild("VoteManager"))
local MonetizationHandler = require(script.Parent:WaitForChild("MonetizationHandler"))
local TeleportHandler     = require(script.Parent:WaitForChild("TeleportHandler"))

print("[Main] Modules chargés ✅")

-- Setup portails
TeleportHandler.setupPortails()

-- ------------------------------------------------------------
-- PREMIER FETCH AU DÉMARRAGE
-- ------------------------------------------------------------
local function fetchEtDiffuser()
    local jeux, statut = DataFetcher.fetch()

    if statut == "erreur" then
        warn("[Main] Erreur fetch — données de fallback utilisées")
    end

    if #jeux == 0 then
        warn("[Main] Aucune donnée disponible")
        return
    end

    -- Mettre à jour les portails
    TeleportHandler.mettreAJourPortails(jeux)

    -- Diffuser à tous les clients connectés
    remotes.MiseAJourClassement:FireAllClients(jeux)

    -- Mettre à jour le leaderboard analystes
    local lb = VoteManager.getLeaderboard()
    remotes.MiseAJourLeaderboard:FireAllClients(lb)

    print(string.format("[Main] Classement diffusé — %d jeux ✅", #jeux))
end

-- Fetch initial
fetchEtDiffuser()

-- Boucle de refresh automatique
task.spawn(function()
    while true do
        task.wait(Config.FetchInterval)
        fetchEtDiffuser()
    end
end)

-- ------------------------------------------------------------
-- GESTION DES JOUEURS QUI ARRIVENT EN COURS DE PARTIE
-- ------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
    -- Envoyer les données actuelles au nouveau joueur
    task.wait(2) -- Attendre que le client soit prêt

    local jeux = DataFetcher.getCache()
    if #jeux > 0 then
        remotes.MiseAJourClassement:FireClient(player, jeux)
    end

    -- Appliquer Analyst Pro si déjà acheté
    if MonetizationHandler.aAnalystPro(player) then
        task.wait(1)
        local applyEvent = remotes:FindFirstChild("AppliquerAnalystPro")
        if applyEvent then
            applyEvent:FireClient(player)
        end
    end
end)

-- ------------------------------------------------------------
-- REMOTE EVENTS — CÔTÉ SERVEUR
-- ------------------------------------------------------------

-- Vote
remotes.DemandeVote.OnServerEvent:Connect(function(player, nomJeuVote)
    -- Validation
    if type(nomJeuVote) ~= "string" or #nomJeuVote > 100 then
        return
    end

    local ok, message = VoteManager.voter(player, nomJeuVote)

    remotes.Notification:FireClient(player, {
        type    = ok and "vote" or "erreur",
        message = message,
    })
end)

-- Nom jeu pour boost
remotes.DemandeBoostNom.OnServerEvent:Connect(function(player, nomJeu)
    if type(nomJeu) ~= "string" or #nomJeu > 100 then return end
    MonetizationHandler.setNomJeuBoost(player, nomJeu)
end)

-- Téléportation (backup si portail physique échoue)
remotes.DemandeTeleport.OnServerEvent:Connect(function(player, gameId)
    if type(gameId) ~= "number" then return end
    TeleportHandler.teleporter(player, gameId)
end)

-- ------------------------------------------------------------
-- REMOTE FUNCTIONS — RETOUR DE VALEUR
-- ------------------------------------------------------------

local rfStats = remotes:FindFirstChild("GetStatsJoueur")
if rfStats then
    rfStats.OnServerInvoke = function(player)
        return VoteManager.getStatsJoueur(player.UserId)
    end
end

local rfLB = remotes:FindFirstChild("GetLeaderboard")
if rfLB then
    rfLB.OnServerInvoke = function(_player)
        return VoteManager.getLeaderboard()
    end
end

local rfClassement = remotes:FindFirstChild("GetClassement")
if rfClassement then
    rfClassement.OnServerInvoke = function(_player)
        return DataFetcher.getCache()
    end
end

print("[Main] BrainRot Radar Hub opérationnel 🧠✅")
