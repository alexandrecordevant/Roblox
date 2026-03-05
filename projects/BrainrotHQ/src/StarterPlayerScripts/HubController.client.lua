-- ============================================================
-- HubController.client.lua — BrainRot Radar Hub
-- LocalScript → StarterPlayerScripts
-- Rôle : GUI salle de contrôle, classement, vote, shop, notifs
-- ============================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local SoundService       = game:GetService("SoundService")

local player   = Players.LocalPlayer
local playerGui = player.PlayerGui

-- Attendre les RemoteEvents
local remotes = ReplicatedStorage:WaitForChild("RadarEvents", 10)
if not remotes then
    warn("[HubController] RadarEvents introuvable")
    return
end

local rfClassement = remotes:WaitForChild("GetClassement")
local rfStats      = remotes:WaitForChild("GetStatsJoueur")
local rfLB         = remotes:WaitForChild("GetLeaderboard")

-- Config couleurs (dupliquée côté client pour éviter require serveur)
local C = {
    FOND       = Color3.fromRGB(10, 10, 15),
    SURFACE    = Color3.fromRGB(18, 18, 26),
    BORDER     = Color3.fromRGB(30, 30, 46),
    ROUGE      = Color3.fromRGB(255, 45, 85),
    VERT       = Color3.fromRGB(0, 245, 160),
    JAUNE      = Color3.fromRGB(255, 214, 10),
    TEXTE      = Color3.fromRGB(232, 232, 240),
    MUTED      = Color3.fromRGB(85, 85, 112),
    BLANC      = Color3.fromRGB(255, 255, 255),
}

-- État local
local analyistProActif = false
local donneesActuelles = {}
local ongletActif = "classement"

