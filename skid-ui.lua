--=============================================================================
-- SKIDWARE UI · v1.0.0 —— 面板壳（从 GitHub 加载，通过 mount(core) 渲染功能模块）
--
--  契约：
--    return { version = "1.0.0",
--             mount   = function(core) end,   -- 构建全部界面并接管 core.api
--             unmount = function() end,       -- 销毁界面、断开连接、恢复 core.api
--             refresh = function() end }      -- 按模块配置重画控件
--
--  只依赖 core 暴露的东西：
--    core.registry（list/byId/define） core.modules  core.bus  core.store
--    core.theme  core.util  core.layout  core.pill  core.const  core.api
--  不包含任何战斗逻辑；按钮只调用模块的 actions/api。
--=============================================================================
local Shell = {}
Shell.version = "1.0.0"

local core            -- mount 时注入
local U, T            -- 工具 / 主题
local Layout, Store, Bus, Modules
local PILL_W, PILL_H

local S = {
    root = nil, win = nil, tabBar = nil, pages = nil, footer = nil,
    tabs = { defs = {}, active = 0 }, pagesByName = {},
    edit = { active = false, brackets = {}, gripLines = {}, ghostFrame = nil, ghostHit = nil, ghostPill = nil, hint = nil },
    minimized = false,
    refreshing = false,
    alive = false,
}
local refreshers = {}
local subs = {}
local drag = nil
local statusToken = 0

Shell.editActive = false

