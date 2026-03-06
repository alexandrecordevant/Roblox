-- ============================================================
-- DataFetcher.lua — BrainRot HQ v4
-- Liste Brain Rot scrappée depuis roblox.com/discover
-- Stats (joueurs, visites, votes) récupérées en temps réel
-- ModuleScript → ServerScriptService
-- ============================================================

local HttpService = game:GetService("HttpService")

-- Proxy Cloudflare Worker (Roblox bloque les appels directs à *.roblox.com)
local PROXY = "https://roblox-proxy.getrewardfr.workers.dev"

-- ------------------------------------------------------------
-- LISTE BRAIN ROT — scrappée depuis roblox.com/discover
-- Mettre à jour via le script scrape_brainrot.mjs (Node.js)
-- Le nom ici est un fallback ; le vrai nom vient de l'API
-- ------------------------------------------------------------
local JEUX_TRACKED = {
    { universeId = 7709344486, nom = "Steal a Brainrot" },
    { universeId = 9363735110, nom = "Escape Tsunami For Brainrots!" },
    { universeId = 9753814298, nom = "Swing Obby for Brainrots!" },
    { universeId = 9649298941, nom = "Survive LAVA for Brainrots!" },
    { universeId = 9706113201, nom = "Brainrot Laboratory" },
    { universeId = 9715909786, nom = "Jump To Steal Lucky Blocks" },
    { universeId = 9710064812, nom = "Fly for Brainrots!" },
    { universeId = 9712933917, nom = "Get Tall For Brainrots" },
    { universeId = 9704343971, nom = "Grow Beanstalk For Brainrots!" },
    { universeId = 9695620503, nom = "Reel a Brainrot!" },
    { universeId = 9745497386, nom = "Jump and Escape Brainrots" },
    { universeId = 9671940985, nom = "Run For Brainrots!" },
    { universeId = 9626728130, nom = "Speed Escape for Brainrots!" },
    { universeId = 9570888371, nom = "Jump for Brainrots!" },
    { universeId = 9681943457, nom = "Catch Brainrots From River" },
    { universeId = 9694950178, nom = "Slide For Brainrots" },
    { universeId = 9671135973, nom = "Glide for Brainrots" },
    { universeId = 9676360773, nom = "Sail For Brainrots!" },
    { universeId = 9604810345, nom = "Escape Rising Lava For Brainrots!" },
    { universeId = 9684872190, nom = "Catch a Brainrot Container" },
    { universeId = 9550364666, nom = "Survive Disasters for Brainrots!" },
    { universeId = 9509746595, nom = "Survive HEAT for Brainrots!" },
    { universeId = 9510293839, nom = "Brainrot Heroes" },
    { universeId = 9497278040, nom = "My Scamming Brainrots!" },
    { universeId = 9233317754, nom = "FIND The New BRAINROTS Morphs" },
    { universeId = 8472682462, nom = "Brainrot BOSS — Hold the Last Line!" },
    { universeId = 8343243056, nom = "Brainrot Tower Defense" },
    { universeId = 8015734617, nom = "Steal Brainrots Trading Plaza" },
    { universeId = 8842956505, nom = "Brainrot Royale" },
    { universeId = 7674469859, nom = "Brainrot Tower" },
    { universeId = 7332711118, nom = "Brainrot Evolution" },
    { universeId = 7143545906, nom = "Enter Brainrot" },
    { universeId = 7950997475, nom = "Blue Lock: Skibidi" },
    { universeId = 9296252245, nom = "Phonk Edit Tower" },
    { universeId = 8902327228, nom = "Aura Phonk Edit Tower" },
    { universeId = 9751615286, nom = "Ultra Toilet Fight 2" },
    { universeId = 7893515528, nom = "My Singing Brainrot" },
    { universeId = 9517544700, nom = "Escape Tower For Brainrots!" },
    { universeId = 9594335382, nom = "Steal From Gatito" },
    { universeId = 5530781226, nom = "UGC Steal Points" },
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
-- FETCH INFOS JEUX (joueurs actifs, visites, nom officiel)
-- GET /v1/games?universeIds=X,Y,Z
-- Retourne une table indexée par universeId (string)
-- ------------------------------------------------------------
local function fetchInfos(universeIds)
    if #universeIds == 0 then return {} end
    local url = PROXY .. "/v1/games?universeIds=" .. table.concat(universeIds, ",")
    local ok, response = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok then
        warn("[DataFetcher] Erreur fetch infos : " .. tostring(response))
        return {}
    end
    local okJson, data = pcall(function() return HttpService:JSONDecode(response) end)
    if not okJson or not data or not data.data then return {} end

    local result = {}
    for _, g in ipairs(data.data) do
        result[tostring(g.id)] = {
            nom         = g.name or "Sans nom",
            joueurs     = g.playing or 0,
            visites     = g.visits or 0,
            rootPlaceId = g.rootPlaceId or 0,
        }
    end
    return result
end

-- ------------------------------------------------------------
-- FETCH VOTES
-- GET /v1/games/votes?universeIds=X,Y,Z
-- Retourne une table indexée par universeId (string)
-- ------------------------------------------------------------
local function fetchVotes(universeIds)
    if #universeIds == 0 then return {} end
    local url = PROXY .. "/v1/games/votes?universeIds=" .. table.concat(universeIds, ",")
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
    print(string.format("[DataFetcher] 🔄 Fetch stats pour %d jeux Brain Rot...", #JEUX_TRACKED))

    -- Construire la liste des universeIds (sans doublons)
    local universeIds = {}
    local idToConfig  = {}
    for _, jeu in ipairs(JEUX_TRACKED) do
        local idStr = tostring(jeu.universeId)
        if not idToConfig[idStr] then
            table.insert(universeIds, idStr)
            idToConfig[idStr] = jeu
        end
    end

    -- Fetch infos et votes en parallèle (deux appels HTTP)
    local infosData = fetchInfos(universeIds)
    local votesData = fetchVotes(universeIds)

    -- Calculer les scores
    local resultats = {}
    for idStr, config in pairs(idToConfig) do
        local info      = infosData[idStr] or {}
        local vote      = votesData[idStr] or {}
        local joueurs   = info.joueurs or 0
        local visites   = info.visites or 0
        local upVotes   = vote.upVotes or 0
        local downVotes = vote.downVotes or 0
        local totalV    = upVotes + downVotes
        local likeRatio = totalV > 0 and math.floor((upVotes / totalV) * 100) or 50

        table.insert(resultats, {
            universeId  = config.universeId,
            gameId      = info.rootPlaceId or 0,
            nom         = info.nom or config.nom,  -- nom officiel depuis API
            joueurs     = joueurs,
            visites     = visites,
            upVotes     = upVotes,
            downVotes   = downVotes,
            likeRatio   = likeRatio,
            score       = calculerScore(joueurs, upVotes, downVotes, visites),
            statut      = "",  -- rempli après tri
        })
    end

    -- Trier par score décroissant, garder les 16 meilleurs
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
        print(string.format("[DataFetcher] ✅ Top 16 — #1 : %s (score %.2f, %d joueurs)",
            top.nom, top.score, top.joueurs))
    end

    return top16
end

-- ------------------------------------------------------------
-- API PUBLIQUE
-- ------------------------------------------------------------
local DataFetcher = {}

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
        table.insert(lignes, string.format("#%d  %s  %s", j.rang, j.nom, j.statut))
    end
    return table.concat(lignes, "\n")
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
        "🏆 #1  %s\nScore : %.2f\n👥 %s joueurs\n👍 %d%% likes\n🎮 %s visites\n%s",
        j.nom,
        j.score,
        string.format("%d", j.joueurs):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""),
        j.likeRatio,
        visitesStr,
        j.statut
    )
end

-- Texte compact pour BillboardGui au-dessus d'un portail
function DataFetcher.formaterPortail(rang)
    local data = DataFetcher.getCache()
    local j = data[rang]
    if not j then return "" end

    -- Abréviation joueurs : 15640 → "15K", 1200 → "1.2K", 800 → "800"
    local joueursStr
    if j.joueurs >= 10000 then
        joueursStr = math.floor(j.joueurs / 1000) .. "K"
    elseif j.joueurs >= 1000 then
        joueursStr = string.format("%.1fK", j.joueurs / 1000)
    else
        joueursStr = tostring(j.joueurs)
    end

    local emoji = j.statut:match("^(%S+)")  -- premier token (emoji)
    return string.format("#%d\n%s\n%s %.2f • %s",
        j.rang,
        string.sub(j.nom, 1, 16),
        emoji, j.score, joueursStr
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
