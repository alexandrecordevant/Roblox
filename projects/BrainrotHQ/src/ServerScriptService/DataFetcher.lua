-- ============================================================
-- DataFetcher.lua — BrainRot Radar Hub
-- ModuleScript → ServerScriptService
-- Rôle : fetch CSV Google Sheet → parse → calcul Score Radar → cache DataStore
-- ============================================================

local DataFetcher = {}

local HttpService    = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local Config         = require(game.ReplicatedStorage.Modules.Config)

-- Cache en mémoire (évite les appels DataStore inutiles)
local cacheData      = {}
local dernierFetch   = 0

-- DataStore pour persister le cache entre redémarrages serveur
local cacheStore     = DataStoreService:GetDataStore("BrainRotRadar_Cache_v1")
local boostStore     = DataStoreService:GetDataStore(Config.Leaderboard.DataStoreBoosts)

-- ------------------------------------------------------------
-- PARSE CSV
-- Format attendu : Jeu,Joueurs,Joueurs_24h,Likes,Dislikes,GameId
-- Ligne 1 = headers (skippée)
-- ------------------------------------------------------------
local function parseCSV(csvText)
    local jeux = {}
    local lignes = csvText:split("\n")

    for i = 2, #lignes do -- skip header
        local ligne = lignes[i]:gsub("\r", ""):gsub('"', '')
        if ligne ~= "" then
            local cols = ligne:split(",")
            if #cols >= 5 then
                local jeu = {
                    nom        = cols[1] or "?",
                    joueurs    = tonumber(cols[2]) or 0,
                    joueurs24h = tonumber(cols[3]) or 0,
                    likes      = tonumber(cols[4]) or 0,
                    dislikes   = tonumber(cols[5]) or 0,
                    gameId     = tonumber(cols[6]) or 0,
                }
                -- Validation basique
                if jeu.nom ~= "?" and jeu.nom ~= "" then
                    table.insert(jeux, jeu)
                end
            end
        end
    end

    return jeux
end

-- ------------------------------------------------------------
-- CALCUL SCORE RADAR
-- Score = (Variation% × 3) + (LikeRatio × 2)
-- ------------------------------------------------------------
local function calculerScore(jeu)
    local total = jeu.likes + jeu.dislikes
    local likeRatio = total > 0 and (jeu.likes / total) or 0.5

    local variation = jeu.joueurs24h > 0
        and ((jeu.joueurs - jeu.joueurs24h) / jeu.joueurs24h)
        or 0

    local score = (variation * 3) + (likeRatio * 2)
    return math.round(score * 100) / 100, math.round(likeRatio * 100), math.round(variation * 100)
end

-- ------------------------------------------------------------
-- APPLIQUER LES BOOSTS ACTIFS
-- Les devs qui ont acheté "Boost" voient leur score augmenter
-- ------------------------------------------------------------
local function appliquerBoosts(jeux)
    local ok, boostsData = pcall(function()
        return boostStore:GetAsync("active_boosts")
    end)

    if not ok or not boostsData then return jeux end

    local maintenant = os.time()

    for _, jeu in ipairs(jeux) do
        local cleBoost = "boost_" .. jeu.nom:lower():gsub("%s+", "_")
        local boost = boostsData[cleBoost]

        if boost and boost.expireAt > maintenant then
            jeu.score = jeu.score + Config.Produits.Boost.BonusScore
            jeu.boosted = true
        end
    end

    return jeux
end

-- ------------------------------------------------------------
-- DÉTERMINER LE STATUT
-- ------------------------------------------------------------
local function getStatut(score)
    if score >= 2.5 then return "VIRAL", "🚀"
    elseif score >= 1.5 then return "WATCH", "🟡"
    else return "WEAK", "❌"
    end
end