-- ============================================================
-- CRÉATION DE LA GUI
-- ============================================================
local function creerGUI()
    -- Supprimer ancienne GUI si elle existe
    local ancienne = playerGui:FindFirstChild("RadarHubGUI")
    if ancienne then ancienne:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RadarHubGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    -- --------------------------------------------------------
    -- FRAME PRINCIPALE
    -- --------------------------------------------------------
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 680, 0, 520)
    mainFrame.Position = UDim2.new(0.5, -340, 0.5, -260)
    mainFrame.BackgroundColor3 = C.FOND
    mainFrame.BorderSizePixel = 0
    mainFrame.Visible = false -- Ouvert via bouton toggle
    mainFrame.Parent = screenGui

    -- Bordure néon
    local stroke = Instance.new("UIStroke")
    stroke.Color = C.ROUGE
    stroke.Thickness = 1.5
    stroke.Parent = mainFrame

    -- --------------------------------------------------------
    -- HEADER
    -- --------------------------------------------------------
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 56)
    header.BackgroundColor3 = C.SURFACE
    header.BorderSizePixel = 0
    header.Parent = mainFrame

    local titre = Instance.new("TextLabel")
    titre.Size = UDim2.new(1, -120, 1, 0)
    titre.Position = UDim2.new(0, 16, 0, 0)
    titre.BackgroundTransparency = 1
    titre.Text = "🧠 BRAINROT RADAR"
    titre.TextColor3 = C.TEXTE
    titre.Font = Enum.Font.GothamBold
    titre.TextSize = 18
    titre.TextXAlignment = Enum.TextXAlignment.Left
    titre.Parent = header

    local liveDot = Instance.new("Frame")
    liveDot.Size = UDim2.new(0, 8, 0, 8)
    liveDot.Position = UDim2.new(0, 160, 0.5, -4)
    liveDot.BackgroundColor3 = C.VERT
    liveDot.BorderSizePixel = 0
    liveDot.Parent = header
    Instance.new("UICorner").Parent = liveDot

    -- Bouton fermer
    local btnFermer = Instance.new("TextButton")
    btnFermer.Size = UDim2.new(0, 36, 0, 36)
    btnFermer.Position = UDim2.new(1, -46, 0.5, -18)
    btnFermer.BackgroundColor3 = Color3.fromRGB(40, 20, 30)
    btnFermer.BorderSizePixel = 0
    btnFermer.Text = "✕"
    btnFermer.TextColor3 = C.ROUGE
    btnFermer.Font = Enum.Font.GothamBold
    btnFermer.TextSize = 16
    btnFermer.Parent = header

    btnFermer.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    -- --------------------------------------------------------
    -- ONGLETS
    -- --------------------------------------------------------
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, 0, 0, 40)
    tabBar.Position = UDim2.new(0, 0, 0, 56)
    tabBar.BackgroundColor3 = C.SURFACE
    tabBar.BorderSizePixel = 0
    tabBar.Parent = mainFrame

    local separateur = Instance.new("Frame")
    separateur.Size = UDim2.new(1, 0, 0, 1)
    separateur.Position = UDim2.new(0, 0, 1, -1)
    separateur.BackgroundColor3 = C.BORDER
    separateur.BorderSizePixel = 0
    separateur.Parent = tabBar

    local onglets = {
        { id = "classement", label = "📊 CLASSEMENT" },
        { id = "vote",       label = "🗳️ VOTER" },
        { id = "top",        label = "🏆 TOP ANALYSTES" },
        { id = "shop",       label = "💎 SHOP" },
    }

    local tabBtns = {}
    for i, onglet in ipairs(onglets) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.25, 0, 1, 0)
        btn.Position = UDim2.new((i-1) * 0.25, 0, 0, 0)
        btn.BackgroundTransparency = 1
        btn.Text = onglet.label
        btn.TextColor3 = C.MUTED
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Name = "Tab_" .. onglet.id
        btn.Parent = tabBar
        tabBtns[onglet.id] = btn
    end

    -- --------------------------------------------------------
    -- CONTENU PRINCIPAL (zone scrollable)
    -- --------------------------------------------------------
    local contentArea = Instance.new("Frame")
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, 0, 1, -96)
    contentArea.Position = UDim2.new(0, 0, 0, 96)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = mainFrame

    -- CLASSEMENT
    local classementFrame = Instance.new("ScrollingFrame")
    classementFrame.Name = "Classement"
    classementFrame.Size = UDim2.new(1, 0, 1, 0)
    classementFrame.BackgroundTransparency = 1
    classementFrame.BorderSizePixel = 0
    classementFrame.ScrollBarThickness = 3
    classementFrame.ScrollBarImageColor3 = C.ROUGE
    classementFrame.Parent = contentArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = classementFrame

    -- VOTE
    local voteFrame = Instance.new("Frame")
    voteFrame.Name = "Vote"
    voteFrame.Size = UDim2.new(1, 0, 1, 0)
    voteFrame.BackgroundTransparency = 1
    voteFrame.Visible = false
    voteFrame.Parent = contentArea

    -- TOP ANALYSTES
    local topFrame = Instance.new("ScrollingFrame")
    topFrame.Name = "TopAnalystes"
    topFrame.Size = UDim2.new(1, 0, 1, 0)
    topFrame.BackgroundTransparency = 1
    topFrame.BorderSizePixel = 0
    topFrame.ScrollBarThickness = 3
    topFrame.ScrollBarImageColor3 = C.JAUNE
    topFrame.Visible = false
    topFrame.Parent = contentArea

    local topLayout = Instance.new("UIListLayout")
    topLayout.Padding = UDim.new(0, 2)
    topLayout.Parent = topFrame

    -- SHOP
    local shopFrame = Instance.new("Frame")
    shopFrame.Name = "Shop"
    shopFrame.Size = UDim2.new(1, 0, 1, 0)
    shopFrame.BackgroundTransparency = 1
    shopFrame.Visible = false
    shopFrame.Parent = contentArea

    -- --------------------------------------------------------
    -- BOUTTON TOGGLE (toujours visible)
    -- --------------------------------------------------------
    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Size = UDim2.new(0, 52, 0, 52)
    toggleBtn.Position = UDim2.new(0, 16, 0.5, -26)
    toggleBtn.BackgroundColor3 = C.SURFACE
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Parent = screenGui

    local toggleStroke = Instance.new("UIStroke")
    toggleStroke.Color = C.ROUGE
    toggleStroke.Thickness = 1.5
    toggleStroke.Parent = toggleBtn

    local toggleLabel = Instance.new("TextLabel")
    toggleLabel.Size = UDim2.new(1, 0, 1, 0)
    toggleLabel.BackgroundTransparency = 1
    toggleLabel.Text = "🧠"
    toggleLabel.TextSize = 24
    toggleLabel.Font = Enum.Font.GothamBold
    toggleLabel.Parent = toggleBtn

    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
        if mainFrame.Visible then
            -- Animer l'ouverture
            mainFrame.Size = UDim2.new(0, 0, 0, 0)
            mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
            TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
                Size = UDim2.new(0, 680, 0, 520),
                Position = UDim2.new(0.5, -340, 0.5, -260),
            }):Play()
        end
    end)

    -- --------------------------------------------------------
    -- NOTIFICATION TOAST
    -- --------------------------------------------------------
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.Size = UDim2.new(0, 360, 0, 52)
    toast.Position = UDim2.new(0.5, -180, 1, 20) -- Hors écran par défaut
    toast.BackgroundColor3 = C.SURFACE
    toast.BorderSizePixel = 0
    toast.Parent = screenGui

    local toastStroke = Instance.new("UIStroke")
    toastStroke.Color = C.VERT
    toastStroke.Thickness = 1
    toastStroke.Parent = toast

    local toastText = Instance.new("TextLabel")
    toastText.Size = UDim2.new(1, -16, 1, 0)
    toastText.Position = UDim2.new(0, 8, 0, 0)
    toastText.BackgroundTransparency = 1
    toastText.Text = ""
    toastText.TextColor3 = C.TEXTE
    toastText.Font = Enum.Font.Gotham
    toastText.TextSize = 13
    toastText.TextWrapped = true
    toastText.Parent = toast

    return {
        mainFrame       = mainFrame,
        classementFrame = classementFrame,
        voteFrame       = voteFrame,
        topFrame        = topFrame,
        shopFrame       = shopFrame,
        tabBtns         = tabBtns,
        toast           = toast,
        toastText       = toastText,
        toastStroke     = toastStroke,
        contentArea     = contentArea,
    }
