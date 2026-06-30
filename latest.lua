--[[
    ============================================================
    ALLUMINIUM UI LIBRARY
    ============================================================
    Biblioteca de UI minimalista para Roblox.
    Loading screen compacto + Janela com abas + componentes prontos.

    NOVIDADES DESTA VERSÃO:
        - Anti-duplicação real: se o script for re-executado (loadstring
          de novo), a instância anterior é destruída automaticamente
          (GUIs, conexões de input, partículas) antes de criar a nova.
        - Partículas brancas também na janela principal (não só no loading).
        - Botão de Unload na TopBar (ao lado do botão de fechar), que
          chama Library:Unload() diretamente.
        - Window:Unload() disponível como atalho que chama Library:Unload().

    COMO USAR (LocalScript):

        local Alluminium = loadstring(game:HttpGet("URL_RAW_DO_ARQUIVO"))()
        -- ou, se for um ModuleScript: local Alluminium = require(path.to.module)

        local Window = Alluminium:CreateWindow({
            Title = "Meu Hub",
            Icon = "rbxassetid://0",        -- opcional
            ToggleKey = Enum.KeyCode.RightShift,
            MinimizeKey = Enum.KeyCode.RightControl,
            Size = {X = 560, Y = 360},      -- opcional
            LoadingEnabled = true,          -- opcional
            LoadingDuration = 1.8,          -- opcional
        })

        local Home = Window:CreateTab("Home")
        Home:CreateLabel("SEÇÃO")
        Home:CreateButton({ Text = "Clique aqui", Callback = function() print("clicado") end })
        Home:CreateToggle({ Text = "Som", Default = true, Callback = function(v) print(v) end })
        Home:CreateSlider({ Text = "Volume", Min = 0, Max = 100, Default = 50, Callback = function(v) end })
        Home:CreateColorPicker({ Text = "Cor", Default = Color3.new(1,1,1), Callback = function(c) end })
        Home:CreateKeybind({ Text = "Atalho X", Default = Enum.KeyCode.E, Callback = function(key) end })

        Window:Notify({ Title = "Pronto!", Content = "Menu carregado.", Duration = 3 })

        -- Para descarregar a lib inteira (todas as janelas, conexões e partículas):
        Alluminium:Unload()

    Veja o arquivo Example.lua para um exemplo completo de uso.
    ============================================================
]]
print("v1.0.6")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------
-- ANTI-DUPLICAÇÃO GLOBAL
-- Se a lib já tiver sido carregada antes (outro loadstring na mesma
-- sessão), descarrega a instância anterior por completo antes de
-- continuar, evitando GUIs duplicadas, conexões de input acumuladas
-- e loops de partículas "fantasmas".
------------------------------------------------------------
if _G.__AlluminiumUnload then
	pcall(_G.__AlluminiumUnload)
	_G.__AlluminiumUnload = nil
end

local Library = {}
Library.Theme = {
	Background    = Color3.fromRGB(15, 15, 18),
	Surface       = Color3.fromRGB(22, 22, 26),
	SurfaceLight  = Color3.fromRGB(30, 30, 35),
	Accent        = Color3.fromRGB(255, 255, 255),
	TextPrimary   = Color3.fromRGB(245, 245, 245),
	TextSecondary = Color3.fromRGB(150, 150, 155),
	Stroke        = Color3.fromRGB(45, 45, 50),
	Toggle_On     = Color3.fromRGB(255, 255, 255),
	Toggle_Off    = Color3.fromRGB(50, 50, 55),
}

-- Janelas ativas e conexões de input rastreadas, para que Library:Unload()
-- consiga limpar tudo de uma vez.
Library.Windows = {}
local Connections = {}

local function track(connection)
	table.insert(Connections, connection)
	return connection
end

------------------------------------------------------------
-- UTIL
------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function tween(obj, props, time, style, dir)
	local info = TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function mergeTheme(custom)
	local result = {}
	for k, v in pairs(Library.Theme) do
		result[k] = v
	end
	if custom then
		for k, v in pairs(custom) do
			result[k] = v
		end
	end
	return result
end

-- Spawna uma partícula branca caindo dentro de "parent". Reutilizada tanto
-- pela loading screen quanto pela janela principal.
local function spawnParticle(parent, zindex, alphaRange)
	alphaRange = alphaRange or {20, 70}
	local dot = Instance.new("Frame")
	local size = math.random(2, 4)
	dot.Size = UDim2.fromOffset(size, size)
	dot.Position = UDim2.fromScale(math.random(0, 1000) / 1000, -0.05)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BackgroundTransparency = 1 - (math.random(alphaRange[1], alphaRange[2]) / 100)
	dot.BorderSizePixel = 0
	dot.ZIndex = zindex or 1
	dot.Parent = parent
	corner(dot, size)

	local fallTime = math.random(40, 90) / 10
	local t = TweenService:Create(dot, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
		Position = UDim2.fromScale(dot.Position.X.Scale, 1.05)
	})
	t:Play()
	t.Completed:Connect(function()
		dot:Destroy()
	end)
end

