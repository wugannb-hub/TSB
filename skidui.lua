--=============================================================
-- skidui.lua · 独立 UI 库（纯界面组件，不含任何游戏逻辑）
--
-- Usage
--   local UILib = loadstring(game:HttpGet("<你的 raw 地址>"))()
--   local ui = UILib.mount({ ... })          -- 见下
--   local page = ui.tab("Home")
--   local body = ui.card(page, "Status")
--   ui.toggle(body, "Enable", getter, setter)
--   ui.slider(body, "Speed", 1, 50, 1, 0, getter, setter, "x")
--   ui.segment(body, "Mode", {"A","B"}, getter, setter)
--   ui.keybind(body, "Hotkey", getter, setter)
--   ui.action(body, "Do thing", onClick, true)
--   ui.refresh()  ui.toast("hi")  ui.setStatus("READY", true)  ui.destroy()
--
-- mount 参数
--   title, version, name, displayOrder
--   layout    兼容旧版 Layout 表（WinX/WinY/WinW/WinH/Snap/Grid），UI 会读写它
--   persist   (可选) 需要保存时回调
--   accent    默认强调色
--   onEditMode(可选) 布局编辑开关回调
--   onClose   (可选) 点关闭时回调，不传则直接销毁
--=============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

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
}

local function new(class, props, parent)
    local inst = Instance.new(class)
    if props then for k, v in pairs(props) do inst[k] = v end end
    if parent then inst.Parent = parent end
    return inst
