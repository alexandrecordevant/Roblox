-- ============================================================
-- TeleportHandler.lua — BrainRot Radar Hub
-- ModuleScript → ServerScriptService
-- Rôle : portails 3D → téléportation vers les jeux du classement
-- ============================================================

local TeleportHandler = {}

local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local Config          = require(game.ReplicatedStorage.Modules.Config)

-- ------------------------------------------------------------
-- MISE À JOUR DES PORTAILS DANS LE WORKSPACE
-- Appelé par Main.server.lua après chaque fetch de données
-- Les portails sont des Parts nommées "Portal_1" à "Portal_N"
-- dans un Folder workspace.Portals
-- ------------------------------------------------------------
function TeleportHandler.mettreAJourPortails(jeux)
    local dossierPortails = workspace:FindFirstChild("Portals")
    if not dossierPortails then
        warn("[TeleportHandler] Folder 'Portals' introuvable dans Workspace")
        return
    end

    local nbMax = math.min(#jeux, Config.NbPortailsMax)

    for i = 1, nbMax do
        local jeu      = jeux[i]
        local portal   = dossierPortails:FindFirstChild("Portal_" .. i)

        if portal then
            -- Stocker les infos dans les attributs du portail
            portal:SetAttribute("GameId",  jeu.gameId or 0)
            portal:SetAttribute("NomJeu",  jeu.nom or "?")
            portal:SetAttribute("Score",   jeu.score or 0)
            portal:SetAttribute("Statut",  jeu.statut or "WEAK")
            portal:SetAttribute("Rang",    i)
            portal:SetAttribute("Boosted", jeu.boosted or false)

            -- Changer la couleur du portail selon le statut
            local couleur = Config.Couleurs.Muted
            if jeu.statut == "VIRAL" then
                couleur = Config.Couleurs.Primaire   -- Rouge néon
            elseif jeu.statut == "WATCH" then
                couleur = Config.Couleurs.Accent     -- Jaune néon
            else
                couleur = Config.Couleurs.Muted
            end

            -- Appliquer la couleur au portail et ses enfants
            if portal:IsA("BasePart") then
                portal.Color = couleur
            end

            -- Mettre à jour le BillboardGui au-dessus du portail
            local billboard = portal:FindFirstChild("PortalInfo")
            if billboard then
                local title = billboard:FindFirstChild("Title")
                local score = billboard:FindFirstChild("Score")
                local rang  = billboard:FindFirstChild("Rang")

                if title then title.Text = jeu.nom end
                if score then score.Text = string.format("Score: %.2f %s", jeu.score, jeu.emoji or "") end
                if rang  then rang.Text  = "#" .. i end
            end

            -- Activer le portail si gameId valide
            portal:SetAttribute("Actif", jeu.gameId and jeu.gameId > 0)
        end
    end

    -- Désactiver les portails excédentaires
    for i = nbMax + 1, Config.NbPortailsMax do
        local portal = dossierPortails:FindFirstChild("Portal_" .. i)
        if portal then
            portal:SetAttribute("Actif", false)
            portal:SetAttribute("NomJeu", "")
            if portal:IsA("BasePart") then
                portal.Color = Config.Couleurs.Muted
            end
        end
    end
end

-- ------------------------------------------------------------
-- TÉLÉPORTER UN JOUEUR VERS UN JEU
-- Appelé via RemoteEvent depuis le client (quand il touche un portail)
-- Validation côté serveur obligatoire
-- ------------------------------------------------------------
function TeleportHandler.teleporter(player, gameId)
    -- Validation
    if not gameId or type(gameId) ~= "number" or gameId <= 0 then
        warn("[TeleportHandler] GameId invalide :", gameId)
        return false, "Ce jeu n'est pas disponible."
    end

    -- Vérifier que le gameId est dans notre liste (anti-exploit)
    local DataFetcher = require(script.Parent.DataFetcher)
    local cache = DataFetcher.getCache()
    local gameIdValide = false

    for _, jeu in ipairs(cache) do
        if jeu.gameId == gameId then
            gameIdValide = true
            break
        end
    end

    if not gameIdValide then
        warn("[TeleportHandler] GameId non trouvé dans le cache :", gameId)
        return false, "Jeu introuvable dans le classement."
    end

    -- Téléporter
    local ok, err = pcall(function()
        TeleportService:Teleport(gameId, player)
    end)

    if not ok then
        warn("[TeleportHandler] Erreur téléportation :", err)
        return false, "Téléportation échouée, réessaie."
    end

    return true, "Téléportation en cours... 🚀"
end

-- ------------------------------------------------------------
-- SETUP DES DÉTECTEURS DE TOUCHER SUR LES PORTAILS
-- Appelé une fois au démarrage par Main.server.lua
-- ------------------------------------------------------------
function TeleportHandler.setupPortails()
    local dossierPortails = workspace:FindFirstChild("Portals")
    if not dossierPortails then
        -- Créer le folder automatiquement si absent
        local folder = Instance.new("Folder")
        folder.Name = "Portals"
        folder.Parent = workspace
        dossierPortails = folder
        warn("[TeleportHandler] Folder 'Portals' créé automatiquement. Ajoute tes Part Portal_1 à Portal_N dedans.")
        return
    end

    -- Cooldown téléportation par joueur
    local cooldowns = {}

    for i = 1, Config.NbPortailsMax do
        local portal = dossierPortails:FindFirstChild("Portal_" .. i)
        if portal and portal:IsA("BasePart") then
            portal.Touched:Connect(function(hit)
                local character = hit.Parent
                local player = Players:GetPlayerFromCharacter(character)

                if not player then return end

                local userId = player.UserId
                local maintenant = tick()

                -- Cooldown 3 secondes entre téléportations
                if cooldowns[userId] and maintenant - cooldowns[userId] < 3 then
                    return
                end

                local actif  = portal:GetAttribute("Actif")
                local gameId = portal:GetAttribute("GameId")

                if not actif or not gameId or gameId == 0 then return end

                cooldowns[userId] = maintenant

                -- Notifier le client avant téléportation
                local remote = game.ReplicatedStorage:FindFirstChild("RadarEvents")
                if remote then
                    local notif = remote:FindFirstChild("Notification")
                    local nomJeu = portal:GetAttribute("NomJeu") or "ce jeu"
                    if notif then
                        notif:FireClient(player, {
                            type    = "teleport",
                            message = string.format("🚀 Téléportation vers '%s'...", nomJeu),
                        })
                    end
                end

                task.wait(1) -- Laisser la notif s'afficher

                TeleportHandler.teleporter(player, gameId)
            end)
        end
    end
end

return TeleportHandler
