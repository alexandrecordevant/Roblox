-- ============================================================
-- Config.lua — BrainRot Radar Hub
-- ModuleScript → ReplicatedStorage/Modules/Config
-- Seul fichier à modifier entre versions
-- ============================================================

local Config = {}

-- ------------------------------------------------------------
-- IDENTITÉ DU JEU
-- ------------------------------------------------------------
Config.NomDuJeu       = "🧠 BrainRot Radar"
Config.Version        = "1.0.0"

-- ------------------------------------------------------------
-- SOURCE DE DONNÉES — Google Sheet publié en CSV
-- Fichier → Partager → Publier sur le web → CSV
-- Format colonnes : Jeu | Joueurs | Joueurs_24h | Likes | Dislikes | GameId
-- ------------------------------------------------------------
Config.SheetCSV_URL = "REMPLACE_PAR_TON_URL_CSV"
-- Exemple :
-- "https://docs.google.com/spreadsheets/d/TON_ID/pub?gid=0&single=true&output=csv"

-- Intervalle de fetch (secondes) — minimum 30 pour éviter le rate limit
Config.FetchInterval  = 300 -- 5 minutes

-- ------------------------------------------------------------
-- MONÉTISATION
-- Créer dans Creator Hub → Monétisation avant de remplir
-- ------------------------------------------------------------
Config.GamePass = {
    AnalystPro = {
        Id    = 0,         -- ← Remplacer par vrai ID Game Pass
        Prix  = 99,        -- Robux
        Label = "Analyst Pro",
    },
}

Config.Produits = {
    Boost = {
        Id          = 0,   -- ← Remplacer par vrai ID Developer Product
        Prix        = 25,  -- Robux
        Label       = "Boost Mon Jeu",
        DureeHeures = 24,  -- Durée du boost en heures
        BonusScore  = 0.5, -- Score Radar ajouté pendant le boost
    },
}

-- ------------------------------------------------------------
-- BADGES
-- ------------------------------------------------------------
Config.Badges = {
    PremierVote      = 0,  -- ← ID badge "Premier Vote"
    AnalysteSemaine  = 0,  -- ← ID badge "Meilleur Analyste de la Semaine"
    Prophete         = 0,  -- ← ID badge "Prophète" (5 bonnes prédictions)
}

-- ------------------------------------------------------------
-- SYSTÈME DE VOTE / POINTS
-- ------------------------------------------------------------
Config.Vote = {
    PointsBonnePrediction = 10,  -- Points si prédiction correcte
    PointsMauvaise        = 0,   -- Points si raté
    BonusStreak           = 5,   -- Bonus par streak (3 bonnes de suite)
    CooldownVote          = 60,  -- Secondes entre deux votes du même joueur
    DureeRoundHeures      = 168, -- 1 semaine = 7 × 24h
}

-- ------------------------------------------------------------
-- LEADERBOARD
-- ------------------------------------------------------------
Config.Leaderboard = {
    NbJoueursAffiches = 10,
    DataStoreName     = "BrainRotRadar_Leaderboard_v1",
    DataStoreVotes    = "BrainRotRadar_Votes_v1",
    DataStoreBoosts   = "BrainRotRadar_Boosts_v1",
}

-- ------------------------------------------------------------
-- SONS (IDs audio Roblox — utiliser des sons libres de droits)
-- ------------------------------------------------------------
Config.Sons = {
    Vote        = 0,   -- Son quand le joueur vote
    BonneReponse = 0,  -- Son si prédiction correcte
    Achat       = 0,   -- Son confirmation achat
    Teleport    = 0,   -- Son téléportation vers un jeu
}

-- ------------------------------------------------------------
-- COULEURS THÈME NÉON
-- ------------------------------------------------------------
Config.Couleurs = {
    Primaire    = Color3.fromRGB(255, 45, 85),   -- Rouge néon
    Secondaire  = Color3.fromRGB(0, 245, 160),   -- Vert néon
    Accent      = Color3.fromRGB(255, 214, 10),  -- Jaune néon
    Fond        = Color3.fromRGB(10, 10, 15),    -- Noir profond
    Texte       = Color3.fromRGB(232, 232, 240), -- Blanc cassé
    Muted       = Color3.fromRGB(85, 85, 112),   -- Gris
}

-- ------------------------------------------------------------
-- PORTAILS — positionnés dans le Workspace
-- Chaque portail est un Part nommé "Portal_1", "Portal_2", etc.
-- Le GameId est lu depuis les données du Sheet (colonne 6)
-- ------------------------------------------------------------
Config.NbPortailsMax = 8  -- Nombre max de portails affichés dans le hub

return Config
