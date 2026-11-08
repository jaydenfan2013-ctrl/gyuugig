--==========================================================================
--  Kicia Rebuild  -  Rivals
--  Kiciahook v3, rebuilt from a decompiled build.
--==========================================================================
if getgenv().KiciaRebuild and getgenv().KiciaRebuild.Unload then
    pcall(getgenv().KiciaRebuild.Unload)
end
if not game:IsLoaded() then game.Loaded:Wait() end

local K = { connections = {}, cleanups = {}, destroyed = false }
getgenv().KiciaRebuild = K

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer

local rawget, rawset = rawget, rawset

function K.fn(name)
    local v
    pcall(function() v = getfenv(0)[name] end)
    if type(v) ~= "function" then pcall(function() v = getfenv()[name] end) end
    return type(v) == "function" and v or nil
end

local getthreadidentity_ = K.fn("getthreadidentity") or K.fn("getidentity")
local setthreadidentity_ = K.fn("setthreadidentity") or K.fn("setidentity")
local sethiddenproperty_ = K.fn("sethiddenproperty")
local gethui_ = K.fn("gethui")
local function identity(n)
    if not setthreadidentity_ then return function() end end
    local old = getthreadidentity_ and getthreadidentity_() or nil
    pcall(setthreadidentity_, n)
    return function() if old then pcall(setthreadidentity_, old) end end
end
K.identity = identity
local function hudParent()
    local ok, h = pcall(function() return gethui_ and gethui_() end)
    if ok and h then return h end
    return game:GetService("CoreGui")
end
K.hudParent = hudParent

