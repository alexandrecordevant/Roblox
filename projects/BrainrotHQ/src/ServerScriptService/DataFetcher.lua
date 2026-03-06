-- ============================================================
-- DataFetcher.lua — BrainRot HQ v3
-- 100% automatique — zéro liste en dur
-- Fetch top 100 jeux Roblox → filtre Brain Rot → Top 16
-- ModuleScript → ServerScriptService
-- ============================================================

local HttpService = game:GetService("HttpService")

local DataFetcher = {}

-- ------------------------------------------------------------
-- MOTS-CLÉS BRAIN ROT (filtre insensible à la casse)
-- ------------------------------------------------------------
local KEYWORDS = {
    "brainrot", "brain rot", "skibidi", "fanum", "sigma", "ohio", "rizz",
    "gyatt", "mewing", "grimace", "phonk", "italian", "toilet", "hawk tuah",
    "lockjaw", "tralalero", "bombardiro", "tung tung", "sussy",
}

-- ------------------------------------------------------------
-- CACHE
-- ------------------------------------------------------------
local cache          = {}
local cacheTimestamp = 0
local CACHE_TTL      = 300  -- 5 minutes

-- ------------------------------------------------------------
-- UTILITAIRES
-- ------------------------------------------------------------

-- Vérifie si un nom de jeu contient un mot-clé Brain Rot
local function estBrainRot(nom)
    local nomLower = string.lower(nom)
    for _, kw in ipairs(KEYWORDS) do
        if string.find(nomLower, kw, 1, true) then
            return true
        end
    end
    return false
end

local function getStatut(score)
    if score >= 7 then return "🔥 VIRAL"
    elseif score >= 5 then return "📈 HOT"
    elseif score >= 3 then return "➡️ STABLE"
    else return "📉 WEAK" end
end

-- Calcul Score Radar sur 10 :
--   Joueurs actifs  → 5 pts max (saturé à 1000 joueurs)
--   Like ratio      → 3 pts max
--   Visites totales → 2 pts max (saturé à 1M visites)
local function calculerScore(joueurs, upVotes, downVotes, visites)
    local scoreJoueurs = math.min(joueurs / 1000, 1) * 5
    local totalVotes   = upVotes + downVotes
    local likeRatio    = totalVotes > 0 and (upVotes / totalVotes) or 0.5
    local scoreLikes   = likeRatio * 3
    local scoreVisites = math.min(visites / 1000000, 1) * 2
    return math.floor((scoreJoueurs + scoreLikes + scoreVisites) * 100) / 100
end

-- ------------------------------------------------------------
-- FETCH TOP 100 JEUX
-- GET https://games.roblox.com/v1/games/list?sortToken=CuratedGames&maxRows=100
-- Retourne un tableau de { universeId, nom, joueurs, visites, rootPlaceId }
-- ------------------------------------------------------------
local function fetchTop100()
    local url = "https://games.roblox.com/v1/games/list?sortToken=CuratedGames&maxRows=100"
    local ok, response = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok then
        warn("[DataFetcher] Erreur fetch top 100 : " .. tostring(response))
        return {}
    end
    local okJson, data = pcall(function() return HttpService:JSONDecode(response) end)
    if not okJson or not data or not data.games then
        warn("[DataFetcher] Réponse inattendue du top 100")
        return {}
    end

    local jeux = {}
    for _, g in ipairs(data.games) do
        table.insert(jeux, {
            universeId  = g.universeId,
            nom         = g.name or "Sans nom",
            joueurs     = g.playerCount or 0,
            visites     = g.totalVisits or 0,
            rootPlaceId = g.rootPlaceId or 0,
        })
    end
    return jeux
end