------------------------------------------------------------
-- LIBRARY:UNLOAD
-- Destroi todas as janelas criadas, para todos os loops de partículas
-- e desconecta todas as conexões de UserInputService rastreadas.
------------------------------------------------------------
function Library:Unload()
	for _, win in ipairs(Library.Windows) do
		pcall(function()
			if win.StopParticles then
				win.StopParticles()
			end
			if win.ScreenGui then
				win.ScreenGui:Destroy()
			end
		end)
	end
	Library.Windows = {}

	for _, conn in ipairs(Connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	Connections = {}

	-- Segurança extra: remove qualquer ScreenGui órfã da lib que ainda
	-- esteja no PlayerGui.
	for _, g in ipairs(PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and string.match(g.Name, "^Alluminium_") then
			g:Destroy()
		end
	end
end

------------------------------------------------------------
-- LOADING SCREEN (compacto, centralizado)
------------------------------------------------------------
local function playLoadingScreen(screenGui, theme, title, duration)
	local LoadingScreen = Instance.new("Frame")
	LoadingScreen.Name = "LoadingScreen"
	LoadingScreen.Size = UDim2.fromScale(1, 1)
	LoadingScreen.BackgroundColor3 = theme.Background
	LoadingScreen.BorderSizePixel = 0
	LoadingScreen.ZIndex = 50
	LoadingScreen.Parent = screenGui

	local ParticleHolder = Instance.new("Frame")
	ParticleHolder.Name = "Particles"
	ParticleHolder.Size = UDim2.fromScale(1, 1)
	ParticleHolder.BackgroundTransparency = 1
	ParticleHolder.ClipsDescendants = true
	ParticleHolder.ZIndex = 51
	ParticleHolder.Parent = LoadingScreen

	local LoadingCard = Instance.new("Frame")
	LoadingCard.Name = "LoadingCard"
	LoadingCard.AnchorPoint = Vector2.new(0.5, 0.5)
	LoadingCard.Position = UDim2.fromScale(0.5, 0.5)
	LoadingCard.Size = UDim2.fromOffset(230, 0)
	LoadingCard.BackgroundColor3 = theme.Surface
	LoadingCard.BackgroundTransparency = 1
	LoadingCard.BorderSizePixel = 0
	LoadingCard.ClipsDescendants = true
	LoadingCard.ZIndex = 52
	LoadingCard.Parent = LoadingScreen
	corner(LoadingCard, 14)
	local LoadingCardStroke = stroke(LoadingCard, theme.Stroke, 1)
	LoadingCardStroke.Transparency = 1

	local LogoLabel = Instance.new("TextLabel")
	LogoLabel.AnchorPoint = Vector2.new(0.5, 0)
	LogoLabel.Position = UDim2.new(0.5, 0, 0, 22)
	LogoLabel.Size = UDim2.new(1, -20, 0, 26)
	LogoLabel.BackgroundTransparency = 1
	LogoLabel.Font = Enum.Font.GothamBlack
	LogoLabel.Text = string.upper(title)
	LogoLabel.TextColor3 = theme.TextPrimary
	LogoLabel.TextSize = 18
	LogoLabel.TextTransparency = 1
	LogoLabel.ZIndex = 53
	LogoLabel.Parent = LoadingCard

	local SubLabel = Instance.new("TextLabel")
	SubLabel.AnchorPoint = Vector2.new(0.5, 0)
	SubLabel.Position = UDim2.new(0.5, 0, 0, 48)
	SubLabel.Size = UDim2.new(1, -20, 0, 16)
	SubLabel.BackgroundTransparency = 1
	SubLabel.Font = Enum.Font.Gotham
	SubLabel.Text = "carregando..."
	SubLabel.TextColor3 = theme.TextSecondary
	SubLabel.TextSize = 11
	SubLabel.TextTransparency = 1
	SubLabel.ZIndex = 53
	SubLabel.Parent = LoadingCard

	local BarBack = Instance.new("Frame")
	BarBack.AnchorPoint = Vector2.new(0.5, 0)
	BarBack.Position = UDim2.new(0.5, 0, 0, 78)
	BarBack.Size = UDim2.new(1, -40, 0, 4)
	BarBack.BackgroundColor3 = theme.SurfaceLight
	BarBack.BorderSizePixel = 0
	BarBack.BackgroundTransparency = 1
	BarBack.ZIndex = 53
	BarBack.Parent = LoadingCard
	corner(BarBack, 2)

	local BarFill = Instance.new("Frame")
	BarFill.Size = UDim2.new(0, 0, 1, 0)
	BarFill.BackgroundColor3 = theme.Accent
	BarFill.BorderSizePixel = 0
	BarFill.ZIndex = 54
	BarFill.Parent = BarBack
	corner(BarFill, 2)

	local particlesRunning = true
	task.spawn(function()
		while particlesRunning do
			spawnParticle(ParticleHolder, 51)
			task.wait(0.08)
		end
	end)

	tween(LoadingCard, {Size = UDim2.fromOffset(230, 100), BackgroundTransparency = 0}, 0.4, Enum.EasingStyle.Quint)
	tween(LoadingCardStroke, {Transparency = 0}, 0.4)
	task.wait(0.15)
	tween(LogoLabel, {TextTransparency = 0}, 0.4)
	task.wait(0.1)
	tween(SubLabel, {TextTransparency = 0}, 0.4)
	tween(BarBack, {BackgroundTransparency = 0}, 0.3)
	tween(BarFill, {Size = UDim2.new(1, 0, 1, 0)}, math.max(duration - 0.3, 0.3), Enum.EasingStyle.Quad)

	task.wait(duration)

	tween(LogoLabel, {TextTransparency = 1}, 0.3)
	tween(SubLabel, {TextTransparency = 1}, 0.3)
	tween(BarBack, {BackgroundTransparency = 1}, 0.3)
	tween(BarFill, {BackgroundTransparency = 1}, 0.3)
	tween(LoadingCardStroke, {Transparency = 1}, 0.3)
	tween(LoadingCard, {BackgroundTransparency = 1, Size = UDim2.fromOffset(230, 70)}, 0.35)
	tween(LoadingScreen, {BackgroundTransparency = 1}, 0.5)

	task.wait(0.55)
	particlesRunning = false
	LoadingScreen:Destroy()
end

------------------------------------------------------------
-- CREATE WINDOW
------------------------------------------------------------
function Library:CreateWindow(config)
	config = config or {}
	local theme       = mergeTheme(config.Theme)
	local title        = config.Title or "Alluminium"
	local iconId        = config.Icon or "rbxassetid://0"
	local toggleKey     = config.ToggleKey or Enum.KeyCode.RightShift
	local minimizeKey   = config.MinimizeKey or Enum.KeyCode.RightControl
	local sidebarWidth  = config.SidebarWidth or 140
	local winWidth      = (config.Size and config.Size.X) or 560
	local winHeight     = (config.Size and config.Size.Y) or 360
	local loadingOn     = config.LoadingEnabled
	if loadingOn == nil then loadingOn = true end
	local loadingTime   = config.LoadingDuration or 1.8

	-- evita duplicar a GUI se CreateWindow for chamado de novo com o mesmo título
	local existing = PlayerGui:FindFirstChild("Alluminium_" .. title)
	if existing then
		existing:Destroy()
	end

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "Alluminium_" .. title
	ScreenGui.ResetOnSpawn = false
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.DisplayOrder = 999
	ScreenGui.Parent = PlayerGui

	if loadingOn then
		playLoadingScreen(ScreenGui, theme, title, loadingTime)
	end

	------------------------------------------------------------
	-- MAIN FRAME
	------------------------------------------------------------
	local Main = Instance.new("Frame")
	Main.Name = "Main"
	Main.AnchorPoint = Vector2.new(0.5, 0.5)
	Main.Position = UDim2.fromScale(0.5, 0.47)
	Main.Size = UDim2.fromOffset(winWidth, 0)
	Main.BackgroundColor3 = theme.Background
	Main.BackgroundTransparency = 1
	Main.BorderSizePixel = 0
	Main.ClipsDescendants = true
	Main.Parent = ScreenGui
	corner(Main, 12)
	local MainStroke = stroke(Main, theme.Stroke, 1)

	-- Partículas brancas dentro da janela principal (mesmo estilo da loading screen)
	local MenuParticles = Instance.new("Frame")
	MenuParticles.Name = "Particles"
	MenuParticles.Size = UDim2.fromScale(1, 1)
	MenuParticles.BackgroundTransparency = 1
	MenuParticles.ZIndex = 1
	MenuParticles.Parent = Main

	local menuParticlesRunning = true
	task.spawn(function()
		while menuParticlesRunning do
			spawnParticle(MenuParticles, 1, {10, 40})
			task.wait(0.15)
		end
	end)

	------------------------------------------------------------
	-- HOTKEY LIST
	-- Painel flutuante (fora da janela principal) que lista, com
	-- animação, todas as teclas registradas pelos componentes de
	-- Keybind / KeybindToggle. Pode ser escondido/mostrado com a
	-- tecla HotkeyListKey (RightAlt por padrão).
	------------------------------------------------------------
	local hotkeyListKey = config.HotkeyListKey or Enum.KeyCode.RightAlt
	local hotkeyListEnabled = config.HotkeyListEnabled
	if hotkeyListEnabled == nil then hotkeyListEnabled = true end
	local hotkeyListCorner = config.HotkeyListPosition or "BottomLeft" -- BottomLeft, BottomRight, TopLeft, TopRight

	local hotkeyAnchor = Vector2.new(0, 1)
	local hotkeyPos = UDim2.new(0, 16, 1, -16)
	local hotkeyAlign = Enum.HorizontalAlignment.Left
	local hotkeyFromRight = false
	if hotkeyListCorner == "BottomRight" then
		hotkeyAnchor, hotkeyPos, hotkeyAlign, hotkeyFromRight = Vector2.new(1, 1), UDim2.new(1, -16, 1, -16), Enum.HorizontalAlignment.Right, true
	elseif hotkeyListCorner == "TopLeft" then
		hotkeyAnchor, hotkeyPos, hotkeyAlign = Vector2.new(0, 0), UDim2.new(0, 16, 0, 16), Enum.HorizontalAlignment.Left
	elseif hotkeyListCorner == "TopRight" then
		hotkeyAnchor, hotkeyPos, hotkeyAlign, hotkeyFromRight = Vector2.new(1, 0), UDim2.new(1, -16, 0, 16), Enum.HorizontalAlignment.Right, true
	end

	local HotkeyListGui = Instance.new("CanvasGroup")
	HotkeyListGui.Name = "HotkeyList"
	HotkeyListGui.BackgroundTransparency = 1
	HotkeyListGui.GroupTransparency = 0
	HotkeyListGui.AnchorPoint = hotkeyAnchor
	HotkeyListGui.Position = hotkeyPos
	HotkeyListGui.Size = UDim2.fromOffset(220, 0)
	HotkeyListGui.AutomaticSize = Enum.AutomaticSize.Y
	HotkeyListGui.Visible = hotkeyListEnabled
	HotkeyListGui.ZIndex = 30
	HotkeyListGui.Parent = ScreenGui

	local hotkeyListLayout = Instance.new("UIListLayout")
	hotkeyListLayout.Padding = UDim.new(0, 6)
	hotkeyListLayout.HorizontalAlignment = hotkeyAlign
	hotkeyListLayout.VerticalAlignment = string.match(hotkeyListCorner, "^Bottom") and Enum.VerticalAlignment.Bottom or Enum.VerticalAlignment.Top
	hotkeyListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotkeyListLayout.Parent = HotkeyListGui

	local HotkeyList = {}
	local hotkeyEntryCount = 0

	function HotkeyList:AddEntry(name, keyText, modeText)
		hotkeyEntryCount = hotkeyEntryCount + 1
		local row = Instance.new("Frame")
		row.AutomaticSize = Enum.AutomaticSize.X
		row.Size = UDim2.fromOffset(0, 26)
		row.BackgroundColor3 = theme.Surface
		row.LayoutOrder = hotkeyEntryCount
		row.ZIndex = 30
		row.Parent = HotkeyListGui
		corner(row, 6)
		stroke(row, theme.Stroke, 1)

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = row

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Padding = UDim.new(0, 6)
		rowList.Parent = row

		local modeLabel = Instance.new("TextLabel")
		modeLabel.AutomaticSize = Enum.AutomaticSize.X
		modeLabel.Size = UDim2.fromOffset(0, 26)
		modeLabel.BackgroundTransparency = 1
		modeLabel.Font = Enum.Font.GothamBold
		modeLabel.Text = modeText and string.upper(modeText) or ""
		modeLabel.TextColor3 = theme.TextSecondary
		modeLabel.TextSize = 10
		modeLabel.ZIndex = 30
		modeLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.AutomaticSize = Enum.AutomaticSize.X
		nameLabel.Size = UDim2.fromOffset(0, 26)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.Text = name
		nameLabel.TextColor3 = theme.TextSecondary
		nameLabel.TextSize = 12
		nameLabel.ZIndex = 30
		nameLabel.Parent = row

		local keyLabel = Instance.new("TextLabel")
		keyLabel.AutomaticSize = Enum.AutomaticSize.X
		keyLabel.Size = UDim2.fromOffset(0, 26)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.Text = "[" .. (keyText or "?") .. "]"
		keyLabel.TextColor3 = theme.TextPrimary
		keyLabel.TextSize = 12
		keyLabel.ZIndex = 30
		keyLabel.Parent = row

		-- animação de entrada: desliza + aparece
		local slideFrom = hotkeyFromRight and 30 or -30
		row.Position = UDim2.fromOffset(slideFrom, 0)
		row.BackgroundTransparency = 1
		tween(row, {BackgroundTransparency = 0, Position = UDim2.fromOffset(0, 0)}, 0.3, Enum.EasingStyle.Quint)

		local entry = {}

		function entry:SetKey(text)
			keyLabel.Text = "[" .. text .. "]"
			tween(keyLabel, {TextColor3 = theme.Accent}, 0.1)
			task.delay(0.2, function()
				tween(keyLabel, {TextColor3 = theme.TextPrimary}, 0.3)
			end)
		end

		function entry:SetMode(text)
			modeLabel.Text = text and string.upper(text) or ""
		end

		function entry:Destroy()
			local slideTo = hotkeyFromRight and 30 or -30
			local outT = tween(row, {BackgroundTransparency = 1, Position = UDim2.fromOffset(slideTo, 0)}, 0.2)
			outT.Completed:Connect(function()
				row:Destroy()
			end)
		end

		return entry
	end

	local hotkeyListVisible = hotkeyListEnabled
	local function setHotkeyListVisible(state)
		hotkeyListVisible = state
		HotkeyListGui.Visible = true
		if state then
			tween(HotkeyListGui, {GroupTransparency = 0, Position = hotkeyPos}, 0.25, Enum.EasingStyle.Quint)
		else
			local offset = hotkeyFromRight and 40 or -40
			local slidePos = UDim2.new(hotkeyPos.X.Scale, hotkeyPos.X.Offset + offset, hotkeyPos.Y.Scale, hotkeyPos.Y.Offset)
			local t = tween(HotkeyListGui, {GroupTransparency = 1, Position = slidePos}, 0.25, Enum.EasingStyle.Quint)
			t.Completed:Connect(function()
				if not hotkeyListVisible then
					HotkeyListGui.Visible = false
				end
			end)
		end
	end

	track(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == hotkeyListKey then
			setHotkeyListVisible(not hotkeyListVisible)
		end
	end))

	------------------------------------------------------------
	-- MENU DE CONTEXTO (clique direito) — usado pelo KeybindToggle
	-- para escolher o modo: Always, Hold, Toggle.
	------------------------------------------------------------
	local activeContextMenu = nil

	local function closeContextMenu()
		if activeContextMenu then
			local menu = activeContextMenu
			activeContextMenu = nil
			local t = tween(menu, {BackgroundTransparency = 1}, 0.12)
			for _, c in ipairs(menu:GetDescendants()) do
				if c:IsA("TextButton") or c:IsA("TextLabel") then
					tween(c, {TextTransparency = 1}, 0.12)
				end
			end
			t.Completed:Connect(function()
				menu:Destroy()
			end)
		end
	end

	local function openModeMenu(anchorButton, currentMode, onSelect)
		closeContextMenu()

		local menu = Instance.new("Frame")
		menu.Name = "ModeMenu"
		menu.Size = UDim2.fromOffset(110, 0)
		menu.AutomaticSize = Enum.AutomaticSize.Y
		menu.BackgroundColor3 = theme.SurfaceLight
		menu.BackgroundTransparency = 1
		menu.ZIndex = 40
		menu.Parent = ScreenGui
		corner(menu, 8)
		stroke(menu, theme.Stroke, 1)

		local absPos = anchorButton.AbsolutePosition
		local absSize = anchorButton.AbsoluteSize
		menu.Position = UDim2.fromOffset(absPos.X - 54, absPos.Y + absSize.Y + 4)

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 4)
		pad.Parent = menu

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 2)
		list.Parent = menu

		for _, optName in ipairs({"Always", "Hold", "Toggle"}) do
			local isCurrent = optName == currentMode
			local optBtn = Instance.new("TextButton")
			optBtn.Size = UDim2.new(1, 0, 0, 28)
			optBtn.BackgroundColor3 = theme.Surface
			optBtn.BackgroundTransparency = isCurrent and 0 or 1
			optBtn.AutoButtonColor = false
			optBtn.Font = isCurrent and Enum.Font.GothamBold or Enum.Font.Gotham
			optBtn.Text = optName
			optBtn.TextColor3 = isCurrent and theme.TextPrimary or theme.TextSecondary
			optBtn.TextSize = 12
			optBtn.ZIndex = 41
			optBtn.Parent = menu
			corner(optBtn, 6)

			optBtn.MouseEnter:Connect(function()
				tween(optBtn, {BackgroundColor3 = theme.SurfaceLight, BackgroundTransparency = 0}, 0.12)
			end)
			optBtn.MouseLeave:Connect(function()
				if optName == currentMode then
					tween(optBtn, {BackgroundColor3 = theme.Surface}, 0.12)
				else
					tween(optBtn, {BackgroundTransparency = 1}, 0.12)
				end
			end)
			optBtn.MouseButton1Click:Connect(function()
				onSelect(optName)
				closeContextMenu()
			end)
		end

		activeContextMenu = menu
		tween(menu, {BackgroundTransparency = 0}, 0.15)

		task.defer(function()
			local conn
			conn = track(UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if not menu.Parent then
						if conn then conn:Disconnect() end
						return
					end
					local mousePos = UserInputService:GetMouseLocation()
					local menuPos = menu.AbsolutePosition
					local menuSize = menu.AbsoluteSize
					if mousePos.X < menuPos.X or mousePos.X > menuPos.X + menuSize.X or mousePos.Y < menuPos.Y or mousePos.Y > menuPos.Y + menuSize.Y then
						closeContextMenu()
						if conn then conn:Disconnect() end
					end
				end
			end))
		end)
	end

	local TopBar = Instance.new("Frame")
	TopBar.Name = "TopBar"
	TopBar.Size = UDim2.new(1, 0, 0, 46)
	TopBar.BackgroundColor3 = theme.Surface
	TopBar.BorderSizePixel = 0
	TopBar.ZIndex = 2
	TopBar.Parent = Main
	corner(TopBar, 12)

	local TopBarFix = Instance.new("Frame")
	TopBarFix.Size = UDim2.new(1, 0, 0, 12)
	TopBarFix.Position = UDim2.fromOffset(0, 34)
	TopBarFix.BackgroundColor3 = theme.Surface
	TopBarFix.BorderSizePixel = 0
	TopBarFix.ZIndex = 2
	TopBarFix.Parent = TopBar

	local TitleIcon = Instance.new("ImageLabel")
	TitleIcon.Size = UDim2.fromOffset(18, 18)
	TitleIcon.Position = UDim2.new(0, 14, 0.5, -9)
	TitleIcon.BackgroundTransparency = 1
	TitleIcon.Image = iconId
	TitleIcon.ScaleType = Enum.ScaleType.Fit
	TitleIcon.ZIndex = 3
	TitleIcon.Parent = TopBar

	local TitleLabel = Instance.new("TextLabel")
	TitleLabel.Size = UDim2.new(1, -165, 1, 0)
	TitleLabel.Position = UDim2.fromOffset(40, 0)
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Font = Enum.Font.GothamBold
	TitleLabel.Text = title
	TitleLabel.TextColor3 = theme.TextPrimary
	TitleLabel.TextSize = 16
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.ZIndex = 3
	TitleLabel.Parent = TopBar

	-- Botão de Unload: chama Library:Unload() diretamente
	local UnloadBtn = Instance.new("TextButton")
	UnloadBtn.Name = "UnloadButton"
	UnloadBtn.Size = UDim2.fromOffset(28, 28)
	UnloadBtn.Position = UDim2.new(1, -72, 0.5, -14)
	UnloadBtn.BackgroundColor3 = theme.SurfaceLight
	UnloadBtn.Text = "⏻"
	UnloadBtn.Font = Enum.Font.GothamBold
	UnloadBtn.TextSize = 14
	UnloadBtn.TextColor3 = theme.TextSecondary
	UnloadBtn.AutoButtonColor = false
	UnloadBtn.ZIndex = 3
	UnloadBtn.Parent = TopBar
	corner(UnloadBtn, 6)

	UnloadBtn.MouseEnter:Connect(function()
		tween(UnloadBtn, {BackgroundColor3 = Color3.fromRGB(60, 45, 20)}, 0.15)
		tween(UnloadBtn, {TextColor3 = Color3.fromRGB(255, 190, 110)}, 0.15)
	end)
	UnloadBtn.MouseLeave:Connect(function()
		tween(UnloadBtn, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
		tween(UnloadBtn, {TextColor3 = theme.TextSecondary}, 0.15)
	end)
	UnloadBtn.MouseButton1Click:Connect(function()
		Library:Unload()
	end)

	local CloseBtn = Instance.new("TextButton")
	CloseBtn.Size = UDim2.fromOffset(28, 28)
	CloseBtn.Position = UDim2.new(1, -38, 0.5, -14)
	CloseBtn.BackgroundColor3 = theme.SurfaceLight
	CloseBtn.Text = "×"
	CloseBtn.Font = Enum.Font.GothamBold
	CloseBtn.TextSize = 18
	CloseBtn.TextColor3 = theme.TextSecondary
	CloseBtn.AutoButtonColor = false
	CloseBtn.ZIndex = 3
	CloseBtn.Parent = TopBar
	corner(CloseBtn, 6)

	CloseBtn.MouseEnter:Connect(function()
		tween(CloseBtn, {BackgroundColor3 = Color3.fromRGB(60, 30, 30)}, 0.15)
		tween(CloseBtn, {TextColor3 = Color3.fromRGB(255, 120, 120)}, 0.15)
	end)
	CloseBtn.MouseLeave:Connect(function()
		tween(CloseBtn, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
		tween(CloseBtn, {TextColor3 = theme.TextSecondary}, 0.15)
	end)

	local Sidebar = Instance.new("Frame")
	Sidebar.Name = "Sidebar"
	Sidebar.Size = UDim2.new(0, sidebarWidth, 1, -46)
	Sidebar.Position = UDim2.fromOffset(0, 46)
	Sidebar.BackgroundColor3 = theme.Surface
	Sidebar.BorderSizePixel = 0
	Sidebar.ZIndex = 2
	Sidebar.Parent = Main

	local SidebarList = Instance.new("UIListLayout")
	SidebarList.Padding = UDim.new(0, 4)
	SidebarList.Parent = Sidebar

	local SidebarPad = Instance.new("UIPadding")
	SidebarPad.PaddingTop = UDim.new(0, 10)
	SidebarPad.PaddingLeft = UDim.new(0, 8)
	SidebarPad.PaddingRight = UDim.new(0, 8)
	SidebarPad.Parent = Sidebar

	local ContentArea = Instance.new("Frame")
	ContentArea.Name = "ContentArea"
	ContentArea.Size = UDim2.new(1, -sidebarWidth, 1, -46)
	ContentArea.Position = UDim2.fromOffset(sidebarWidth, 46)
	ContentArea.BackgroundTransparency = 1
	ContentArea.ZIndex = 2
	ContentArea.Parent = Main

	------------------------------------------------------------
	-- TAB SYSTEM (estado interno da janela)
	------------------------------------------------------------
	local Tabs = {}
	local TabButtons = {}
	local currentTab = nil

	local function selectTab(name)
		if currentTab == name then return end
		currentTab = name
		for tname, page in pairs(Tabs) do
			local active = tname == name
			page.Visible = active
			local ref = TabButtons[tname]
			if active then
				tween(ref.Button, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
				tween(ref.Indicator, {BackgroundTransparency = 0}, 0.15)
				tween(ref.Label, {TextColor3 = theme.TextPrimary}, 0.15)
			else
				tween(ref.Button, {BackgroundColor3 = theme.Surface}, 0.15)
				tween(ref.Indicator, {BackgroundTransparency = 1}, 0.15)
				tween(ref.Label, {TextColor3 = theme.TextSecondary}, 0.15)
			end
		end
	end

	------------------------------------------------------------
	-- COMPONENTES (compartilhados por todas as abas desta janela)
	------------------------------------------------------------
	local function createSectionLabel(parent, text)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 20)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = text
		lbl.TextColor3 = theme.TextSecondary
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = parent
		return lbl
	end

	local function createParagraph(parent, titleText, contentText)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = theme.Surface
		card.Parent = parent
		corner(card, 8)

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = card

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 4)
		list.Parent = card

		if titleText then
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(1, 0, 0, 18)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBold
			t.Text = titleText
			t.TextColor3 = theme.TextPrimary
			t.TextSize = 13
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.Parent = card
		end

		local c = Instance.new("TextLabel")
		c.Size = UDim2.new(1, 0, 0, 0)
		c.AutomaticSize = Enum.AutomaticSize.Y
		c.BackgroundTransparency = 1
		c.Font = Enum.Font.Gotham
		c.Text = contentText or ""
		c.TextColor3 = theme.TextSecondary
		c.TextSize = 12
		c.TextWrapped = true
		c.TextXAlignment = Enum.TextXAlignment.Left
		c.Parent = card

		return card
	end

	local function createButton(parent, text, callback)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 36)
		btn.BackgroundColor3 = theme.Surface
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamMedium
		btn.Text = text
		btn.TextColor3 = theme.TextPrimary
		btn.TextSize = 13
		btn.Parent = parent
		corner(btn, 8)

		btn.MouseEnter:Connect(function()
			tween(btn, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
		end)
		btn.MouseLeave:Connect(function()
			tween(btn, {BackgroundColor3 = theme.Surface}, 0.15)
		end)
		btn.MouseButton1Click:Connect(function()
			if callback then task.spawn(callback) end
		end)

		return btn
	end

	local function createToggle(parent, text, default, callback)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 38)
		holder.BackgroundColor3 = theme.Surface
		holder.Parent = parent
		corner(holder, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -70, 1, 0)
		label.Position = UDim2.fromOffset(14, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = text
		label.TextColor3 = theme.TextPrimary
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local switchBack = Instance.new("Frame")
		switchBack.Size = UDim2.fromOffset(40, 20)
		switchBack.AnchorPoint = Vector2.new(1, 0.5)
		switchBack.Position = UDim2.new(1, -14, 0.5, 0)
		switchBack.BackgroundColor3 = default and theme.Toggle_On or theme.Toggle_Off
		switchBack.Parent = holder
		corner(switchBack, 10)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(16, 16)
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Position = default and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		knob.BackgroundColor3 = default and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(230, 230, 230)
		knob.Parent = switchBack
		corner(knob, 8)

		local state = default or false

		local clickBtn = Instance.new("TextButton")
		clickBtn.Size = UDim2.fromScale(1, 1)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.Parent = holder

		clickBtn.MouseButton1Click:Connect(function()
			state = not state
			if state then
				tween(switchBack, {BackgroundColor3 = theme.Toggle_On}, 0.18)
				tween(knob, {Position = UDim2.new(1, -18, 0.5, 0), BackgroundColor3 = Color3.fromRGB(20, 20, 20)}, 0.18)
			else
				tween(switchBack, {BackgroundColor3 = theme.Toggle_Off}, 0.18)
				tween(knob, {Position = UDim2.new(0, 2, 0.5, 0), BackgroundColor3 = Color3.fromRGB(230, 230, 230)}, 0.18)
			end
			if callback then
				task.spawn(callback, state)
			end
		end)

		return holder
	end

	local function createSlider(parent, text, min, max, default, callback)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 50)
		holder.BackgroundColor3 = theme.Surface
		holder.Parent = parent
		corner(holder, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -60, 0, 30)
		label.Position = UDim2.fromOffset(14, 4)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = text
		label.TextColor3 = theme.TextPrimary
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.fromOffset(50, 30)
		valueLabel.Position = UDim2.new(1, -60, 0, 4)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.Text = tostring(default)
		valueLabel.TextColor3 = theme.TextSecondary
		valueLabel.TextSize = 13
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = holder

		local barBack = Instance.new("Frame")
		barBack.Size = UDim2.new(1, -28, 0, 4)
		barBack.Position = UDim2.fromOffset(14, 36)
		barBack.BackgroundColor3 = theme.SurfaceLight
		barBack.Parent = holder
		corner(barBack, 2)

		local barFill = Instance.new("Frame")
		local pct = (default - min) / (max - min)
		barFill.Size = UDim2.new(pct, 0, 1, 0)
		barFill.BackgroundColor3 = theme.Accent
		barFill.Parent = barBack
		corner(barFill, 2)

		local dragging = false

		local function setFromX(x)
			local rel = math.clamp((x - barBack.AbsolutePosition.X) / barBack.AbsoluteSize.X, 0, 1)
			local value = math.floor(min + (max - min) * rel)
			barFill.Size = UDim2.new(rel, 0, 1, 0)
			valueLabel.Text = tostring(value)
			if callback then
				task.spawn(callback, value)
			end
		end

		barBack.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		track(UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				setFromX(input.Position.X)
			end
		end))
		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))

		return holder
	end

	local function createColorPicker(parent, text, default, callback)
		default = default or Color3.fromRGB(255, 255, 255)
		local collapsedHeight = 38
		local expandedHeight = 150

		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, collapsedHeight)
		holder.BackgroundColor3 = theme.Surface
		holder.ClipsDescendants = true
		holder.Parent = parent
		corner(holder, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -70, 0, collapsedHeight)
		label.Position = UDim2.fromOffset(14, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = text
		label.TextColor3 = theme.TextPrimary
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(22, 22)
		swatch.AnchorPoint = Vector2.new(1, 0.5)
		swatch.Position = UDim2.new(1, -14, 0, collapsedHeight / 2)
		swatch.BackgroundColor3 = default
		swatch.Parent = holder
		corner(swatch, 6)
		stroke(swatch, theme.Stroke, 1)

		local openBtn = Instance.new("TextButton")
		openBtn.Size = UDim2.new(1, 0, 0, collapsedHeight)
		openBtn.BackgroundTransparency = 1
		openBtn.Text = ""
		openBtn.ZIndex = 2
		openBtn.Parent = holder

		local panel = Instance.new("Frame")
		panel.Position = UDim2.fromOffset(0, collapsedHeight)
		panel.Size = UDim2.new(1, 0, 0, expandedHeight - collapsedHeight)
		panel.BackgroundTransparency = 1
		panel.Visible = false
		panel.Parent = holder

		local panelPad = Instance.new("UIPadding")
		panelPad.PaddingLeft = UDim.new(0, 14)
		panelPad.PaddingRight = UDim.new(0, 14)
		panelPad.PaddingTop = UDim.new(0, 6)
		panelPad.Parent = panel

		local panelList = Instance.new("UIListLayout")
		panelList.Padding = UDim.new(0, 8)
		panelList.Parent = panel

		local r, g, b = math.floor(default.R * 255), math.floor(default.G * 255), math.floor(default.B * 255)

		local function updateColor()
			local color = Color3.fromRGB(r, g, b)
			swatch.BackgroundColor3 = color
			if callback then
				task.spawn(callback, color)
			end
		end

		local function miniSlider(channelName, startValue, trackColor, onChange)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.Parent = panel

			local chLabel = Instance.new("TextLabel")
			chLabel.Size = UDim2.fromOffset(16, 28)
			chLabel.BackgroundTransparency = 1
			chLabel.Font = Enum.Font.GothamBold
			chLabel.Text = channelName
			chLabel.TextColor3 = trackColor
			chLabel.TextSize = 12
			chLabel.Parent = row

			local valLabel = Instance.new("TextLabel")
			valLabel.Size = UDim2.fromOffset(30, 28)
			valLabel.AnchorPoint = Vector2.new(1, 0)
			valLabel.Position = UDim2.new(1, 0, 0, 0)
			valLabel.BackgroundTransparency = 1
			valLabel.Font = Enum.Font.GothamBold
			valLabel.Text = tostring(startValue)
			valLabel.TextColor3 = theme.TextSecondary
			valLabel.TextSize = 12
			valLabel.TextXAlignment = Enum.TextXAlignment.Right
			valLabel.Parent = row

			local trackBack = Instance.new("Frame")
			trackBack.Size = UDim2.new(1, -56, 0, 4)
			trackBack.Position = UDim2.fromOffset(22, 12)
			trackBack.BackgroundColor3 = theme.SurfaceLight
			trackBack.Parent = row
			corner(trackBack, 2)

			local trackFill = Instance.new("Frame")
			trackFill.Size = UDim2.new(startValue / 255, 0, 1, 0)
			trackFill.BackgroundColor3 = trackColor
			trackFill.Parent = trackBack
			corner(trackFill, 2)

			local dragging = false
			local function setFromX(x)
				local rel = math.clamp((x - trackBack.AbsolutePosition.X) / trackBack.AbsoluteSize.X, 0, 1)
				local value = math.floor(255 * rel)
				trackFill.Size = UDim2.new(rel, 0, 1, 0)
				valLabel.Text = tostring(value)
				onChange(value)
				updateColor()
			end

			trackBack.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					setFromX(input.Position.X)
				end
			end)
			track(UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					setFromX(input.Position.X)
				end
			end))
			track(UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end))
		end

		miniSlider("R", r, Color3.fromRGB(255, 90, 90), function(v) r = v end)
		miniSlider("G", g, Color3.fromRGB(90, 255, 110), function(v) g = v end)
		miniSlider("B", b, Color3.fromRGB(110, 150, 255), function(v) b = v end)

		local opened = false
		openBtn.MouseButton1Click:Connect(function()
			opened = not opened
			if opened then
				panel.Visible = true
				tween(holder, {Size = UDim2.new(1, 0, 0, expandedHeight)}, 0.25, Enum.EasingStyle.Quint)
			else
				panel.Visible = false
				tween(holder, {Size = UDim2.new(1, 0, 0, collapsedHeight)}, 0.25, Enum.EasingStyle.Quint)
			end
		end)

		return holder
	end

	local function createKeybind(parent, text, default, callback, showInHotkeyList)
		if showInHotkeyList == nil then showInHotkeyList = true end

		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 38)
		holder.BackgroundColor3 = theme.Surface
		holder.Parent = parent
		corner(holder, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -90, 1, 0)
		label.Position = UDim2.fromOffset(14, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = text
		label.TextColor3 = theme.TextPrimary
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local keyBtn = Instance.new("TextButton")
		keyBtn.Size = UDim2.fromOffset(70, 24)
		keyBtn.AnchorPoint = Vector2.new(1, 0.5)
		keyBtn.Position = UDim2.new(1, -10, 0.5, 0)
		keyBtn.BackgroundColor3 = theme.SurfaceLight
		keyBtn.AutoButtonColor = false
		keyBtn.Font = Enum.Font.GothamBold
		keyBtn.Text = default.Name
		keyBtn.TextColor3 = theme.TextSecondary
		keyBtn.TextSize = 12
		keyBtn.Parent = holder
		corner(keyBtn, 6)

		local listening = false
		local currentKey = default

		local hotkeyEntry = nil
		if showInHotkeyList then
			hotkeyEntry = HotkeyList:AddEntry(text, currentKey.Name, "Press")
		end

		keyBtn.MouseButton1Click:Connect(function()
			if listening then return end
			listening = true
			keyBtn.Text = "..."
			tween(keyBtn, {BackgroundColor3 = theme.Toggle_On}, 0.15)
			tween(keyBtn, {TextColor3 = Color3.fromRGB(20, 20, 20)}, 0.15)
		end)

		track(UserInputService.InputBegan:Connect(function(input, gpe)
			if not listening then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

			listening = false
			tween(keyBtn, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
			tween(keyBtn, {TextColor3 = theme.TextSecondary}, 0.15)

			if input.KeyCode == Enum.KeyCode.Escape then
				keyBtn.Text = currentKey.Name
				return
			end

			currentKey = input.KeyCode
			keyBtn.Text = currentKey.Name
			if hotkeyEntry then hotkeyEntry:SetKey(currentKey.Name) end
			if callback then
				callback(currentKey)
			end
		end))

		return holder
	end

	-- KEYBIND TOGGLE: combina um switch (toggle) com uma tecla vinculada.
	-- Clique direito no botão da tecla abre um menu pra escolher o modo:
	--   Always  -> ignora a tecla, fica sempre ligado
	--   Hold    -> fica ligado só enquanto a tecla está pressionada
	--   Toggle  -> cada aperto da tecla alterna ligado/desligado
	-- (clicar no próprio switch também alterna, exceto em Hold/Always)
	local function createKeybindToggle(parent, opts)
		opts = opts or {}
		local text = opts.Text or "Keybind"
		local defaultKey = opts.Default or Enum.KeyCode.E
		local mode = opts.Mode or "Toggle"
		local defaultState = opts.DefaultState
		if defaultState == nil then defaultState = false end
		local callback = opts.Callback
		local modeCallback = opts.ModeCallback
		local showInHotkeyList = opts.ShowInHotkeyList
		if showInHotkeyList == nil then showInHotkeyList = true end

		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 0, 38)
		holder.BackgroundColor3 = theme.Surface
		holder.Parent = parent
		corner(holder, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -158, 1, 0)
		label.Position = UDim2.fromOffset(14, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.Text = text
		label.TextColor3 = theme.TextPrimary
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = holder

		local modeTag = Instance.new("TextLabel")
		modeTag.Size = UDim2.fromOffset(44, 18)
		modeTag.AnchorPoint = Vector2.new(1, 0.5)
		modeTag.Position = UDim2.new(1, -120, 0.5, 0)
		modeTag.BackgroundColor3 = theme.SurfaceLight
		modeTag.Font = Enum.Font.GothamBold
		modeTag.Text = string.upper(mode)
		modeTag.TextColor3 = theme.TextSecondary
		modeTag.TextSize = 9
		modeTag.Parent = holder
		corner(modeTag, 5)

		local keyBtn = Instance.new("TextButton")
		keyBtn.Size = UDim2.fromOffset(56, 24)
		keyBtn.AnchorPoint = Vector2.new(1, 0.5)
		keyBtn.Position = UDim2.new(1, -60, 0.5, 0)
		keyBtn.BackgroundColor3 = theme.SurfaceLight
		keyBtn.AutoButtonColor = false
		keyBtn.Font = Enum.Font.GothamBold
		keyBtn.Text = defaultKey.Name
		keyBtn.TextColor3 = theme.TextSecondary
		keyBtn.TextSize = 12
		keyBtn.Parent = holder
		corner(keyBtn, 6)

		local switchBack = Instance.new("Frame")
		switchBack.Size = UDim2.fromOffset(40, 20)
		switchBack.AnchorPoint = Vector2.new(1, 0.5)
		switchBack.Position = UDim2.new(1, -14, 0.5, 0)
		switchBack.BackgroundColor3 = defaultState and theme.Toggle_On or theme.Toggle_Off
		switchBack.Parent = holder
		corner(switchBack, 10)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(16, 16)
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Position = defaultState and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		knob.BackgroundColor3 = defaultState and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(230, 230, 230)
		knob.Parent = switchBack
		corner(knob, 8)

		local switchClick = Instance.new("TextButton")
		switchClick.Size = UDim2.fromScale(1, 1)
		switchClick.BackgroundTransparency = 1
		switchClick.Text = ""
		switchClick.Parent = switchBack

		local state = defaultState
		local currentKey = defaultKey
		local currentMode = mode
		local listening = false

		local hotkeyEntry = nil
		if showInHotkeyList then
			hotkeyEntry = HotkeyList:AddEntry(text, currentKey.Name, currentMode)
		end

		local function applyVisual(newState)
			state = newState
			if state then
				tween(switchBack, {BackgroundColor3 = theme.Toggle_On}, 0.18)
				tween(knob, {Position = UDim2.new(1, -18, 0.5, 0), BackgroundColor3 = Color3.fromRGB(20, 20, 20)}, 0.18)
			else
				tween(switchBack, {BackgroundColor3 = theme.Toggle_Off}, 0.18)
				tween(knob, {Position = UDim2.new(0, 2, 0.5, 0), BackgroundColor3 = Color3.fromRGB(230, 230, 230)}, 0.18)
			end
		end

		local function setState(newState, fire)
			if state == newState then return end
			applyVisual(newState)
			if fire ~= false and callback then
				task.spawn(callback, newState)
			end
		end

		local function applyMode(newMode)
			currentMode = newMode
			modeTag.Text = string.upper(newMode)
			if hotkeyEntry then hotkeyEntry:SetMode(newMode) end
			if modeCallback then task.spawn(modeCallback, newMode) end
			if newMode == "Always" then
				setState(true)
			end
		end

		switchClick.MouseButton1Click:Connect(function()
			if currentMode == "Always" or currentMode == "Hold" then return end
			setState(not state)
		end)

		keyBtn.MouseButton1Click:Connect(function()
			if listening then return end
			listening = true
			keyBtn.Text = "..."
			tween(keyBtn, {BackgroundColor3 = theme.Toggle_On}, 0.15)
			tween(keyBtn, {TextColor3 = Color3.fromRGB(20, 20, 20)}, 0.15)
		end)

		keyBtn.MouseButton2Click:Connect(function()
			openModeMenu(keyBtn, currentMode, function(selected)
				applyMode(selected)
			end)
		end)

		track(UserInputService.InputBegan:Connect(function(input, gpe)
			if listening then
				if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
				listening = false
				tween(keyBtn, {BackgroundColor3 = theme.SurfaceLight}, 0.15)
				tween(keyBtn, {TextColor3 = theme.TextSecondary}, 0.15)

				if input.KeyCode == Enum.KeyCode.Escape then
					keyBtn.Text = currentKey.Name
					return
				end

				currentKey = input.KeyCode
				keyBtn.Text = currentKey.Name
				if hotkeyEntry then hotkeyEntry:SetKey(currentKey.Name) end
				return
			end

			if gpe then return end
			if currentMode == "Always" then return end
			if input.KeyCode == currentKey then
				if currentMode == "Toggle" then
					setState(not state)
				elseif currentMode == "Hold" then
					setState(true)
				end
			end
		end))

		track(UserInputService.InputEnded:Connect(function(input)
			if currentMode ~= "Hold" then return end
			if input.KeyCode == currentKey then
				setState(false)
			end
		end))

		applyMode(currentMode)

		return holder
	end

	------------------------------------------------------------
	-- CRIAÇÃO DE ABAS
	------------------------------------------------------------
	local function createTab(name)
		local page = Instance.new("ScrollingFrame")
		page.Name = name
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = theme.SurfaceLight
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.Visible = false
		page.ZIndex = 2
		page.Parent = ContentArea

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = page

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 16)
		pad.PaddingLeft = UDim.new(0, 18)
		pad.PaddingRight = UDim.new(0, 18)
		pad.PaddingBottom = UDim.new(0, 16)
		pad.Parent = page

		Tabs[name] = page

		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(1, 0, 0, 34)
		btn.BackgroundColor3 = theme.Surface
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Parent = Sidebar
		corner(btn, 8)

		local indicator = Instance.new("Frame")
		indicator.Size = UDim2.new(0, 3, 0, 16)
		indicator.AnchorPoint = Vector2.new(0, 0.5)
		indicator.Position = UDim2.fromScale(0, 0.5)
		indicator.BackgroundColor3 = theme.Accent
		indicator.BackgroundTransparency = 1
		indicator.BorderSizePixel = 0
		indicator.Parent = btn
		corner(indicator, 2)

		local tabLabel = Instance.new("TextLabel")
		tabLabel.Size = UDim2.new(1, -20, 1, 0)
		tabLabel.Position = UDim2.fromOffset(14, 0)
		tabLabel.BackgroundTransparency = 1
		tabLabel.Font = Enum.Font.GothamMedium
		tabLabel.Text = name
		tabLabel.TextColor3 = theme.TextSecondary
		tabLabel.TextSize = 13
		tabLabel.TextXAlignment = Enum.TextXAlignment.Left
		tabLabel.Parent = btn

		btn.MouseButton1Click:Connect(function()
			selectTab(name)
		end)

		TabButtons[name] = {Button = btn, Indicator = indicator, Label = tabLabel}

		if not currentTab then
			selectTab(name)
		end

		local Tab = {}

		function Tab:CreateLabel(text)
			return createSectionLabel(page, text)
		end

		function Tab:CreateParagraph(opts)
			opts = opts or {}
			return createParagraph(page, opts.Title, opts.Content)
		end

		function Tab:CreateButton(opts)
			opts = opts or {}
			return createButton(page, opts.Text or "Botão", opts.Callback)
		end

		function Tab:CreateToggle(opts)
			opts = opts or {}
			return createToggle(page, opts.Text or "Toggle", opts.Default or false, opts.Callback)
		end

		function Tab:CreateSlider(opts)
			opts = opts or {}
			return createSlider(page, opts.Text or "Slider", opts.Min or 0, opts.Max or 100, opts.Default or 0, opts.Callback)
		end

		function Tab:CreateColorPicker(opts)
			opts = opts or {}
			return createColorPicker(page, opts.Text or "Cor", opts.Default, opts.Callback)
		end

		function Tab:CreateKeybind(opts)
			opts = opts or {}
			local show = opts.ShowInHotkeyList
			if show == nil then show = true end
			return createKeybind(page, opts.Text or "Atalho", opts.Default or Enum.KeyCode.E, opts.Callback, show)
		end

		function Tab:CreateKeybindToggle(opts)
			opts = opts or {}
			return createKeybindToggle(page, opts)
		end

		return Tab
	end

	------------------------------------------------------------
	-- NOTIFICAÇÕES
	------------------------------------------------------------
	local NotifyHolder = Instance.new("Frame")
	NotifyHolder.AnchorPoint = Vector2.new(1, 0)
	NotifyHolder.Position = UDim2.new(1, -16, 0, 16)
	NotifyHolder.Size = UDim2.fromOffset(260, 0)
	NotifyHolder.AutomaticSize = Enum.AutomaticSize.Y
	NotifyHolder.BackgroundTransparency = 1
	NotifyHolder.Parent = ScreenGui

	local NotifyList = Instance.new("UIListLayout")
	NotifyList.Padding = UDim.new(0, 8)
	NotifyList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	NotifyList.Parent = NotifyHolder

	local function notify(opts)
		opts = opts or {}
		local duration = opts.Duration or 3

		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(260, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = theme.Surface
		card.BackgroundTransparency = 1
		card.Position = UDim2.fromOffset(40, 0)
		card.Parent = NotifyHolder
		corner(card, 8)
		local cStroke = stroke(card, theme.Stroke, 1)
		cStroke.Transparency = 1

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = card

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 2)
		list.Parent = card

		if opts.Title then
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(1, 0, 0, 16)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBold
			t.Text = opts.Title
			t.TextColor3 = theme.TextPrimary
			t.TextSize = 13
			t.TextTransparency = 1
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.Parent = card
		end

		if opts.Content then
			local c = Instance.new("TextLabel")
			c.Size = UDim2.new(1, 0, 0, 0)
			c.AutomaticSize = Enum.AutomaticSize.Y
			c.BackgroundTransparency = 1
			c.Font = Enum.Font.Gotham
			c.Text = opts.Content
			c.TextColor3 = theme.TextSecondary
			c.TextSize = 12
			c.TextWrapped = true
			c.TextTransparency = 1
			c.TextXAlignment = Enum.TextXAlignment.Left
			c.Parent = card
		end

		tween(card, {Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0}, 0.3, Enum.EasingStyle.Quint)
		tween(cStroke, {Transparency = 0}, 0.3)
		for _, child in ipairs(card:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, {TextTransparency = 0}, 0.3)
			end
		end

		task.delay(duration, function()
			tween(card, {Position = UDim2.fromOffset(40, 0), BackgroundTransparency = 1}, 0.25)
			tween(cStroke, {Transparency = 1}, 0.25)
			for _, child in ipairs(card:GetDescendants()) do
				if child:IsA("TextLabel") then
					tween(child, {TextTransparency = 1}, 0.25)
				end
			end
			task.wait(0.3)
			card:Destroy()
		end)
	end

	------------------------------------------------------------
	-- ABRIR/FECHAR + RECOLHER + ARRASTAR
	------------------------------------------------------------
	tween(Main, {Size = UDim2.fromOffset(winWidth, winHeight), BackgroundTransparency = 0}, 0.45, Enum.EasingStyle.Quint)

	-- Agora existe um único estado: "minimizado" ou não. A janela NUNCA
	-- fica invisível/some da tela — quando "fechada" ela só encolhe até
	-- sobrar a barrinha do TopBar, que pode ser clicada (ou reaberta
	-- pela tecla) para expandir de novo.
	local minimized = false
	local BAR_HEIGHT = 46

	local function setMinimized(state)
		if minimized == state then return end
		minimized = state
		if minimized then
			Sidebar.Visible = false
			ContentArea.Visible = false
			tween(Main, {Size = UDim2.fromOffset(winWidth, BAR_HEIGHT)}, 0.3, Enum.EasingStyle.Quint)
		else
			Sidebar.Visible = true
			ContentArea.Visible = true
			tween(Main, {Size = UDim2.fromOffset(winWidth, winHeight)}, 0.3, Enum.EasingStyle.Quint)
		end
	end

	local function toggleMinimized()
		setMinimized(not minimized)
	end

	track(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == toggleKey or input.KeyCode == minimizeKey then
			toggleMinimized()
		end
	end))

	-- Arrastar pela TopBar. Também detecta clique (sem arrastar) na
	-- barra para restaurar a janela quando ela estiver minimizada.
	local dragging, dragInput, dragStart, startPos, dragMoved
	TopBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMoved = false
			dragStart = input.Position
			startPos = Main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not dragMoved and minimized then
						setMinimized(false)
					end
				end
			end)
		end
	end)
	TopBar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
				dragMoved = true
			end
			Main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))

	-- O "X" agora só minimiza para a barrinha, nunca esconde a janela.
	CloseBtn.MouseButton1Click:Connect(function()
		setMinimized(true)
	end)

	------------------------------------------------------------
	-- OBJETO WINDOW (API PÚBLICA)
	------------------------------------------------------------
	local Window = {}

	Window.ScreenGui = ScreenGui
	Window.Main = Main

	-- Permite que Library:Unload() pare o loop de partículas desta janela
	Window.StopParticles = function()
		menuParticlesRunning = false
	end

	function Window:CreateTab(name)
		return createTab(name)
	end

	function Window:SetToggleKey(key)
		toggleKey = key
	end

	function Window:SetMinimizeKey(key)
		minimizeKey = key
	end

	function Window:ShowHotkeyList()
		setHotkeyListVisible(true)
	end

	function Window:HideHotkeyList()
		setHotkeyListVisible(false)
	end

	function Window:ToggleHotkeyList()
		setHotkeyListVisible(not hotkeyListVisible)
	end

	function Window:SetAccentColor(color)
		MainStroke.Color = color
		local ref = TabButtons[currentTab]
		if ref then
			ref.Indicator.BackgroundColor3 = color
		end
	end

	function Window:SelectTab(name)
		if Tabs[name] then
			selectTab(name)
		end
	end

	function Window:Toggle()
		toggleMinimized()
	end

	function Window:Minimize()
		setMinimized(true)
	end

	function Window:Restore()
		setMinimized(false)
	end

	function Window:Notify(opts)
		notify(opts)
	end

	function Window:Destroy()
		menuParticlesRunning = false
		ScreenGui:Destroy()
		for i, win in ipairs(Library.Windows) do
			if win == Window then
				table.remove(Library.Windows, i)
				break
			end
		end
	end

	-- Atalho: descarrega a lib inteira (todas as janelas), chamando
	-- diretamente Library:Unload().
	function Window:Unload()
		Library:Unload()
	end

	table.insert(Library.Windows, Window)

	return Window
end

-- Registra o handler de unload desta instância como o atual, para que
-- uma próxima execução do script (re-loadstring) consiga limpá-la.
_G.__AlluminiumUnload = function()
	Library:Unload()
end

return Library
