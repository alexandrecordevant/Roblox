-- ============================================================
-- DataFetcher.lua — BrainRot HQ v2
-- API Roblox native — zéro Google Sheet, 100% automatique
-- ModuleScript → ServerScriptService
-- ============================================================

local HttpService = game:GetService("HttpService")
local Config = require(game.ReplicatedStorage.Modules.Config)

local DataFetcher = {}

-- ------------------------------------------------------------
-- LISTE DES JEUX À TRACKER
-- Seule chose à mettre à jour manuellement (1x/mois max)
-- UniverseId ≠ PlaceId — trouver sur roblox.com/games/PLACEID
-- Clic droit sur un jeu → "Copy Universe ID" dans Studio
-- ------------------------------------------------------------
local JEUX_TRACKED = {
    { universeId = 3233893879, nom = "Skibidi Obby" },
    { universeId = 4922741943, nom = "Fanum Tax Obby" },
    { universeId = 5094069760, nom = "Sigma Obby" },
    { universeId = 4372543374, nom = "Brain Rot Run" },
    { universeId = 3260590327, nom = "Toilet Tower Defense" },
    { universeId = 4924922148, nom = "Rizz Obby" },
    { universeId = 5108494873, nom = "Gyatt Obby" },
    { universeId = 4490140733, nom = "Grimace Shake Obby" },
    { universeId = 4482558690, nom = "Phonk Obby" },
    { universeId = 3698890740, nom = "UNO" },
    { universeId = 4372543374, nom = "Mewing Obby" },
    { universeId = 3260590327, nom = "Ohio Rizz Obby" },
}

-- ------------------------------------------------------------
-- CACHE
-- ------------------------------------------------------------
local cache          = {}
local cacheTimestamp = 0
local CACHE_TTL      = 300  -- 5 minutes

-- ------------------------------------------------------------
-- FETCH JOUEURS ACTIFS + INFOS
-- GET https://games.roblox.com/v1/games?universeIds=X,Y,Z
-- ------------------------------------------------------------
local function fetchJoueursActifs(universeIds)
    local url = "https://games.roblox.com/v1/games?universeIds=" .. table.concat(universeIds, ",")
    local ok, response = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok then
        warn("[DataFetcher] Erreur fetch joueurs : " .. tostring(response))
        return {}
    end
    local okJson, data = pcall(function() return HttpService:JSONDecode(response) end)
    if not okJson or not data or not data.data then return {} end

    local result = {}
    for _, jeu in ipairs(data.data) do
        result[tostring(jeu.id)] = {
            joueurs     = jeu.playing or 0,
            visites     = jeu.visits or 0,
            rootPlaceId = jeu.rootPlaceId or 0,
        }
    end
    return result
end

-- ------------------------------------------------------------
-- FETCH VOTES
-- GET https://games.roblox.com/v1/games/votes?universeIds=X,Y,Z
-- ------------------------------------------------------------
local function fetchVotes(universeIds)
    local url = "https://games.roblox.com/v1/games/votes?universeIds=" .. table.concat(universeIds, ",")
    local ok, response = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok then return {} end
    local okJson, data = pcall(function() return HttpService:JSONDecode(response) end)
    if not okJson or not data or not data.data then return {} end

    local result = {}
    for _, vote in ipairs(data.data) do
        result[tostring(vote.id)] = {
            upVotes   = vote.upVotes or 0,
            downVotes = vote.downVotes or 0,
        }
    end
    return result
end

-- ------------------------------------------------------------
-- CALCUL SCORE RADAR
-- Score sur 10 :
--   Joueurs actifs  → 5 pts max  (saturé à 1000 joueurs)
--   Like ratio      → 3 pts max
--   Visites totales → 2 pts max  (saturé à 1M visites)
-- ------------------------------------------------------------
local function calculerScore(joueurs, upVotes, downVotes, visites)
    local scoreJoueurs = math.min(joueurs / 1000, 1) * 5
    local totalVotes   = upVotes + downVotes
    local likeRatio    = totalVotes > 0 and (upVotes / totalVotes) or 0.5
    local scoreLikes   = likeRatio * 3
    local scoreVisites = math.min(visites / 1000000, 1) * 2
    return math.floor((scoreJoueurs + scoreLikes + scoreVisites) * 100) / 100
end

local function getStatut(score)
    if score >= 7 then return "🔥 VIRAL"
    elseif score >= 5 then return "📈 HOT"
    elseif score >= 3 then return "➡️ STABLE"
    else return "📉 WEAK" end