local function onSignal(sig, fn)
    local c = sig:Connect(fn)
    subs[#subs + 1] = c
    return c
end

local function onBus(evt, fn)
    local c = Bus.on(evt, fn)
    subs[#subs + 1] = c
    return c
end

--=============================================================================
-- 挂载
--=============================================================================
function Shell.mount(c)
    core = c
    U, T = core.util, core.theme
    Layout, Store, Bus, Modules = core.layout, core.store, core.bus, core.registry
    PILL_W, PILL_H = core.const.PILL_W, core.const.PILL_H
    S.alive = true
    S.minimized = false
    S.lastViewport = nil
    S.edit.active = false
    Shell.editActive = false
    refreshers = {}
    subs = {}

    --// ── 根 / 窗口 ────────────────────────────────────────────
    local root = U.new("ScreenGui", {
        Name = "SkidwareUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local guiParentOk = pcall(function() root.Parent = game:GetService("CoreGui") end)
    if not guiParentOk then
        root.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end
    S.root = root

    local PAD, TOP_H = 10, 30
    local TAB_TOP, TAB_H = 34, 20
    local PAGE_TOP, PAGE_BOTTOM = TAB_TOP + TAB_H + 8, 24
    local MARGIN, MAGNET = 6, 10

    local function windowSize() return UDim2.fromOffset(Layout.winW, Layout.winH) end
    local function snapPx(v)
        if not Layout.snap then return v end
        return math.floor(v / Layout.grid + 0.5) * Layout.grid
    end

    local viewport = function()
        local cam = workspace.CurrentCamera
        return (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    end

    local function clampWindow()
        local vp = viewport()
        local maxW = math.max(240, math.min(460, vp.X - MARGIN * 2))
        local maxH = math.max(260, math.min(640, vp.Y - MARGIN * 2))
        Layout.winW = math.floor(U.clamp(Layout.winW, 240, maxW))
        Layout.winH = math.floor(U.clamp(Layout.winH, 260, maxH))
        Layout.winX = math.floor(U.clamp(Layout.winX, MARGIN, math.max(MARGIN, vp.X - Layout.winW - MARGIN)))
        Layout.winY = math.floor(U.clamp(Layout.winY, MARGIN, math.max(MARGIN, vp.Y - Layout.winH - MARGIN)))
    end

    if Layout.winX < 0 or Layout.winY < 0 then
        local vp = viewport()
        Layout.winX = math.floor((vp.X - Layout.winW) / 2)
        Layout.winY = math.floor((vp.Y - Layout.winH) / 2)
    end
    clampWindow()

    local win = U.new("Frame", {
        Name = "Window",
        BackgroundColor3 = T.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(Layout.winX, Layout.winY),
        Size = windowSize(),
        ZIndex = 1,
    }, root)
    U.round(win, 10)
    local winStroke = U.stroke(win, T.Line, 1, 0.15)
    local winScale = U.new("UIScale", { Scale = 0.965 }, win)
    S.win = win

    local function applyWindow(animate)
        clampWindow()
        if animate then
            U.tween(win, { Position = UDim2.fromOffset(Layout.winX, Layout.winY), Size = windowSize() }, 0.18)
        else
            win.Position = UDim2.fromOffset(Layout.winX, Layout.winY)
            if not S.minimized then win.Size = windowSize() end
        end
        Bus.emit("ui:viewport")
    end

    U.new("Frame", {
        BackgroundColor3 = T.White, BackgroundTransparency = 0.94, BorderSizePixel = 0,
        Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 0, 0), ZIndex = 2,
    }, win)

    --// ── 标题栏 ──────────────────────────────────────────────
    local topBar = U.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TOP_H), ZIndex = 3 }, win)
    local grip = U.new("Frame", {
        Name = "TitleGrip", BackgroundTransparency = 1, Size = UDim2.new(1, -96, 1, 0), Active = true, ZIndex = 3,
    }, topBar)

    local statusDot = U.new("Frame", {
        Name = "StatusDot", BackgroundColor3 = T.Green, BorderSizePixel = 0,
        Size = UDim2.fromOffset(5, 5), Position = UDim2.new(0, 11, 0.5, -2.5), ZIndex = 3,
    }, grip)
    U.round(statusDot, 2.5)

    U.new("TextLabel", {
        Text = "skidware", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.Text,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 21, 0, 0), Size = UDim2.new(0, 100, 1, 0), ZIndex = 3,
    }, grip)
    U.new("TextLabel", {
        Text = "ui v" .. Shell.version, Font = Enum.Font.Gotham, TextSize = 8, TextColor3 = T.Muted,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 74, 0, 0), Size = UDim2.new(0, 90, 1, 0), ZIndex = 3,
    }, grip)

    grip.InputBegan:Connect(function(obj)
        if not U.isPrimary(obj) then return end
        local sx, sy = Layout.winX, Layout.winY
        drag = { input = obj, start = obj.Position }
        drag.move = function(d)
            local vp = viewport()
            local limitX = math.max(MARGIN, vp.X - Layout.winW - MARGIN)
            local limitY = math.max(MARGIN, vp.Y - Layout.winH - MARGIN)
            local nx, ny = snapPx(sx + d.X), snapPx(sy + d.Y)
            nx, ny = U.clamp(nx, MARGIN, limitX), U.clamp(ny, MARGIN, limitY)
            if Layout.edgeSnap then
                if math.abs(nx - MARGIN) <= MAGNET then nx = MARGIN
                elseif math.abs(nx - limitX) <= MAGNET then nx = limitX end
                if math.abs(ny - MARGIN) <= MAGNET then ny = MARGIN
                elseif math.abs(ny - limitY) <= MAGNET then ny = limitY end
            end
            nx, ny = math.floor(nx), math.floor(ny)
            if nx == Layout.winX and ny == Layout.winY then return end
            Layout.winX, Layout.winY = nx, ny
            win.Position = UDim2.fromOffset(nx, ny)
        end
        drag.stop = Store.mark
    end)

    --// ── 标签栏 ──────────────────────────────────────────────
    local tabBar = U.new("Frame", {
        Name = "TabBar", BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 0, TAB_TOP), Size = UDim2.new(1, -PAD * 2, 0, TAB_H), ZIndex = 3,
    }, win)
    S.tabBar = tabBar
    U.new("Frame", {
        BackgroundColor3 = T.LineSoft, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), ZIndex = 2,
    }, tabBar)

    local underline = U.new("Frame", {
        BackgroundColor3 = T.White, BorderSizePixel = 0,
        Size = UDim2.new(0.2, -12, 0, 2), Position = UDim2.new(0, 6, 1, -2), ZIndex = 3,
    }, tabBar)
    U.round(underline, 1)

    local pages = U.new("Frame", {
        Name = "Pages", BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 0, PAGE_TOP),
        Size = UDim2.new(1, -PAD * 2, 1, -(PAGE_TOP + PAGE_BOTTOM)), ZIndex = 3,
    }, win)
    S.pages = pages

    local function makePage()
        local scroller = U.new("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.Sub, ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y, ScrollingEnabled = true,
            ElasticBehavior = Enum.ElasticBehavior.Never, Visible = false, ZIndex = 3,
        }, pages)
        U.new("UIPadding", { PaddingBottom = UDim.new(0, 10) }, scroller)
        U.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroller)
        return scroller
    end

    --// ── 控件工厂 ────────────────────────────────────────────
    local W = {}

    function W.card(parent, title, subtitle)
        local frame = U.new("Frame", {
            Name = subtitle and ("ModuleCard:" .. subtitle) or nil,
            BackgroundColor3 = T.Card, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 3,
        }, parent)
        U.round(frame, 8)
        U.stroke(frame, T.LineSoft, 1, 0.25)
        U.new("UIPadding", {
            PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9),
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        }, frame)
        U.new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, frame)

        local head = U.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), ZIndex = 3 }, frame)
        U.new("Frame", {
            BackgroundColor3 = T.Muted, BorderSizePixel = 0,
            Size = UDim2.fromOffset(2, 8), Position = UDim2.new(0, 0, 0, 1), ZIndex = 3,
        }, head)
        U.new("TextLabel", {
            Text = string.upper(title), Font = Enum.Font.GothamBold, TextSize = 8,
            TextColor3 = T.Muted, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 7, 0, 0), Size = UDim2.new(1, -90, 1, 0), ZIndex = 3,
        }, head)
        if subtitle then
            U.new("TextLabel", {
                Text = subtitle, Font = Enum.Font.Gotham, TextSize = 8,
                TextColor3 = Color3.fromRGB(74, 74, 74), BackgroundTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Right,
                Position = UDim2.new(1, -80, 0, 0), Size = UDim2.new(0, 80, 1, 0), ZIndex = 3,
            }, head)
        end

        local body = U.new("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 3,
        }, frame)
        U.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
        return body
    end

    local function rowLabel(parent, text, h)
        return U.new("TextLabel", {
            Text = text, Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = T.Text,
            BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -40, 0, h), ZIndex = 3,
        }, parent)
    end

    function W.toggle(parent, label, getter, setter, opts)
        opts = opts or {}
        local row = U.new("Frame", {
            Name = opts.name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), ZIndex = 3,
        }, parent)
        local lbl = rowLabel(row, label, 20)
        lbl.Size = UDim2.new(1, -40, 0, 20)

        local track = U.new("Frame", {
            BackgroundColor3 = T.BgSoft, BorderSizePixel = 0,
            Size = UDim2.fromOffset(28, 16), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 3,
        }, row)
        U.round(track, 8)
        local trackStroke = U.stroke(track, T.Line, 1, 0.1)

        local knob = U.new("Frame", {
            BackgroundColor3 = Color3.fromRGB(118, 118, 118), BorderSizePixel = 0,
            Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 3, 0.5, 0), ZIndex = 4,
        }, track)
        U.round(knob, 5)

        local onColor = opts.accent and T.Green or Color3.fromRGB(242, 242, 242)
        local offColor = Color3.fromRGB(118, 118, 118)

        local function render(on, animate)
            local kp = UDim2.new(0, on and 15 or 3, 0.5, 0)
            local kc = on and Color3.fromRGB(10, 10, 10) or offColor
            local tc = on and onColor or T.BgSoft
            local sc = on and onColor or T.Line
            if animate then
                U.tween(knob, { Position = kp, BackgroundColor3 = kc }, 0.14)
                U.tween(track, { BackgroundColor3 = tc }, 0.14)
                U.tween(trackStroke, { Color = sc }, 0.14)
            else
                knob.Position, knob.BackgroundColor3 = kp, kc
                track.BackgroundColor3, trackStroke.Color = tc, sc
            end
        end
        render(getter(), false)
        refreshers[#refreshers + 1] = function() render(getter(), false) end

        local hit = U.new("TextButton", {
            Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1), ZIndex = 5,
        }, row)
        hit.MouseEnter:Connect(function() lbl.TextColor3 = T.White end)
        hit.MouseLeave:Connect(function() lbl.TextColor3 = T.Text end)
        hit.MouseButton1Click:Connect(function()
            local v = not getter()
            setter(v)
            render(v, true)
            Store.mark()
        end)
        return row
    end

    function W.slider(parent, label, min, max, step, decimals, getter, setter, suffix, stepper)
        local row = U.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 31), ZIndex = 3 }, parent)
        local lbl = rowLabel(row, label, 12)
        lbl.Size = UDim2.new(1, stepper and -92 or -50, 0, 12)

        local valueLabel = U.new("TextLabel", {
            Text = "", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = T.Sub,
            BackgroundTransparency = 1,
            TextXAlignment = stepper and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right,
            Size = stepper and UDim2.new(0, 42, 0, 12) or UDim2.new(0, 50, 0, 12),
            Position = stepper and UDim2.new(1, -68, 0, 0) or UDim2.new(1, -50, 0, 0),
            ZIndex = 4,
        }, row)

        local track = U.new("Frame", {
            BackgroundColor3 = T.Line, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 0, 22), ZIndex = 3,
        }, row)
        U.round(track, 2)

        local fill = U.new("Frame", {
            BackgroundColor3 = T.White, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0), ZIndex = 4,
        }, track)
        U.round(fill, 2)

        local knob = U.new("Frame", {
            BackgroundColor3 = T.White, BorderSizePixel = 0,
            Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 5,
        }, track)
        U.round(knob, 5)
        local knobStroke = U.stroke(knob, Color3.fromRGB(10, 10, 10), 2, 0)

        local hit = U.new("TextButton", {
            Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 17), Position = UDim2.new(0, 0, 0, 14), ZIndex = 6,
        }, row)

        local function render()
            local v = getter()
            local rel = U.clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            valueLabel.Text = U.fmt(v, decimals) .. (suffix or "")
        end
        refreshers[#refreshers + 1] = render

        local function apply(v)
            v = U.clamp(v, min, max)
            setter(tonumber(string.format("%.4f", v)))
            render()
        end
        local function applyFromX(px)
            local rel = U.clamp((px - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
            local raw = min + (max - min) * rel
            apply(min + math.floor((raw - min) / step + 0.5) * step)
        end

        if stepper then
            local function stepBtn(glyph, x, delta)
                local b = U.new("TextButton", {
                    Text = glyph, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.Sub,
                    BackgroundColor3 = T.BgSoft, BorderSizePixel = 0, AutoButtonColor = false,
                    Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, x, 0, -2), ZIndex = 7,
                }, row)
                U.round(b, 4)
                local bst = U.stroke(b, T.Line, 1, 0.2)
                b.MouseEnter:Connect(function()
                    U.tween(b, { BackgroundColor3 = T.Hover, TextColor3 = T.Text }, 0.1)
                    U.tween(bst, { Color = Color3.fromRGB(58, 58, 58) }, 0.1)
                end)
                b.MouseLeave:Connect(function()
                    U.tween(b, { BackgroundColor3 = T.BgSoft, TextColor3 = T.Sub }, 0.1)
                    U.tween(bst, { Color = T.Line }, 0.1)
                end)
                b.MouseButton1Click:Connect(function()
                    apply(getter() + delta)
                    Store.mark()
                end)
                return b
            end
            stepBtn("-", -88, -step)
            stepBtn("+", -20, step)
        end

        hit.MouseEnter:Connect(function()
            lbl.TextColor3 = T.White
            U.tween(knobStroke, { Transparency = 0.4 }, 0.1)
        end)
        hit.MouseLeave:Connect(function()
            lbl.TextColor3 = T.Text
            U.tween(knobStroke, { Transparency = 0 }, 0.1)
        end)
        hit.InputBegan:Connect(function(obj)
            if not U.isPrimary(obj) then return end
            applyFromX(obj.Position.X)
            drag = { input = obj, start = obj.Position }
            drag.move = function(d) applyFromX(obj.Position.X + d.X) end
            drag.stop = Store.mark
        end)

        render()
        return row
    end

    function W.segment(parent, label, options, getter, setter)
        local row = U.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), ZIndex = 3 }, parent)
        local lbl = rowLabel(row, label, 12)
        lbl.Size = UDim2.new(1, 0, 0, 12)

        local holder = U.new("Frame", {
            BackgroundColor3 = Color3.fromRGB(16, 16, 16), BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 16), ZIndex = 3,
        }, row)
        U.round(holder, 7)
        U.stroke(holder, T.Line, 1, 0.35)

        local buttons = {}
        local ON_BG, OFF_BG = Color3.fromRGB(238, 238, 238), Color3.fromRGB(16, 16, 16)
        local function render(animate)
            local current = getter()
            for i, opt in ipairs(options) do
                local b = buttons[i]
                if b then
                    local active = current == opt
                    local bg = active and ON_BG or OFF_BG
                    local tc = active and Color3.fromRGB(12, 12, 12) or Color3.fromRGB(124, 124, 124)
                    b.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
                    if animate then
                        U.tween(b, { BackgroundColor3 = bg, TextColor3 = tc }, 0.12)
                    else
                        b.BackgroundColor3, b.TextColor3 = bg, tc
                    end
                end
            end
        end
        refreshers[#refreshers + 1] = function() render(false) end

        for i, opt in ipairs(options) do
            local b = U.new("TextButton", {
                Text = opt, Font = Enum.Font.Gotham, TextSize = 9,
                TextColor3 = Color3.fromRGB(124, 124, 124), BackgroundColor3 = OFF_BG,
                BorderSizePixel = 0, AutoButtonColor = false,
                Size = UDim2.new(1 / #options, -4, 1, -4),
                Position = UDim2.new((i - 1) / #options, 2, 0, 2), ZIndex = 4,
            }, holder)
            U.round(b, 5)
            buttons[i] = b
            b.MouseButton1Click:Connect(function()
                setter(opt)
                render(true)
                Store.mark()
            end)
        end
        render(false)
        return row
    end

    function W.keybind(parent, label, getter, setter)
        local row = U.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), ZIndex = 3 }, parent)
        local lbl = rowLabel(row, label, 20)
        lbl.Size = UDim2.new(1, -62, 0, 20)

        local btn = U.new("TextButton", {
            Text = tostring(getter()), Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = T.Text, BackgroundColor3 = Color3.fromRGB(19, 19, 19),
            BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.fromOffset(52, 19), Position = UDim2.new(1, -52, 0.5, -9.5), ZIndex = 4,
        }, row)
        U.round(btn, 5)
        local bst = U.stroke(btn, Color3.fromRGB(46, 46, 46), 1, 0.1)

        local listening, conn, token = false, nil, 0
        local function stop()
            listening = false
            token = token + 1
            if conn then pcall(function() conn:Disconnect() end) conn = nil end
            btn.Text = tostring(getter())
            btn.TextColor3 = T.Text
            U.tween(bst, { Color = Color3.fromRGB(46, 46, 46) }, 0.12)
        end

        btn.MouseButton1Click:Connect(function()
            if listening then stop() return end
            listening = true
            token = token + 1
            local my = token
            btn.Text = "…"
            btn.TextColor3 = T.Muted
            U.tween(bst, { Color = T.Sub }, 0.12)
            local uis = game:GetService("UserInputService")
            conn = uis.InputBegan:Connect(function(obj, gpe)
                if not listening or token ~= my then return end
                if gpe then return end
                if obj.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if obj.KeyCode == Enum.KeyCode.Escape then stop() return end
                if obj.KeyCode == Enum.KeyCode.Unknown then return end
                setter(obj.KeyCode.Name)
                stop()
                Store.mark()
            end)
            task.delay(4, function()
                if listening and token == my then stop() end
            end)
        end)
        refreshers[#refreshers + 1] = function()
            if not listening then btn.Text = tostring(getter()) end
        end
        return row
    end

    function W.button(parent, label, onClick, opts)
        opts = opts or {}
        local primary = opts.primary
        local base = primary and T.OnBg or T.BgSoft
        local btn = U.new("TextButton", {
            Text = label, Font = Enum.Font.GothamSemibold, TextSize = 10,
            TextColor3 = primary and Color3.fromRGB(10, 10, 10) or T.Text,
            BackgroundColor3 = base, BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 23), ZIndex = 4,
        }, parent)
        U.round(btn, 6)
        local st = U.stroke(btn, primary and base or T.Line, 1, primary and 0 or 0.4)
        local hover = primary and Color3.fromRGB(224, 224, 224) or T.Hover
        local down = primary and Color3.fromRGB(206, 206, 206) or T.Press
        btn.MouseEnter:Connect(function()
            U.tween(btn, { BackgroundColor3 = hover }, 0.1)
            if not primary then U.tween(st, { Color = Color3.fromRGB(58, 58, 58) }, 0.1) end
        end)
        btn.MouseLeave:Connect(function()
            U.tween(btn, { BackgroundColor3 = base }, 0.1)
            if not primary then U.tween(st, { Color = T.Line }, 0.1) end
        end)
        btn.MouseButton1Down:Connect(function() U.tween(btn, { BackgroundColor3 = down }, 0.06) end)
        btn.MouseButton1Up:Connect(function() U.tween(btn, { BackgroundColor3 = hover }, 0.08) end)
        btn.MouseButton1Click:Connect(function()
            local ok, err = pcall(onClick)
            if not ok then warn("[skid-ui] button: " .. tostring(err)) end
        end)
        return btn
    end

    function W.note(parent, text)
        return U.new("TextLabel", {
            Text = text, Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = T.Muted,
            BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 3,
        }, parent)
    end

    function W.divider(parent)
        return U.new("Frame", {
            BackgroundColor3 = T.LineSoft, BackgroundTransparency = 0.4, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1), ZIndex = 3,
        }, parent)
    end

    --// ── Schema 渲染 ────────────────────────────────────────
    local function getterFor(mod, item)
        if item.get then return item.get end
        return function() return mod.get(item.key) end
    end
    local function setterFor(mod, item)
        if item.set then return item.set end
        return function(v) mod.set(item.key, v) end
    end

    local function renderItem(body, mod, item)
        local t = item.type
        if t == "toggle" then
            W.toggle(body, item.label or item.key, getterFor(mod, item), setterFor(mod, item))
        elseif t == "slider" then
            W.slider(body, item.label or item.key,
                item.min or 0, item.max or 1, item.step or 1, item.decimals or 0,
                getterFor(mod, item), setterFor(mod, item), item.suffix, item.stepper)
        elseif t == "segment" then
            W.segment(body, item.label or item.key, item.options or { "on", "off" },
                getterFor(mod, item), setterFor(mod, item))
        elseif t == "keybind" then
            W.keybind(body, item.label or "Key", getterFor(mod, item), setterFor(mod, item))
        elseif t == "button" then
            W.button(body, item.label or "Run", function()
                local fn = item.onClick or (item.action and mod.actions[item.action])
                if fn then return fn(mod) end
            end, { primary = item.primary })
        elseif t == "note" then
            W.note(body, item.label or "")
        elseif t == "divider" then
            W.divider(body)
        elseif t == "custom" and item.build then
            local ok, err = pcall(item.build, body, mod, { widgets = W, theme = T })
            if not ok then warn("[skid-ui] custom row: " .. tostring(err)) end
        end
    end

    local function renderCard(page, mod)
        local body = W.card(page, mod.title, mod.id)
        if not mod.spec.hideToggle then
            W.toggle(body, "Enabled", function() return mod.enabled end, function(v)
                mod.setEnabled(v)
            end, { accent = true, name = "Enable:" .. mod.id })
        end
        for _, item in ipairs(mod.settings) do
            renderItem(body, mod, item)
        end
        return body
    end

    --// ── 按模块分标签 ───────────────────────────────────────
    local TAB_ORDER = { "Combat", "HUD", "Input", "Layout", "System" }
    local TAB_INDEX = {}
    for i, name in ipairs(TAB_ORDER) do TAB_INDEX[name] = i end

    local groups, names = {}, {}
    for _, m in ipairs(Modules.list) do
        local tabName = m.tab or "General"
        if not groups[tabName] then
            groups[tabName] = {}
            names[#names + 1] = tabName
        end
        groups[tabName][#groups[tabName] + 1] = m
    end
    table.sort(names, function(a, b)
        local ia, ib = TAB_INDEX[a] or 99, TAB_INDEX[b] or 99
        if ia ~= ib then return ia < ib end
        return a < b
    end)
    for _, tabName in ipairs(names) do
        table.sort(groups[tabName], function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.id < b.id
        end)
    end

    local tabCount = math.max(1, #names)
    S.tabs.defs = {}
    local function selectTab(index)
        if S.tabs.active == index then return end
        local prev = S.tabs.active > 0 and S.tabs.defs[S.tabs.active] or nil
        if prev then prev.scroll = prev.page.CanvasPosition end
        S.tabs.active = index
        for i, def in ipairs(S.tabs.defs) do
            local on = i == index
            def.page.Visible = on
            def.btn.TextColor3 = on and T.Text or T.Muted
            def.btn.Font = on and Enum.Font.GothamBold or Enum.Font.GothamSemibold
            if on and def.scroll then def.page.CanvasPosition = def.scroll end
        end
        U.tween(underline, { Position = UDim2.new((index - 1) / tabCount, 6, 1, -2) }, 0.18)
    end

    for i, tabName in ipairs(names) do
        local page = makePage()
        S.pagesByName[tabName] = page
        local btn = U.new("TextButton", {
            Name = "Tab:" .. tabName,
            Text = tabName, Font = Enum.Font.GothamSemibold, TextSize = 10, TextColor3 = T.Muted,
            BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.new(1 / tabCount, 0, 1, 0),
            Position = UDim2.new((i - 1) / tabCount, 0, 0, 0), ZIndex = 3,
        }, tabBar)
        btn.MouseEnter:Connect(function()
            if S.tabs.active ~= i then btn.TextColor3 = T.Sub end
        end)
        btn.MouseLeave:Connect(function()
            if S.tabs.active ~= i then btn.TextColor3 = T.Muted end
        end)
        btn.MouseButton1Click:Connect(function() selectTab(i) end)
        S.tabs.defs[i] = { name = tabName, btn = btn, page = page, mods = groups[tabName] }
    end

    for _, def in ipairs(S.tabs.defs) do
        for _, mod in ipairs(def.mods) do
            mod.ui = mod.ui or {}
            mod.ui.card = renderCard(def.page, mod)
        end
    end

    --// ── 状态栏 ──────────────────────────────────────────────
    local footer = U.new("Frame", {
        Name = "Footer", BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 1, -20), Size = UDim2.new(1, -PAD * 2, 0, 14), ZIndex = 3,
    }, win)
    S.footer = footer
    local footDot = U.new("Frame", {
        BackgroundColor3 = T.Green, BorderSizePixel = 0,
        Size = UDim2.fromOffset(4, 4), Position = UDim2.new(0, 0, 0.5, -2), ZIndex = 3,
    }, footer)
    U.round(footDot, 2)
    local footText = U.new("TextLabel", {
        Text = "READY", Font = Enum.Font.GothamBold, TextSize = 8, TextColor3 = T.Green,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 9, 0, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 3,
    }, footer)
    local footHint = U.new("TextLabel", {
        Text = "EDIT LAYOUT", Font = Enum.Font.Gotham, TextSize = 8, TextColor3 = T.Muted,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0, 108, 1, 0), Position = UDim2.new(1, -122, 0, 0), ZIndex = 3,
    }, footer)

    --// ── Toast ──────────────────────────────────────────────
    local toast = U.new("Frame", {
        Name = "Toast", BackgroundColor3 = T.CardHi, BackgroundTransparency = 0.05,
        BorderSizePixel = 0, Size = UDim2.fromOffset(150, 24), Visible = false, ZIndex = 40,
    }, root)
    U.round(toast, 6)
    U.stroke(toast, T.Line, 1, 0.1)
    local toastLabel = U.new("TextLabel", {
        Text = "", Font = Enum.Font.GothamSemibold, TextSize = 9, TextColor3 = T.Text,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), ZIndex = 41,
    }, toast)

    local function placeToast()
        if not S.root then return end
        local w = U.clamp(toastLabel.TextBounds.X + 22, 80, math.max(90, viewport().X - 24))
        toast.Size = UDim2.fromOffset(w, 24)
        local x = win.AbsolutePosition.X + (win.AbsoluteSize.X - w) * 0.5
        local y = win.AbsolutePosition.Y + win.AbsoluteSize.Y - 32
        x = U.clamp(x, 6, math.max(6, viewport().X - w - 6))
        y = U.clamp(y, 6, math.max(6, viewport().Y - 24 - 6))
        toast.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end

    local toastToken, toastA, toastB = 0, nil, nil
    local function showToast(text)
        if not S.root or not S.root.Parent then return end
        toastToken = toastToken + 1
        local my = toastToken
        if toastA then pcall(function() toastA:Cancel() end) end
        if toastB then pcall(function() toastB:Cancel() end) end
        toastLabel.Text = text
        placeToast()
        toast.Visible = true
        toast.BackgroundTransparency = 0.05
        toastLabel.TextTransparency = 0
        task.delay(1.3, function()
            if my ~= toastToken or not S.root then return end
            local tween = game:GetService("TweenService")
            toastA = tween:Create(toast, TweenInfo.new(0.18), { BackgroundTransparency = 0.6 })
            toastB = tween:Create(toastLabel, TweenInfo.new(0.18), { TextTransparency = 0.5 })
            toastA:Play()
            toastB:Play()
            task.delay(0.22, function()
                if my == toastToken and S.root then toast.Visible = false end
            end)
        end)
    end

    --// ── 编辑模式 ───────────────────────────────────────────
    local function makeBrackets()
        local frames = {}
        for _, ax in ipairs({ 0, 1 }) do
            for _, ay in ipairs({ 0, 1 }) do
                local corner = U.new("Frame", {
                    BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10),
                    AnchorPoint = Vector2.new(ax, ay), Position = UDim2.new(ax, 0, ay, 0),
                    Visible = false, ZIndex = 30,
                }, win)
                U.new("Frame", {
                    BackgroundColor3 = T.White, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 1),
                    Position = UDim2.new(0, 0, ay, ay == 0 and 0 or -1), ZIndex = 30,
                }, corner)
                U.new("Frame", {
                    BackgroundColor3 = T.White, BorderSizePixel = 0,
                    Size = UDim2.new(0, 1, 1, 0),
                    Position = UDim2.new(ax, ax == 0 and 0 or -1, 0, 0), ZIndex = 30,
                }, corner)
                frames[#frames + 1] = corner
            end
        end
        return frames
    end
    S.edit.brackets = makeBrackets()

    local resizeGrip = U.new("TextButton", {
        Name = "ResizeGrip", Text = "", TextTransparency = 1, BackgroundTransparency = 1,
        AutoButtonColor = false, Size = UDim2.fromOffset(24, 24),
        Position = UDim2.new(1, -24, 1, -24), ZIndex = 34,
    }, win)
    for i = 1, 2 do
        S.edit.gripLines[i] = U.new("Frame", {
            BackgroundColor3 = T.Sub, BorderSizePixel = 0,
            Size = UDim2.fromOffset(1, 6), Rotation = 45, AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(1, -i * 4, 1, -i * 4), Visible = false, ZIndex = 30,
        }, resizeGrip)
    end
    local function gripVisual(on)
        for _, line in ipairs(S.edit.gripLines) do line.Visible = on end
    end
    resizeGrip.MouseEnter:Connect(function() if not S.minimized then gripVisual(true) end end)
    resizeGrip.MouseLeave:Connect(function() if not S.edit.active then gripVisual(false) end end)
    resizeGrip.InputBegan:Connect(function(obj)
        if not U.isPrimary(obj) then return end
        local sw, sh = Layout.winW, Layout.winH
        local vp = viewport()
        local maxW = math.max(240, math.min(460, vp.X - MARGIN * 2))
        local maxH = math.max(260, math.min(640, vp.Y - MARGIN * 2))
        drag = { input = obj, start = obj.Position }
        drag.move = function(d)
            local w = U.clamp(sw + d.X, 240, maxW)
            local h = U.clamp(sh + d.Y, 260, maxH)
            if Layout.snap then
                w = math.floor(w / Layout.grid + 0.5) * Layout.grid
                h = math.floor(h / Layout.grid + 0.5) * Layout.grid
            end
            w, h = math.floor(w), math.floor(h)
            if w == Layout.winW and h == Layout.winH then return end
            Layout.winW, Layout.winH = w, h
            win.Size = UDim2.fromOffset(w, h)
        end
        drag.stop = Store.mark
    end)

    local hint = U.new("Frame", {
        Name = "EditHint", BackgroundColor3 = T.BgSoft, BackgroundTransparency = 0.05,
        BorderSizePixel = 0, Size = UDim2.new(1, -PAD * 2, 0, 16),
        Position = UDim2.new(0, PAD, 1, -20), Visible = false, ZIndex = 30,
    }, win)
    U.round(hint, 5)
    U.stroke(hint, T.Line, 1, 0.1)
    U.new("TextLabel", {
        Text = "EDIT · 拖标题栏移动 · 右下角缩放 · 拖头顶计时器定位 · ESC 退出",
        Font = Enum.Font.Gotham, TextSize = 8, TextColor3 = T.Sub,
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 31,
    }, hint)
    S.edit.hint = hint

    -- 幽灵胶囊（用 core.pill，样子跟随 hud 模块）
    local ghostHolder = U.new("Frame", {
        Name = "HeadTimerGhost", BackgroundTransparency = 1,
        Size = UDim2.fromOffset(PILL_W, PILL_H), Visible = false, ZIndex = 25,
    }, root)
    local ghostPill = core.pill.build(ghostHolder)
    core.pill.reset(ghostPill, 1, true)
    ghostPill.Label.Text = "5.0"
    local ghostHit = U.new("TextButton", {
        Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1), ZIndex = 30,
    }, ghostHolder)
    S.edit.ghostFrame, S.edit.ghostPill, S.edit.ghostHit = ghostHolder, ghostPill, ghostHit

    local function styleGhost()
        if not S.edit.ghostPill then return end
        local hud = Modules.get("hud")
        if hud and hud.api and hud.api.stylePreview then
            local ok, err = pcall(hud.api.stylePreview, S.edit.ghostPill)
            if not ok then warn("[skid-ui] ghost style: " .. tostring(err)) end
        else
            core.pill.reset(S.edit.ghostPill, 1, true)
            core.pill.setScale(S.edit.ghostPill, 1)
        end
    end
    S.styleGhost = styleGhost

    ghostHit.InputBegan:Connect(function(obj)
        if not S.edit.active or not U.isPrimary(obj) then return end
        local cam = workspace.CurrentCamera
        local char = core.char.character
        local head = char and char:FindFirstChild("Head")
        if not cam or not head then
            showToast("No character to anchor")
            return
        end
        local startX, startY = Layout.headX, Layout.headY
        local cf = cam.CFrame
        local anchor = head.Position + cf.RightVector * startX + cf.UpVector * startY
        local dist = math.max((cf.Position - anchor).Magnitude, 1)
        local pps = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2) * dist)
        drag = { input = obj, start = obj.Position }
        drag.move = function(d)
            Layout.headX = U.clamp(startX + d.X / pps, -4, 4)
            Layout.headY = U.clamp(startY - d.Y / pps, 0.2, 8)
        end
        drag.stop = Store.mark
    end)

    local function updateGhost()
        if not S.edit.active then return end
        local cam = workspace.CurrentCamera
        local char = core.char.character
        local head = char and char:FindFirstChild("Head")
        if not cam or not head then
            ghostHolder.Visible = false
            return
        end
        local cf = cam.CFrame
        local off = cf.RightVector * Layout.headX + cf.UpVector * Layout.headY
        local sp, onScreen = cam:WorldToViewportPoint(head.Position + off)
        if onScreen then
            ghostHolder.Visible = true
            ghostHolder.Position = UDim2.fromOffset(sp.X - PILL_W / 2, sp.Y - PILL_H / 2)
        else
            ghostHolder.Visible = false
        end
    end

    local function setEditMode(on)
        if S.edit.active == on then return end
        S.edit.active = on
        Shell.editActive = on
        for _, b in ipairs(S.edit.brackets) do b.Visible = on and not S.minimized end
        hint.Visible = on and not S.minimized
        footer.Visible = (not on) and (not S.minimized)
        gripVisual(on)
        U.tween(winStroke, { Color = on and T.White or T.Line, Transparency = on and 0.2 or 0.15 }, 0.14)
        footHint.Text = on and "EDIT MODE · ON" or "EDIT LAYOUT"
        footHint.TextColor3 = on and T.Text or T.Muted
        ghostHolder.Visible = false
        if on then
            styleGhost()
            showToast("Layout edit on")
        else
            Store.mark()
        end
    end

    local function setMinimized(on)
        if S.minimized == on then return end
        if on then setEditMode(false) end
        S.minimized = on
        tabBar.Visible = not on
        pages.Visible = not on
        footer.Visible = (not on) and (not S.edit.active)
        hint.Visible = (not on) and S.edit.active
        resizeGrip.Visible = not on
        for _, b in ipairs(S.edit.brackets) do b.Visible = (not on) and S.edit.active end
        ghostHolder.Visible = false
        U.tween(win, { Size = on and UDim2.fromOffset(Layout.winW, TOP_H) or windowSize() }, 0.18)
    end

    --// ── 顶部按钮 / 确认框 ───────────────────────────────────
    local confirm = U.new("TextButton", {
        Name = "ConfirmDialog", Text = "", AutoButtonColor = false,
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 40,
    }, win)
    U.round(confirm, 10)
    confirm.MouseButton1Click:Connect(function() confirm.Visible = false end)

    local confirmCard = U.new("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = T.CardHi,
        BorderSizePixel = 0, Size = UDim2.fromOffset(196, 96),
        Position = UDim2.new(0.5, -98, 0.5, -48), ZIndex = 41,
    }, confirm)
    U.round(confirmCard, 8)
    U.stroke(confirmCard, T.Line, 1, 0)
    U.new("TextLabel", {
        Text = "Close skidware?", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.Text,
        BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 14),
        Position = UDim2.new(0, 12, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42,
    }, confirmCard)
    U.new("TextLabel", {
        Text = "配置与布局会写入本地文件。", Font = Enum.Font.Gotham, TextSize = 9,
        TextColor3 = T.Muted, BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 12), Position = UDim2.new(0, 12, 0, 33),
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42,
    }, confirmCard)

    local function confirmButton(text, x, primary, onClick)
        local base = primary and T.OnBg or Color3.fromRGB(26, 26, 26)
        local b = U.new("TextButton", {
            Text = text, Font = Enum.Font.GothamSemibold, TextSize = 9,
            TextColor3 = primary and Color3.fromRGB(10, 10, 10) or T.Text,
            BackgroundColor3 = base, BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.fromOffset(80, 22), Position = UDim2.new(0, x, 0, 62), ZIndex = 42,
        }, confirmCard)
        U.round(b, 6)
        U.stroke(b, primary and base or T.Line, 1, primary and 0 or 0.35)
        b.MouseEnter:Connect(function()
            U.tween(b, { BackgroundColor3 = primary and Color3.fromRGB(224, 224, 224) or Color3.fromRGB(34, 34, 34) }, 0.1)
        end)
        b.MouseLeave:Connect(function() U.tween(b, { BackgroundColor3 = base }, 0.1) end)
        b.MouseButton1Click:Connect(onClick)
        return b
    end
    confirmButton("Cancel", 12, false, function() confirm.Visible = false end)
    confirmButton("Close", 104, true, function()
        if _G.SkidwareDestroy then _G.SkidwareDestroy() end
    end)

    local function iconBar(btn, w, h, rotation)
        return U.new("Frame", {
            BackgroundColor3 = Color3.fromRGB(150, 150, 150), BorderSizePixel = 0,
            Size = UDim2.new(0, w, 0, h), AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Rotation = rotation or 0, ZIndex = 5,
        }, btn)
    end
    local Icons = {
        grid = function(btn)
            for ix = 0, 1 do
                for iy = 0, 1 do
                    U.new("Frame", {
                        BackgroundColor3 = Color3.fromRGB(150, 150, 150), BorderSizePixel = 0,
                        Size = UDim2.fromOffset(3, 3), AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.new(0.5, (ix == 0) and -2.5 or 2.5, 0.5, (iy == 0) and -2.5 or 2.5),
                        ZIndex = 5,
                    }, btn)
                end
            end
        end,
        minus = function(btn) iconBar(btn, 8, 1.5) end,
        close = function(btn)
            iconBar(btn, 7, 1.5, 45)
            iconBar(btn, 7, 1.5, -45)
        end,
    }

    local function topButton(xOffset, name, callback, icon)
        local btn = U.new("TextButton", {
            Name = name, Text = "", BackgroundColor3 = Color3.fromRGB(19, 19, 19),
            BorderSizePixel = 0, Size = UDim2.fromOffset(22, 22),
            Position = UDim2.new(1, xOffset, 0, 4), AutoButtonColor = false, ZIndex = 4,
        }, topBar)
        U.round(btn, 5)
        local st = U.stroke(btn, Color3.fromRGB(46, 46, 46), 1, 0.1)
        if icon then icon(btn) end
        local function tint(color, s)
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("Frame") then U.tween(child, { BackgroundColor3 = color }, s) end
            end
        end
        btn.MouseEnter:Connect(function()
            U.tween(btn, { BackgroundColor3 = Color3.fromRGB(34, 34, 34) }, 0.1)
            U.tween(st, { Color = Color3.fromRGB(70, 70, 70) }, 0.1)
            tint(Color3.fromRGB(244, 244, 244), 0.1)
        end)
        btn.MouseLeave:Connect(function()
            U.tween(btn, { BackgroundColor3 = Color3.fromRGB(19, 19, 19) }, 0.1)
            U.tween(st, { Color = Color3.fromRGB(46, 46, 46) }, 0.1)
            tint(Color3.fromRGB(150, 150, 150), 0.1)
        end)
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    topButton(-80, "TopEdit", function() setEditMode(not S.edit.active) end, Icons.grid)
    topButton(-56, "TopMinimize", function() setMinimized(not S.minimized) end, Icons.minus)
    topButton(-32, "TopClose", function() confirm.Visible = true end, Icons.close)

    --// ── 触屏触发按钮（UI 侧绘制，动作走 core 模块）──────────
    local inputMod = Modules.get("input")
    local TRIG = 52
    local triggerBtn = U.new("TextButton", {
        Name = "MobileTrigger", Text = "SKID",
        Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = T.Text,
        BackgroundColor3 = T.Card, BackgroundTransparency = 0.05, BorderSizePixel = 0,
        AutoButtonColor = false, Size = UDim2.fromOffset(TRIG, TRIG),
        Position = UDim2.fromOffset(0, 0), Visible = false, Active = true, ZIndex = 6,
    }, root)
    U.round(triggerBtn, 26)
    local triggerStroke = U.stroke(triggerBtn, T.Line, 1, 0.1)

    local function triggerClamp()
        if not inputMod then return end
        local vp = viewport()
        if inputMod.C.triggerX < 0 or inputMod.C.triggerY < 0 then
            inputMod.C.triggerX = math.floor(vp.X * 0.74)
            inputMod.C.triggerY = math.floor(vp.Y * 0.55)
        end
        inputMod.C.triggerX = math.floor(U.clamp(inputMod.C.triggerX, 4, math.max(4, vp.X - TRIG - 4)))
        inputMod.C.triggerY = math.floor(U.clamp(inputMod.C.triggerY, 4, math.max(4, vp.Y - TRIG - 4)))
        triggerBtn.Position = UDim2.fromOffset(inputMod.C.triggerX, inputMod.C.triggerY)
    end

    local function triggerSync()
        if not inputMod then return end
        local combat = Modules.get("combat")
        local on = combat and combat.enabled
        triggerBtn.Visible = inputMod.enabled and inputMod.C.touch and inputMod.C.platform == "Mobile"
        triggerBtn.BackgroundColor3 = on and T.Card or Color3.fromRGB(28, 18, 18)
        triggerBtn.TextColor3 = on and T.Text or T.Muted
        triggerStroke.Color = on and T.Line or Color3.fromRGB(64, 32, 32)
    end

    triggerBtn.InputBegan:Connect(function(obj)
        if not U.isPrimary(obj) or not inputMod then return end
        local sx, sy = inputMod.C.triggerX, inputMod.C.triggerY
        local moved = false
        drag = { input = obj, start = obj.Position }
        drag.move = function(d)
            if math.abs(d.X) + math.abs(d.Y) > 6 then moved = true end
            local vp = viewport()
            local nx = U.clamp(sx + d.X, 4, math.max(4, vp.X - TRIG - 4))
            local ny = U.clamp(sy + d.Y, 4, math.max(4, vp.Y - TRIG - 4))
            inputMod.C.triggerX, inputMod.C.triggerY = math.floor(nx), math.floor(ny)
            triggerBtn.Position = UDim2.fromOffset(inputMod.C.triggerX, inputMod.C.triggerY)
        end
        drag.stop = function()
            if moved then Store.mark() else
                if inputMod.api and inputMod.api.fire then inputMod.api.fire() end
            end
        end
    end)

    --// ── core.api 接管 ──────────────────────────────────────
    core.api.toast = showToast
    core.api.refresh = function() Shell.refresh() end
    core.api.setEditMode = setEditMode
    core.api.toggleEditMode = function() setEditMode(not S.edit.active) end
    core.api.resetLayout = function()
        core.resetLayoutData()
        applyWindow(true)
        styleGhost()
    end
    core.api.styleGhost = styleGhost
    S.applyWindow = applyWindow
    S.placeToast = placeToast
    S.styleGhost = styleGhost

    --// ── 总线 / 输入 ────────────────────────────────────────
    onBus("ui:refresh", function() Shell.refresh() end)
    onBus("store:reset", function()
        applyWindow(true)
        Shell.refresh()
        styleGhost()
        triggerClamp()
    end)
    onBus("layout:reset", function()
        applyWindow(true)
        styleGhost()
    end)
    onBus("input:resetPos", function() triggerClamp() end)
    onBus("hud:style", function() styleGhost() end)
    onBus("module", function() triggerSync() end)
    onBus("config", function(id)
        if id == "input" then
            triggerClamp()
            triggerSync()
        end
    end)

    local uis = game:GetService("UserInputService")
    onSignal(uis.InputChanged, function(obj)
        if not drag then return end
        local t = obj.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
        if not (obj == drag.input or (drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and t == Enum.UserInputType.MouseMovement)) then return end
        if drag.move then drag.move(obj.Position - drag.start) end
    end)
    onSignal(uis.InputEnded, function(obj)
        if not drag then return end
        local t = obj.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        if not (obj == drag.input or (drag.input.UserInputType == Enum.UserInputType.MouseButton1
            and t == Enum.UserInputType.MouseButton1)) then return end
        local d = drag
        drag = nil
        if d.stop then d.stop() end
    end)
    onSignal(uis.InputBegan, function(obj, gpe)
        if obj.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if obj.KeyCode == Enum.KeyCode.Escape then
            if confirm.Visible then
                confirm.Visible = false
            elseif S.edit.active then
                setEditMode(false)
            end
            return
        end
        if gpe then return end
        if obj.KeyCode == Enum.KeyCode.Return and confirm.Visible then
            if _G.SkidwareDestroy then _G.SkidwareDestroy() end
        end
    end)

    --// ── 状态刷新 / 幽灵跟随 / 视口变化 ──────────────────────
    local lastStatus = nil
    local function syncStatus()
        if not S.root then return end
        local cd = Modules.get("cooldown")
        local remain = (cd and cd.enabled and cd.api and cd.api.remaining) and cd.api.remaining() or 0
        local text, color
        if remain > 0 then
            text = string.format("COOLDOWN %.1fs", remain)
            color = T.Sub
        else
            text = "READY · " .. tostring(Modules.countEnabled()) .. "/" .. tostring(#Modules.list) .. " modules"
            color = T.Green
        end
        if text == lastStatus then return end
        lastStatus = text
        footText.Text = text
        footText.TextColor3 = color
        footDot.BackgroundColor3 = color
    end
    S.syncStatus = syncStatus

    local renderConn = game:GetService("RunService").RenderStepped:Connect(function()
        if not S.alive or not S.root then return end
        updateGhost()
        if S.root and S.root.Parent == nil then return end
        local vp = viewport()
        if S.lastViewport and (S.lastViewport.X ~= vp.X or S.lastViewport.Y ~= vp.Y) then
            applyWindow(false)
            placeToast()
            triggerClamp()
        end
        S.lastViewport = vp
    end)
    subs[#subs + 1] = { Disconnect = function() renderConn:Disconnect() end }

    local myToken = statusToken + 1
    statusToken = myToken
    task.spawn(function()
        while S.alive and statusToken == myToken do
            syncStatus()
            task.wait(0.1)
        end
    end)

    --// ── 打开动画 / 收尾 ────────────────────────────────────
    selectTab(1)
    S.tabs.active = 1
    triggerClamp()
    triggerSync()
    U.tween(winScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
    return true
end

--=============================================================================
-- 刷新 / 卸载
--=============================================================================
function Shell.refresh()
    if not S.root or S.refreshing then return end
    S.refreshing = true
    for i = 1, #refreshers do pcall(refreshers[i]) end
    S.refreshing = false
end

function Shell.unmount()
    S.alive = false
    statusToken = statusToken + 1
    for _, c in ipairs(subs) do pcall(function() c:Disconnect() end) end
    subs = {}
    drag = nil
    if S.root then S.root:Destroy() end
    S.root, S.win, S.tabBar, S.pages, S.footer = nil, nil, nil, nil, nil
    S.tabs.defs, S.tabs.active, S.pagesByName = {}, 0, {}
    S.edit.brackets, S.edit.gripLines = {}, {}
    S.edit.ghostFrame, S.edit.ghostHit, S.edit.ghostPill = nil, nil, nil
    S.edit.hint, S.edit.active = nil, false
    Shell.editActive = false
    refreshers = {}
    if core then core.resetApi() end
end

return Shell