end

-- ============================================================
-- AFFICHER UNE NOTIFICATION TOAST
-- ============================================================
local toastActif = false
local function afficherToast(gui, message, typeNotif)
    if toastActif then return end
    toastActif = true

    local couleur = typeNotif == "erreur" and C.ROUGE
        or typeNotif == "boost" and C.JAUNE
        or C.VERT

    gui.toastStroke.Color = couleur
    gui.toastText.Text = message

    TweenService:Create(gui.toast, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5, -180, 1, -72),
    }):Play()

    task.wait(3)

    TweenService:Create(gui.toast, TweenInfo.new(0.3), {
        Position = UDim2.new(0.5, -180, 1, 20),
    }):Play()

    task.wait(0.3)
    toastActif = false
end

-- ============================================================
-- REMPLIR LE CLASSEMENT
-- ============================================================
local function afficherClassement(gui, jeux)
    -- Nettoyer
    for _, child in ipairs(gui.classementFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for i, jeu in ipairs(jeux) do
        local couleurStatut = jeu.statut == "VIRAL" and C.ROUGE
            or jeu.statut == "WATCH" and C.JAUNE
            or C.MUTED

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 52)
        row.BackgroundColor3 = i % 2 == 0 and C.SURFACE or C.FOND
        row.BorderSizePixel = 0
        row.Parent = gui.classementFrame

        -- Rang
        local rangLabel = Instance.new("TextLabel")
        rangLabel.Size = UDim2.new(0, 40, 1, 0)
        rangLabel.BackgroundTransparency = 1
        rangLabel.Text = "#" .. i
        rangLabel.TextColor3 = i <= 3 and C.JAUNE or C.MUTED
        rangLabel.Font = Enum.Font.GothamBold
        rangLabel.TextSize = 16
        rangLabel.Parent = row

        -- Nom jeu
        local nomLabel = Instance.new("TextLabel")
        nomLabel.Size = UDim2.new(0.4, 0, 0.6, 0)
        nomLabel.Position = UDim2.new(0, 42, 0, 4)
        nomLabel.BackgroundTransparency = 1
        nomLabel.Text = (jeu.boosted and "⚡ " or "") .. (jeu.nom or "?")
        nomLabel.TextColor3 = C.TEXTE
        nomLabel.Font = Enum.Font.GothamBold
        nomLabel.TextSize = 12
        nomLabel.TextXAlignment = Enum.TextXAlignment.Left
        nomLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nomLabel.Parent = row

        -- Statut
        local statutLabel = Instance.new("TextLabel")
        statutLabel.Size = UDim2.new(0, 70, 0.5, 0)
        statutLabel.Position = UDim2.new(0, 42, 0.5, 0)
        statutLabel.BackgroundTransparency = 1
        statutLabel.Text = (jeu.emoji or "") .. " " .. (jeu.statut or "")
        statutLabel.TextColor3 = couleurStatut
        statutLabel.Font = Enum.Font.Gotham
        statutLabel.TextSize = 10
        statutLabel.TextXAlignment = Enum.TextXAlignment.Left
        statutLabel.Parent = row

        -- Score
        local scoreLabel = Instance.new("TextLabel")
        scoreLabel.Size = UDim2.new(0, 60, 1, 0)
        scoreLabel.Position = UDim2.new(0.6, 0, 0, 0)
        scoreLabel.BackgroundTransparency = 1
        scoreLabel.Text = string.format("%.2f", jeu.score or 0)
        scoreLabel.TextColor3 = couleurStatut
        scoreLabel.Font = Enum.Font.GothamBold
        scoreLabel.TextSize = 20
        scoreLabel.Parent = row

        -- Variation
        local varLabel = Instance.new("TextLabel")
        varLabel.Size = UDim2.new(0, 70, 1, 0)
        varLabel.Position = UDim2.new(0.75, 0, 0, 0)
        varLabel.BackgroundTransparency = 1
        local varPct = jeu.variationPct or 0
        local varSign = varPct > 0 and "+" or ""
        varLabel.Text = varSign .. varPct .. "%"
        varLabel.TextColor3 = varPct > 5 and C.VERT or varPct < -5 and C.ROUGE or C.MUTED
        varLabel.Font = Enum.Font.GothamBold
        varLabel.TextSize = 13
        varLabel.Parent = row

        -- Bouton voter (si pas encore voté)
        if jeu.gameId and jeu.gameId > 0 then
            local btnTeleport = Instance.new("TextButton")
            btnTeleport.Size = UDim2.new(0, 60, 0, 28)
            btnTeleport.Position = UDim2.new(1, -68, 0.5, -14)
            btnTeleport.BackgroundColor3 = Color3.fromRGB(20, 40, 30)
            btnTeleport.BorderSizePixel = 0
            btnTeleport.Text = "JOUER →"
            btnTeleport.TextColor3 = C.VERT
            btnTeleport.Font = Enum.Font.GothamBold
            btnTeleport.TextSize = 9
            btnTeleport.Parent = row

            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = C.VERT
            btnStroke.Thickness = 1
            btnStroke.Parent = btnTeleport

            local capturedGameId = jeu.gameId
            btnTeleport.MouseButton1Click:Connect(function()
                remotes.DemandeTeleport:FireServer(capturedGameId)
            end)
        end
    end

    -- Mettre à jour la taille du frame scrollable
    gui.classementFrame.CanvasSize = UDim2.new(0, 0, 0, #jeux * 54)
end

-- ============================================================
-- REMPLIR LE PANNEAU VOTE
-- ============================================================
local function afficherVote(gui, jeux)
    -- Nettoyer
    for _, child in ipairs(gui.voteFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local titre = Instance.new("TextLabel")
    titre.Size = UDim2.new(1, -32, 0, 40)
    titre.Position = UDim2.new(0, 16, 0, 12)
    titre.BackgroundTransparency = 1
    titre.Text = "Quel jeu sera #1 la semaine prochaine ?"
    titre.TextColor3 = C.TEXTE
    titre.Font = Enum.Font.GothamBold
    titre.TextSize = 15
    titre.TextXAlignment = Enum.TextXAlignment.Left
    titre.Parent = gui.voteFrame

    local sousTitre = Instance.new("TextLabel")
    sousTitre.Size = UDim2.new(1, -32, 0, 24)
    sousTitre.Position = UDim2.new(0, 16, 0, 50)
    sousTitre.BackgroundTransparency = 1
    sousTitre.Text = "Bonne prédiction = +10 points • Streak x3 = +5 bonus"
    sousTitre.TextColor3 = C.MUTED
    sousTitre.Font = Enum.Font.Gotham
    sousTitre.TextSize = 11
    sousTitre.TextXAlignment = Enum.TextXAlignment.Left
    sousTitre.Parent = gui.voteFrame

    -- Boutons de vote pour chaque jeu (top 5)
    local nb = math.min(#jeux, 5)
    for i = 1, nb do
        local jeu = jeux[i]

        local btnVote = Instance.new("TextButton")
        btnVote.Size = UDim2.new(1, -32, 0, 44)
        btnVote.Position = UDim2.new(0, 16, 0, 84 + (i-1) * 50)
        btnVote.BackgroundColor3 = C.SURFACE
        btnVote.BorderSizePixel = 0
        btnVote.Text = string.format("%s  %s  (Score %.2f)", jeu.emoji or "❓", jeu.nom or "?", jeu.score or 0)
        btnVote.TextColor3 = C.TEXTE
        btnVote.Font = Enum.Font.GothamBold
        btnVote.TextSize = 13
        btnVote.Parent = gui.voteFrame

        local voteStroke = Instance.new("UIStroke")
        voteStroke.Color = C.BORDER
        voteStroke.Thickness = 1
        voteStroke.Parent = btnVote

        local capturedNom = jeu.nom
        btnVote.MouseButton1Click:Connect(function()
            remotes.DemandeVote:FireServer(capturedNom)
            -- Feedback visuel
            TweenService:Create(voteStroke, TweenInfo.new(0.2), {
                Color = C.VERT
            }):Play()
        end)

        btnVote.MouseEnter:Connect(function()
            TweenService:Create(btnVote, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(25, 35, 30)
            }):Play()
        end)

        btnVote.MouseLeave:Connect(function()
            TweenService:Create(btnVote, TweenInfo.new(0.1), {
                BackgroundColor3 = C.SURFACE
            }):Play()
        end)
    end
end

-- ============================================================
-- REMPLIR LE TOP ANALYSTES
-- ============================================================
local function afficherTopAnalystes(gui, leaderboard)
    for _, child in ipairs(gui.topFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for i, entry in ipairs(leaderboard) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 48)
        row.BackgroundColor3 = i % 2 == 0 and C.SURFACE or C.FOND
        row.BorderSizePixel = 0
        row.Parent = gui.topFrame

        local couleurRang = i == 1 and C.JAUNE or i == 2 and C.MUTED or i == 3 and Color3.fromRGB(205,127,50) or C.MUTED

        local rangL = Instance.new("TextLabel")
        rangL.Size = UDim2.new(0, 48, 1, 0)
        rangL.BackgroundTransparency = 1
        rangL.Text = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or "#"..i
        rangL.TextColor3 = couleurRang
        rangL.Font = Enum.Font.GothamBold
        rangL.TextSize = i <= 3 and 18 or 14
        rangL.Parent = row

        local nomL = Instance.new("TextLabel")
        nomL.Size = UDim2.new(0.6, 0, 1, 0)
        nomL.Position = UDim2.new(0, 50, 0, 0)
        nomL.BackgroundTransparency = 1
        nomL.Text = entry.nom or "???"
        nomL.TextColor3 = C.TEXTE
        nomL.Font = Enum.Font.Gotham
        nomL.TextSize = 14
        nomL.TextXAlignment = Enum.TextXAlignment.Left
        nomL.Parent = row

        local ptsL = Instance.new("TextLabel")
        ptsL.Size = UDim2.new(0, 80, 1, 0)
        ptsL.Position = UDim2.new(1, -88, 0, 0)
        ptsL.BackgroundTransparency = 1
        ptsL.Text = (entry.points or 0) .. " pts"
        ptsL.TextColor3 = C.JAUNE
        ptsL.Font = Enum.Font.GothamBold
        ptsL.TextSize = 15
        ptsL.TextXAlignment = Enum.TextXAlignment.Right
        ptsL.Parent = row
    end

    gui.topFrame.CanvasSize = UDim2.new(0, 0, 0, #leaderboard * 50)
end

-- ============================================================
-- REMPLIR LE SHOP
-- ============================================================
local function afficherShop(gui)
    for _, child in ipairs(gui.shopFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end

    -- ANALYST PRO
    local cardPro = Instance.new("Frame")
    cardPro.Size = UDim2.new(1, -32, 0, 140)
    cardPro.Position = UDim2.new(0, 16, 0, 16)
    cardPro.BackgroundColor3 = C.SURFACE
    cardPro.BorderSizePixel = 0
    cardPro.Parent = gui.shopFrame

    local proStroke = Instance.new("UIStroke")
    proStroke.Color = C.JAUNE
    proStroke.Thickness = 1.5
    proStroke.Parent = cardPro

    local proTitre = Instance.new("TextLabel")
    proTitre.Size = UDim2.new(1, -16, 0, 32)
    proTitre.Position = UDim2.new(0, 12, 0, 10)
    proTitre.BackgroundTransparency = 1
    proTitre.Text = "💎 ANALYST PRO — 99 Robux"
    proTitre.TextColor3 = C.JAUNE
    proTitre.Font = Enum.Font.GothamBold
    proTitre.TextSize = 15
    proTitre.TextXAlignment = Enum.TextXAlignment.Left
    proTitre.Parent = cardPro

    local proDesc = Instance.new("TextLabel")
    proDesc.Size = UDim2.new(1, -16, 0, 48)
    proDesc.Position = UDim2.new(0, 12, 0, 44)
    proDesc.BackgroundTransparency = 1
    proDesc.Text = "✓ Stats détaillées de chaque jeu\n✓ Badge exclusif Analyst Pro\n✓ Accès aux prédictions avancées"
    proDesc.TextColor3 = C.MUTED
    proDesc.Font = Enum.Font.Gotham
    proDesc.TextSize = 12
    proDesc.TextXAlignment = Enum.TextXAlignment.Left
    proDesc.Parent = cardPro

    local btnPro = Instance.new("TextButton")
    btnPro.Size = UDim2.new(0, 140, 0, 32)
    btnPro.Position = UDim2.new(1, -152, 1, -42)
    btnPro.BackgroundColor3 = Color3.fromRGB(40, 35, 10)
    btnPro.BorderSizePixel = 0
    btnPro.Text = analyistProActif and "✓ DÉJÀ ACHETÉ" or "ACHETER →"
    btnPro.TextColor3 = analyistProActif and C.VERT or C.JAUNE
    btnPro.Font = Enum.Font.GothamBold
    btnPro.TextSize = 12
    btnPro.Parent = cardPro

    Instance.new("UIStroke").Color = C.JAUNE
    local btnProStroke = Instance.new("UIStroke")
    btnProStroke.Color = C.JAUNE
    btnProStroke.Thickness = 1
    btnProStroke.Parent = btnPro

    btnPro.MouseButton1Click:Connect(function()
        if not analyistProActif then
            remotes.DemandeVote:FireServer("__prompt_analyst_pro__") -- Handled server-side
        end
    end)

    -- BOOST
    local cardBoost = Instance.new("Frame")
    cardBoost.Size = UDim2.new(1, -32, 0, 160)
    cardBoost.Position = UDim2.new(0, 16, 0, 172)
    cardBoost.BackgroundColor3 = C.SURFACE
    cardBoost.BorderSizePixel = 0
    cardBoost.Parent = gui.shopFrame

    local boostStroke = Instance.new("UIStroke")
    boostStroke.Color = C.ROUGE
    boostStroke.Thickness = 1.5
    boostStroke.Parent = cardBoost

    local boostTitre = Instance.new("TextLabel")
    boostTitre.Size = UDim2.new(1, -16, 0, 32)
    boostTitre.Position = UDim2.new(0, 12, 0, 10)
    boostTitre.BackgroundTransparency = 1
    boostTitre.Text = "⚡ BOOST MON JEU — 25 Robux"
    boostTitre.TextColor3 = C.ROUGE
    boostTitre.Font = Enum.Font.GothamBold
    boostTitre.TextSize = 15
    boostTitre.TextXAlignment = Enum.TextXAlignment.Left
    boostTitre.Parent = cardBoost

    local boostDesc = Instance.new("TextLabel")
    boostDesc.Size = UDim2.new(1, -16, 0, 36)
    boostDesc.Position = UDim2.new(0, 12, 0, 44)
    boostDesc.BackgroundTransparency = 1
    boostDesc.Text = "Ton jeu Brain Rot remonte dans le classement +0.5 score pendant 24h"
    boostDesc.TextColor3 = C.MUTED
    boostDesc.Font = Enum.Font.Gotham
    boostDesc.TextSize = 12
    boostDesc.TextXAlignment = Enum.TextXAlignment.Left
    boostDesc.TextWrapped = true
    boostDesc.Parent = cardBoost

    -- Champ texte nom du jeu
    local inputLabel = Instance.new("TextLabel")
    inputLabel.Size = UDim2.new(0, 120, 0, 24)
    inputLabel.Position = UDim2.new(0, 12, 0, 88)
    inputLabel.BackgroundTransparency = 1
    inputLabel.Text = "Nom de ton jeu :"
    inputLabel.TextColor3 = C.MUTED
    inputLabel.Font = Enum.Font.Gotham
    inputLabel.TextSize = 11
    inputLabel.TextXAlignment = Enum.TextXAlignment.Left
    inputLabel.Parent = cardBoost

    local inputNom = Instance.new("TextBox")
    inputNom.Size = UDim2.new(1, -148, 0, 28)
    inputNom.Position = UDim2.new(0, 132, 0, 84)
    inputNom.BackgroundColor3 = C.FOND
    inputNom.BorderSizePixel = 0
    inputNom.Text = ""
    inputNom.PlaceholderText = "Ex: Skibidi Obby..."
    inputNom.TextColor3 = C.TEXTE
    inputNom.PlaceholderColor3 = C.MUTED
    inputNom.Font = Enum.Font.Gotham
    inputNom.TextSize = 12
    inputNom.ClearTextOnFocus = false
    inputNom.Parent = cardBoost

    Instance.new("UIStroke").Color = C.BORDER

    inputNom.FocusLost:Connect(function()
        if inputNom.Text ~= "" then
            remotes.DemandeBoostNom:FireServer(inputNom.Text)
        end
    end)

    local btnBoost = Instance.new("TextButton")
    btnBoost.Size = UDim2.new(0, 140, 0, 32)
    btnBoost.Position = UDim2.new(1, -152, 1, -42)
    btnBoost.BackgroundColor3 = Color3.fromRGB(40, 15, 20)
    btnBoost.BorderSizePixel = 0
    btnBoost.Text = "BOOSTER →"
    btnBoost.TextColor3 = C.ROUGE
    btnBoost.Font = Enum.Font.GothamBold
    btnBoost.TextSize = 12
    btnBoost.Parent = cardBoost

    local btnBoostStroke = Instance.new("UIStroke")
    btnBoostStroke.Color = C.ROUGE
    btnBoostStroke.Thickness = 1
    btnBoostStroke.Parent = btnBoost

    btnBoost.MouseButton1Click:Connect(function()
        if inputNom.Text ~= "" then
            remotes.DemandeBoostNom:FireServer(inputNom.Text)
            -- Prompt achat (via event serveur qui appellera MarketplaceService)
            remotes.DemandeVote:FireServer("__prompt_boost__")
        end
    end)
end

-- ============================================================
-- SYSTÈME D'ONGLETS
-- ============================================================
local function setupOnglets(gui)
    local frames = {
        classement = gui.classementFrame,
        vote       = gui.voteFrame,
        top        = gui.topFrame,
        shop       = gui.shopFrame,
    }

    for id, btn in pairs(gui.tabBtns) do
        btn.MouseButton1Click:Connect(function()
            -- Cacher tous
            for _, f in pairs(frames) do f.Visible = false end
            -- Afficher le bon
            if frames[id] then frames[id].Visible = true end
            -- Mettre à jour couleurs
            for otherId, otherBtn in pairs(gui.tabBtns) do
                otherBtn.TextColor3 = otherId == id and C.VERT or C.MUTED
            end
            ongletActif = id

            -- Charger les données de l'onglet
            if id == "top" then
                task.spawn(function()
                    local lb = rfLB:InvokeServer()
                    if lb then afficherTopAnalystes(gui, lb) end
                end)
            elseif id == "shop" then
                afficherShop(gui)
            end
        end)
    end

    -- Onglet par défaut
    gui.tabBtns["classement"].TextColor3 = C.VERT
end

-- ============================================================
-- INITIALISATION
-- ============================================================
local gui = creerGUI()
setupOnglets(gui)

-- Demander les données initiales
task.spawn(function()
    task.wait(1.5)
    local jeux = rfClassement:InvokeServer()
    if jeux and #jeux > 0 then
        donneesActuelles = jeux
        afficherClassement(gui, jeux)
        afficherVote(gui, jeux)
    end
end)

-- ============================================================
-- REMOTE EVENTS — RÉCEPTION
-- ============================================================

-- Nouveau classement
remotes.MiseAJourClassement.OnClientEvent:Connect(function(jeux)
    donneesActuelles = jeux
    afficherClassement(gui, jeux)
    if ongletActif == "vote" then
        afficherVote(gui, jeux)
    end
end)

-- Nouveau leaderboard
remotes.MiseAJourLeaderboard.OnClientEvent:Connect(function(lb)
    if ongletActif == "top" then
        afficherTopAnalystes(gui, lb)
    end
end)

-- Notification toast
remotes.Notification.OnClientEvent:Connect(function(data)
    afficherToast(gui, data.message or "OK", data.type or "info")
end)

-- Analyst Pro débloqué
remotes.AppliquerAnalystPro.OnClientEvent:Connect(function()
    analyistProActif = true
    if ongletActif == "shop" then
        afficherShop(gui)
    end
    afficherToast(gui, "💎 Analyst Pro activé ! Stats débloquées.", "boost")
end)