end

-- ------------------------------------------------------------
-- FETCH COMPLET
-- ------------------------------------------------------------
local function fetchAll()
    print("[DataFetcher] 🔄 Fetch API Roblox...")

    local universeIds = {}
    local idToConfig  = {}
    for _, jeu in ipairs(JEUX_TRACKED) do
        local idStr = tostring(jeu.universeId)
        -- Éviter doublons
        local deja = false
        for _, id in ipairs(universeIds) do
            if id == idStr then deja = true break end
        end
        if not deja then
            table.insert(universeIds, idStr)
            idToConfig[idStr] = jeu
        end
    end

    local joueursData = fetchJoueursActifs(universeIds)
    local votesData   = fetchVotes(universeIds)

    local resultats = {}
    for idStr, config in pairs(idToConfig) do
        local jData = joueursData[idStr] or {}
        local vData = votesData[idStr]   or {}

        local joueurs   = jData.joueurs or 0
        local visites   = jData.visites or 0
        local upVotes   = vData.upVotes or 0
        local downVotes = vData.downVotes or 0
        local totalV    = upVotes + downVotes
        local likeRatio = totalV > 0 and math.floor((upVotes / totalV) * 100) or 50

        table.insert(resultats, {
            universeId  = config.universeId,
            gameId      = jData.rootPlaceId or 0,
            nom         = config.nom,
            joueurs     = joueurs,
            visites     = visites,
            upVotes     = upVotes,
            downVotes   = downVotes,
            likeRatio   = likeRatio,
            score       = calculerScore(joueurs, upVotes, downVotes, visites),
            statut      = "",  -- rempli après sort
        })
    end

    -- Trier par score
    table.sort(resultats, function(a, b) return a.score > b.score end)

    -- Rang + statut
    for i, r in ipairs(resultats) do
        r.rang   = i
        r.statut = getStatut(r.score)
    end

    cache          = resultats
    cacheTimestamp = tick()

    local top = resultats[1]
    if top then
        print(string.format("[DataFetcher] ✅ %d jeux — #1 : %s (score %.2f, %d joueurs)",
            #resultats, top.nom, top.score, top.joueurs))
    end

    return resultats
end

-- ------------------------------------------------------------
-- API PUBLIQUE
-- ------------------------------------------------------------
function DataFetcher.getCache()
    if tick() - cacheTimestamp > CACHE_TTL or #cache == 0 then
        fetchAll()
    end
    return cache
end

function DataFetcher.refresh()
    return fetchAll()
end

function DataFetcher.getByRang(rang)
    return DataFetcher.getCache()[rang]
end

-- Texte classement pour Board Normal (top N)
function DataFetcher.formaterClassement(topN)
    local data   = DataFetcher.getCache()
    local lignes = {}
    for i = 1, math.min(topN or 8, #data) do
        local j = data[i]
        table.insert(lignes, string.format(
            "#%d  %s\n     %s  👥%d  👍%d%%",
            j.rang, j.nom, j.statut, j.joueurs, j.likeRatio
        ))
    end
    return table.concat(lignes, "\n\n")
end

-- Texte stats pour Board VIP (jeu #1 détaillé)
function DataFetcher.formaterStatsVIP()
    local data = DataFetcher.getCache()
    if #data == 0 then return "Données indisponibles" end
    local j = data[1]
    local visitesStr = j.visites >= 1000000
        and string.format("%.1fM", j.visites / 1000000)
        or  tostring(j.visites)
    return string.format(
        "🏆 JEU #1 CETTE SEMAINE\n\n%s\n\n📊 Score Radar : %.2f\n👥 %d joueurs actifs\n👍 %d%% likes\n🎮 %s visites\n\n%s",
        j.nom, j.score, j.joueurs, j.likeRatio, visitesStr, j.statut
    )
end

-- ------------------------------------------------------------
-- AUTO-REFRESH toutes les 5 minutes
-- ------------------------------------------------------------
task.spawn(function()
    task.wait(3)  -- laisser Main.server créer les RemoteEvents
    fetchAll()

    while true do
        task.wait(CACHE_TTL)
        local data = fetchAll()

        -- Notifier tous les clients pour maj écrans
        local remotes = game.ReplicatedStorage:FindFirstChild("RadarEvents")
        if remotes then
            local ev = remotes:FindFirstChild("DataUpdate")
            if ev then ev:FireAllClients(data) end
        end
    end
end)

return DataFetcher