-- ============================================================
-- VoteManager.lua — BrainRot Radar Hub
-- ModuleScript → ServerScriptService
-- Rôle : votes joueurs, prédictions, points, leaderboard analystes
-- ============================================================

local VoteManager = {}

local DataStoreService = game:GetService("DataStoreService")
local BadgeService     = game:GetService("BadgeService")
local Players          = game:GetService("Players")
local Config           = require(game.ReplicatedStorage.Modules.Config)

local lbStore    = DataStoreService:GetOrderedDataStore(Config.Leaderboard.DataStoreName)
local votesStore = DataStoreService:GetDataStore(Config.Leaderboard.DataStoreVotes)

-- Cache des votes en cours (mémoire serveur)
-- Structure : { [userId] = { voteNom = string, timestamp = number, streak = number } }
local votesSession = {}

-- Cache leaderboard
local leaderboardCache = {}
local derniereLBUpdate = 0
local LB_CACHE_TTL = 60 -- secondes

-- ------------------------------------------------------------
-- CHARGER LES DONNÉES D'UN JOUEUR
-- ------------------------------------------------------------
local function chargerJoueur(userId)
    local ok, data = pcall(function()
        return votesStore:GetAsync("player_" .. userId)
    end)

    if ok and data then
        return data
    end

    -- Données par défaut
    return {
        points       = 0,
        totalVotes   = 0,
        bonnesPredictions = 0,
        streak       = 0,
        dernierVote  = 0,
        historiqueVotes = {},
    }
end

-- ------------------------------------------------------------
-- SAUVEGARDER LES DONNÉES D'UN JOUEUR
-- ------------------------------------------------------------
local function sauvegarderJoueur(userId, data)
    pcall(function()
        votesStore:SetAsync("player_" .. userId, data)
    end)

    -- Mettre à jour le leaderboard ordonné
    pcall(function()
        lbStore:SetAsync(tostring(userId), data.points)
    end)
end

-- ------------------------------------------------------------
-- VOTE D'UN JOUEUR
-- Le joueur prédit quel jeu sera #1 la semaine prochaine
-- ------------------------------------------------------------
function VoteManager.voter(player, nomJeuVote)
    local userId = player.UserId
    local maintenant = os.time()

    -- Charger données joueur
    local data = chargerJoueur(userId)

    -- Vérifier cooldown
    local tempsDepuisDernierVote = maintenant - (data.dernierVote or 0)
    if tempsDepuisDernierVote < Config.Vote.CooldownVote then
        local resteSecondes = Config.Vote.CooldownVote - tempsDepuisDernierVote
        return false, string.format("Attends encore %ds avant de revoter !", resteSecondes)
    end

    -- Enregistrer le vote
    data.dernierVote = maintenant
    data.totalVotes = (data.totalVotes or 0) + 1

    -- Stocker le vote actif (sera évalué à la fin du round)
    local voteActif = {
        nom       = nomJeuVote,
        timestamp = maintenant,
        roundId   = math.floor(maintenant / (Config.Vote.DureeRoundHeures * 3600)),
    }

    data.voteActif = voteActif

    -- Premier vote → badge
    if data.totalVotes == 1 and Config.Badges.PremierVote ~= 0 then
        task.spawn(function()
            pcall(function()
                BadgeService:AwardBadge(userId, Config.Badges.PremierVote)
            end)
        end)
    end

    -- Session cache
    votesSession[userId] = {
        nomJeu    = nomJeuVote,
        timestamp = maintenant,
    }

    -- Sauvegarder
    sauvegarderJoueur(userId, data)

    return true, string.format("Vote enregistré pour '%s' ! 🗳️", nomJeuVote)
end

