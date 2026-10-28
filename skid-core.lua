--=============================================================================
-- SKIDWARE CORE · v4.1 —— 功能层（不含面板）
--
-- 职责：
-- · 模块注册表 / 生命周期 / 配置持久化 / 事件总线 / 角色事件
-- · 功能模块：combat · noclip · cooldown · hud · input · layout · system
-- · 从 GitHub 拉取 UI 壳（skid-ui.lua）并 mount(core)；拉取失败功能照常跑
--
-- UI 壳的契约（见 skid-ui.lua）：
-- return { version = "1.x", mount = function(core) end, unmount = function() end,
-- refresh = function() end }
-- 壳通过 core.registry / core.store / core.bus / core.theme / core.util 工作
--=============================================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local CORE_VERSION = "4.1"

local player = Players.LocalPlayer
local clock = os.clock
local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)

--// ── 单实例 / 错误隔离 ───────────────────────────────────────
local scriptId = math.random(1, 1000000)
if _G.SkidwareDestroy then pcall(_G.SkidwareDestroy) end
_G.SkidwareId = scriptId
local function isCurrent() return _G.SkidwareId == scriptId end

local function safe(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn("[skid-core] " .. tostring(tag) .. ": " .. tostring(err)) end
	return ok
end

--=============================================================================
-- 工具
--=============================================================================
local U = {}

function U.new(class, props, parent)
	local inst = Instance.new(class)
	if props then for k, v in pairs(props) do inst[k] = v end end
	if parent then inst.Parent = parent end
	return inst
end

function U.round(obj, r) return U.new("UICorner", { CornerRadius = UDim.new(0, r) }, obj) end

function U.stroke(obj, color, thickness, transparency)
	return U.new("UIStroke", {
		Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, obj)
end

function U.tween(obj, props, seconds, style, dir)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(seconds or 0.14, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

function U.clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
function U.fmt(v, d) return string.format("%." .. tostring(d or 0) .. "f", v) end

function U.isPrimary(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

function U.deep(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = U.deep(v) end
	return out
end

function U.getPath(t, path)
	if not path then return nil end
	local cur = t
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
	end
	return cur
end

function U.setPath(t, path, value)
	local parts = {}
	for p in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = p end
	if #parts == 0 then return end
	local cur = t
	for i = 1, #parts - 1 do
		if type(cur[parts[i]]) ~= "table" then cur[parts[i]] = {} end
		cur = cur[parts[i]]
	end
	cur[parts[#parts]] = value
end

function U.merge(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then return end
	for k, dv in pairs(dst) do
		local sv = src[k]
		if sv ~= nil and type(sv) == type(dv) then
			if type(dv) == "table" then U.merge(dv, sv) else dst[k] = sv end
		end
	end
end

--// ── 信号 / 总线 ────────────────────────────────────────────
local Bus = { map = {} }

function Bus.on(evt, fn)
	Bus.map[evt] = Bus.map[evt] or {}
	local c = { fn = fn, dead = false }
	c.Disconnect = function()
		c.dead = true
		local list = Bus.map[evt]
		if not list then return end
		for i, x in ipairs(list) do
			if x == c then table.remove(list, i) return end
		end
	end
	Bus.map[evt][#Bus.map[evt] + 1] = c
	return c
end

function Bus.emit(evt, ...)
	local list = Bus.map[evt]
	if not list then return end
	local snapshot = {}
	for i, c in ipairs(list) do if not c.dead then snapshot[#snapshot + 1] = c end end
	for _, c in ipairs(snapshot) do safe("bus:" .. evt, c.fn, ...) end
end

function Bus.clear()
	for _, list in pairs(Bus.map) do
		for _, c in ipairs(list) do c.dead = true end
	end
	Bus.map = {}
end

local Connections = {}
local function bind(sig, fn)
	local c = sig:Connect(fn)
	Connections[#Connections + 1] = c
	return c
end

--// ── 主题（core 只用来画头顶胶囊，面板用同一份配色）──────────
local Theme = {
	Bg = Color3.fromRGB(12, 12, 12),
	BgSoft = Color3.fromRGB(18, 18, 18),
	Card = Color3.fromRGB(23, 23, 23),
	CardHi = Color3.fromRGB(32, 32, 32),
	Line = Color3.fromRGB(40, 40, 40),
	LineSoft = Color3.fromRGB(31, 31, 31),
	Text = Color3.fromRGB(240, 240, 240),
	Sub = Color3.fromRGB(150, 150, 150),
	Muted = Color3.fromRGB(92, 92, 92),
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(86, 240, 128),
	Red = Color3.fromRGB(240, 96, 96),
	Hover = Color3.fromRGB(30, 30, 30),
	Press = Color3.fromRGB(24, 24, 24),
	OnBg = Color3.fromRGB(238, 238, 238),
}

local PILL_W, PILL_H = 92, 40

-- 前向声明：下面的模块闭包会引用 core 与 Pill（赋值在文件后段）
local core
local Pill

--=============================================================================
-- 状态
--=============================================================================
local Modules

local Layout = {
	winX = -1, winY = -1, winW = 276, winH = 386,
	headX = 0, headY = 3.2,
	snap = true, edgeSnap = true, grid = 4,
}
local DefaultLayout = U.deep(Layout)

local function hook(m, name)
	local fn = m[name]
	if fn ~= nil then return fn end
	return m.spec[name]
end

--=============================================================================
-- 配置存储
--=============================================================================
local FILE = "skidware_v5.json"
local LEGACY_FILES = { "skidware_v4.json", "skidware_v3.json", "skidware_layout.json" }
local CONFIG_VERSION = 5
local SAVE_DEBOUNCE = 0.6   -- 最后一次改动后多久落盘
local SAVE_MAX_WAIT = 3     -- 连续拖滑块时，最迟多久必须落盘

local wf = rawget(_G, "writefile")
local rf = rawget(_G, "readfile")
local ixf = rawget(_G, "isfile")
local canSave = type(wf) == "function"
local canRead = type(rf) == "function" and type(HttpService.JSONDecode) == "function"

local Store = {}
Store.extra = {}            -- 模块之外要存的配置：面板收起状态、当前标签页、自定义绑定等
Store.lastError = nil

local savePending, saveAt, saveDeadline = false, 0, 0

local function encode()
	local mods = {}
	if Modules then
		for _, m in ipairs(Modules.list) do mods[m.id] = m.C end
	end
	return {
		version = CONFIG_VERSION,
		savedAt = os.time and os.time() or 0,
		ui = Layout,
		extra = Store.extra,
		modules = mods,
	}
end

function Store.flush()
	if not canSave or not savePending then return false end
	savePending = false
	local ok, payload = pcall(function() return HttpService:JSONEncode(encode()) end)
	if not ok or type(payload) ~= "string" then
		Store.lastError = "encode: " .. tostring(payload)
		return false
	end
	local wok, err = pcall(wf, FILE, payload)
	if not wok then
		Store.lastError = "write: " .. tostring(err)
		warn("[skid-core] 配置写入失败: " .. tostring(err))
		return false
	end
	Store.lastError = nil
	return true
end

function Store.mark()
	if not canSave then return end
	local now = clock()
	if not savePending then saveDeadline = now + SAVE_MAX_WAIT end
	savePending = true
	saveAt = math.min(now + SAVE_DEBOUNCE, saveDeadline)
end

function Store.saveNow()
	if not canSave then return false end
	savePending = true
	return Store.flush()
end

-- 模块之外的持久化入口（存不下的东西别硬塞进模块 C 表）
function Store.setExtra(key, value)
	if Store.extra[key] == value then return end
	Store.extra[key] = value
	Store.mark()
end

function Store.getExtra(key, default)
	local v = Store.extra[key]
	if v == nil then return default end
	return v
end

-- 备份 / 换设备：Store.importString(Store.exportString())
function Store.exportString()
	local ok, payload = pcall(function() return HttpService:JSONEncode(encode()) end)
	return ok and payload or nil
end

function Store.importString(text)
	if type(text) ~= "string" then return false end
	local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
	if not ok or type(data) ~= "table" then return false end
	if type(data.ui) == "table" then U.merge(Layout, data.ui) end
	if type(data.extra) == "table" then U.merge(Store.extra, data.extra) end
	if type(data.modules) == "table" then
		for id, saved in pairs(data.modules) do
			local m = Modules.byId[id]
			if m and type(saved) == "table" then U.merge(m.C, saved) end
		end
	end
	Modules.refreshHooks()
	Bus.emit("store:reset")
	Store.saveNow()
	return true
end

local LEGACY_MAP_V2 = {
	Enabled = "combat.enabled",
	LethalMode = "combat.mode",
	LethalDelay = "combat.delay",
	LethalJump = "combat.jump",
	LethalAccuracy = "combat.accuracy",
	LethalCancelDelay = "combat.cancelDelay",
	DashRange = "combat.dashRange",
	CancelEnabled = "combat.cancelOnAttach",
	NoClipEnabled = "noclip.enabled",
	NoClipRange = "noclip.range",
	CooldownActive = "cooldown.enabled",
	CooldownTime = "cooldown.duration",
	TouchMode = "input.touch",
	Platform = "input.platform",
	Keybind = "input.keybind",
	HeadTimer = "hud.enabled",
	TimerDecimals = "hud.decimals",
}

local LEGACY_LAYOUT_V2 = {
	WinX = "winX", WinY = "winY", WinW = "winW", WinH = "winH",
	HeadX = "headX", HeadY = "headY",
	Snap = "snap", Grid = "grid",
}

local function readJSON(name)
	if not canRead or type(rf) ~= "function" then return nil end
	if type(ixf) == "function" and not ixf(name) then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(rf(name)) end)
	if ok and type(data) == "table" then return data end
	return nil
end

-- v4 / v5 结构相同，共用；v5 多了 extra 与 savedAt，缺了也不会报错
local function loadCurrent(data)
	if type(data.ui) == "table" then U.merge(Layout, data.ui) end
	if type(data.extra) == "table" then U.merge(Store.extra, data.extra) end
	if type(data.modules) == "table" then
		for id, saved in pairs(data.modules) do
			local m = Modules.byId[id]
			if m and type(saved) == "table" then U.merge(m.C, saved) end
		end
	end
end
local loadLegacyV3 = loadCurrent

local function loadLegacyV2(data)
	local cfg = type(data.config) == "table" and data.config or {}
	for oldKey, path in pairs(LEGACY_MAP_V2) do
		local v = cfg[oldKey]
		local modId, key = string.match(path, "^([^%.]+)%.(.+)$")
		local mod = modId and Modules.byId[modId] or nil
		if mod and v ~= nil and type(v) == type(U.getPath(mod.C, key)) then
			U.setPath(mod.C, key, v)
		end
	end
	local trig = type(cfg.AnimConfig) == "table" and cfg.AnimConfig["12296882427"] or nil
	local combat = Modules.byId.combat
	if combat and type(trig) == "table" then
		if type(trig.delay) == "number" then combat.C.trigger.delay = U.clamp(trig.delay, 0, 3) end
		if type(trig.mode) == "string" then combat.C.trigger.mode = trig.mode end
	end
	local lay = type(data.layout) == "table" and data.layout or {}
	for oldKey, newKey in pairs(LEGACY_LAYOUT_V2) do
		local v = lay[oldKey]
		if v ~= nil and type(v) == type(Layout[newKey]) then Layout[newKey] = v end
	end
	local hud = Modules.byId.hud
	if hud then
		if type(lay.HeadScale) == "number" then hud.C.scale = U.clamp(lay.HeadScale, 0.7, 1.6) end
		if type(lay.HeadOpacity) == "number" then hud.C.opacity = U.clamp(lay.HeadOpacity, 0.3, 1) end
		if type(lay.TimerBackdrop) == "boolean" then hud.C.backdrop = lay.TimerBackdrop end
		if type(lay.FadeAim) == "boolean" then hud.C.fade = lay.FadeAim end
	end
end

function Store.load()
	local data = readJSON(FILE)
	if data then
		loadCurrent(data)
	else
		for _, name in ipairs(LEGACY_FILES) do
			local legacy = readJSON(name)
			if legacy then
				if type(legacy.modules) == "table" then
					loadCurrent(legacy)     -- v4 / v3 同结构
				else
					loadLegacyV2(legacy)    -- v2 老文件
				end
				break
			end
		end
	end
	for _, m in ipairs(Modules.list) do
		m.C.enabled = m.C.enabled ~= false
	end
end

function Store.resetAll()
	for _, m in ipairs(Modules.list) do
		if m.enabled then
			local off = hook(m, "onDisable")
			if off then safe(m.id .. ":onDisable", off, m) end
		end
		local def = U.deep(m.spec.defaults or {})
		def.enabled = def.enabled ~= false
		m.C = def
		m.enabled = false
		if def.enabled then
			m.enabled = true
			local on = hook(m, "onEnable")
			if on then safe(m.id .. ":onEnable", on, m) end
		end
	end
	for k, v in pairs(U.deep(DefaultLayout)) do Layout[k] = v end
	Layout.winX = math.floor((viewport.X - Layout.winW) / 2)
	Layout.winY = math.floor((viewport.Y - Layout.winH) / 2)
	for k in pairs(Store.extra) do Store.extra[k] = nil end
	Modules.refreshHooks()
	Bus.emit("store:reset")
	Store.saveNow()
end

--=============================================================================
-- 模块注册表
--=============================================================================
Modules = { list = {}, byId = {}, renderList = {}, tickList = {} }

function Modules.define(spec)
	local mod = {
		id = spec.id,
		title = spec.title or spec.id,
		tab = spec.tab or "General",
		order = spec.order or 100,
		spec = spec,
		settings = spec.settings or {},
		actions = spec.actions or {},
		C = U.deep(spec.defaults or {}),
		enabled = false,
		api = {},
	}
	if mod.C.enabled == nil then mod.C.enabled = true end
	function mod.get(key) return U.getPath(mod.C, key) end
	function mod.set(key, value, silent)
		local old = mod.get(key)
		if old == value then return end
		if type(old) == "table" then return end
		U.setPath(mod.C, key, value)
		Store.mark()
		if not silent then
			local fn = hook(mod, "onChange")
			if fn then safe(mod.id .. ":onChange", fn, mod, key, value) end
			Bus.emit("config", mod.id, key, value)
		end
	end
	function mod.setEnabled(on, silent)
		on = on and true or false
		if mod.enabled == on then return end
		mod.enabled = on
		mod.C.enabled = on
		if not silent then Store.mark() end
		local fn = hook(mod, on and "onEnable" or "onDisable")
		if fn then safe(mod.id .. ":" .. (on and "onEnable" or "onDisable"), fn, mod) end
		Modules.refreshHooks()
		Bus.emit("module", mod.id, on)
		if not silent then Bus.emit("ui:refresh") end
	end
	Modules.list[#Modules.list + 1] = mod
	Modules.byId[mod.id] = mod
	return mod
end

function Modules.get(id) return Modules.byId[id] end

function Modules.refreshHooks()
	local r, t = {}, {}
	for _, m in ipairs(Modules.list) do
		if m.enabled then
			local onRender = hook(m, "onRender")
			local onTick = hook(m, "onTick")
			if onRender then r[#r + 1] = { m = m, fn = onRender } end
			if onTick then t[#t + 1] = { m = m, fn = onTick } end
		end
	end
	Modules.renderList, Modules.tickList = r, t
end

function Modules.countEnabled()
	local n = 0
	for _, m in ipairs(Modules.list) do if m.enabled then n = n + 1 end end
	return n
end

function Modules.initAll()
	for _, m in ipairs(Modules.list) do
		local fn = hook(m, "init")
		if fn then safe(m.id .. ":init", fn, m) end
	end
end

function Modules.startAll()
	for _, m in ipairs(Modules.list) do
		if m.C.enabled ~= false then m.setEnabled(true, true) end
	end
	Modules.refreshHooks()
end

function Modules.stopAll()
	for _, m in ipairs(Modules.list) do
		if m.enabled then
			m.enabled = false
			local fn = hook(m, "onDisable")
			if fn then safe(m.id .. ":onDisable", fn, m) end
		end
	end
	Modules.renderList, Modules.tickList = {}, {}
end

--=============================================================================
-- 角色事件
--=============================================================================
local CharSvc = { character = nil, hum = nil, conn = nil }

function CharSvc.attach(char)
	if CharSvc.conn then CharSvc.conn:Disconnect() CharSvc.conn = nil end
	CharSvc.character = char
	CharSvc.hum = char:FindFirstChildOfClass("Humanoid")
	if CharSvc.hum then
		CharSvc.conn = CharSvc.hum.AnimationPlayed:Connect(function(track)
			local id = nil
			pcall(function() id = string.match(tostring(track.Animation.AnimationId), "%d+") end)
			Bus.emit("anim", id, track)
		end)
	end
	Bus.emit("character", char)
end

function CharSvc.detach()
	if CharSvc.conn then CharSvc.conn:Disconnect() CharSvc.conn = nil end
	CharSvc.character, CharSvc.hum = nil, nil
	Bus.emit("character", nil)
end

--=============================================================================
-- 模块 · combat
--=============================================================================
local TRIGGER_ID = "12296882427"
local LETHAL_ANIM = "rbxassetid://10503381238"

local combat = Modules.define({
	id = "combat",
	title = "Lethal dash",
	tab = "Combat",
	order = 10,
	defaults = {
		enabled = true,
		mode = "V1",
		delay = 0.232,
		jump = 55,
		accuracy = 15,
		cancelDelay = 0.4,
		dashRange = 8,
		cancelOnAttach = true,
		trigger = { delay = 0.30, mode = "V1" },
	},
	settings = {
		{ type = "segment", key = "mode", label = "Execution mode", options = { "V1", "V2" } },
		{ type = "slider", key = "delay", label = "Trigger delay", min = 0.1, max = 0.6, step = 0.002, decimals = 3, suffix = "s" },
		{ type = "slider", key = "jump", label = "Jump power", min = 20, max = 90, step = 1, decimals = 0 },
		{ type = "slider", key = "accuracy", label = "Accuracy / flip", min = 0.25, max = 30, step = 0.25, decimals = 2 },
		{ type = "slider", key = "dashRange", label = "Dash range", min = 4, max = 20, step = 1, decimals = 0, suffix = " st" },
		{ type = "slider", key = "cancelDelay", label = "Cancel delay", min = 0.1, max = 1.2, step = 0.01, decimals = 2, suffix = "s" },
		{ type = "toggle", key = "cancelOnAttach", label = "Cancel on attach" },
		{ type = "divider" },
		{ type = "segment", key = "trigger.mode", label = "Trigger mode", options = { "V1", "V2" } },
		{ type = "slider", key = "trigger.delay", label = "Delay after end", min = 0, max = 3, step = 0.01, decimals = 2, suffix = "s", stepper = true },
		{ type = "button", label = "Force cancel / reset velocity", action = "cancel" },
	},
	actions = {},
})

local scan = OverlapParams.new()
scan.FilterType = Enum.RaycastFilterType.Exclude
local scanChar = nil

local function torsoTarget(char, root, range)
	if scanChar ~= char then
		scanChar = char
		scan.FilterDescendantsInstances = char and { char } or {}
	end
	local best, bestDist = nil, range
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, range, scan)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= char and model:FindFirstChildOfClass("Humanoid") then
			local torso = model:FindFirstChild("Torso")
				or model:FindFirstChild("UpperTorso")
				or model:FindFirstChild("HumanoidRootPart")
			if torso then
				local d = (root.Position - torso.Position).Magnitude
				if d < bestDist then bestDist, best = d, torso end
			end
		end
	end
	return best
end

local isExecuting = false
local lastTrigger, lastSelfDash = 0, 0

local function fireDash(char)
	local communicate = char and char:FindFirstChild("Communicate")
	if communicate then
		lastSelfDash = clock()
		communicate:FireServer({ Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress" })
	end
end

local function resetRotation()
	if CharSvc.hum then CharSvc.hum.AutoRotate = true end
end

local function releaseNoclip()
	local nc = Modules.get("noclip")
	if nc and nc.api.release then nc.api.release() end
end

function combat.api.cancel()
	isExecuting = false
	releaseNoclip()
	resetRotation()
	local char = CharSvc.character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for _, obj in ipairs(hrp:GetChildren()) do
		local c = obj.ClassName
		if c == "BodyVelocity" or c == "LinearVelocity" or c == "Attachment" or c == "BodyAngularVelocity" then
			obj:Destroy()
		end
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
end

function combat.api.execute(modeOverride)
	local m = combat
	if not isCurrent() or not m.enabled or isExecuting then return false end
	if clock() - lastTrigger < 0.12 then return false end
	local cd = Modules.get("cooldown")
	if cd and cd.enabled and cd.api.ready and not cd.api.ready() then return false end
	local char = CharSvc.character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then return false end
	local torso = torsoTarget(char, root, m.C.dashRange)
	if not torso then return false end

	local mode = modeOverride or m.C.mode
	local accuracy = (mode ~= m.C.mode) and ((mode == "V2") and 0.25 or 15) or m.C.accuracy
	lastTrigger = clock()
	isExecuting = true

	local inp = Modules.get("input")
	if not (inp and inp.enabled and inp.C.touch) then task.wait(m.C.delay) end
	if not isCurrent() or not m.enabled then
		isExecuting = false
		return false
	end

	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, m.C.jump, v.Z)
	local nc = Modules.get("noclip")
	if nc and nc.api.engage then nc.api.engage() end
	fireDash(char)

	local startT = clock()
	local flipped = false
	local forwardDir = (torso.Position - root.Position).Unit
	local sideVec = Vector3.new(-forwardDir.Z, 0, forwardDir.X)
	local bav
	if mode == "V1" then
		bav = U.new("BodyAngularVelocity", { MaxTorque = Vector3.new(0, 1000000, 0), P = 15000 }, root)
	end
	local conn
	local function stop()
		if bav then bav:Destroy() end
		isExecuting = false
		releaseNoclip()
		if conn then conn:Disconnect() end
	end
	conn = RS.Heartbeat:Connect(function()
		if not isCurrent() or not m.enabled or not torso.Parent or not root.Parent then
			resetRotation()
			stop()
			return
		end
		local elapsed = clock() - startT
		local torsoPos, rootPos = torso.Position, root.Position
		hum.AutoRotate = false
		if mode == "V1" then
			local angle = (elapsed / 0.45) * (math.pi / 1.5)
			local radius = accuracy * (1 - U.clamp(elapsed / 0.45, 0, 1))
			local target = torsoPos + (sideVec * math.cos(angle) + forwardDir * math.sin(angle)) * radius
			local lookCF = CFrame.lookAt(rootPos, Vector3.new(target.X, rootPos.Y, target.Z))
			local _, y = (root.CFrame:Inverse() * lookCF):ToEulerAnglesXYZ()
			if bav and bav.Parent then bav.AngularVelocity = Vector3.new(0, y * 30, 0) end
		elseif elapsed >= accuracy and not flipped then
			root.CFrame = root.CFrame * CFrame.Angles(0, math.pi, 0)
			flipped = true
		end
		local distXZ = (Vector2.new(rootPos.X, rootPos.Z) - Vector2.new(torsoPos.X, torsoPos.Z)).Magnitude
		if m.C.cancelOnAttach and elapsed > m.C.cancelDelay and distXZ < 2.2 then
			combat.api.cancel()
			stop()
			return
		end
		if elapsed > 1.5 then
			resetRotation()
			stop()
		end
	end)
end

local postPending = false
local function armAfter(track, delay, mode)
	if postPending then return end
	postPending = true
	task.spawn(function()
		local nominal = 0
		pcall(function()
			local sp = track.Speed
			if not sp or sp == 0 then sp = 1 end
			nominal = U.clamp(track.Length / sp, 0, 5)
		end)
		local t0 = clock()
		while clock() - t0 < nominal and isCurrent() do task.wait(0.03) end
		local t1 = clock()
		while clock() - t1 < 1.2 do
			local ok, playing = pcall(function() return track.IsPlaying end)
			if not ok or not playing then break end
			task.wait(0.03)
		end
		task.wait(delay or 0.3)
		postPending = false
		if isCurrent() and clock() - lastSelfDash > 0.6 then
			combat.api.execute(mode)
		end
	end)
end

combat.animConn = nil
combat.init = function(self)
	combat.animConn = Bus.on("anim", function(id, track)
		if not self.enabled then return end
		if id and id == string.match(LETHAL_ANIM, "%d+") then
			combat.api.execute()
			return
		end
		if id and id == TRIGGER_ID then
			armAfter(track, self.C.trigger.delay, self.C.trigger.mode)
		end
	end)
	Bus.on("character", function()
		isExecuting = false
		postPending = false
	end)
end

combat.onDisable = function()
	isExecuting = false
	postPending = false
	releaseNoclip()
	resetRotation()
end

combat.onChange = function(self, key, value)
	if key == "mode" then
		self.C.accuracy = (value == "V2") and 0.25 or 15
		Bus.emit("ui:refresh")
	end
end

combat.actions.cancel = function() combat.api.cancel() end

--=============================================================================
-- 模块 · noclip
--=============================================================================
local noclip = Modules.define({
	id = "noclip",
	title = "No-clip",
	tab = "Combat",
	order = 20,
	defaults = { enabled = true, range = 40, throttle = 0.12 },
	settings = {
		{ type = "slider", key = "range", label = "Scan radius", min = 10, max = 80, step = 1, decimals = 0, suffix = " st" },
		{ type = "slider", key = "throttle", label = "Refresh rate", min = 0.04, max = 0.4, step = 0.01, decimals = 2, suffix = "s" },
		{ type = "note", label = "只在冲刺期间生效；退出时自动恢复所有被关闭的碰撞。" },
	},
})

local ncActive = false
local ncAcc = 0
local ncTouched = {}
local ncScan = OverlapParams.new()
ncScan.FilterType = Enum.RaycastFilterType.Exclude

local function ncRestore()
	for part in pairs(ncTouched) do
		if part.Parent then pcall(function() part.CanCollide = true end) end
	end
	ncTouched = {}
end

noclip.api.engage = function() if noclip.enabled then ncActive = true end end
noclip.api.release = function() ncActive = false; ncRestore() end
noclip.api.isActive = function() return ncActive end

noclip.onTick = function(self, dt)
	if not ncActive then return end
	ncAcc = ncAcc + dt
	if ncAcc < self.C.throttle then return end
	ncAcc = 0
	local char = CharSvc.character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	ncScan.FilterDescendantsInstances = char and { char } or {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, self.C.range, ncScan)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= char and model:FindFirstChildOfClass("Humanoid") then
			if part.CanCollide and not ncTouched[part] then
				ncTouched[part] = true
				part.CanCollide = false
			end
		end
	end
end

noclip.onDisable = function()
	ncActive = false
	ncRestore()
end

noclip.init = function()
	Bus.on("character", function()
		ncActive = false
		ncRestore()
	end)
end

--=============================================================================
-- 模块 · cooldown
--=============================================================================
local cooldown = Modules.define({
	id = "cooldown",
	title = "Cooldown",
	tab = "Combat",
	order = 30,
	defaults = {
		enabled = true,
		duration = 5,
		anims = {
			["10491993682"] = true,
			["10479335397"] = true,
			["13380255751"] = true,
		},
	},
	settings = {
		{ type = "slider", key = "duration", label = "Cooldown time", min = 2, max = 10, step = 0.1, decimals = 1, suffix = "s" },
		{ type = "note", label = "跟踪 3 个冷却动画：命中后进入冷却并通知 HUD。" },
		{ type = "button", label = "Preview cooldown (5s)", action = "preview" },
	},
})

local cdUntil = 0

function cooldown.api.remaining()
	local r = cdUntil - clock()
	return r > 0 and r or 0
end

function cooldown.api.ready() return clock() >= cdUntil end

function cooldown.api.start(seconds)
	if not cooldown.enabled then return end
	if clock() < cdUntil then return end
	local dur = seconds or cooldown.C.duration
	cdUntil = clock() + dur
	Bus.emit("cooldown:start", dur)
end

cooldown.actions.preview = function() cooldown.api.start(5) end

cooldown.init = function(self)
	Bus.on("anim", function(id)
		if not self.enabled or not id then return end
		if self.C.anims[id] then cooldown.api.start() end
	end)
end

cooldown.onDisable = function() cdUntil = 0 end

--=============================================================================
-- 模块 · hud（头顶胶囊，属于功能层：世界空间表现）
--=============================================================================
local hud
hud = Modules.define({
	id = "hud",
	title = "Overhead timer",
	tab = "HUD",
	order = 10,
	defaults = { enabled = true, scale = 1, opacity = 1, fade = true, backdrop = true, decimals = 1 },
	settings = {
		{ type = "slider", key = "scale", label = "Scale", min = 0.7, max = 1.6, step = 0.01, decimals = 2, suffix = "x" },
		{ type = "slider", key = "opacity", label = "Opacity", min = 0.3, max = 1, step = 0.01, decimals = 2 },
		{ type = "toggle", key = "fade", label = "Fade near crosshair" },
		{ type = "toggle", key = "backdrop", label = "Number backplate" },
		{
			type = "segment", label = "Precision", options = { "0.1s", "1s" },
			get = function() return hud.C.decimals == 1 and "0.1s" or "1s" end,
			set = function(v) hud.set("decimals", v == "0.1s" and 1 or 0) end,
		},
		{ type = "button", label = "Preview head timer (5s)", action = "preview", primary = true },
	},
})

local H = {
	gui = nil, pill = nil, active = false, fading = false,
	alpha = 1, endsAt = 0, duration = 0,
	lastOffset = nil, lastText = "", lastRatio = -1, lastAlpha = -1,
}

local function hudHead()
	local char = CharSvc.character
	if not char then return nil end
	return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local function hudStyle()
	if not H.pill then return end
	Pill.reset(H.pill, hud.C.opacity, hud.C.backdrop)
	Pill.setScale(H.pill, hud.C.scale)
	H.pill.Label.Text = U.fmt(5, hud.C.decimals)
end

local function hudBuild()
	if H.gui then H.gui:Destroy() end
	H.gui, H.pill = nil, nil
	local head = hudHead()
	if not head then return end
	local gui = U.new("BillboardGui", {
		Name = "SkidwareHeadTimer",
		Adornee = head,
		Size = UDim2.fromOffset(PILL_W, PILL_H),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 160,
		Enabled = false,
	}, head)
	H.gui = gui
	H.pill = Pill.build(gui)
	Pill.setScale(H.pill, hud.C.scale)
	hudStyle()
end

local function hudShow(duration)
	if not hud.enabled then return end
	local head = hudHead()
	if not head then return end
	if not H.gui or H.gui.Parent == nil or H.gui.Adornee ~= head then hudBuild() end
	if not H.gui or not H.pill then return end
	H.gui.Enabled = true
	H.active, H.fading = true, false
	H.duration = duration
	H.endsAt = clock() + duration
	H.alpha = hud.C.opacity
	Pill.reset(H.pill, hud.C.opacity, hud.C.backdrop)
	H.lastText, H.lastRatio, H.lastAlpha = "", -1, -1
	H.pill.Label.Text = U.fmt(duration, hud.C.decimals)
	H.pill.Fill.Size = UDim2.new(1, 0, 1, 0)
	Pill.setScale(H.pill, hud.C.scale * 0.82)
	task.delay(0.01, function()
		if H.pill and H.active then
			U.tween(H.pill.Scale, { Scale = hud.C.scale }, 0.2, Enum.EasingStyle.Back)
		end
	end)
end

local function hudReadyFade()
	if not H.pill or not H.gui then return end
	H.fading = true
	H.pill.Label.Text = U.fmt(0, hud.C.decimals)
	H.pill.Label.TextColor3 = Theme.Green
	H.pill.Fill.BackgroundColor3 = Theme.Green
	Pill.setScale(H.pill, hud.C.scale * 1.12)
	task.delay(0.24, function()
		if not H.pill or H.active then return end
		local p = H.pill
		p.Scale.Scale = hud.C.scale
		p.Holder.Position = UDim2.fromOffset(0, 0)
		local fade = TweenInfo.new(0.22, Enum.EasingStyle.Linear)
		TweenService:Create(p.Label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(p.Track, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(p.Fill, fade, { BackgroundTransparency = 1 }):Play()
		task.delay(0.26, function()
			if H.gui and not H.active then H.gui.Enabled = false end
		end)
	end)
end

hud.onRender = function(self, dt)
	local cam = workspace.CurrentCamera
	if not H.active or not H.pill or not H.gui or not H.gui.Parent then
		H.lastOffset = nil
		return
	end
	local head = hudHead()
	if not cam or not head then return end
	local cf = cam.CFrame
	local off = cf.RightVector * Layout.headX + cf.UpVector * Layout.headY
	local sp, onScreen = cam:WorldToViewportPoint(head.Position + off)
	if not H.lastOffset or (off - H.lastOffset).Magnitude > 0.001 then
		H.lastOffset = off
		H.gui.StudsOffsetWorldSpace = off
	end
	if not H.fading then
		local target = self.C.opacity
		if self.C.fade and onScreen then
			local vs = cam.ViewportSize
			local dx, dy = sp.X - vs.X * 0.5, sp.Y - vs.Y * 0.5
			target = target * U.clamp((math.sqrt(dx * dx + dy * dy) - 55) / 75, 0, 1)
		end
		local a = H.alpha + (target - H.alpha) * math.min(1, dt * 12)
		H.alpha = a
		if math.abs(a - H.lastAlpha) > 0.01 then
			H.lastAlpha = a
			Pill.alpha(H.pill, a, self.C.backdrop)
		end
	end
	local remain = H.endsAt - clock()
	if remain <= 0 then
		H.active = false
		H.pill.Fill.Size = UDim2.new(0, 0, 1, 0)
		H.lastAlpha = -1
		hudReadyFade()
	else
		local text = U.fmt(remain, self.C.decimals)
		if text ~= H.lastText then
			H.lastText = text
			H.pill.Label.Text = text
		end
		local ratio = U.clamp(remain / H.duration, 0, 1)
		if math.abs(ratio - H.lastRatio) > 0.01 then
			H.lastRatio = ratio
			H.pill.Fill.Size = UDim2.new(ratio, 0, 1, 0)
		end
	end
end

hud.init = function(self)
	Bus.on("cooldown:start", function(d)
		if hud.enabled then hudShow(d) end
	end)
	Bus.on("character", function()
		H.active = false
		if H.gui then H.gui:Destroy() end
		H.gui, H.pill = nil, nil
	end)
end

hud.api.preview = function(d) hudShow(d or 5) end
hud.api.style = function() hudStyle() end
hud.api.stylePreview = function(pill)
	Pill.reset(pill, hud.C.opacity, hud.C.backdrop)
	Pill.setScale(pill, hud.C.scale)
	pill.Label.Text = U.fmt(5, hud.C.decimals)
end

hud.actions.preview = function() hudShow(5) end

hud.onChange = function(self, key)
	if key == "scale" or key == "opacity" or key == "backdrop" or key == "decimals" then
		hudStyle()
		Bus.emit("hud:style")
	end
end

hud.onDisable = function()
	if H.gui then H.gui:Destroy() end
	H.gui, H.pill = nil, nil
	H.active, H.fading = false, false
end

--=============================================================================
-- 模块 · input（键盘逻辑；触屏按钮由 UI 壳绘制）
--=============================================================================
local input = Modules.define({
	id = "input",
	title = "Input",
	tab = "Input",
	order = 10,
	defaults = { enabled = true, keybind = "E", touch = false, platform = "PC", triggerX = -1, triggerY = -1 },
	settings = {
		{ type = "keybind", key = "keybind", label = "Trigger key" },
		{ type = "toggle", key = "touch", label = "Touch mode" },
		{ type = "segment", key = "platform", label = "Platform", options = { "PC", "Mobile" } },
		{ type = "note", label = "触屏按钮由 UI 壳绘制：可拖动，轻点触发，拖动不会触发。" },
		{ type = "button", label = "Reset trigger position", action = "resetPos" },
	},
})

local keyConn = nil

local function inputFire()
	local c = Modules.get("combat")
	if c and c.enabled and c.api.execute then c.api.execute() end
end

input.api.fire = inputFire

input.onEnable = function(self)
	if keyConn then keyConn:Disconnect() keyConn = nil end
	keyConn = UIS.InputBegan:Connect(function(obj, gpe)
		if gpe or not isCurrent() then return end
		if obj.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if obj.KeyCode == Enum.KeyCode.Unknown then return end
		local ok, key = pcall(function() return Enum.KeyCode[self.C.keybind] end)
		if ok and key and obj.KeyCode == key then inputFire() end
	end)
end

input.onDisable = function()
	if keyConn then keyConn:Disconnect() keyConn = nil end
end

input.actions.resetPos = function(self)
	self.C.triggerX, self.C.triggerY = -1, -1
	Store.mark()
	Bus.emit("input:resetPos")
	core.api.toast("Trigger position reset")
end

--=============================================================================
-- 模块 · layout（几何数据；编辑模式由 UI 壳实现）
--=============================================================================
local layout = Modules.define({
	id = "layout",
	title = "Window & HUD layout",
	tab = "Layout",
	order = 10,
	defaults = { enabled = true },
	settings = {
		{
			type = "toggle", label = "Snap to grid",
			get = function() return Layout.snap end,
			set = function(v) Layout.snap = v; Store.mark() end,
		},
		{
			type = "toggle", label = "Snap to screen edge",
			get = function() return Layout.edgeSnap end,
			set = function(v) Layout.edgeSnap = v; Store.mark() end,
		},
		{ type = "button", label = "Edit layout", action = "edit", primary = true },
		{ type = "button", label = "Reset layout", action = "reset" },
		{ type = "note", label = "编辑模式：拖标题栏移动、右下角缩放、拖头顶计时器定位、ESC 退出。" },
	},
})

layout.actions.edit = function() core.api.toggleEditMode() end
layout.actions.reset = function() core.resetLayoutData() end

--=============================================================================
-- 模块 · system
--=============================================================================
local system = Modules.define({
	id = "system",
	title = "System",
	tab = "System",
	order = 10,
	hideToggle = true,
	defaults = { enabled = true },
	settings = {
		{ type = "note", label = "配置写入 skidware_v5.json；v2/v3/v4 旧文件会自动迁移。" },
		{ type = "button", label = "Restore default config", action = "reset", primary = true },
		{ type = "button", label = "Close UI", action = "close" },
		{
			type = "custom",
			build = function(body, mod, ui)
				ui.widgets.note(body, "v" .. CORE_VERSION .. " · " .. tostring(#Modules.list) .. " modules · 已启用 "
					.. tostring(Modules.countEnabled()))
			end,
		},
	},
})

system.actions.reset = function()
	Store.resetAll()
	core.api.toast("Defaults restored")
end
system.actions.close = function() core.shutdown() end

--=============================================================================
-- 头顶胶囊原语（core 与 UI 壳共用）
--=============================================================================
Pill = {}

function Pill.build(parent)
	local holder = U.new("Frame", {
		Name = "Pill", Size = UDim2.fromOffset(PILL_W, PILL_H), BackgroundTransparency = 1,
	}, parent)
	local scale = U.new("UIScale", { Scale = 1 }, holder)
	local backdrop = U.new("Frame", {
		Name = "Backdrop", Size = UDim2.fromOffset(64, 25), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 1,
	}, holder)
	U.round(backdrop, 13)
	local label = U.new("TextLabel", {
		Name = "Value", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 25),
		Font = Enum.Font.GothamBlack, Text = "5.0", TextColor3 = Theme.White, TextSize = 19,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0, ZIndex = 2,
	}, holder)
	local track = U.new("Frame", {
		Name = "Track", Size = UDim2.new(0, 42, 0, 2), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 29), BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 2,
	}, holder)
	U.round(track, 1)
	local fill = U.new("Frame", {
		Name = "Fill", Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Theme.White, BorderSizePixel = 0,
	}, track)
	U.round(fill, 1)
	return { Holder = holder, Scale = scale, Backdrop = backdrop, Label = label, Track = track, Fill = fill }
end

function Pill.setScale(pill, s)
	if not pill then return end
	pill.Scale.Scale = s
	pill.Holder.Position = UDim2.fromOffset(-(PILL_W / 2) * (s - 1), -(PILL_H / 2) * (s - 1))
end

function Pill.alpha(pill, a, backdrop)
	if not pill then return end
	a = U.clamp(a, 0, 1)
	pill.Label.TextTransparency = 1 - a
	pill.Label.TextStrokeTransparency = 1 - a
	pill.Track.BackgroundTransparency = 1 - a * 0.55
	pill.Fill.BackgroundTransparency = 1 - a
	pill.Backdrop.BackgroundTransparency = backdrop and (1 - a * 0.5) or 1
end

function Pill.reset(pill, opacity, backdrop)
	pill.Label.TextColor3 = Theme.White
	pill.Fill.BackgroundColor3 = Theme.White
	pill.Fill.Size = UDim2.new(1, 0, 1, 0)
	Pill.alpha(pill, opacity or 1, backdrop)
end

--=============================================================================
-- Core 对象 + UI 能力槽
--=============================================================================
core = {
	version = CORE_VERSION,
	registry = Modules,
	modules = Modules.byId,
	list = Modules.list,
	bus = Bus,
	store = Store,
	char = CharSvc,
	theme = Theme,
	util = U,
	layout = Layout,
	pill = Pill,
	const = { PILL_W = PILL_W, PILL_H = PILL_H },
	uiShell = nil,
	uiVersion = nil,
}
_G.SkidwareCore = core

-- UI 可以覆盖这些能力；没挂 UI 时保持空实现，功能照常跑
core.api = {
	toast = function() end,
	toggleEditMode = function() end,
	setEditMode = function() end,
	resetLayout = function() end,
	styleGhost = function() end,
	refresh = function() end,
}
local DEFAULT_API = {}
for k, v in pairs(core.api) do DEFAULT_API[k] = v end

function core.resetApi()
	for k, v in pairs(DEFAULT_API) do core.api[k] = v end
end

function core.resetLayoutData()
	Layout.winW, Layout.winH = DefaultLayout.winW, DefaultLayout.winH
	Layout.winX = math.floor((viewport.X - Layout.winW) / 2)
	Layout.winY = math.floor((viewport.Y - Layout.winH) / 2)
	Layout.headX, Layout.headY = 0, 3.2
	Layout.snap, Layout.edgeSnap, Layout.grid = true, true, 4
	Store.mark()
	Bus.emit("layout:reset")
end

--=============================================================================
-- UI 壳加载器（GitHub）
--=============================================================================
local UI_CONFIG = {
	-- 改成你自己的仓库；下面的镜像与缓存键都跟它配套
	url = "https://raw.githubusercontent.com/USER/REPO/main/skid-ui.lua",
	mirrors = {
		"https://cdn.jsdelivr.net/gh/USER/REPO@main/skid-ui.lua",
		"https://raw.githack.com/USER/REPO/main/skid-ui.lua",
	},
	cache = "skid-ui-cache.lua",
	pin = "",             -- 可选：填 UI 文件的 sha256 十六进制，做完整性校验
	preferCache = true,   -- 先挂本地缓存秒开，再后台拉新版
	autoUpdate = true,    -- 后台比对版本，不同则热替换
	retryDelay = 20,
	maxRetries = 3,
	minBytes = 512,       -- 太短的内容当失败（错误页/空响应）
}

-- 允许外层脚本在加载 core 之前覆盖，避免改文件：
-- _G.SKID_UI_URL = "https://raw.githubusercontent.com/you/repo/main/skid-ui.lua"
-- _G.SKID_UI_PIN = ""
if type(_G.SKID_UI_URL) == "string" and #_G.SKID_UI_URL > 10 then UI_CONFIG.url = _G.SKID_UI_URL end
if type(_G.SKID_UI_PIN) == "string" then UI_CONFIG.pin = _G.SKID_UI_PIN end
if type(_G.SKID_UI_CACHE) == "string" and #_G.SKID_UI_CACHE > 3 then UI_CONFIG.cache = _G.SKID_UI_CACHE end

local UI_URL_IS_PLACEHOLDER = UI_CONFIG.url:find("USER/REPO", 1, true) ~= nil

local function fileExists(name)
	if type(ixf) == "function" then return ixf(name) end
	return false
end

local function readFile(name)
	if type(rf) ~= "function" then return nil end
	if type(ixf) == "function" and not fileExists(name) then return nil end
	local ok, data = pcall(rf, name)
	if ok and type(data) == "string" and #data >= UI_CONFIG.minBytes then return data end
	return nil
end

local function writeFile(name, data)
	if type(wf) ~= "function" then return end
	pcall(wf, name, data)
end

local function httpGet(url)
	local body
	if type(game) == "table" and type(game.HttpGet) == "function" then
		local ok, res = pcall(game.HttpGet, game, url, true)
		if ok and type(res) == "string" then body = res end
	end
	if not body and type(httpget) == "function" then
		local ok, res = pcall(httpget, url)
		if ok and type(res) == "string" then body = res end
	end
	if not body and type(request) == "function" then
		local ok, res = pcall(function() return request({ Url = url, Method = "GET" }).Body end)
		if ok and type(res) == "string" then body = res end
	end
	if not body and game and type(game.HttpGetAsync) == "function" then
		local ok, res = pcall(game.HttpGetAsync, game, url)
		if ok and type(res) == "string" then body = res end
	end
	if not body and HttpService then
		local ok, res = pcall(function() return HttpService:GetAsync(url, true) end)
		if ok and type(res) == "string" then body = res end
	end
	if body and #body >= UI_CONFIG.minBytes then return body end
	return nil
end

local function sha256(text)
	local fn
	if syn and syn.crypt and type(syn.crypt.hash) == "function" then fn = syn.crypt.hash end
	if not fn and crypt and type(crypt.hash) == "function" then fn = crypt.hash end
	if not fn and type(hashes) == "function" then fn = hashes end
	if not fn then return nil end
	local ok, out = pcall(fn, text)
	if ok and type(out) == "string" then return out:lower() end
	return nil
end

local function compileShell(src, name)
	local loaderFn = loadstring or load
	if type(loaderFn) ~= "function" then return nil, "no loadstring/load" end
	local ok, chunk = pcall(loaderFn, src, name or "=skid-ui")
	if not ok or type(chunk) ~= "function" then return nil, "compile failed: " .. tostring(chunk) end
	local ok2, shell = pcall(chunk)
	if not ok2 then return nil, "chunk error: " .. tostring(shell) end
	if type(shell) ~= "table" or type(shell.mount) ~= "function" then
		return nil, "shell 契约不符（需要 mount 函数）"
	end
	return shell
end

local function unmountShell()
	local shell = core.uiShell
	if not shell then return end
	core.uiShell = nil
	core.uiVersion = nil
	if type(shell.unmount) == "function" then pcall(shell.unmount) end
	core.resetApi()
	Bus.emit("ui:unmounted")
end

local function mountShell(shell, src)
	if core.uiShell == shell then return true end
	unmountShell()
	local ok, err = pcall(shell.mount, core)
	if not ok then
		warn("[skid-core] shell mount 失败: " .. tostring(err))
		core.resetApi()
		-- 远端壳坏了就退回上次缓存，别把用户晾在无面板状态
		local cachedShell = nil
		if src then
			local cached = readFile(UI_CONFIG.cache)
			if cached and cached ~= src then
				cachedShell = compileShell(cached, "=skid-ui-cache")
			end
		end
		if cachedShell and pcall(cachedShell.mount, core) then
			core.uiShell = cachedShell
			core.uiVersion = cachedShell.version
			warn("[skid-core] 已回退到缓存 UI v" .. tostring(cachedShell.version))
			Bus.emit("ui:mounted", cachedShell.version)
			return true
		end
		return false
	end
	core.uiShell = shell
	core.uiVersion = shell.version
	if src then writeFile(UI_CONFIG.cache, src) end
	Bus.emit("ui:mounted", shell.version)
	return true
end

local function pullRemote()
	if UI_URL_IS_PLACEHOLDER then
		return false, "UI_CONFIG.url 仍是占位地址（USER/REPO），请改成你的仓库 raw 链接"
	end
	local src = nil
	local urls = { UI_CONFIG.url }
	for _, u in ipairs(UI_CONFIG.mirrors) do urls[#urls + 1] = u end
	for _, url in ipairs(urls) do
		src = httpGet(url)
		if src then break end
	end
	if not src then return false, "fetch failed" end
	if UI_CONFIG.pin ~= "" then
		local digest = sha256(src)
		if digest and digest ~= UI_CONFIG.pin:lower() then
			return false, "sha256 mismatch"
		end
	end
	local shell, err = compileShell(src, "=skid-ui")
	if not shell then return false, err end
	if core.uiShell and core.uiVersion == shell.version then
		writeFile(UI_CONFIG.cache, src) -- 同版本：静默刷新缓存
		return true
	end
	local ok, mountErr = mountShell(shell, src)
	if not ok then return false, mountErr end
	return true
end

core.pullRemoteUI = pullRemote
core.uiConfig = UI_CONFIG

local function announce(msg)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "skidware", Text = msg, Duration = 4 })
	end)
end

local function bootUI()
	local cached = UI_CONFIG.preferCache and readFile(UI_CONFIG.cache) or nil
	if cached then
		local shell = compileShell(cached, "=skid-ui-cache")
		if shell then
			mountShell(shell)
		else
			warn("[skid-core] 本地 UI 缓存损坏，忽略")
		end
	end
	if not core.uiShell then
		local ok, err = pullRemote()
		if not ok then
			warn("[skid-core] UI 拉取失败（功能继续运行）: " .. tostring(err))
		end
	elseif UI_CONFIG.autoUpdate then
		task.spawn(function()
			task.wait(1)
			if isCurrent() then pcall(pullRemote) end
		end)
	end
	if not core.uiShell then
		task.spawn(function()
			local tries = 0
			while isCurrent() and not core.uiShell and tries < UI_CONFIG.maxRetries do
				task.wait(UI_CONFIG.retryDelay)
				tries = tries + 1
				if isCurrent() then pcall(pullRemote) end
			end
		end)
	end
end

--=============================================================================
-- 主循环
--=============================================================================
local function renderLoop(dt)
	if not isCurrent() then return end
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize ~= viewport then viewport = cam.ViewportSize end
	local list = Modules.renderList
	for i = 1, #list do
		local entry = list[i]
		if not entry.m.enabled then
			Modules.refreshHooks()
			break
		end
		local ok, err = pcall(entry.fn, entry.m, dt)
		if not ok then
			warn("[skid-core] " .. entry.m.id .. ":onRender: " .. tostring(err))
			entry.m.setEnabled(false, true)
			Bus.emit("ui:refresh")
			break
		end
	end
end

local function tickLoop(dt)
	if not isCurrent() then return end
	local list = Modules.tickList
	for i = 1, #list do
		local entry = list[i]
		if not entry.m.enabled then
			Modules.refreshHooks()
			break
		end
		local ok, err = pcall(entry.fn, entry.m, dt)
		if not ok then
			warn("[skid-core] " .. entry.m.id .. ":onTick: " .. tostring(err))
			entry.m.setEnabled(false, true)
			Bus.emit("ui:refresh")
			break
		end
	end
end

--=============================================================================
-- 启动
--=============================================================================
Store.load()
Modules.initAll()
Modules.startAll()
Modules.refreshHooks()

bind(RS.RenderStepped, renderLoop)
bind(RS.Heartbeat, tickLoop)

if player.Character then CharSvc.attach(player.Character) end
bind(player.CharacterAdded, function(char)
	if isCurrent() then CharSvc.attach(char) end
end)
bind(player.CharacterRemoving, function()
	if isCurrent() then CharSvc.detach() end
end)

task.spawn(function()
	while isCurrent() do
		if savePending and canSave and clock() >= saveAt then Store.flush() end
		task.wait(0.1)
	end
end)

bootUI()

--=============================================================================
-- 关闭
--=============================================================================
function core.shutdown()
	_G.SkidwareId = nil
	pcall(Store.flush)
	unmountShell()
	Modules.stopAll()
	Bus.clear()
	for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
	Connections = {}
	_G.SkidwareCore = nil
	_G.SkidwareDestroy = nil
end
_G.SkidwareDestroy = core.shutdown

task.spawn(function()
	announce("core v" .. CORE_VERSION .. " · " .. tostring(#Modules.list) .. " modules · UI "
		.. (core.uiShell and ("v" .. tostring(core.uiVersion)) or "待加载"))
end)