function K.track(c) K.connections[#K.connections + 1] = c return c end
function K.onUnload(f) K.cleanups[#K.cleanups + 1] = f end

--==========================================================================
--  Signal / Trove (Kicia's own small versions)
--==========================================================================
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _handlers = {} }, Signal) end
function Signal:Connect(fn)
    local h = { fn = fn, connected = true }
    table.insert(self._handlers, h)
    local sig = self
    return {
        Connected = true,
        Disconnect = function(c)
            if not h.connected then return end
            h.connected = false
            c.Connected = false
            local i = table.find(sig._handlers, h)
            if i then table.remove(sig._handlers, i) end
        end,
    }
end
function Signal:Once(fn)
    local c
    c = self:Connect(function(...) c:Disconnect() fn(...) end)
    return c
end
function Signal:Fire(...)
    local list = table.clone(self._handlers)
    for _, h in ipairs(list) do
        if h.connected then task.spawn(h.fn, ...) end
    end
end
function Signal:FireSync(...)
    for _, h in ipairs(table.clone(self._handlers)) do
        if h.connected then h.fn(...) end
    end
end
function Signal:Destroy() table.clear(self._handlers) end
K.Signal = Signal

local Trove = {}
Trove.__index = Trove
function Trove.new(name) return setmetatable({ _name = name, _items = {} }, Trove) end
local function cleanItem(o)
    local t = typeof(o)
    if t == "RBXScriptConnection" then o:Disconnect()
    elseif t == "Instance" then pcall(function() o:Destroy() end)
    elseif t == "thread" then pcall(task.cancel, o)
    elseif type(o) == "function" then pcall(o)
    elseif type(o) == "table" then
        --  some objects (Kicia's signal connections) error on unknown fields
        local function member(k)
            local ok, v = pcall(function() return o[k] end)
            return ok and type(v) == "function" and v or nil
        end
        local cancel, getStatus = member("cancel"), member("getStatus")
        if cancel and getStatus then pcall(cancel, o) return end
        local destroy = member("Destroy")
        if destroy then pcall(destroy, o) return end
        local disconnect = member("Disconnect")
        if disconnect then pcall(disconnect, o) end
    end
end
function Trove:Add(o) table.insert(self._items, o) return o end
function Trove:Connect(sig, fn) return self:Add(sig:Connect(fn)) end
function Trove:Extend() return self:Add(Trove.new(self._name)) end
function Trove:Remove(o, keep)
    local i = table.find(self._items, o)
    if i then
        table.remove(self._items, i)
        if not keep then cleanItem(o) end
    end
end
--  Promise held until it settles; cancelled if the trove is cleaned first.
function Trove:AddPromise(promise)
    if tostring(promise:getStatus()) == "Started" then
        self:Add(promise)
        promise:finally(function()
            if not self._cleaning then self:Remove(promise, true) end
        end)
    end
    return promise
end
--  Sub-trove that cleans itself up when `instance` is destroyed.
function Trove:AttachExtend(instance)
    local sub = self:Extend()
    sub:Connect(instance.Destroying, function() self:Remove(sub) end)
    return sub
end
function Trove:Clean()
    local items = self._items
    self._items = {}
    self._cleaning = true
    for i = #items, 1, -1 do cleanItem(items[i]) end
    self._cleaning = false
end
Trove.Destroy = Trove.Clean
K.Trove = Trove

--==========================================================================
--  Kicia's constant pool (v86[...]) as recovered from usage in the dump
--==========================================================================
local C = {
    [3] = "Toggle", [9] = 20, [12] = 12, [18] = "0", [26] = 4, [34] = true, [44] = "Enabled",
    [45] = 90, [48] = 2, [53] = 20, [55] = "Mode", [56] = 2, [62] = 0.1, [63] = 1, [68] = "table",
    [75] = "None", [83] = 64, [91] = 100, [95] = "number", [101] = 0.5, [108] = 255, [116] = "boolean",
    [118] = 16, [122] = 8, [126] = 0.15, [127] = "CFrame", [128] = "Frame", [133] = 10, [137] = 256,
    [147] = 0.1, [149] = 1, [153] = false, [155] = 3, [160] = 50, [162] = 8, [165] = "string",
    [170] = 9, [173] = 0.88, [175] = 5, [186] = 0, [192] = 30, [195] = 0.7,
}
K.C = C

--==========================================================================
--  Kicia's own UI, settings store and Combat menu (lifted from the dump)
--==========================================================================
local v86 = {
    [2] = "ReactiveStore",
    [3] = "Toggle",
    [4] = "UIListLayout",
    [5] = "BackgroundColor3",
    [6] = 0,
    [7] = 60,
    [8] = 60,
    [9] = 20,
    [12] = 12,
    [13] = 14,
    [14] = "Settings",
    [15] = 120,
    [16] = "min",
    [17] = 200,
    [18] = "0",
    [19] = 200,
    [20] = "Vector3",
    [21] = "Always",
    [22] = "",
    [23] = 1.4707963267948965,
    [24] = "Roboto",
    [25] = 24,
    [26] = 4,
    [27] = "Color",
    [28] = 0.2,
    [29] = "Size",
    [30] = 0.35,
    [31] = 29,
    [32] = 24,
    [33] = "Button",
    [34] = true,
    [35] = "ConfigManager",
    [36] = "ApplyMigrations",
    [37] = "TextBounds",
    [38] = "DeleteFile",
    [39] = "Slider",
    [40] = "...",
    [42] = "left",
    [43] = "Proggy Clean",
    [44] = "Enabled",
    [45] = 90,
    [46] = "UIGradient",
    [47] = "CanvasGroup",
    [48] = 0.3,
    [49] = 2,
    [50] = "Side",
    [51] = " ",
    [52] = "BottomRight",
    [53] = 92,
    [54] = 6,
    [55] = "Mode",
    [56] = 2,
    [57] = "TextColor",
    [58] = 80,
    [59] = "Font",
    [60] = 29,
    [61] = 20,
    [62] = 0.1,
    [63] = 1,
    [64] = "ScrollingFrame",
    [65] = 200,
    [66] = 0.5,
    [67] = 100,
    [68] = "table",
    [69] = "Catalog unavailable",
    [70] = "GradientDark",
    [71] = 10,
    [72] = 12,
    [73] = "Keybind",
    [74] = 0.9,
    [75] = "None",
    [76] = "LoadFromFile",
    [77] = "FireServer",
    [78] = 720,
    [79] = 255,
    [80] = "Text",
    [81] = 1,
    [82] = "Realize() can only be called on the root",
    [83] = 64,
    [84] = 0.5,
    [85] = "UIStroke",
    [87] = 0.8,
    [88] = "TabHighlight",
    [89] = "Loading",
    [90] = "Gradient",
    [91] = 100,
    [92] = "TextButton",
    [93] = "ColorSequence",
    [94] = "Options",
    [95] = "number",
    [96] = "Unselected",
    [97] = "Mode",
    [98] = "UICorner",
    [99] = "ExportToJson",
    [100] = 14,
    [101] = 0.5,
    [102] = 231,
    [103] = 52,
    [104] = "Fonts",
    [105] = 0.85,
    [106] = "Menu Keybind",
    [107] = 40,
    [108] = 255,
    [109] = 77,
    [110] = 70,
    [111] = "Fetching items...",
    [112] = "Invisible",
    [113] = "UIPadding",
    [114] = "primary",
    [115] = "Color3",
    [116] = "boolean",
    [118] = 16,
    [119] = 159,
    [120] = "Outline",
    [121] = "ImageButton",
    [122] = 8,
    [123] = 19,
    [124] = "X",
    [125] = "Proggy Tiny",
    [126] = 0.15,
    [127] = "CFrame",
    [128] = "Frame",
    [129] = "Show Watermark",
    [131] = "AbsoluteSize",
    [132] = "Breathing",
    [133] = 10,
    [134] = "GradientTop",
    [135] = "TextLabel",
    [136] = "Unselected Text",
    [137] = 256,
    [138] = 0.85,
    [139] = "Accent",
    [140] = "danger",
    [141] = "GradientDeep",
    [142] = "Silent Load",
    [143] = 32,
    [144] = 20,
    [145] = "Dialog has been destroyed",
    [146] = "ImageLabel",
    [147] = 0.1,
    [148] = "TextBox",
    [149] = 1,
    [150] = "stop",
    [151] = "family",
    [153] = false,
    [154] = "ScrollBarImageColor3",
    [155] = 3,
    [156] = "ImageColor3",
    [157] = 20,
    [158] = "secondary",
    [159] = 20,
    [160] = 50,
    [161] = 0.5,
    [162] = 8,
    [163] = 80,
    [164] = "hue",
    [165] = "string",
    [166] = "family",
    [167] = "TextColor3",
    [168] = "ElementBackground",
    [169] = "FromJson",
    [170] = 9,
    [172] = "none",
    [173] = 0.88,
    [174] = "Unselected",
    [175] = 5,
    [176] = "UISizeConstraint",
    [177] = "Try a different search.",
    [178] = "ElementBackground",
    [181] = 10,
    [182] = "HttpService",
    [183] = 72,
    [184] = "Color",
    [186] = 0,
    [187] = "GradientMid",
    [189] = "Position",
    [190] = "Search...",
    [191] = "TabShadow",
    [192] = 30,
    [193] = 0,
    [194] = "Hold",
    [195] = 0.7,
    [196] = "Viewport",
    [197] = "Y",
    [198] = 400,
    [199] = "Unload",
    [200] = 26,
}
--  Environment Kicia's modules expect: the module table and the aliases its
--  loader set up before them (v102 = rawget, v103 = rawset, v107 = pcall).
local tbl17 = { cache = {} }
local v102, v103, v107 = rawget, rawset, pcall
--  The obfuscator's integrity counters. Every check in the lifted code has one
--  branch that hangs and one that runs the real code; these values sit inside
--  the window where all of them take the real branch (n26 in [4790, 4809),
--  n25 in [3866, 3887]).
local n25, n26 = 3870, 4800
local flag2, flag3 = true, true
local function n29() return 0 end
local cloneref = K.fn("cloneref") or function(x) return x end
local gethui = K.fn("gethui") or function() return game:GetService("CoreGui") end
local getthreadidentity = K.fn("getthreadidentity") or K.fn("getidentity") or function() return 8 end
local setthreadidentity = K.fn("setthreadidentity") or K.fn("setidentity") or function() end
--  The rest of the loader's locals (clonefunction'd so hooks on them can't see us).
local function clonefn(f)
    local c = K.fn("clonefunction")
    if c and f then
        local ok, r = pcall(c, f)
        if ok and r then return r end
    end
    return f
end
local fireServer = clonefn(Instance.new("RemoteEvent").FireServer)
local fireServer2 = clonefn(Instance.new("UnreliableRemoteEvent").FireServer)
local v104 = clonefn(K.fn("sethiddenproperty"))
local v108 = clonefn(K.fn("setfflag")) or function() end
local v109 = clonefn(K.fn("isexecutorclosure")) or function() return false end
local v110 = clonefn(K.fn("setrawmetatable")) or setmetatable
local v111 = clonefn(K.fn("getrawmetatable")) or getmetatable
local v112 = clonefn(v111(game).__newindex)
local v113 = clonefn(v111(game).__index)
local v114 = clonefn(game.FindFirstChildOfClass)
local function n27() return 0 end
local firetouchinterest = K.fn("firetouchinterest") or function() end
local getconnections = K.fn("getconnections") or function() return {} end
local setclipboard = K.fn("setclipboard") or K.fn("toclipboard") or function() end
local InstanceHandle
pcall(function() InstanceHandle = getfenv(0).InstanceHandle end)
if InstanceHandle == nil then pcall(function() InstanceHandle = getgenv().InstanceHandle end) end
if InstanceHandle == nil then InstanceHandle = { new = function(x) return x end } end
--  The modules the decompiler lost (their bodies are `fn35(...) end` in
--  the dump), rebuilt from how the rest of Kicia's code calls them.

--  k: Trove
tbl17.k = function() return { new = function(name) return Trove.new(name) end } end

--  w: viewport / pointer / key / path helpers
do
    local UIS = UserInputService
    local GuiService = game:GetService("GuiService")
    local function camera() return workspace.CurrentCamera end
    local W = {}
    function W.appendPath(path, key)
        local p = table.clone(path)
        table.insert(p, key)
        return p
    end
    function W.currentViewportSize()
        local c = camera()
        return c and c.ViewportSize or Vector2.new(1920, 1080)
    end
    function W.connectCurrentCameraViewport(trove, cb)
        local inner = trove:Extend()
        local function bind()
            inner:Clean()
            local c = camera()
            if c == nil then return end
            inner:Connect(c:GetPropertyChangedSignal("ViewportSize"), function() cb(c.ViewportSize) end)
            cb(c.ViewportSize)
        end
        trove:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bind)
        bind()
    end
    function W.absoluteToLayerOffset(layer, pos)
        return pos - layer.AbsolutePosition
    end
    function W.clampOffsetToViewport(x, y, size)
        local vp = W.currentViewportSize()
        return math.clamp(x, 0, math.max(0, vp.X - size.X)), math.clamp(y, 0, math.max(0, vp.Y - size.Y))
    end
    function W.clampGuiToViewport(gui)
        local vp = W.currentViewportSize()
        local ap, as = gui.AbsolutePosition, gui.AbsoluteSize
        local dx = math.clamp(ap.X, 0, math.max(0, vp.X - as.X)) - ap.X
        local dy = math.clamp(ap.Y, 0, math.max(0, vp.Y - as.Y)) - ap.Y
        if dx ~= 0 or dy ~= 0 then
            local p = gui.Position
            gui.Position = UDim2.new(p.X.Scale, p.X.Offset + dx, p.Y.Scale, p.Y.Offset + dy)
        end
    end
    function W.snapPosition(u)
        return UDim2.new(u.X.Scale, math.round(u.X.Offset), u.Y.Scale, math.round(u.Y.Offset))
    end
    function W.onScreenKeyboardTop()
        local ok, visible = pcall(function() return UIS.OnScreenKeyboardVisible end)
        if not ok or not visible then return nil end
        local ok2, pos = pcall(function() return UIS.OnScreenKeyboardPosition end)
        return ok2 and pos and pos.Y or nil
    end
    function W.connectOnScreenKeyboard(trove, cb)
        pcall(function() trove:Connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardVisible"), cb) end)
        pcall(function() trove:Connect(UIS:GetPropertyChangedSignal("OnScreenKeyboardPosition"), cb) end)
    end
    function W.getPointerPosition()
        return UIS:GetMouseLocation()
    end
    function W.matchesPointerDrag(input, started, movement)
        if started ~= nil and started.UserInputType == Enum.UserInputType.Touch then return input == started end
        return input.UserInputType == movement
    end
    function W.round(v, step)
        if step == nil or step == 0 then return v end
        return math.round(v / step) * step
    end
    W.KeyNames = {
        [Enum.UserInputType.MouseButton1] = "MB1", [Enum.UserInputType.MouseButton2] = "MB2",
        [Enum.UserInputType.MouseButton3] = "MB3", [Enum.KeyCode.LeftShift] = "LShift",
        [Enum.KeyCode.RightShift] = "RShift", [Enum.KeyCode.LeftControl] = "LCtrl",
        [Enum.KeyCode.RightControl] = "RCtrl", [Enum.KeyCode.LeftAlt] = "LAlt", [Enum.KeyCode.RightAlt] = "RAlt",
    }
    function W.serializeKey(key)
        if typeof(key) ~= "EnumItem" then return nil end
        return tostring(key.EnumType) .. "." .. key.Name
    end
    function W.deserializeKey(s)
        if type(s) ~= "string" then return nil end
        local kind, name = s:match("^(%w+)%.(%w+)$")
        if kind == nil then return nil end
        local ok, v = pcall(function() return Enum[kind][name] end)
        return ok and v or nil
    end
    function W.findScrollingAncestor(inst)
        local p = inst and inst.Parent
        while p ~= nil do
            if p:IsA("ScrollingFrame") then return p end
            p = p.Parent
        end
        return nil
    end
    function W.isEffectivelyVisible(gui)
        local p = gui
        while p ~= nil and p ~= game do
            if p:IsA("GuiObject") and not p.Visible then return false end
            if p:IsA("LayerCollector") then return p.Enabled end
            p = p.Parent
        end
        return false
    end
    function W.ensureStorageDirectories(dir)
        local isf, mkf = K.fn("isfolder"), K.fn("makefolder")
        if not (isf and mkf) or type(dir) ~= "string" then return end
        local function make(path)
            local acc
            for part in path:gmatch("[^/]+") do
                acc = acc and (acc .. "/" .. part) or part
                pcall(function() if not isf(acc) then mkf(acc) end end)
            end
        end
        make(dir)
        make(dir .. "/configs")
    end
    tbl17.w = function() return W end
end

--  P: two-way link between a control and a settings path. Sliders ask for
--  Debounce so dragging writes once per short burst instead of every frame.
do
    local P = {}
    function P.bind(trove, config, control, path, opts)
        local debounce = opts ~= nil and opts.Debounce == true
        local writeBack = opts ~= nil and opts.WriteBack or nil
        control:Set(config:Get(path), true)
        trove:Connect(config:Changed(path), function(v) control:Set(v, true) end)
        local pending, scheduled = nil, false
        local function write(v)
            if writeBack then writeBack(v) else config:Set(path, v) end
        end
        trove:Connect(control.Changed, function(v)
            if not debounce then write(v) return end
            pending = v
            if scheduled then return end
            scheduled = true
            task.delay(0.05, function()
                scheduled = false
                write(pending)
            end)
        end)
    end
    tbl17.P = function() return P end
end

--  c5: the critically damped Spring (Position, Velocity, Target, Speed, Damper).
do
    local Spring = {}
    local function posVel(self, now)
        local p0, v0, p1, d, s = self._p0, self._v0, self._target, self._damper, self._speed
        local t = s * (now - self._t0)
        local d2 = d * d
        local h, si, co
        if d2 < 1 then
            h = math.sqrt(1 - d2)
            local ep = math.exp(-d * t) / h
            co, si = ep * math.cos(h * t), ep * math.sin(h * t)
        elseif d2 == 1 then
            h = 1
            local ep = math.exp(-d * t) / h
            co, si = ep, ep * t
        else
            h = math.sqrt(d2 - 1)
            local u, v = math.exp((-d + h) * t) / (2 * h), math.exp((-d - h) * t) / (2 * h)
            co, si = u + v, u - v
        end
        local a0, a1 = h * co + d * si, 1 - (h * co + d * si)
        local a2 = si / s
        local b0, b1, b2 = -s * si, s * si, h * co - d * si
        return a0 * p0 + a1 * p1 + a2 * v0, b0 * p0 + b1 * p1 + b2 * v0
    end
    function Spring.new(initial, clock)
        initial = initial or 0
        clock = clock or os.clock
        return setmetatable({ _clock = clock, _t0 = clock(), _p0 = initial, _v0 = 0 * initial, _target = initial,
            _damper = 1, _speed = 1 }, Spring)
    end
    function Spring:Impulse(v) self.Velocity = self.Velocity + v end
    function Spring:SetTarget(value, doNotAnimate)
        if doNotAnimate then
            self._p0, self._v0, self._target, self._t0 = value, 0 * value, value, self._clock()
        else
            self.Target = value
        end
    end
    function Spring:TimeSkip(delta)
        local now = self._clock()
        local p, v = posVel(self, now + delta)
        self._p0, self._v0, self._t0 = p, v, now
    end
    Spring.__index = function(self, k)
        if Spring[k] then return Spring[k] end
        if k == "Value" or k == "Position" or k == "p" then local p = posVel(self, self._clock()) return p
        elseif k == "Velocity" or k == "v" then local _, v = posVel(self, self._clock()) return v
        elseif k == "Target" or k == "t" then return self._target
        elseif k == "Damper" or k == "d" then return self._damper
        elseif k == "Speed" or k == "s" then return self._speed
        elseif k == "Clock" then return self._clock end
        return nil
    end
    Spring.__newindex = function(self, k, v)
        local now = self._clock()
        if k == "Value" or k == "Position" or k == "p" then
            local _, vel = posVel(self, now)
            self._p0, self._v0 = v, vel
        elseif k == "Velocity" or k == "v" then
            local pos = posVel(self, now)
            self._p0, self._v0 = pos, v
        elseif k == "Target" or k == "t" then
            local pos, vel = posVel(self, now)
            self._p0, self._v0, self._target = pos, vel, v
        elseif k == "Damper" or k == "d" then
            local pos, vel = posVel(self, now)
            self._p0, self._v0, self._damper = pos, vel, v
        elseif k == "Speed" or k == "s" then
            local pos, vel = posVel(self, now)
            self._p0, self._v0, self._speed = pos, vel, v < 0 and 0 or v
        elseif k == "Clock" then
            local pos, vel = posVel(self, now)
            self._clock, self._t0, self._p0, self._v0 = v, v(), pos, vel
            return
        else
            rawset(self, k, v)
            return
        end
        self._t0 = now
    end
    tbl17.c5 = function() return Spring end
end

--  ca: the AI aim mode's network weights. They are not in the dump; cc falls
--  back to Linear movement without them.
tbl17.ca = function() return nil end

--  hH: weather emitter specs and lightning / thunder constants. Kicia's own
--  values are not in the dump; these fit every field the weather module reads
--  and use particle textures that ship with Roblox.
do
    local soft = "rbxasset://textures/particles/smoke_main.dds"
    local sparkle = "rbxasset://textures/particles/sparkles_main.dds"
    local function spec(t)
        t.RotationMin, t.RotationMax = t.RotationMin or 0, t.RotationMax or 360
        t.RotationSpeedMin, t.RotationSpeedMax = t.RotationSpeedMin or -40, t.RotationSpeedMax or 40
        return t
    end
    local W = {
        EmitterSpecsByPreset = {
            Snow = {
                spec({ Texture = soft, TransparencyMax = 0.15, LifetimeMin = 6, LifetimeMax = 9, BaseRate = 220,
                    SpeedMin = 6, SpeedMax = 10, SizeStart = 0.35, SizeEnd = 0.25, BaseSpread = 0.4, BaseAccelerationY = -1 }),
                spec({ Texture = sparkle, TransparencyMax = 0.35, LifetimeMin = 6, LifetimeMax = 9, BaseRate = 60,
                    SpeedMin = 5, SpeedMax = 8, SizeStart = 0.2, SizeEnd = 0.15, BaseSpread = 0.6, BaseAccelerationY = -0.5 }),
            },
            Rain = {
                spec({ Texture = soft, TransparencyMax = 0.35, LifetimeMin = 1.2, LifetimeMax = 1.8, BaseRate = 600,
                    SpeedMin = 70, SpeedMax = 90, SizeStart = 0.12, SizeEnd = 0.1, BaseSpread = 0.05, BaseAccelerationY = -40,
                    RotationMin = 0, RotationMax = 0, RotationSpeedMin = 0, RotationSpeedMax = 0,
                    Orientation = Enum.ParticleOrientation.VelocityParallel }),
            },
            Blizzard = {
                spec({ Texture = soft, TransparencyMax = 0.1, LifetimeMin = 3, LifetimeMax = 5, BaseRate = 700,
                    SpeedMin = 18, SpeedMax = 28, SizeStart = 0.3, SizeEnd = 0.2, BaseSpread = 0.8, BaseAccelerationY = -6 }),
                spec({ Texture = soft, TransparencyMax = 0.75, LifetimeMin = 3, LifetimeMax = 5, BaseRate = 120,
                    SpeedMin = 14, SpeedMax = 22, SizeStart = 3, SizeEnd = 5, BaseSpread = 1, BaseAccelerationY = -2 }),
            },
        },
        LightningPresetSet = { Rain = true },
        LightningRadiusMin = 20,
        LightningGroundDrop = 40,
        LightningRayLength = 1000,
        LightningJitter = 30,
        ThunderSoundId = "",
        ThunderSpeed = 340,
        ThunderVolumeFloor = 0.2,
        ThunderFalloff = 600,
        ThunderPitchMin = 0.85,
        ThunderPitchMax = 1.1,
    }
    tbl17.hH = function() return W end
end

--  iQ: the Visuals > Player ESP page. Its builder is lost; rebuilt with the
--  same menu calls Kicia's other pages use, over Kicia's own Esp settings.
tbl17.iQ = function()
    return function(_, _, grid)
        local enable = tbl17.h6()
        local fonts = tbl17.az().Order
        local function P(...) return { "Esp", ... } end

        local main = grid:AddSection({ Title = "Player ESP", Side = "left" })
        enable(main, "Enable ESP", { "Always", "Toggle", "Hold" }, P("Main"), true)
        main:AddDropdown({ Label = "Box Fit", Options = { "Static", "Dynamic" }, Config = P("Main", "Mode") })

        local look = grid:AddSection({ Title = "Text", Side = "right" })
        look:AddToggle({ Label = "Use Display Names", Config = P("Settings", "UseDisplayName") })
        look:AddDropdown({ Label = "Font", Options = fonts, Config = P("Settings", "Font") })
        look:AddSlider({ Label = "Font Size", Min = 8, Max = 32, Config = P("Settings", "FontSize") })
        look:AddDropdown({ Label = "Text Case", Options = { "Standard", "UPPERCASE", "lowercase" }, Config = P("Settings", "TextCase") })
        look:AddDropdown({ Label = "Text Surround", Options = { "None", "[]", "()", "<>", "{}" }, Config = P("Settings", "TextSurround") })
        look:AddDivider({ Label = "Flags" })
        look:AddDropdown({ Label = "Flag Font", Options = fonts, Config = P("Settings", "FlagFont") })
        look:AddSlider({ Label = "Flag Font Size", Min = 6, Max = 24, Config = P("Settings", "FlagFontSize") })
        look:AddDropdown({ Label = "Flag Text Case", Options = { "Standard", "UPPERCASE", "lowercase" }, Config = P("Settings", "FlagTextCase") })
        look:AddDropdown({ Label = "Flag Surround", Options = { "None", "[]", "()", "<>", "{}" }, Config = P("Settings", "FlagTextSurround") })
        look:AddGroup({ Source = look:AddToggle({ Label = "Scale With Distance", Config = P("Settings", "DistanceScaling") }) })
            :AddSlider({ Label = "Reference Distance", Min = 10, Max = 300, Config = P("Settings", "DistanceScalingRef") })

        local function side(title, key, where)
            local s = grid:AddSection({ Title = title, Side = where })
            local function Q(...) return P(key, ...) end
            --  Kicia's ESP draws a side only when Main AND this side are enabled
            enable(s, "Enable " .. title .. " ESP", { "Always", "Toggle", "Hold" }, P(key), true)
            local function color(label, path, transparency)
                local t = s:AddToggle({ Label = label, Config = Q(path, "Enabled") })
                s:AddColor({ Row = t.Row, Config = Q(path, "Color"), Transparency = transparency and Q(path, "Transparency") or nil, Alpha = transparency or nil })
                return t
            end
            local function gradient(label, path)
                local t = s:AddToggle({ Label = label, Config = Q(path, "Enabled") })
                s:AddColor({ Row = t.Row, Gradient = "editable", Alpha = true, Config = Q(path, "Color"), Transparency = Q(path, "Transparency") })
                return t
            end
            color("Name", "Name", true)
            s:AddGroup({ Source = color("Box", "Box") }):AddDropdown({ Label = "Style", Options = { "Full", "Corner" }, Config = Q("Box", "Style") })
            gradient("Filled Box", "FilledBox")
            local hb = s:AddToggle({ Label = "Health Bar", Config = Q("HealthBar", "Enabled") })
            s:AddColor({ Row = hb.Row, Gradient = "editable", Config = Q("HealthBar", "Color") })
            s:AddGroup({ Source = hb }):AddDropdown({ Label = "Color Mode", Options = { "Solid", "Gradient", "Reactive" }, Config = Q("HealthBar", "ColorMode") })
            color("Health Number", "HealthNumber")
            color("Held Weapon", "HeldWeapon", true)
            local ab = s:AddToggle({ Label = "Ammo Bar", Config = Q("AmmoBar", "Enabled") })
            s:AddColor({ Row = ab.Row, Gradient = "editable", Config = Q("AmmoBar", "Color") })
            s:AddGroup({ Source = ab }):AddDropdown({ Label = "Color Mode", Options = { "Solid", "Gradient", "Reactive" }, Config = Q("AmmoBar", "ColorMode") })
            color("Distance", "Distance")
            color("Rank", "Rank")
            color("Win Streak", "Winstreak")
            color("Deflecting", "Deflecting", true)
            local ch = s:AddGroup({ Source = s:AddToggle({ Label = "Chams", Config = Q("Chams", "Enabled") }) })
            ch:AddDropdown({ Label = "Kind", Options = { "Legacy", "Highlight" }, Config = Q("Chams", "Kind") })
            local fill = ch:AddLabel({ Label = "Fill" })
            ch:AddColor({ Row = fill.Row, Alpha = true, Config = Q("Chams", "InnerColor"), Transparency = Q("Chams", "InnerTransparency") })
            local outline = ch:AddLabel({ Label = "Outline" })
            ch:AddColor({ Row = outline.Row, Alpha = true, Config = Q("Chams", "OutlineColor"), Transparency = Q("Chams", "OutlineTransparency") })
            local glow = ch:AddToggle({ Label = "Glow", Config = Q("Chams", "Glow") })
            ch:AddColor({ Row = glow.Row, Config = Q("Chams", "GlowColor") })
            s:AddGroup({ Source = gradient("Skeleton", "Skeleton") })
                :AddSlider({ Label = "Thickness", Min = 1, Max = 6, Config = Q("Skeleton", "Thickness") })
            local hm = s:AddGroup({ Source = color("Head Marker", "HeadMarker", true) })
            hm:AddDropdown({ Label = "Shape", Options = { "Cross", "Circle", "Diamond" }, Config = Q("HeadMarker", "Shape") })
            hm:AddToggle({ Label = "Filled", Config = Q("HeadMarker", "Filled") })
            local hmo = hm:AddToggle({ Label = "Outline", Config = Q("HeadMarker", "Outline") })
            hm:AddColor({ Row = hmo.Row, Alpha = true, Config = Q("HeadMarker", "OutlineColor"), Transparency = Q("HeadMarker", "OutlineTransparency") })
            local tr = s:AddGroup({ Source = gradient("Tracer", "Tracer") })
            tr:AddSlider({ Label = "Thickness", Min = 1, Max = 6, Config = Q("Tracer", "Thickness") })
            tr:AddDropdown({ Label = "From", Options = { "Bottom", "Center", "Top", "Mouse" }, Config = Q("Tracer", "Origin") })
            tr:AddDropdown({ Label = "To", Options = { "Feet", "Head" }, Config = Q("Tracer", "Target") })
            local tro = tr:AddToggle({ Label = "Outline", Config = Q("Tracer", "Outline") })
            tr:AddColor({ Row = tro.Row, Alpha = true, Config = Q("Tracer", "OutlineColor"), Transparency = Q("Tracer", "OutlineTransparency") })
            tr:AddSlider({ Label = "Outline Thickness", Min = 1, Max = 6, Config = Q("Tracer", "OutlineThickness") })
        end
        side("Enemies", "Enemy", "left")
        side("Teammates", "Team", "right")
    end
end

--  eZ: Kicia's online user service (sessions with user.kicia.cc). Offline here:
--  nothing is sent anywhere, connecting is refused.
tbl17.eZ = function()
    local Offline = {}
    Offline.__index = Offline
    function Offline.new()
        local Signal = tbl17.g()
        local self = setmetatable({ Connected = Signal.new(), ShowActiveChanged = Signal.new(),
            PeerPayloadReceived = Signal.new(), PeerRemoved = Signal.new(), ShowActivated = Signal.new(),
            _playerByHash = {} }, Offline)
        self._leaving = Players.PlayerRemoving:Connect(function(p) self.PeerRemoved:Fire(p) end)
        return self
    end
    function Offline:ShouldShowActive() return false end
    function Offline:IsConnected() return false end
    function Offline:Send() return tbl17.a().err("UserServer", "offline", "the online user service is disabled") end
    function Offline:FindPlayerByHash() return nil end
    function Offline:Connect() return tbl17.ay().reject("the online user service is disabled") end
    function Offline:Destroy()
        self.Connected:Destroy()
        self.ShowActiveChanged:Destroy()
        self.PeerPayloadReceived:Destroy()
        self.PeerRemoved:Destroy()
        self.ShowActivated:Destroy()
        self._leaving:Disconnect()
    end
    return Offline
end
--  Kicia's own modules, lifted from the dump (extract.py). Do not edit by hand.
do -- a
local function fn35()
return {
ok = function(arg)
return { Ok = true, Value = arg }
end,
err = function(arg, arg2, arg3)
return { Ok = false, Error = { Source = arg, Stage = arg2, Detail = arg3, Timestamp = os.clock() } }
end,
formatError = function(arg)
local v115 = tostring
local detail = arg.Detail
return string.format("'%s' @ %s failed during stage '%s'; %s", tostring(arg.Source), tostring(arg.Timestamp), tostring(arg.Stage), v115(detail))
end,
VoidOk = table.freeze({ Ok = true, Value = nil }),
}
end

tbl17.a = function()
local a = tbl17.cache.a

if not a then
a = { c = fn35() }
tbl17.cache.a = a
end

return a.c
end
end
do -- b
local function fn35()
tbl17.a()
local v115 = nil

return {
use = function(arg)
v115 = arg
end,
get = function()
assert(v115)
return v115
end,
}
end

tbl17.b = function()
local b = tbl17.cache.b

if not b then
b = { c = fn35() }
tbl17.cache.b = b
end

return b.c
end
end
do -- d
local function fn35()
local function copy(t)
if type(t) ~= "table" then return t end
local o = {}
for k, v in next, t do o[k] = copy(v) end
return setmetatable(o, getmetatable(t))
end
return copy
end

tbl17.d = function()
local d = tbl17.cache.d

if not d then
d = { c = fn35() }
tbl17.cache.d = d
end

return d.c
end
end
do -- e
local function fn35()
local v115 = tbl17.a()

return function(arg, arg2)
local parts = arg:split("/")
arg2 = arg2 or ""

for k, v116 in parts, nil, nil do
if v116 == "" then
continue
end
local str7 = k == #parts and "" or "/"
local v117 = tostring
arg2 ..= string.format("%s%s", tostring(v116), v117(str7))
if isfile(arg2) then
return v115.err("ensureFolderPath", "collision", string.format("expected `%s` to be non-existant or a folder, found a file instead.", tostring(arg2)))
end

if not isfolder(arg2) then
makefolder(arg2)
end
end

return v115.VoidOk
end
end

tbl17.e = function()
local e = tbl17.cache.e

if not e then
e = { c = fn35() }
tbl17.cache.e = e
end

return e.c
end
end
do -- f
local function fn35()
local v115 = tbl17.a()
local v116 = tbl17.d()
local v117 = tbl17.e()
local v118 = cloneref(game:GetService(v86[182]))
local index2 = {}
index2.__index = index2

local function fn36(arg)
local v119 = v86[68]
if type(arg) == v119 then
return v116(arg)
end
return arg
end

local function fn37(arg)
if arg == nil or arg == "" then
return ""
end

if arg:sub(-v86[63]) == "/" then
return arg
end
return arg .. "/"
end

local function fn38(arg)
if arg == "" then
return v115.err("ConfigManager", "validateConfigName", "config name cannot be empty")
end

if arg:find("/") or arg:find("\\") then
return v115.err("ConfigManager", "validateConfigName", "expected no directory traversal")
end
return v115.VoidOk
end

index2.new = function(arg)
assert(type(arg.CurrentVersion) == "number" and arg.CurrentVersion >= v86[63], "expected `CurrentVersion` >= 1")
local v119 = fn37(arg.SavePath)

if v119 ~= "" then
local v120 = v117(v119)

if not v120.Ok then
error(v120.Error.Detail, 2)
end
end

local serialize = arg.Serialize or function(arg2)
return arg2
end

local deserialize = arg.Deserialize or function(arg2)
return arg2
end

local v120 = fn36(arg.DefaultConfig)

local tbl18 = {
Data = fn36(v120),
_defaultConfig = v120,
_currentVersion = arg.CurrentVersion,
_legacyVersion = arg.LegacyVersion or 1,
_savePath = v119,
_migrations = arg.Migrations or {},
_serialize = serialize,
_deserialize = deserialize,
}

setmetatable(tbl18, index2)
return tbl18
end

index2._ConfigPath = function(arg, arg2)
if arg2:match("%.json$") then
return arg._savePath .. arg2
end
local v119 = tostring
return string.format("%s%s.json", tostring(arg._savePath), v119(arg2))
end

index2._ApplyMigrations = function(arg, arg2, arg3)
if arg2 < 1 then
return v115.err("ConfigManager", "ApplyMigrations", string.format("invalid file version %s", tostring(arg2)))
end

if arg._currentVersion < arg2 then
local v119 = tostring
local currentVersion = arg._currentVersion
return v115.err("ConfigManager", "ApplyMigrations", string.format("file version %s is newer than current version %s", tostring(arg2), v119(currentVersion)))
end

local v119 = fn36(arg3)

while arg2 < arg._currentVersion do
local v120 = arg._migrations[arg2]
if v120 == nil then
local v121 = tostring
return v115.err("ConfigManager", v86[36], string.format("missing migration for version %s -> %s", tostring(arg2), v121(arg2 + 1)))
end
local v121, v122 = v107(v120, v119, arg2, arg2 + v86[63])
if not v121 then
local v123 = tostring
return v115.err(v86[35], "ApplyMigrations", string.format("migration %s -> %s failed: %s", tostring(arg2), tostring(arg2 + v86[63]), v123(v122)))
end

if v122 == nil then
local v123 = tostring
return v115.err("ConfigManager", "ApplyMigrations", string.format("migration %s -> %s returned nil", tostring(arg2), v123(arg2 + 1)))
end
arg2 += 1
v119 = v122
end

return v115.ok(v119)
end

index2.SetData = function(arg, data)
arg.Data = data
end

index2.Reset = function(arg)
local v119 = v116(arg._defaultConfig)
arg.Data = v119
return v119
end

index2.ToJson = function(arg, arg2)
if arg2 == nil then
arg2 = arg.Data
end

local v119, v120 = v107(arg._serialize, arg2)
if not v119 then
return v115.err("ConfigManager", "ToJson", string.format("failed to serialize config: %s", tostring(v120)))
end
local v121, v122 = v107(v118.JSONEncode, v118, { Version = arg._currentVersion, Data = v120 })
if not v121 then
return v115.err("ConfigManager", "ToJson", string.format("failed to encode config payload as JSON: %s", tostring(v122)))
end
return v115.ok(v122)
end

index2.FromJson = function(arg, arg2)
local v119, v120 = v107(v118.JSONDecode, v118, arg2)
if not v119 then
return v115.err(v86[35], v86[169], string.format("failed to decode JSON payload: %s", tostring(v120)))
end

if type(v120) ~= "table" then
return v115.err("ConfigManager", "FromJson", "expected decoded config JSON to be a table")
end
local legacyVersion = arg._legacyVersion
local version = v120.Version
local data = v120.Data

if version == nil and data == nil then
version = v120.version
data = v120.data
end

if not (type(version) == "number" and data ~= nil) then
data = v120
version = legacyVersion
end

local v121 = arg:_ApplyMigrations(version, data)
if not v121.Ok then
return v115.err("ConfigManager", v86[169], v121.Error.Detail)
end
local v122, v123 = v107(arg._deserialize, v121.Value)
if not v122 then
return v115.err("ConfigManager", "FromJson", string.format("failed to deserialize config data: %s", tostring(v123)))
end

if v123 == nil then
return v115.err("ConfigManager", "FromJson", "deserializer returned nil")
end
arg.Data = v123
return v115.ok(v123)
end

index2._SaveImpl = function(arg, arg2, arg3, arg4)
local v119 = fn38(arg2)
if not v119.Ok then
return v119
end
local v120 = arg:_ConfigPath(arg2)
if arg4 and isfile(v120) then
return v115.err("ConfigManager", "SaveImpl", string.format("path `%s` already exists", tostring(v120)))
end
local v121 = arg:ToJson(arg3)
if not v121.Ok then
return v115.err("ConfigManager", "SaveImpl", v121.Error.Detail)
end
writefile(v120, v121.Value)
return v115.VoidOk
end

index2.SaveToFile = function(arg, arg2, arg3)
return arg:_SaveImpl(arg2, nil, arg3)
end

index2.LoadFromFile = function(arg, arg2)
local v119 = fn38(arg2)
if not v119.Ok then
return v115.err("ConfigManager", v86[76], v119.Error.Detail)
end
local v120 = arg:_ConfigPath(arg2)
if not isfile(v120) then
return v115.err(v86[35], "LoadFromFile", string.format("path `%s` does not exist", tostring(v120)))
end
local v121 = readfile(v120)
return arg:FromJson(v121)
end

index2.Exists = function(arg, arg2)
if not fn38(arg2).Ok then
return v86[153]
end
return isfile(arg:_ConfigPath(arg2))
end

index2.SaveDefaultToFile = function(arg, arg2, arg3)
return arg:_SaveImpl(arg2, arg._defaultConfig, arg3)
end

index2.Delete = function(arg, arg2)
local v119 = fn38(arg2)
if not v119.Ok then
return v119
end
local v120 = arg:_ConfigPath(arg2)
if not isfile(v120) then
return v115.err("ConfigManager", v86[38], string.format("path `%s` does not exist", tostring(v120)))
end
delfile(v120)
return v115.VoidOk
end

index2.AllConfigs = function(arg)
local tbl18 = {}
if arg._savePath == "" then
return tbl18
end

for _, v119 in listfiles(arg._savePath) do
if isfile(v119) then
local match = (v119:match("[/\\]([^/\\]+)$") or v119):match("(.+)%.json$")

if match ~= nil then
table.insert(tbl18, match)
end
end
end

return tbl18
end

return index2
end

tbl17.f = function()
local f = tbl17.cache.f

if not f then
f = { c = fn35() }
tbl17.cache.f = f
end

return f.c
end
end
do -- g
local function fn35()local I;local function W(N,...)local P=I;I=nil;N(...);I=P;end;local function N(...)W(...);while true do W(coroutine.yield());end;end;local W={};W.__index=W;W.Disconnect=function(P)if not P.Connected then return;end;P.Connected=false;if P._signal._handlerListHead==P then P._signal._handlerListHead=P._next;else local a=P._signal._handlerListHead;while a and a._next~=P do a=a._next;end;if a then a._next=P._next;end;end;end;W.Destroy=W.Disconnect;setmetatable(W,{__index=function(P,P)error(("Attempt to get Connection::%s (not a valid member)"):format(tostring(P)),2);end,__newindex=function(P,P,a)error(("Attempt to set Connection::%s (not a valid member)"):format(tostring(P)),2);end});local P={};P.__index=P;P.new=function()return(setmetatable({_handlerListHead=false,_proxyHandler=nil,_yieldedThreads=nil},P));end;P.Wrap=function(a)assert(typeof(a)=="RBXScriptSignal","Argument #1 to Signal.Wrap must be a RBXScriptSignal; got "..typeof(a));local e=P.new();e._proxyHandler=a:Connect(function(...)e:Fire(...);end);return e;end;P.Is=function(a)return type(a)=="table"and getmetatable(a)==P;end;P.Connect=function(a,e)local c=setmetatable({Connected=true,_signal=a,_fn=e,_next=false},W);if a._handlerListHead then c._next=a._handlerListHead;a._handlerListHead=c;else a._handlerListHead=c;end;return c;end;P.ConnectOnce=function(W,a)return W:Once(a);end;P.Once=function(W,a)local e;local c=false;e=W:Connect(function(...)if c then return;end;c=true;e:Disconnect();a(...);end);return e;end;P.GetConnections=function(W)local a,e={},W._handlerListHead;while e do table.insert(a,e);e=e._next;end;return a;end;P.DisconnectAll=function(W)local a=W._handlerListHead;while a do a.Connected=false;a=a._next;end;W._handlerListHead=false;a= v102 (W,"_yieldedThreads");if a then for e in a,nil,nil do if coroutine.status(e)=="suspended"then warn(debug.traceback(e,"signal disconnected; yielded thread cancelled",2));task.cancel(e);end;end;table.clear(W._yieldedThreads);end;end;P.Fire=function(W,...)local a=W._handlerListHead;while a do if a.Connected then W=I;if not W then I=coroutine.create(N);end;task.spawn(I,a._fn,...);end;a=a._next;end;end;P.FireDeferred=function(I,...)local W=I._handlerListHead;while W do local I=W;task.defer(function(...)if I.Connected then I._fn(...);end;end,...);W=W._next;end;end;P.Wait=function(I)local W= v102 (I,"_yieldedThreads");if not W then W={}; v103 (I,"_yieldedThreads",W);end;local N=coroutine.running();W[N]=true;I:Once(function(...)W[N]=nil;if coroutine.status(N)=="suspended"then task.spawn(N,...);end;end);return coroutine.yield();end;P.Destroy=function(I)I:DisconnectAll();local W= v102 (I,"_proxyHandler");if W then W:Disconnect();end;end;return table.freeze({new=P.new,Wrap=P.Wrap,Is=P.Is});end

tbl17.g = function()
local g = tbl17.cache.g

if not g then
local g2 = { c = fn35() }
tbl17.cache.g = g2
g = g2
end

return g.c
end
end
do -- h
local function fn35()
local v115 = tbl17.g()
local index2 = {}
index2.__index = index2
local index3 = {}
index3.__index = index3
index3.Enable = function(l)if l.Connected then return;end;l.Connected=true;l._inner=l._signal._inner:Connect(l._callback);end
index3.Disable = function(l)if not l.Connected then return;end;l.Connected=false;local I=l._inner;if I~=nil then I:Disconnect();end;l._inner=nil;end
index3.Disconnect = index3.Disable
index3.Destroy = index3.Disable
index2.Connect = function(I,W)local N=setmetatable({_signal=I,_callback=W,_inner=nil,Connected=false}, index3 );N:Enable();return N;end
index2.Fire = function(l,I)l._inner:Fire(I);end

index2.FireDeferred = function(arg, arg2)
arg._inner:FireDeferred(arg2)
end

index2.Once = function(arg, arg2)
return arg._inner:Once(arg2)
end

index2.Wait = function(arg)
return arg._inner:Wait()
end

index2.DisconnectAll = function(arg)
arg._inner:DisconnectAll()
end

index2.GetConnections = function(arg)
return arg._inner:GetConnections()
end

index2.Destroy = function(arg)
arg._inner:Destroy()
end

return table.freeze({ new = function()
return (setmetatable({ _inner = v115.new() }, index2))
end })
end

tbl17.h = function()
local h = tbl17.cache.h

if not h then
local h2 = { c = fn35() }
tbl17.cache.h = h2
h = h2
end

return h.c
end
end
do -- i
local function fn35()
local tbl18 = {}

return {
atomic = function(arg)
setmetatable(arg, tbl18)
return arg
end,
isAtomic = function(I)return type(I)=="table"and getmetatable(I)== tbl18 ;end,
}
end

tbl17.i = function()
local i = tbl17.cache.i

if not i then
local i2 = { c = fn35() }
tbl17.cache.i = i2
i = i2
end

return i.c
end
end
do -- j
local function fn35()
if true then
local isAtomic = tbl17.i().isAtomic
local tbl18

tbl18 = {
PathToKey = function(l)return table.concat(l,".");end,
KeyToPath = function(l)return l:split(".");end,
NavigateTo = function(l,I,W)if#I==0 then return nil;end;for N=1,#I,1 do local P=I[N];if N==#I then return l[P];end;l=l[P];if l==nil then if W then return nil;end;error(string.format("Invalid path specified '%s', key %s is nil!",tostring(table.concat(I,".")),tostring(P)),2);elseif type(l)~="table"then if W then return nil;end;error(string.format("Invalid path specified '%s', key %s is not a branch!",tostring(table.concat(I,".")),tostring(P)),2);end;end;return nil;end,
Set = function(I,W,N)for P=1,#W,1 do local a=W[P];if P==#W then I[a]=N;return;end;P=I[a];if P==nil then P={};I[a]=P;elseif type(P)~="table"then local N= tbl18 .PathToKey(W);error(string.format("Invalid path specified '%s', key %s is not a table!",tostring(N),tostring(a)),2);end;I=P;end;end,
ForEachEntry = function(I,W)local N={};local function P(a)for e,c in a,nil,nil do table.insert(N,e);W(N,c);if type(c)=="table"and not  isAtomic (c)then P(c);end;table.remove(N);end;end;P(I);end,
ForEachLeafValue = function(I,W,N)local P={};local function a(e,c)for E,p in e,nil,nil do table.insert(P,E);local e=if c~=nil then c[E]else nil;local c=type(e)=="table";E=if type(p)=="table"and not  isAtomic (p)and not(c and( isAtomic (e)))and(e==nil or c)then(a(p,if c then e else nil))else if c and not  isAtomic (e)then false else N(P,p)==true;table.remove(P);if E then return true;end;end;return false;end;a(I,W);end,
}

return tbl18
end

while v86[34] do
end
end

tbl17.j = function()
local j = tbl17.cache.j

if not j then
local j2 = { c = fn35() }
tbl17.cache.j = j2
j = j2
end

return j.c
end
end
do -- l
local function fn35()
local v115 = tbl17.f()
local v116 = tbl17.h()
local v117 = tbl17.j()
local v118 = tbl17.a()
local v119 = tbl17.g()
local v120 = tbl17.k()
local v121 = tbl17.d()
local isAtomic = tbl17.i().isAtomic
local index2 = {}
index2.__index = index2

index2.new = function(arg)
local ReactiveStore = v120.new("ReactiveStore")

return setmetatable({
_trove = ReactiveStore,
Default = arg.DefaultConfig,
Data = v121(arg.DefaultConfig),
_middleware = {},
_configManager = v115.new({
DefaultConfig = arg.DefaultConfig,
CurrentVersion = arg.CurrentVersion,
LegacyVersion = arg.LegacyVersion,
SavePath = arg.SavePath,
Migrations = arg.Migrations,
Serialize = arg.Serialize,
... (2 MB left)