-- ------------------------------------------------------------
-- ÉVALUER LES VOTES (appelé par Main en fin de round)
-- Compare les prédictions avec le vrai #1 du classement
-- ------------------------------------------------------------
function VoteManager.evaluerRound(nomJeuGagnant)
    local roundId = math.floor(os.time() / (Config.Vote.DureeRoundHeures * 3600)) - 1

    -- Lire tous les votes sauvegardés
    -- (en production : utiliser un DataStore dédié par round)
    for _, player in ipairs(Players:GetPlayers()) do
        local userId = player.UserId
        local data = chargerJoueur(userId)

        if data.voteActif and data.voteActif.roundId == roundId then
            local bonneReponse = data.voteActif.nom == nomJeuGagnant

            if bonneReponse then
                data.streak = (data.streak or 0) + 1
                data.bonnesPredictions = (data.bonnesPredictions or 0) + 1

                -- Points de base
                local points = Config.Vote.PointsBonnePrediction

                -- Bonus streak (toutes les 3 bonnes réponses consécutives)
                if data.streak % 3 == 0 then
                    points = points + Config.Vote.BonusStreak
                end

                data.points = (data.points or 0) + points

                -- Badge Prophète (5 bonnes prédictions)
                if data.bonnesPredictions >= 5 and Config.Badges.Prophete ~= 0 then
                    task.spawn(function()
                        pcall(function()
                            BadgeService:AwardBadge(userId, Config.Badges.Prophete)
                        end)
                    end)
                end

                -- Notifier le joueur
                local remote = game.ReplicatedStorage:FindFirstChild("RadarEvents")
                if remote then
                    local notif = remote:FindFirstChild("Notification")
                    if notif then
                        notif:FireClient(player, {
                            type    = "bonnePrediction",
                            message = string.format("+%d points ! '%s' était bien #1 🎯", points, nomJeuGagnant),
                            points  = data.points,
                        })
                    end
                end
            else
                -- Mauvaise prédiction → reset streak
                data.streak = 0
            end

            -- Archiver le vote
            table.insert(data.historiqueVotes or {}, {
                roundId   = roundId,
                vote      = data.voteActif.nom,
                gagnant   = nomJeuGagnant,
                correct   = bonneReponse,
            })

            -- Nettoyer le vote actif
            data.voteActif = nil

            sauvegarderJoueur(userId, data)
        end
    end
end

-- ------------------------------------------------------------
-- OBTENIR LE LEADERBOARD TOP 10
-- ------------------------------------------------------------
function VoteManager.getLeaderboard()
    local maintenant = os.time()

    -- Retourner cache si frais
    if maintenant - derniereLBUpdate < LB_CACHE_TTL and #leaderboardCache > 0 then
        return leaderboardCache
    end

    local ok, pages = pcall(function()
        return lbStore:GetSortedAsync(false, 10)
    end)

    if not ok then
        return leaderboardCache -- retourner ancien cache
    end

    local items = {}
    local okPage, page = pcall(function()
        return pages:GetCurrentPage()
    end)

    if okPage and page then
        for rang, entry in ipairs(page) do
            local userId = tonumber(entry.key)
            local nomJoueur = "???"

            -- Essayer de résoudre le nom
            local okNom, nom = pcall(function()
                return Players:GetNameFromUserIdAsync(userId)
            end)
            if okNom then nomJoueur = nom end

            table.insert(items, {
                rang    = rang,
                userId  = userId,
                nom     = nomJoueur,
                points  = entry.value,
            })
        end
    end

    leaderboardCache = items
    derniereLBUpdate = maintenant

    return items
end

-- ------------------------------------------------------------
-- OBTENIR LES STATS D'UN JOUEUR
-- ------------------------------------------------------------
function VoteManager.getStatsJoueur(userId)
    local data = chargerJoueur(userId)
    return {
        points            = data.points or 0,
        totalVotes        = data.totalVotes or 0,
        bonnesPredictions = data.bonnesPredictions or 0,
        streak            = data.streak or 0,
        voteActif         = data.voteActif,
        winRate           = data.totalVotes > 0
            and math.round((data.bonnesPredictions / data.totalVotes) * 100)
            or 0,
    }
end

-- ------------------------------------------------------------
-- VÉRIFIER SI UN JOUEUR A DÉJÀ VOTÉ CE ROUND
-- ------------------------------------------------------------
function VoteManager.aVoteRound(userId)
    local roundId = math.floor(os.time() / (Config.Vote.DureeRoundHeures * 3600))
    local data = chargerJoueur(userId)
    return data.voteActif and data.voteActif.roundId == roundId
end

return VoteManager