-- ------------------------------------------------------------
-- FETCH VOTES
-- GET https://games.roblox.com/v1/games/votes?universeIds=X,Y,Z
-- Retourne une table indexée par universeId (string)
-- ------------------------------------------------------------
local function fetchVotes(universeIds)
    if #universeIds == 0 then return {} end
    local url = "https://games.roblox.com/v1/games/votes?universeIds=" .. table.concat(universeIds, ",")
    local ok, response = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok then
        warn("[DataFetcher] Erreur fetch votes : " .. tostring(response))
        return {}
    end
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
-- FETCH COMPLET
-- ------------------------------------------------------------
local function fetchAll()
    print("[DataFetcher] 🔄 Fetch automatique top 100 Roblox...")

    -- Étape 1 : Récupérer les 100 jeux les plus populaires
    local top100 = fetchTop100()
    if #top100 == 0 then
        warn("[DataFetcher] ⚠️ Aucun jeu récupéré depuis l'API")
        return cache  -- garder le cache précédent
    end

    -- Étape 2 : Filtrer les jeux Brain Rot
    local brainRotJeux = {}
    for _, jeu in ipairs(top100) do
        if estBrainRot(jeu.nom) then
            table.insert(brainRotJeux, jeu)
        end
    end

    -- Fallback : si aucun Brain Rot trouvé, garder les 16 plus joués sans filtre
    local source   = brainRotJeux
    local fallback = false
    if #brainRotJeux == 0 then
        warn("[DataFetcher] ⚠️ Aucun jeu Brain Rot trouvé — fallback top 16 sans filtre")
        source   = top100
        fallback = true
    end

    -- Étape 3 : Construire la liste des universeIds pour les votes
    local universeIds = {}
    local idToJeu     = {}
    for _, jeu in ipairs(source) do
        local idStr = tostring(jeu.universeId)
        table.insert(universeIds, idStr)
        idToJeu[idStr] = jeu
    end

    -- Étape 4 : Récupérer les votes pour les jeux filtrés
    local votesData = fetchVotes(universeIds)

    -- Étape 5 : Calculer les scores
    local resultats = {}
    for idStr, jeu in pairs(idToJeu) do
        local vData     = votesData[idStr] or {}
        local upVotes   = vData.upVotes or 0
        local downVotes = vData.downVotes or 0
        local totalV    = upVotes + downVotes
        local likeRatio = totalV > 0 and math.floor((upVotes / totalV) * 100) or 50

        table.insert(resultats, {
            universeId  = jeu.universeId,
            gameId      = jeu.rootPlaceId,
            nom         = jeu.nom,
            joueurs     = jeu.joueurs,
            visites     = jeu.visites,
            upVotes     = upVotes,
            downVotes   = downVotes,
            likeRatio   = likeRatio,
            score       = calculerScore(jeu.joueurs, upVotes, downVotes, jeu.visites),
            statut      = "",  -- rempli après tri
        })
    end

    -- Étape 6 : Trier par score décroissant, garder les 16 meilleurs
    table.sort(resultats, function(a, b) return a.score > b.score end)

    local top16 = {}
    for i = 1, math.min(16, #resultats) do
        local r = resultats[i]
        r.rang   = i
        r.statut = getStatut(r.score)
        table.insert(top16, r)
    end

    cache          = top16
    cacheTimestamp = tick()

    local top = top16[1]
    if top then
        print(string.format("[DataFetcher] ✅ %d jeux Brain Rot%s — #1 : %s (score %.2f, %d joueurs)",
            #top16, fallback and " (fallback)" or "", top.nom, top.score, top.joueurs))
    end

    return top16
end

-- ------------------------------------------------------------
-- API PUBLIQUE
-- ------------------------------------------------------------

-- Retourne le cache (fetch si expiré)
function DataFetcher.getCache()
    if tick() - cacheTimestamp > CACHE_TTL or #cache == 0 then
        fetchAll()
    end
    return cache
end

-- Force un refresh immédiat
function DataFetcher.refresh()
    return fetchAll()
end

-- Retourne le jeu au rang donné (1-indexé)
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
    task.wait(3)  -- laisser Main.server.lua créer les RemoteEvents
    fetchAll()

    while true do
        task.wait(CACHE_TTL)
        local data = fetchAll()

        -- Notifier tous les clients (mise à jour des écrans)
        local remotes = game.ReplicatedStorage:FindFirstChild("RadarEvents")
        if remotes then
            local ev = remotes:FindFirstChild("DataUpdate")
            if ev then ev:FireAllClients(data) end
        end
    end
end)

return DataFetcher