end
local function round(obj, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, obj) end
local function outline(obj, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Theme.Line,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end
local function tweenTo(obj, props, seconds, style, dir)
    local t = TweenService:Create(
        obj,
        TweenInfo.new(seconds or 0.14, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function fmtValue(v, d) return string.format("%." .. tostring(d or 0) .. "f", v) end

local UILib = {}

function UILib.mount(opts)
    opts = opts or {}
    local Layout = opts.layout or {}
    Layout.WinX = tonumber(Layout.WinX) or -1
    Layout.WinY = tonumber(Layout.WinY) or -1
    Layout.WinW = tonumber(Layout.WinW) or 276
    Layout.WinH = tonumber(Layout.WinH) or 372
    if Layout.Snap == nil then Layout.Snap = true end
    Layout.Grid = tonumber(Layout.Grid) or 4

    local Persist = opts.persist or function() end
    local Refreshers = {}
    local Connections = {}
    local function keep(c) Connections[#Connections + 1] = c return c end

    local cam = workspace.CurrentCamera
    local viewport = (cam and cam.ViewportSize) or Vector2.new(1280, 720)

    --// ── 拖拽（窗口 / 缩放 / 滑块共用）──────────────────────────
    local drag = nil
    local function beginDrag(startPos, onDelta, onEnd)
        drag = { start = startPos, move = onDelta, stop = onEnd }
    end
    keep(UIS.InputChanged:Connect(function(i)
        if not drag then return end
        local t = i.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
        drag.move(i.Position - drag.start)
    end))
    keep(UIS.InputEnded:Connect(function(i)
        if not drag then return end
        local t = i.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        local d = drag
        drag = nil
        if d.stop then d.stop() end
    end))

    --// ── 根容器 ───────────────────────────────────────────────
    local Root = new("ScreenGui", {
        Name = opts.name or "UILibRoot",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = opts.displayOrder or 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    if not pcall(function() Root.Parent = CoreGui end) then
        Root.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local PAD = 10
    local TOP_H = 30
    local TAB_TOP, TAB_H = 34, 20
    local PAGE_TOP = TAB_TOP + TAB_H + 8
    local PAGE_BOTTOM = 24

    local Win = new("Frame", {
        Name = "Window",
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 1,
    }, Root)
    round(Win, 10)
    local winStroke = outline(Win, Theme.Line, 1, 0.15)

    local function windowSize() return UDim2.fromOffset(Layout.WinW, Layout.WinH) end
    local function snapPx(v)
        if not Layout.Snap then return v end
        return math.floor(v / Layout.Grid + 0.5) * Layout.Grid
    end
    local function clampWindow()
        local maxW = math.max(240, math.min(460, viewport.X - 16))
        local maxH = math.max(240, math.min(620, viewport.Y - 16))
        Layout.WinW = clamp(Layout.WinW, 240, maxW)
        Layout.WinH = clamp(Layout.WinH, 248, maxH)
        Layout.WinX = clamp(Layout.WinX, 4, math.max(4, viewport.X - Layout.WinW - 4))
        Layout.WinY = clamp(Layout.WinY, 4, math.max(4, viewport.Y - Layout.WinH - 4))
    end

    if Layout.WinX < 0 or Layout.WinY < 0 then
        Layout.WinW = math.min(Layout.WinW, math.max(240, viewport.X - 32))
        Layout.WinH = math.min(Layout.WinH, math.max(248, viewport.Y - 32))
        Layout.WinX = math.floor((viewport.X - Layout.WinW) / 2)
        Layout.WinY = math.floor((viewport.Y - Layout.WinH) / 2)
    end
    clampWindow()
    Win.Position = UDim2.fromOffset(Layout.WinX, Layout.WinY)
    Win.Size = windowSize()

    new("Frame", {
        BackgroundColor3 = Theme.White,
        BackgroundTransparency = 0.94,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -16, 0, 1),
        Position = UDim2.new(0, 8, 0, 0),
        ZIndex = 2,
    }, Win)

    --// ── 标题栏 ───────────────────────────────────────────────
    local TopBar = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TOP_H), ZIndex = 3 }, Win)
    local Grip = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -96, 1, 0),
        Active = true,
        ZIndex = 3,
    }, TopBar)

    local statusDot = new("Frame", {
        BackgroundColor3 = opts.accent or Theme.Green,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(5, 5),
        Position = UDim2.new(0, 11, 0.5, -2.5),
        ZIndex = 3,
    }, Grip)
    round(statusDot, 2.5)

    new("TextLabel", {
        Text = opts.title or "ui",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.Text,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 21, 0, 0),
        Size = UDim2.new(0, 100, 1, 0),
        ZIndex = 3,
    }, Grip)
    new("TextLabel", {
        Text = opts.version or "",
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 74, 0, 0),
        Size = UDim2.new(0, 40, 1, 0),
        ZIndex = 3,
    }, Grip)

    --// ── 标签栏 ───────────────────────────────────────────────
    local TabBar = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 0, TAB_TOP),
        Size = UDim2.new(1, -PAD * 2, 0, TAB_H),
        ZIndex = 3,
    }, Win)
    new("Frame", {
        BackgroundColor3 = Theme.LineSoft,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        ZIndex = 2,
    }, TabBar)

    local Underline = new("Frame", {
        BackgroundColor3 = Theme.White,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -12, 0, 2),
        Position = UDim2.new(0, 6, 1, -2),
        ZIndex = 3,
    }, TabBar)
    round(Underline, 1)

    local Pages = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 0, PAGE_TOP),
        Size = UDim2.new(1, -PAD * 2, 1, -(PAGE_TOP + PAGE_BOTTOM)),
        ZIndex = 3,
    }, Win)

    --// ── 页面 ─────────────────────────────────────────────────
    local function makePage()
        local scroller = new("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Sub,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollingEnabled = true,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            Visible = false,
            ZIndex = 3,
        }, Pages)
        new("UIPadding", { PaddingBottom = UDim.new(0, 10) }, scroller)
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroller)
        return scroller
    end

    --// ── 组件 ─────────────────────────────────────────────────
    local function card(parent, title)
        local frame = new("Frame", {
            BackgroundColor3 = Theme.Card,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 3,
        }, parent)
        round(frame, 8)
        outline(frame, Theme.LineSoft, 1, 0.25)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9),
        }, frame)
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
        new("TextLabel", {
            Text = string.upper(title or ""),
            Font = Enum.Font.GothamBold,
            TextSize = 8,
            TextColor3 = Theme.Muted,
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, 0, 0, 10),
            ZIndex = 3,
        }, frame)
        local body = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 3,
        }, frame)
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
        return body
    end

    local function rowLabel(parent, text, h)
        return new("TextLabel", {
            Text = text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = Theme.Text,
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -40, 0, h),
            ZIndex = 3,
        }, parent)
    end

    local function toggleRow(parent, text, getter, setter)
        local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), ZIndex = 3 }, parent)
        rowLabel(row, text, 20).Size = UDim2.new(1, -36, 0, 20)

        local track = new("Frame", {
            BackgroundColor3 = Theme.BgSoft,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(28, 16),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            ZIndex = 3,
        }, row)
        round(track, 8)
        local trackStroke = outline(track, Theme.Line, 1, 0.1)

        local knob = new("Frame", {
            BackgroundColor3 = Color3.fromRGB(118, 118, 118),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(10, 10),
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 3, 0.5, 0),
            ZIndex = 4,
        }, track)
        round(knob, 5)

        local C_ON, C_OFF = Color3.fromRGB(242, 242, 242), Color3.fromRGB(118, 118, 118)
        local C_KNOB_ON = Color3.fromRGB(10, 10, 10)

        local function render(on, animate)
            local kp = UDim2.new(0, on and 15 or 3, 0.5, 0)
            local kc = on and C_KNOB_ON or C_OFF
            local tc = on and C_ON or Theme.BgSoft
            local sc = on and C_ON or Theme.Line
            if animate then
                tweenTo(knob, { Position = kp, BackgroundColor3 = kc }, 0.14)
                tweenTo(track, { BackgroundColor3 = tc }, 0.14)
                tweenTo(trackStroke, { Color = sc }, 0.14)
            else
                knob.Position, knob.BackgroundColor3 = kp, kc
                track.BackgroundColor3, trackStroke.Color = tc, sc
            end
        end

        render(getter(), false)
        Refreshers[#Refreshers + 1] = function() render(getter(), false) end

        local hit = new("TextButton", {
            Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1), ZIndex = 5,
        }, row)
        hit.MouseButton1Click:Connect(function()
            local v = not getter()
            setter(v)
            render(v, true)
            Persist()
        end)
        return row
    end

    local function sliderRow(parent, text, min, max, step, decimals, getter, setter, suffix, stepper)
        local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 31), ZIndex = 3 }, parent)
        rowLabel(row, text, 12).Size = UDim2.new(1, stepper and -92 or -50, 0, 12)

        local valueLabel = new("TextLabel", {
            Text = "",
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = Theme.Sub,
            BackgroundTransparency = 1,
            TextXAlignment = stepper and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right,
            Size = stepper and UDim2.new(0, 42, 0, 12) or UDim2.new(0, 50, 0, 12),
            Position = stepper and UDim2.new(1, -68, 0, 0) or UDim2.new(1, -50, 0, 0),
            ZIndex = 4,
        }, row)

        local track = new("Frame", {
            BackgroundColor3 = Theme.Line,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 3),
            Position = UDim2.new(0, 0, 0, 22),
            ZIndex = 3,
        }, row)
        round(track, 2)

        local fill = new("Frame", {
            BackgroundColor3 = Theme.White,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 4,
        }, track)
        round(fill, 2)

        local knob = new("Frame", {
            BackgroundColor3 = Theme.White,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(10, 10),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            ZIndex = 5,
        }, track)
        round(knob, 5)
        outline(knob, Color3.fromRGB(10, 10, 10), 2, 0)

        local hit = new("TextButton", {
            Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 17), Position = UDim2.new(0, 0, 0, 14),
            ZIndex = 6,
        }, row)

        local function render()
            local v = getter()
            local rel = clamp((v - min) / (max - min), 0, 1)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            valueLabel.Text = fmtValue(v, decimals) .. (suffix or "")
        end
        Refreshers[#Refreshers + 1] = render

        local function apply(v)
            v = clamp(v, min, max)
            setter(tonumber(string.format("%.4f", v)))
            render()
        end
        local function applyFromX(px)
            local rel = clamp((px - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
            local raw = min + (max - min) * rel
            apply(min + math.floor((raw - min) / step + 0.5) * step)
        end

        if stepper then
            local function stepBtn(glyph, x, delta)
                local b = new("TextButton", {
                    Text = glyph,
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextColor3 = Theme.Sub,
                    BackgroundColor3 = Theme.BgSoft,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Size = UDim2.fromOffset(16, 16),
                    Position = UDim2.new(1, x, 0, -2),
                    ZIndex = 7,
                }, row)
                round(b, 4)
                outline(b, Theme.Line, 1, 0.2)
                b.MouseButton1Click:Connect(function()
                    apply(getter() + delta)
                    Persist()
                end)
                return b
            end
            stepBtn("-", -88, -step)
            stepBtn("+", -20, step)
        end

        hit.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
            applyFromX(input.Position.X)
            beginDrag(input.Position, function(d)
                applyFromX(input.Position.X + d.X)
            end, Persist)
        end)

        render()
        return row
    end

    local function segmentRow(parent, text, options, getter, setter)
        local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), ZIndex = 3 }, parent)
        rowLabel(row, text, 12).Size = UDim2.new(1, 0, 0, 12)

        local holder = new("Frame", {
            BackgroundColor3 = Color3.fromRGB(16, 16, 16),
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 22),
            Position = UDim2.new(0, 0, 0, 16),
            ZIndex = 3,
        }, row)
        round(holder, 7)
        outline(holder, Theme.Line, 1, 0.35)

        local buttons = {}
        local ON_BG, OFF_BG = Color3.fromRGB(238, 238, 238), Color3.fromRGB(16, 16, 16)
        local function render()
            local current = getter()
            for i, opt in ipairs(options) do
                local b = buttons[i]
                local active = current == opt
                b.BackgroundColor3 = active and ON_BG or OFF_BG
                b.TextColor3 = active and Color3.fromRGB(12, 12, 12) or Color3.fromRGB(124, 124, 124)
                b.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
            end
        end
        Refreshers[#Refreshers + 1] = render

        for i, opt in ipairs(options) do
            local b = new("TextButton", {
                Text = opt,
                Font = Enum.Font.Gotham,
                TextSize = 9,
                TextColor3 = Color3.fromRGB(124, 124, 124),
                BackgroundColor3 = OFF_BG,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.new(1 / #options, -4, 1, -4),
                Position = UDim2.new((i - 1) / #options, 2, 0, 2),
                ZIndex = 4,
            }, holder)
            round(b, 5)
            buttons[i] = b
            b.MouseButton1Click:Connect(function()
                setter(opt)
                render()
                Persist()
            end)
        end
        render()
        return row
    end

    local function keybindRow(parent, text, getter, setter)
        local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), ZIndex = 3 }, parent)
        rowLabel(row, text, 20).Size = UDim2.new(1, -62, 0, 20)

        local btn = new("TextButton", {
            Text = tostring(getter()),
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = Theme.Text,
            BackgroundColor3 = Color3.fromRGB(19, 19, 19),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Size = UDim2.fromOffset(52, 19),
            Position = UDim2.new(1, -52, 0.5, -9.5),
            ZIndex = 4,
        }, row)
        round(btn, 5)
        outline(btn, Color3.fromRGB(46, 46, 46), 1, 0.1)
        Refreshers[#Refreshers + 1] = function() btn.Text = tostring(getter()) end

        local listening = false
        btn.MouseButton1Click:Connect(function()
            if listening then return end
            listening = true
            btn.Text = "..."
            btn.TextColor3 = Theme.Muted
            local conn
            conn = UIS.InputBegan:Connect(function(input, gpe)
                if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if input.KeyCode == Enum.KeyCode.Unknown then return end
                conn:Disconnect()
                listening = false
                setter(input.KeyCode.Name)
                btn.Text = tostring(getter())
                btn.TextColor3 = Theme.Text
                Persist()
            end)
        end)
        return row
    end

    local function actionRow(parent, text, onClick, primary)
        local base = primary and Color3.fromRGB(238, 238, 238) or Theme.BgSoft
        local btn = new("TextButton", {
            Text = text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 10,
            TextColor3 = primary and Color3.fromRGB(10, 10, 10) or Theme.Text,
            BackgroundColor3 = base,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 23),
            ZIndex = 4,
        }, parent)
        round(btn, 6)
        local st = outline(btn, primary and base or Theme.Line, 1, primary and 0 or 0.4)
        local hover = primary and Color3.fromRGB(224, 224, 224) or Color3.fromRGB(30, 30, 30)
        local down = primary and Color3.fromRGB(206, 206, 206) or Color3.fromRGB(24, 24, 24)
        btn.MouseEnter:Connect(function()
            tweenTo(btn, { BackgroundColor3 = hover }, 0.1)
            if not primary then tweenTo(st, { Color = Color3.fromRGB(58, 58, 58) }, 0.1) end
        end)
        btn.MouseLeave:Connect(function()
            tweenTo(btn, { BackgroundColor3 = base }, 0.1)
            if not primary then tweenTo(st, { Color = Theme.Line }, 0.1) end
        end)
        btn.MouseButton1Down:Connect(function() tweenTo(btn, { BackgroundColor3 = down }, 0.06) end)
        btn.MouseButton1Up:Connect(function() tweenTo(btn, { BackgroundColor3 = hover }, 0.08) end)
        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    --// ── 状态栏 ───────────────────────────────────────────────
    local Footer = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, PAD, 1, -20),
        Size = UDim2.new(1, -PAD * 2, 0, 14),
        ZIndex = 3,
    }, Win)

    local footDot = new("Frame", {
        BackgroundColor3 = Theme.Green,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(4, 4),
        Position = UDim2.new(0, 0, 0.5, -2),
        ZIndex = 3,
    }, Footer)
    round(footDot, 2)

    local footText = new("TextLabel", {
        Text = "READY",
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Theme.Green,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 9, 0, 0),
        Size = UDim2.new(0, 130, 1, 0),
        ZIndex = 3,
    }, Footer)

    local footHint = new("TextLabel", {
        Text = "EDIT LAYOUT",
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0, 140, 1, 0),
        Position = UDim2.new(1, -140, 0, 0),
        ZIndex = 3,
    }, Footer)

    --// ── Toast ────────────────────────────────────────────────
    local Toast = new("Frame", {
        BackgroundColor3 = Theme.CardHi,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 176, 0, 22),
        Position = UDim2.new(0.5, -88, 1, -56),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 20,
    }, Win)
    round(Toast, 6)
    outline(Toast, Theme.Line, 1, 0.1)

    local toastLabel = new("TextLabel", {
        Text = "",
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Theme.Text,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        TextTransparency = 1,
        ZIndex = 21,
    }, Toast)

    local toastToken = 0
    local function toast(text)
        toastToken = toastToken + 1
        local token = toastToken
        toastLabel.Text = text
        toastLabel.TextTransparency = 0
        Toast.Visible = true
        Toast.BackgroundTransparency = 0.05
        Toast.Position = UDim2.new(0.5, -88, 1, -56)
        tweenTo(Toast, { Position = UDim2.new(0.5, -88, 1, -64) }, 0.14)
        task.delay(1.2, function()
            if token ~= toastToken then return end
            TweenService:Create(Toast, TweenInfo.new(0.18), { BackgroundTransparency = 0.5 }):Play()
            TweenService:Create(toastLabel, TweenInfo.new(0.18), { TextTransparency = 0.4 }):Play()
            task.delay(0.22, function()
                if token ~= toastToken then return end
                Toast.Visible = false
            end)
        end)
    end

    --// ── 标签页 ───────────────────────────────────────────────
    local tabs = {}
    local function tabCount() return math.max(#tabs, 1) end

    local function selectTab(index)
        local n = tabCount()
        for i, t in ipairs(tabs) do
            local on = (i == index)
            t.page.Visible = on
            t.btn.TextColor3 = on and Theme.Text or Theme.Muted
            t.btn.Font = on and Enum.Font.GothamBold or Enum.Font.GothamSemibold
        end
        tweenTo(Underline, { Position = UDim2.new((index - 1) / n, 6, 1, -2) }, 0.18)
    end

    local function layoutTabs()
        local n = tabCount()
        for i, t in ipairs(tabs) do
            t.btn.Size = UDim2.new(1 / n, 0, 1, 0)
            t.btn.Position = UDim2.new((i - 1) / n, 0, 0, 0)
        end
        Underline.Size = UDim2.new(1 / n, -12, 0, 2)
        selectTab(1)
    end

    local function makeTab(text)
        local page = makePage()
        local entry = {}
        entry.page = page
        entry.btn = new("TextButton", {
            Text = text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 10,
            TextColor3 = Theme.Muted,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 3,
        }, TabBar)
        entry.btn.MouseButton1Click:Connect(function()
            for i, t in ipairs(tabs) do
                if t == entry then selectTab(i) break end
            end
        end)
        tabs[#tabs + 1] = entry
        layoutTabs()
        return page
    end

    --// ── 布局编辑 / 缩放 ──────────────────────────────────────
    local EditActive = false
    local minimized = false

    local Brackets = {}
    for _, ax in ipairs({ 0, 1 }) do
        for _, ay in ipairs({ 0, 1 }) do
            local corner = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(10, 10),
                AnchorPoint = Vector2.new(ax, ay),
                Position = UDim2.new(ax, 0, ay, 0),
                Visible = false,
                ZIndex = 30,
            }, Win)
            new("Frame", {
                BackgroundColor3 = Theme.White, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 1),
                Position = UDim2.new(0, 0, ay, ay == 0 and 0 or -1),
                ZIndex = 30,
            }, corner)
            new("Frame", {
                BackgroundColor3 = Theme.White, BorderSizePixel = 0,
                Size = UDim2.new(0, 1, 1, 0),
                Position = UDim2.new(ax, ax == 0 and 0 or -1, 0, 0),
                ZIndex = 30,
            }, corner)
            Brackets[#Brackets + 1] = corner
        end
    end

    local ResizeGrip = new("TextButton", {
        Text = "", TextTransparency = 1, BackgroundTransparency = 1, AutoButtonColor = false,
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(1, -14, 1, -14),
        Visible = false,
        ZIndex = 34,
    }, Win)
    for i = 1, 2 do
        new("Frame", {
            BackgroundColor3 = Theme.Sub, BorderSizePixel = 0,
            Size = UDim2.fromOffset(1, 6),
            Rotation = 45,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(1, -i * 4, 1, -i * 4),
            ZIndex = 30,
        }, ResizeGrip)
    end

    local Hint = new("Frame", {
        BackgroundColor3 = Theme.BgSoft,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -PAD * 2, 0, 16),
        Position = UDim2.new(0, PAD, 1, -20),
        Visible = false,
        ZIndex = 30,
    }, Win)
    round(Hint, 5)
    outline(Hint, Theme.Line, 1, 0.1)
    new("TextLabel", {
        Text = opts.editHint or "EDIT · 拖标题栏移动 · 右下角缩放",
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Theme.Sub,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 31,
    }, Hint)

    local function setEditMode(on)
        EditActive = on
        for _, b in ipairs(Brackets) do b.Visible = on end
        Hint.Visible = on and not minimized
        Footer.Visible = (not on) and (not minimized)
        ResizeGrip.Visible = on
        tweenTo(winStroke, { Color = on and Theme.White or Theme.Line, Transparency = on and 0.2 or 0.15 }, 0.14)
        footHint.Text = on and "EDIT MODE · ON" or "EDIT LAYOUT"
        footHint.TextColor3 = on and Theme.Text or Theme.Muted
        if opts.onEditMode then task.spawn(opts.onEditMode, on) end
        if on then toast("Layout edit on") else Persist() end
    end

    -- 窗口拖动
    Grip.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        local sx, sy = Layout.WinX, Layout.WinY
        beginDrag(input.Position, function(d)
            local nx, ny = sx + d.X, sy + d.Y
            if Layout.Snap then nx, ny = snapPx(nx), snapPx(ny) end
            nx = clamp(nx, 4, math.max(4, viewport.X - Layout.WinW - 4))
            ny = clamp(ny, 4, math.max(4, viewport.Y - Layout.WinH - 4))
            if nx == Layout.WinX and ny == Layout.WinY then return end
            Layout.WinX, Layout.WinY = nx, ny
            Win.Position = UDim2.fromOffset(nx, ny)
        end, Persist)
    end)

    -- 窗口缩放
    ResizeGrip.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        local sw, sh = Layout.WinW, Layout.WinH
        local maxW = math.max(240, math.min(460, viewport.X - 16))
        local maxH = math.max(240, math.min(620, viewport.Y - 16))
        beginDrag(input.Position, function(d)
            local w = clamp(sw + d.X, 240, maxW)
            local h = clamp(sh + d.Y, 248, maxH)
            if Layout.Snap then w, h = snapPx(w), snapPx(h) end
            if w == Layout.WinW and h == Layout.WinH then return end
            Layout.WinW, Layout.WinH = w, h
            Win.Size = UDim2.fromOffset(w, h)
        end, Persist)
    end)

    --// ── 顶部按钮 ─────────────────────────────────────────────
    local function topButton(xOffset, callback, icon)
        local btn = new("TextButton", {
            Text = "",
            BackgroundColor3 = Color3.fromRGB(19, 19, 19),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(20, 20),
            Position = UDim2.new(1, xOffset, 0, 5),
            AutoButtonColor = false,
            ZIndex = 4,
        }, TopBar)
        round(btn, 5)
        local st = outline(btn, Color3.fromRGB(46, 46, 46), 1, 0.1)
        if icon then icon(btn) end
        local function tint(color, s)
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("Frame") then tweenTo(child, { BackgroundColor3 = color }, s) end
            end
        end
        btn.MouseEnter:Connect(function()
            tweenTo(btn, { BackgroundColor3 = Color3.fromRGB(34, 34, 34) }, 0.1)
            tweenTo(st, { Color = Color3.fromRGB(70, 70, 70) }, 0.1)
            tint(Color3.fromRGB(244, 244, 244), 0.1)
        end)
        btn.MouseLeave:Connect(function()
            tweenTo(btn, { BackgroundColor3 = Color3.fromRGB(19, 19, 19) }, 0.1)
            tweenTo(st, { Color = Color3.fromRGB(46, 46, 46) }, 0.1)
            tint(Color3.fromRGB(150, 150, 150), 0.1)
        end)
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    local function iconBar(btn, w, h, rotation)
        return new("Frame", {
            BackgroundColor3 = Color3.fromRGB(150, 150, 150),
            BorderSizePixel = 0,
            Size = UDim2.new(0, w, 0, h),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Rotation = rotation or 0,
            ZIndex = 5,
        }, btn)
    end

    local Icons = {
        grid = function(btn)
            for ix = 0, 1 do
                for iy = 0, 1 do
                    new("Frame", {
                        BackgroundColor3 = Color3.fromRGB(150, 150, 150),
                        BorderSizePixel = 0,
                        Size = UDim2.fromOffset(3, 3),
                        AnchorPoint = Vector2.new(0.5, 0.5),
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

    topButton(-76, function() setEditMode(not EditActive) end, Icons.grid)
    topButton(-52, function()
        minimized = not minimized
        TabBar.Visible = not minimized
        Pages.Visible = not minimized
        Footer.Visible = (not minimized) and (not EditActive)
        Hint.Visible = (not minimized) and EditActive
        if minimized then
            tweenTo(Win, { Size = UDim2.fromOffset(Layout.WinW, 30) }, 0.18)
        else
            tweenTo(Win, { Size = windowSize() }, 0.18)
        end
    end, Icons.minus)

    --// ── 关闭确认 ─────────────────────────────────────────────
    local Confirm = new("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 40,
    }, Win)
    round(Confirm, 10)

    local confirmCard = new("Frame", {
        BackgroundColor3 = Theme.CardHi,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(176, 84),
        Position = UDim2.new(0.5, -88, 0.5, -42),
        ZIndex = 41,
    }, Confirm)
    round(confirmCard, 8)
    outline(confirmCard, Theme.Line, 1, 0)

    new("TextLabel", {
        Text = "Close " .. (opts.title or "ui") .. "?",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Theme.Text,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 14),
        Position = UDim2.new(0, 12, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 41,
    }, confirmCard)
    new("TextLabel", {
        Text = "布局与设置会保留在本地。",
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 12),
        Position = UDim2.new(0, 12, 0, 31),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 41,
    }, confirmCard)

    local function confirmButton(text, x, primary, onClick)
        local base = primary and Color3.fromRGB(238, 238, 238) or Color3.fromRGB(26, 26, 26)
        local b = new("TextButton", {
            Text = text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 9,
            TextColor3 = primary and Color3.fromRGB(10, 10, 10) or Theme.Text,
            BackgroundColor3 = base,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Size = UDim2.fromOffset(72, 22),
            Position = UDim2.new(0, x, 0, 52),
            ZIndex = 41,
        }, confirmCard)
        round(b, 6)
        outline(b, primary and base or Theme.Line, 1, primary and 0 or 0.35)
        b.MouseEnter:Connect(function()
            tweenTo(b, { BackgroundColor3 = primary and Color3.fromRGB(224, 224, 224) or Color3.fromRGB(34, 34, 34) }, 0.1)
        end)
        b.MouseLeave:Connect(function() tweenTo(b, { BackgroundColor3 = base }, 0.1) end)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    --// ── API ──────────────────────────────────────────────────
    local api = {}
    api.theme = Theme
    api.layout = Layout
    api.root = Root
    api.window = Win
    api.tab = makeTab
    api.card = card
    api.row = rowLabel
    api.toggle = toggleRow
    api.slider = sliderRow
    api.segment = segmentRow
    api.keybind = keybindRow
    api.action = actionRow
    api.toast = toast
    api.persist = Persist
    api.refresh = function()
        for _, f in ipairs(Refreshers) do f() end
    end
    api.setEditMode = setEditMode
    api.toggleEdit = function() setEditMode(not EditActive) end
    api.isEditing = function() return EditActive end
    api.setAccent = function(on)
        statusDot.BackgroundColor3 = on and Theme.Green or Theme.Red
    end

    local lastStatusText, lastStatusOk = nil, nil
    api.setStatus = function(text, ok)
        ok = ok ~= false
        if text == lastStatusText and ok == lastStatusOk then return end
        lastStatusText, lastStatusOk = text, ok
        footText.Text = text
        local c = ok and Theme.Green or Theme.Sub
        footText.TextColor3 = c
        footDot.BackgroundColor3 = c
    end

    local function shutdown()
        pcall(Persist)
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        Connections = {}
        if opts.onDestroy then pcall(opts.onDestroy) end
        if Root then Root:Destroy() end
    end
    api.destroy = shutdown

    confirmButton("Cancel", 12, false, function() Confirm.Visible = false end)
    confirmButton("Close", 92, true, function()
        Persist()
        if opts.onClose then
            Confirm.Visible = false
            task.spawn(opts.onClose)
        else
            shutdown()
        end
    end)
    topButton(-28, function() Confirm.Visible = true end, Icons.close)

    --// ── 视口变化 ─────────────────────────────────────────────
    keep(RS.RenderStepped:Connect(function()
        local c = workspace.CurrentCamera
        if c and c.ViewportSize ~= viewport then
            viewport = c.ViewportSize
            clampWindow()
            Win.Position = UDim2.fromOffset(Layout.WinX, Layout.WinY)
            if not minimized then Win.Size = windowSize() end
        end
    end))

    return api
end

return UILib