-- ------------------------------------------------------------
-- FETCH PRINCIPAL
-- Appelé par Main.server.lua au démarrage et toutes les X minutes
-- ------------------------------------------------------------
function DataFetcher.fetch()
    local maintenant = os.time()

    -- Vérifier si le cache en mémoire est encore frais
    if maintenant - dernierFetch < Config.FetchInterval and #cacheData > 0 then
        return cacheData, nil
    end

    -- Vérifier si URL configurée
    if Config.SheetCSV_URL == "REMPLACE_PAR_TON_URL_CSV" then
        warn("[DataFetcher] URL Sheet non configurée — utilisation données démo")
        return DataFetcher.getDemoData(), nil
    end

    -- Fetch HTTP
    local ok, result = pcall(function()
        return HttpService:GetAsync(Config.SheetCSV_URL, true)
    end)

    if not ok then
        warn("[DataFetcher] Erreur HTTP :", result)
        -- Retourner le cache DataStore si disponible
        local okDS, cached = pcall(function()
            return cacheStore:GetAsync("last_data")
        end)
        if okDS and cached and #cached > 0 then
            return cached, "cache"
        end
        return DataFetcher.getDemoData(), "erreur"
    end

    -- Parsing
    local jeux = parseCSV(result)

    if #jeux == 0 then
        warn("[DataFetcher] Sheet vide ou mal formaté")
        return cacheData, "vide"
    end

    -- Calcul scores
    for _, jeu in ipairs(jeux) do
        jeu.score, jeu.likeRatio, jeu.variationPct = calculerScore(jeu)
        jeu.statut, jeu.emoji = getStatut(jeu.score)
        jeu.boosted = false
    end

    -- Appliquer boosts
    jeux = appliquerBoosts(jeux)

    -- Trier par score décroissant
    table.sort(jeux, function(a, b) return a.score > b.score end)

    -- Ajouter le rang
    for i, jeu in ipairs(jeux) do
        jeu.rang = i
    end

    -- Mettre à jour cache mémoire
    cacheData = jeux
    dernierFetch = maintenant

    -- Persister dans DataStore (sans bloquer)
    task.spawn(function()
        pcall(function()
            cacheStore:SetAsync("last_data", jeux)
        end)
    end)

    return jeux, nil
end

-- ------------------------------------------------------------
-- GETTER CACHE (sans re-fetch)
-- ------------------------------------------------------------
function DataFetcher.getCache()
    return cacheData
end

-- ------------------------------------------------------------
-- DONNÉES DÉMO (fallback si Sheet non configuré)
-- ------------------------------------------------------------
function DataFetcher.getDemoData()
    local demo = {
        { nom = "Skibidi Obby Impossible", joueurs = 1842, joueurs24h = 1320, likes = 4200, dislikes = 380,  gameId = 0 },
        { nom = "Brainrot Tower Escape",   joueurs = 3210, joueurs24h = 2100, likes = 8900, dislikes = 1200, gameId = 0 },
        { nom = "Sigma Obby Challenge",    joueurs = 590,  joueurs24h = 612,  likes = 1100, dislikes = 280,  gameId = 0 },
        { nom = "Fanum Tax Parkour",       joueurs = 2780, joueurs24h = 1890, likes = 6200, dislikes = 900,  gameId = 0 },
        { nom = "Ohio Rizz Obby",          joueurs = 420,  joueurs24h = 490,  likes = 810,  dislikes = 320,  gameId = 0 },
        { nom = "Italian Brainrot Race",   joueurs = 1120, joueurs24h = 680,  likes = 2900, dislikes = 410,  gameId = 0 },
        { nom = "NPC Obby 100 Levels",     joueurs = 4450, joueurs24h = 3200, likes = 11200, dislikes = 1800, gameId = 0 },
        { nom = "Gyatt Escape Room",       joueurs = 230,  joueurs24h = 260,  likes = 420,  dislikes = 190,  gameId = 0 },
    }

    for i, jeu in ipairs(demo) do
        jeu.score, jeu.likeRatio, jeu.variationPct = calculerScore(jeu)
        jeu.statut, jeu.emoji = getStatut(jeu.score)
        jeu.boosted = false
        jeu.rang = i
    end

    table.sort(demo, function(a, b) return a.score > b.score end)
    for i, jeu in ipairs(demo) do jeu.rang = i end

    return demo
end

-- ------------------------------------------------------------
-- ENREGISTRER UN BOOST (appelé par MonetizationHandler)
-- ------------------------------------------------------------
function DataFetcher.enregistrerBoost(nomJeu, dureHeures)
    local cleBoost = "boost_" .. nomJeu:lower():gsub("%s+", "_")
    local expireAt = os.time() + (dureHeures * 3600)

    pcall(function()
        local boostsData = boostStore:GetAsync("active_boosts") or {}
        boostsData[cleBoost] = { expireAt = expireAt, nom = nomJeu }
        boostStore:SetAsync("active_boosts", boostsData)
    end)

    -- Invalider le cache pour forcer re-calcul
    dernierFetch = 0
end

return DataFetcher
