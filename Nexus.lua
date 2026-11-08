-- ============================================================
--  HALLOWEEN SOUL + GOJO — Dual Tab Hub
--  Tab 1: Soul (pumpkin morph, 8 abilities)
--  Tab 2: Gojo (4 tools, void-kill integrated)
-- ============================================================
local CONFIG = {
    MODEL_NAME = "Halloween Soul", ASSET_ID = 98347939019582,
    MODEL_YAW = 0, TARGET_HEIGHT = 16.5,
    NORMAL_SPEED = 22, QUAD_SPEED = 52, JUMP_POWER = 54,
    GRAB_RANGE = 28, SLAM_RANGE = 30, CURSE_RANGE = 95, SWIPE_RANGE = 24,
    PUMPKIN_ASSET = 15429930446, PUMPKIN_MESH = 1157467, PUMPKIN_TEX = 1158033,
    SWIPE_DAMAGE = 25, CURSE_TIME = 30, RESPAWN_DELAY = 18,
    NPC_CLEANUP_TIME = 6.0, MAX_VICTIM_SIZE = 55,
    VOID_Y = -9000, VOID_THROW_VEL = 9999,
    ANIM_SPEED = 2.5, GORE_INTENSITY = 1.15,
    MENU_KEY = Enum.KeyCode.RightShift, INSTINCT_KEY = Enum.KeyCode.J,
    NEON_A = Color3.fromRGB(255, 122, 24), NEON_B = Color3.fromRGB(201, 20, 43),
    NEON_C = Color3.fromRGB(123, 214, 58), NEON_D = Color3.fromRGB(168, 64, 255),
}
local SND = {
    flesh="rbxassetid://3626677712", gore="rbxassetid://429400881", crunch="rbxassetid://4876899660",
    bite="rbxassetid://6305378182", chomp="rbxassetid://6204856270", scare="rbxassetid://971398743",
    amb="rbxassetid://1835337424", roar="rbxassetid://9069609267",
    hit="rbxasset://sounds/hit.wav", slash="rbxasset://sounds/swordslash.wav",
    whoosh="rbxasset://sounds/swordlunge.wav", splat="rbxasset://sounds/impact_water.mp3",
    snap="rbxasset://sounds/snap.mp3", thud="rbxasset://sounds/action_jump_land.mp3",
    ui="rbxasset://sounds/electronicpingshort.wav",
}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
if not player then return end
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if genv.__HALLOWEEN_SOUL_V3 then pcall(genv.__HALLOWEEN_SOUL_V3) end

local ANIM = CONFIG.ANIM_SPEED
local rng = Random.new()
local UP = Vector3.new(0, 1, 0)
local function rnd(a,b) return rng:NextNumber(a,b) end
local function clamp01(x) return math.clamp(x,0,1) end
local function smooth(x) x=clamp01(x) return x*x*(3-2*x) end
local function easeOut(x) x=clamp01(x) return 1-(1-x)^3 end
local function easeIn(x) x=clamp01(x) return x*x*x end
local function lerp(a,b,t) return a+(b-a)*t end

local globalConns, morphConns = {}, {}
local function gtrack(c) globalConns[#globalConns+1]=c; return c end
local function mtrack(c) morphConns[#morphConns+1]=c; return c end

local menuOpen = false
local actRip, actSlam, actDevour, actCurse, actSwipe, actHeadEat, actRoar, spawnDummy
local instinctLabelUI
local activeTab = "soul"
local buildMobilePad

-- ===== SOUL STATE =====
local S = {
    mounted=false, busy=false, character=nil, humanoid=nil, hrp=nil,
    model=nil, entries={}, parts={}, cfs={}, height=CONFIG.TARGET_HEIGHT,
    yaw=CONFIG.MODEL_YAW, yawCF=CFrame.new(),
    groups={}, pivot={}, handRel={},
    headCenter=Vector3.new(0,14,0), neck=Vector3.new(0,12,0), headR=1.8,
    pumpkinRel=nil, mawWorld=Vector3.zero, handL=nil, handR=nil,
    armSign={L=1,R=1}, target=nil,
    flat=Vector3.new(0,0,-1), walk=0, gait=0,
    quad=false, quadBlend=0, quadGait=0, ctrlHeld=false,
    atk=nil, atkStart=0, atkDur=0, ev={}, victim=nil, atkLock=0, cd={},
    shake=0, camBase=Vector3.zero,
    origTransp=setmetatable({}, {__mode="k"}),
}
local soulInstinct = false
local shiftlockOn = false

-- ===== GOJO FORWARD DECLS =====
local Gojo = { mounted=false, instinct=false, cleanup=nil, dmgLib=nil, tools={} }
local toggleGojoInstinct = function() end
local mountGojo, unmountGojo

local fxFolder = Instance.new("Folder")
fxFolder.Name = "HalloweenSoul_FX_v3"
fxFolder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local function refreshFilter() rayParams.FilterDescendantsInstances = {fxFolder, S.character} end
refreshFilter()
local function groundAt(pos, up, depth)
    return workspace:Raycast(pos + Vector3.new(0, up or 6, 0), Vector3.new(0, -(depth or 40), 0), rayParams)
end

local function sfx(id, vol, pitch, parent)
    if not id or id == "" then return end
    local s = Instance.new("Sound")
    s.SoundId = id; s.Volume = vol or 1; s.PlaybackSpeed = pitch or 1
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.RollOffMinDistance = 14; s.RollOffMaxDistance = 250
    s.Parent = parent or (S.hrp and S.hrp.Parent and S.hrp) or workspace
    pcall(function() s:Play() end)
    Debris:AddItem(s, 7)
    return s
end
local function tw(o, t, props, style, dir)
    local x = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    x:Play(); return x
end

-- ===== VOID KILL (shared by both modules) =====
local function voidKill(model)
    if not model or not model.Parent then return false end
    if not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    local myChar = player.Character
    if myChar and (model == myChar or model:IsDescendantOf(myChar)) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(player, "SimulationRadius", 5000)
            sethiddenproperty(player, "MaxSimulationRadius", 5000)
        end
    end)
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and not (myChar and d:IsDescendantOf(myChar)) then
            parts[#parts+1] = d
            pcall(function() d:SetNetworkOwner(player) end)
        end
    end
    task.wait(0.05)
    for _, p in ipairs(parts) do
        if p.Parent then
            pcall(function()
                p.Anchored = false; p.CanCollide = false; p.Massless = false
                p.CFrame = CFrame.new(p.Position.X, CONFIG.VOID_Y, p.Position.Z)
                p.AssemblyLinearVelocity = Vector3.new(0, -CONFIG.VOID_THROW_VEL, 0)
                p.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
    pcall(function() hum.Health = 0; hum:ChangeState(Enum.HumanoidStateType.Dead) end)
    pcall(function() model:BreakJoints() end)
    task.delay(0.15, function()
        if model and model.Parent then
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then pcall(function() d:Destroy() end) end
            end
            pcall(function() model:Destroy() end)
        end
    end)
    return true
end

-- ===== SHIFTLOCK =====
local function tryTogglePlayerShiftlock(on)
    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        if ps then
            local pm = ps:FindFirstChild("PlayerModule")
            if pm then
                local mod = require(pm)
                local cams = mod:GetCameras()
                for _, c in pairs(cams) do
                    if c.GetShiftLockEnabled then
                        if on and not c:GetShiftLockEnabled() then c:ToggleShiftLock(true)
                        elseif not on and c:GetShiftLockEnabled() then c:ToggleShiftLock(false) end
                        break
                    end
                end
            end
        end
    end)
end
local function setShiftlock(on)
    shiftlockOn = on
    if on then
        pcall(function()
            player.CameraMode = Enum.CameraMode.Classic
            player.CameraMinZoomDistance = 12
            player.CameraMaxZoomDistance = 100
        end)
        tryTogglePlayerShiftlock(true)
    else
        pcall(function()
            player.CameraMinZoomDistance = 0.5
            player.CameraMaxZoomDistance = 128
        end)
        tryTogglePlayerShiftlock(false)
    end
end

-- ============================================================
--  SOUL EFFECTS HELPERS
-- ============================================================
local function bloodColor() return Color3.fromRGB(rng:NextInteger(180,245), rng:NextInteger(0,14), rng:NextInteger(0,18)) end
local function boneColor()
    local b = rng:NextInteger(215,245)
    return Color3.fromRGB(b, b-rng:NextInteger(8,20), b-rng:NextInteger(25,40))
end
local function pumpkinColor() return Color3.fromRGB(rng:NextInteger(220,255), rng:NextInteger(100,150), rng:NextInteger(10,40)) end
local function rockColor() return Color3.fromRGB(rng:NextInteger(40,70), rng:NextInteger(30,50), rng:NextInteger(25,40)) end
local function flatCF(pos, normal)
    local ref = (math.abs(normal.Y) > 0.9) and Vector3.new(1,0,0) or UP
    local tangent = ref:Cross(normal).Unit
    return CFrame.fromMatrix(pos, tangent, normal, tangent:Cross(normal))
end
local function coneDir(d, spread)
    local up = (math.abs(d.Y) > 0.95) and Vector3.new(0,0,1) or UP
    return (CFrame.lookAt(Vector3.zero, d, up) * CFrame.Angles(rnd(-spread,spread), rnd(-spread,spread), 0)).LookVector
end
local function anchorPart(pos)
    local a = Instance.new("Part")
    a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.CanTouch=false
    a.Transparency=1; a.Size=Vector3.new(0.2,0.2,0.2); a.Position=pos
    a.Parent = fxFolder; return a
end
local stains = {}
local function makeDisc(pos, normal, d1, d2, thick, color, material)
    local p = Instance.new("Part")
    p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false
    p.Material = material or Enum.Material.SmoothPlastic
    p.Color = color; p.Size = Vector3.new(d1, thick, d2)
    p.CFrame = flatCF(pos, normal) * CFrame.Angles(0, rnd(0,6.28), 0)
    Instance.new("CylinderMesh").Parent = p
    return p
end
local function puddle(pos, normal, radius, life)
    local p = makeDisc(pos + normal*0.04, normal, 0.2, 0.2, 0.05, Color3.fromRGB(rng:NextInteger(95,140),0,rng:NextInteger(0,10)))
    p.Reflectance = 0.2; p.Parent = fxFolder
    stains[#stains+1] = p
    if #stains > 180 then local o = table.remove(stains,1) if o and o.Parent then o:Destroy() end end
    tw(p, rnd(0.4,0.9), {Size=Vector3.new(radius*2,0.05,radius*2)}, Enum.EasingStyle.Quart)
    task.delay(life or 25, function()
        if p.Parent then tw(p, 2.5, {Transparency=1}) Debris:AddItem(p, 2.6) end
    end)
end
local livePieces = 0
local function piece(kind, pos, vel, size)
    if livePieces >= 300 then return end
    livePieces += 1
    local p = Instance.new("Part")
    if kind == "bone" then
        p.Color=boneColor(); p.Material=Enum.Material.SmoothPlastic
        p.Size=Vector3.new(size*0.45, size*rnd(1.1,2.2), size*0.45)
    elseif kind == "pumpkin" then
        p.Color=pumpkinColor(); p.Material=Enum.Material.Neon
        p.Size=Vector3.new(size, size*rnd(0.7,1.2), size)
    elseif kind == "rock" then
        p.Color=rockColor(); p.Material=Enum.Material.Slate
        p.Size=Vector3.new(size, size, size)
    else
        p.Color=bloodColor(); p.Material=Enum.Material.SmoothPlastic
        p.Reflectance=0.18; p.Size=Vector3.new(size, size*rnd(0.8,1.3), size*rnd(0.8,1.3))
    end
    p.CanCollide=false; p.CanQuery=false; p.CanTouch=true
    p.CFrame = CFrame.new(pos) * CFrame.Angles(rnd(0,6.28), rnd(0,6.28), rnd(0,6.28))
    p.Parent = fxFolder
    p.AssemblyLinearVelocity = vel
    p.AssemblyAngularVelocity = Vector3.new(rnd(-22,22), rnd(-22,22), rnd(-22,22))
    p.Destroying:Connect(function() livePieces -= 1 end)
    task.delay(0.14, function() if p.Parent then p.CanCollide = true end end)
    task.delay(rnd(3,6), function()
        if p.Parent then tw(p, 0.8, {Size=Vector3.new(0.05,0.05,0.05), Transparency=1}) Debris:AddItem(p, 0.9) end
    end)
    Debris:AddItem(p, 8)
end
local function carnage(pos, dir, count, o)
    o = o or {}
    local n = math.max(1, math.floor(count * CONFIG.GORE_INTENSITY))
    for _=1,n do
        local roll = rng:NextNumber()
        local kind = (roll < (o.bone or 0.16)) and "bone" or ((roll < 0.28) and "pumpkin" or "blood")
        piece(kind, pos + Vector3.new(rnd(-1,1),rnd(-0.5,1),rnd(-1,1)) * (o.jit or 0.8),
            coneDir(dir, o.spread or 0.9) * rnd(o.vmin or 18, o.vmax or 60), rnd(o.smin or 0.3, o.smax or 0.8))
    end
end
local function mist(pos, amount, size, col)
    local a = anchorPart(pos)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
    pe.Color = ColorSequence.new(col or Color3.fromRGB(220,10,20), Color3.fromRGB(40,0,5))
    pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size*0.5), NumberSequenceKeypoint.new(1, size*1.8)})
    pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
    pe.Lifetime = NumberRange.new(0.7, 1.8); pe.Speed = NumberRange.new(6, 24)
    pe.SpreadAngle = Vector2.new(180, 180); pe.Drag = 3.2; pe.Rate = 0
    pe.Parent = a; pe:Emit(amount); Debris:AddItem(a, 3.5)
end
local function ring(pos, normal, maxR, color, dur)
    local p = makeDisc(pos + normal*0.08, normal, 1, 1, 0.12, color, Enum.Material.Neon)
    p.Transparency = 0.25; p.Parent = fxFolder
    tw(p, dur, {Size=Vector3.new(maxR*2, 0.12, maxR*2), Transparency=1})
    Debris:AddItem(p, dur+0.2)
end
local function lightFlash(pos, col, br, range, dur)
    local a = anchorPart(pos)
    local l = Instance.new("PointLight")
    l.Color=col; l.Brightness=br; l.Range=range; l.Parent=a
    tw(l, dur, {Brightness=0}); Debris:AddItem(a, dur+0.1)
end
local function cracks(pos, normal, len, n)
    for i=1,(n or 8) do
        local a = i/(n or 8) * 6.28 + rnd(-0.2, 0.2)
        local L = rnd(len*0.5, len)
        local d = Vector3.new(math.cos(a),0,math.sin(a))
        local cf = CFrame.lookAt(pos + d*L/2 + normal*0.05, pos + d*L + normal*0.05)
        local c = Instance.new("Part")
        c.Anchored=true; c.CanCollide=false; c.CanQuery=false; c.CanTouch=false
        c.Color = Color3.fromRGB(15,8,8); c.Size = Vector3.new(0.5,0.08,0.1)
        c.CFrame = cf; c.Parent = fxFolder
        tw(c, 0.25, {Size=Vector3.new(0.5,0.08,L)})
        task.delay(7, function() if c.Parent then tw(c, 1.5, {Transparency=1}) end end)
        Debris:AddItem(c, 9)
    end
end
local function arterialFountain(neckPart, dur)
    if not neckPart or not neckPart.Parent then return end
    local att = Instance.new("Attachment")
    att.Position = Vector3.new(0, neckPart.Size.Y*0.45, 0); att.Parent = neckPart
    local jet = Instance.new("ParticleEmitter")
    jet.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    jet.Color = ColorSequence.new(Color3.fromRGB(220,10,20), Color3.fromRGB(80,0,5))
    jet.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.9), NumberSequenceKeypoint.new(1,0.15)})
    jet.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.05), NumberSequenceKeypoint.new(1,0.85)})
    jet.Lifetime = NumberRange.new(0.8,1.5); jet.Rate = 180
    jet.Speed = NumberRange.new(28,48); jet.SpreadAngle = Vector2.new(18,18)
    jet.Acceleration = Vector3.new(0,-90,0); jet.LightEmission = 0.2
    jet.Parent = att
    task.spawn(function()
        local t0 = os.clock()
        while os.clock()-t0 < dur and neckPart.Parent do
            local g = groundAt(neckPart.Position, 1, 20)
            if g then puddle(g.Position, g.Normal, rnd(1.2,2.4), 16) end
            task.wait(0.18)
        end
        jet.Enabled = false
        task.delay(2, function() if att.Parent then att:Destroy() end end)
    end)
end
local tint
local function impactTint(power)
    if not tint then return end
    tint.TintColor = Color3.fromRGB(255, math.floor(160-100*power), math.floor(140-90*power))
    tw(tint, 0.55, {TintColor=Color3.fromRGB(255,230,225)})
end
local baseFOV
local function fovPunch(amount)
    local cam = workspace.CurrentCamera
    if not cam then return end
    baseFOV = baseFOV or cam.FieldOfView
    cam.FieldOfView = baseFOV + amount
    tw(cam, 0.45, {FieldOfView = baseFOV}, Enum.EasingStyle.Quart)
end

-- ============================================================
--  SOUL VICTIM SYSTEM
-- ============================================================
local victims = {}
local function getRoot(m)
    local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso")
    if r and r:IsA("BasePart") then return r end
    if m.PrimaryPart then return m.PrimaryPart end
    local head = m:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    local best, bestVol = nil, 0
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            local v = d.Size.X*d.Size.Y*d.Size.Z
            if v > bestVol then best, bestVol = d, v end
        end
    end
    return best
end
local function validTarget(m)
    if victims[m] or not m.Parent then return nil end
    local ch = S.character
    if ch and (m == ch or m:IsDescendantOf(ch) or ch:IsDescendantOf(m)) then return nil end
    if m == player.Character then return nil end
    if m:IsDescendantOf(fxFolder) then return nil end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return nil end
    local root = getRoot(m)
    if not root then return nil end
    local ok, size = pcall(function() return m:GetExtentsSize() end)
    if not ok then return nil end
    local maxDim = math.max(size.X, size.Y, size.Z)
    if maxDim > CONFIG.MAX_VICTIM_SIZE then
        if not hum then return nil end
        if maxDim > 120 then return nil end
    end
    return root
end
local function candidateFromPart(part)
    local m = part:FindFirstAncestorOfClass("Model")
    while m do
        if m:FindFirstChildOfClass("Humanoid") then return m end
        m = m:FindFirstAncestorOfClass("Model")
    end
    return nil
end
local function findTarget(range, center)
    local hrp = S.hrp
    if not hrp then return nil end
    center = center or (hrp.Position + S.flat*4)
    local best, bestD = nil, range+2
    local seen = {}
    local function consider(m)
        if not m or seen[m] then return end
        seen[m] = true
        local r = validTarget(m)
        if r then
            local d = (r.Position - center).Magnitude
            if d < bestD then best, bestD = m, d end
        end
    end
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = {fxFolder, S.character}
    for _, p in ipairs(workspace:GetPartBoundsInRadius(center, range, op)) do
        consider(candidateFromPart(p))
    end
    if not best then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.ClassName == "Humanoid" and d.Parent and d.Parent:IsA("Model") then
                consider(d.Parent)
            end
        end
    end
    return best
end
local capture
local function targetHeadPosition(model)
    if not model or not model.Parent then return nil end
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head.Position end
    local root = getRoot(model)
    if root then return root.Position + UP*math.max(root.Size.Y, 2) end
    return nil
end
local function grabRadius() return math.clamp(S.height*0.42, 6, 11) end
local function captureOnContact()
    if S.victim then return S.victim end
    local m = S.target
    if not (m and m.Parent) then return nil end
    local hp = targetHeadPosition(m)
    if not hp then return nil end
    local r = grabRadius()
    local touched = false
    if S.handR and (S.handR-hp).Magnitude <= r then touched = true end
    if not touched and S.handL and (S.handL-hp).Magnitude <= r then touched = true end
    if not touched then
        local ok, pivot = pcall(function() return m:GetPivot() end)
        if ok and pivot then
            if S.handR and (S.handR-pivot.Position).Magnitude <= r*1.15 then touched = true end
            if not touched and S.handL and (S.handL-pivot.Position).Magnitude <= r*1.15 then touched = true end
        end
    end
    if not touched then return nil end
    local hand = S.handR or S.handL
    local rec = capture(m)
    if rec then
        rec.grabbedAt = os.clock()
        local ok, pivot = pcall(function() return rec.model:GetPivot() end)
        if ok and pivot then rec.carryOffset = CFrame.new(hand):ToObjectSpace(pivot) else rec.carryOffset = CFrame.new() end
        S.victim = rec; S.target = nil; S.ev.contact = true
    end
    return rec
end
local function vSet(rec, cf) pcall(function() rec.model:PivotTo(cf) end) end
local function vGet(rec)
    local ok, cf = pcall(function() return rec.model:GetPivot() end)
    if ok and cf then return cf end
    return rec.origCF
end
capture = function(m)
    local root = getRoot(m)
    if not root then return nil end
    local isPl = (Players:GetPlayerFromCharacter(m) ~= nil)
    local okp, pivot = pcall(function() return m:GetPivot() end)
    local oks, size = pcall(function() return m:GetExtentsSize() end)
    local rec = {
        model=m, root=root, hum=m:FindFirstChildOfClass("Humanoid"), isPlayer=isPl,
        parts={}, transp={}, collide={}, anch={},
        origCF=okp and pivot or root.CFrame,
        size=oks and size or Vector3.new(4,5,2),
        state="held",
        headPart=m:FindFirstChild("Head"),
        torsoPart=m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso"),
    }
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            rec.parts[#rec.parts+1] = d
            rec.transp[d]=d.Transparency
            rec.collide[d]=d.CanCollide
            rec.anch[d]=d.Anchored
            d.CanCollide=false; d.Anchored=true
        end
    end
    if rec.hum then
        rec.display = rec.hum.DisplayDistanceType
        pcall(function() rec.hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
    end
    victims[m] = rec
    return rec
end
local function freezeVictim(rec)
    if not rec then return end
    for _, d in ipairs(rec.parts) do
        if d.Parent and d:IsA("BasePart") then
            d.Anchored=true; d.CanCollide=true
            d.AssemblyLinearVelocity=Vector3.zero; d.AssemblyAngularVelocity=Vector3.zero
        end
    end
    if rec.hum then
        pcall(function()
            rec.hum.PlatformStand=true; rec.hum.AutoRotate=false
            rec.hum.WalkSpeed=0; rec.hum.JumpPower=0
        end)
    end
end
local function restoreVictim(rec, toOrigin)
    victims[rec.model] = nil
    if toOrigin then pcall(function() rec.model:PivotTo(rec.origCF) end) end
    for _, d in ipairs(rec.parts) do
        if d.Parent then
            d.Transparency = rec.transp[d] or 0
            if d:IsA("BasePart") then
                if rec.collide[d] ~= nil then d.CanCollide = rec.collide[d] end
                if rec.anch[d] ~= nil then d.Anchored = rec.anch[d] end
            end
        end
    end
    if rec.hum then
        pcall(function() rec.hum.DisplayDistanceType = rec.display or Enum.HumanoidDisplayDistanceType.Viewer end)
    end
end
local function makeRagdoll(rec, dropHead, tossImpulse)
    local src = rec.model
    local holder = Instance.new("Model")
    holder.Name = "RagdollCorpse"; holder.Parent = fxFolder
    local clones, headClone, neckClone = {}, nil, nil
    for _, d in ipairs(src:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and (rec.transp[d] or 0) < 0.9 then
            local ok, c = pcall(function() d.Archivable = true; return d:Clone() end)
            if ok and c then
                for _, ch in ipairs(c:GetDescendants()) do
                    if ch:IsA("JointInstance") or ch:IsA("Constraint") or ch:IsA("BillboardGui")
                        or ch:IsA("ParticleEmitter") or ch:IsA("Trail") then ch:Destroy() end
                end
                c.Transparency = rec.transp[d] or 0
                c.Anchored=false; c.CanCollide=true; c.CanQuery=false; c.Massless=false
                c.CFrame = d.CFrame; c.Parent = holder
                clones[d] = c
                if d.Name == "Head" then headClone = c end
                if d.Name == "UpperTorso" or d.Name == "Torso" then neckClone = c end
            end
        end
    end
    for _, j in ipairs(src:GetDescendants()) do
        if j:IsA("Motor6D") and j.Part0 and j.Part1 then
            local a, b = clones[j.Part0], clones[j.Part1]
            local isNeck = (j.Part1 and j.Part1.Name == "Head") or j.Name == "Neck"
            if a and b and not (dropHead and isNeck) then
                local a0 = Instance.new("Attachment"); a0.CFrame = j.C0; a0.Parent = a
                local a1 = Instance.new("Attachment"); a1.CFrame = j.C1; a1.Parent = b
                local bs = Instance.new("BallSocketConstraint")
                bs.Attachment0=a0; bs.Attachment1=a1
                bs.LimitsEnabled=true; bs.UpperAngle=45
                bs.TwistLimitsEnabled=true; bs.TwistLowerAngle=-40; bs.TwistUpperAngle=40
                bs.Parent = a
            end
        end
    end
    local push = tossImpulse or Vector3.zero
    for _, c in pairs(clones) do
        c.AssemblyLinearVelocity = push + Vector3.new(rnd(-4,4), rnd(0,6), rnd(-4,4))
        c.AssemblyAngularVelocity = Vector3.new(rnd(-15,15), rnd(-15,15), rnd(-15,15))
    end
    if dropHead and headClone then
        headClone.AssemblyLinearVelocity = push*0.4 + UP*rnd(14,22) + S.flat*rnd(4,9)
        headClone.AssemblyAngularVelocity = Vector3.new(rnd(-20,20), rnd(-20,20), rnd(-20,20))
        carnage(headClone.Position, -UP, 10, {spread=1.0, vmin=8, vmax=24})
    end
    if dropHead and neckClone then arterialFountain(neckClone, 9) end
    task.delay(18, function()
        for _, c in ipairs(holder:GetChildren()) do
            if c:IsA("BasePart") then tw(c, 2, {Transparency=1}) end
        end
        Debris:AddItem(holder, 2.5)
    end)
    return holder, headClone, neckClone
end
local function killVictim(rec, dropHead, tossImpulse)
    if rec.state == "dead" then return end
    local myChar = player.Character
    if myChar and (rec.model == myChar or rec.model:IsDescendantOf(myChar)) then return end
    rec.state = "dead"
    makeRagdoll(rec, dropHead, tossImpulse)
    for _, d in ipairs(rec.parts) do
        if d.Parent then d.Transparency = 1 end
    end
    if rec.hum then
        pcall(function() rec.hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
    end
    if rec.isPlayer then
        rec.respawnAt = os.clock() + CONFIG.RESPAWN_DELAY
    else
        victims[rec.model] = nil
        local m = rec.model
        task.spawn(function() voidKill(m) end)
        task.delay(CONFIG.NPC_CLEANUP_TIME, function()
            pcall(function() if m.Parent and not (myChar and m:IsDescendantOf(myChar)) then m:Destroy() end end)
        end)
    end
end
local function applyDamage(rec, amount, dropHead, tossImpulse)
    local hum = rec.hum
    if not hum or rec.state == "dead" then return false end
    hum.Health = math.max(0, hum.Health - amount)
    if hum.Health <= 0 then killVictim(rec, dropHead, tossImpulse) return true end
    return false
end
local function checkRespawns()
    local now = os.clock()
    for m, rec in pairs(victims) do
        if not m.Parent then victims[m] = nil
        elseif rec.state == "dead" and rec.respawnAt and now >= rec.respawnAt then
            restoreVictim(rec, true)
            if rec.hum then pcall(function() rec.hum.Health = rec.hum.MaxHealth end) end
            mist(rec.origCF.Position + UP*2, 28, 5, CONFIG.NEON_D)
        end
    end
end

spawnDummy = function()
    if not S.hrp then return end
    local spawnFwd = S.hrp.Position + S.flat*12
    local g = groundAt(spawnFwd, 10, 40)
    local floorY = g and g.Position.Y or (S.hrp.Position.Y-3)
    local basePos = Vector3.new(spawnFwd.X, floorY+3, spawnFwd.Z)
    local faceRot = CFrame.lookAt(basePos, basePos - S.flat)
    local dummy = Instance.new("Model"); dummy.Name = "Dummy"
    local function part(name, size, off, col)
        local p = Instance.new("Part")
        p.Name=name; p.Size=size; p.Color=col or Color3.fromRGB(215,185,160)
        p.Material=Enum.Material.SmoothPlastic
        p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
        p.CanCollide=true; p.CanQuery=true; p.CanTouch=false; p.Anchored=false
        p.CFrame = faceRot * CFrame.new(off); p.Parent = dummy
        return p
    end
    local cloth = Color3.fromRGB(48,52,60)
    local torso = part("Torso", Vector3.new(2,2,1), Vector3.new(0,0,0), cloth)
    local head  = part("Head", Vector3.new(2,1,1), Vector3.new(0,1.5,0))
    local la    = part("Left Arm", Vector3.new(1,2,1), Vector3.new(-1.5,0,0))
    local ra    = part("Right Arm", Vector3.new(1,2,1), Vector3.new(1.5,0,0))
    local ll    = part("Left Leg", Vector3.new(1,2,1), Vector3.new(-0.5,-2,0), cloth)
    local rl    = part("Right Leg", Vector3.new(1,2,1), Vector3.new(0.5,-2,0), cloth)
    dummy.PrimaryPart = torso
    local function joint(name, p0, p1, c0)
        local m = Instance.new("Motor6D")
        m.Name=name; m.Part0=p0; m.Part1=p1; m.C0=c0; m.C1=CFrame.new(); m.Parent=p0
        return m
    end
    joint("Neck", torso, head, CFrame.new(0,1,0)*CFrame.fromEulerAnglesXYZ(-math.pi/2,0,math.pi))
    joint("Left Shoulder", torso, la, CFrame.new(-1,0.5,0)*CFrame.fromEulerAnglesXYZ(0,-math.pi/2,0))
    joint("Right Shoulder", torso, ra, CFrame.new(1,0.5,0)*CFrame.fromEulerAnglesXYZ(0,math.pi/2,0))
    joint("Left Hip", torso, ll, CFrame.new(-0.5,-1,0)*CFrame.fromEulerAnglesXYZ(0,math.pi/2,0))
    joint("Right Hip", torso, rl, CFrame.new(0.5,-1,0)*CFrame.fromEulerAnglesXYZ(0,-math.pi/2,0))
    local hum = Instance.new("Humanoid")
    hum.DisplayName="Dummy [NPC]"; hum.MaxHealth, hum.Health = 100, 100
    hum.WalkSpeed=0; hum.JumpPower=0; hum.AutoRotate=false
    hum.BreakJointsOnDeath=true; hum.RequiresNeck=false; hum.HipHeight=0
    hum.Parent = dummy
    dummy.Parent = workspace
    for _, p in ipairs(dummy:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
    task.delay(0.2, function()
        if not dummy.Parent then return end
        for _, p in ipairs(dummy:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
    end)
    mist(basePos - UP*2, 14, 5, CONFIG.NEON_C)
    sfx(SND.ui, 0.8, 1.2)
end

-- ============================================================
--  SOUL TEMPLATE LOADING & ANALYSIS
-- ============================================================
local template, templateLoading = nil, false
local function stripModel(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("Animator")
            or d:IsA("AnimationController") or d:IsA("JointInstance") or d:IsA("WeldConstraint")
            or d:IsA("BodyMover") or d:IsA("ClickDetector") or d:IsA("ProximityPrompt")
            or d.Name == "AnimSaves" then pcall(function() d:Destroy() end) end
    end
end
local function loadTemplate()
    if template then return template end
    if templateLoading then while templateLoading do task.wait() end return template end
    templateLoading = true
    warn("[Soul] Loading asset " .. tostring(CONFIG.ASSET_ID) .. "...")
    local raw
    local found = workspace:FindFirstChild(CONFIG.MODEL_NAME, true)
        or ReplicatedStorage:FindFirstChild(CONFIG.MODEL_NAME, true)
        or Lighting:FindFirstChild(CONFIG.MODEL_NAME, true)
    if found and found:IsA("Model") then
        local ok, c = pcall(function() found.Archivable = true; return found:Clone() end)
        if ok and c then raw = c end
    end
    if not raw and CONFIG.ASSET_ID and CONFIG.ASSET_ID > 0 then
        local url = "rbxassetid://" .. CONFIG.ASSET_ID
        local tries = {
            {name="game:GetObjects", fn=function() return game:GetObjects(url) end},
            {name="getobjects", fn=function() return getobjects and getobjects(game, url) end},
            {name="LoadLocalAsset", fn=function() return InsertService:LoadLocalAsset(url) end},
            {name="LoadAsset", fn=function() return InsertService:LoadAsset(CONFIG.ASSET_ID) end},
        }
        for _, t in ipairs(tries) do
            if raw then break end
            local ok, res = pcall(t.fn)
            if ok and res then
                if typeof(res) == "table" then
                    local h = Instance.new("Model")
                    for _, i in ipairs(res) do if typeof(i) == "Instance" then i.Parent = h end end
                    raw = h
                elseif typeof(res) == "Instance" and res:IsA("Model") then
                    raw = res
                end
            end
        end
    end
    if raw then
        stripModel(raw); template = raw
        warn("[Soul] ✔ Template loaded (" .. #raw:GetDescendants() .. " descendants)")
    else
        warn("[Soul] ✘ FAILED to load asset " .. CONFIG.ASSET_ID)
    end
    templateLoading = false
    return template
end
local function measure(parts, rot)
    local inv = rot:Inverse()
    local mn = Vector3.new(math.huge, math.huge, math.huge); local mx = -mn
    for _, p in ipairs(parts) do
        local cf = inv * p.CFrame
        local hx, hy, hz = p.Size.X/2, p.Size.Y/2, p.Size.Z/2
        local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
        local e = Vector3.new(
            math.abs(r.X)*hx + math.abs(u.X)*hy + math.abs(l.X)*hz,
            math.abs(r.Y)*hx + math.abs(u.Y)*hy + math.abs(l.Y)*hz,
            math.abs(r.Z)*hx + math.abs(u.Z)*hy + math.abs(l.Z)*hz)
        mn = mn:Min(cf.Position - e); mx = mx:Max(cf.Position + e)
    end
    return mn, mx
end
local function manualScale(parts, f)
    for _, p in ipairs(parts) do
        local cf = p.CFrame
        p.Size = p.Size * f
        p.CFrame = CFrame.new(cf.Position * f) * cf.Rotation
        for _, ch in ipairs(p:GetChildren()) do
            if ch:IsA("SpecialMesh") then ch.Scale = ch.Scale * f; ch.Offset = ch.Offset * f end
        end
    end
end
local function buildEntries(model)
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored=true; d.CanCollide=false; d.CanQuery=false; d.CanTouch=false; d.Massless=true
            parts[#parts+1] = d
        end
    end
    if #parts == 0 then return nil end
    local rr = model:FindFirstChild("HumanoidRootPart", true)
    local rot = (rr and rr:IsA("BasePart")) and rr.CFrame.Rotation or CFrame.new()
    local mn, mx = measure(parts, rot)
    local s = CONFIG.TARGET_HEIGHT / math.max(mx.Y - mn.Y, 0.5)
    if not pcall(function() model:ScaleTo(model:GetScale() * s) end) then manualScale(parts, s) end
    mn, mx = measure(parts, rot)
    local inv = (rot * CFrame.new((mn.X+mx.X)/2, mn.Y, (mn.Z+mx.Z)/2)):Inverse()
    local entries = {}
    for i, p in ipairs(parts) do entries[i] = {part=p, rel=inv * p.CFrame} end
    return entries, parts, math.max(mx.Y - mn.Y, 1)
end
local function tagOf(name)
    local n = string.lower(name):gsub("[%s_%-]", "")
    if n:find("pumpkin", 1, true) then return "pumpkin" end
    if n:find("head", 1, true) or n:find("face", 1, true) then return "head" end
    local side = n:find("left", 1, true) and "L" or (n:find("right", 1, true) and "R" or nil)
    if side and (n:find("hand",1,true) or n:find("claw",1,true)) then return "hand"..side end
    if side and (n:find("lowerarm",1,true) or n:find("forearm",1,true)) then return "arm"..side.."L" end
    if side and (n:find("upperarm",1,true) or n:find("shoulder",1,true)) then return "arm"..side.."U" end
    if side and (n:find("foot",1,true) or n:find("toe",1,true)) then return "foot"..side end
    if side and (n:find("lowerleg",1,true) or n:find("shin",1,true)) then return "leg"..side.."L" end
    if side and (n:find("upperleg",1,true) or n:find("thigh",1,true)) then return "leg"..side.."U" end
    if n:find("torso",1,true) or n:find("body",1,true) then return "torso" end
    return "torso"
end
local function analyze()
    S.yaw = CONFIG.MODEL_YAW
    S.yawCF = CFrame.Angles(0, math.rad(S.yaw), 0)
    local h = S.height
    S.groups = {
        armLU={}, armLL={}, handL={}, armRU={}, armRL={}, handR={},
        legLU={}, legLL={}, footL={}, legRU={}, legRL={}, footR={},
        head={}, pumpkin={}, torso={},
    }
    for _, e in ipairs(S.entries) do
        e.tag = tagOf(e.part.Name)
        e.p0 = (S.yawCF * e.rel).Position
        local g = S.groups[e.tag] or S.groups.torso
        g[#g+1] = e
    end
    local function first(tag) local g = S.groups[tag]; return g and g[1] or nil end
    S.pivot = {}; S.handRel = {}
    for _, side in ipairs({"L","R"}) do
        local up = first("arm"..side.."U"); local lo = first("arm"..side.."L"); local hd = first("hand"..side)
        if up then S.pivot["arm"..side] = up.p0 + Vector3.new(0, up.part.Size.Y*0.46, 0) end
        if lo then S.pivot["elbow"..side] = lo.p0 + Vector3.new(0, lo.part.Size.Y*0.46, 0) end
        if hd then
            S.pivot["wrist"..side] = hd.p0 + Vector3.new(0, hd.part.Size.Y*0.42, 0)
            S.handRel["arm"..side] = hd.rel
        elseif lo then S.handRel["arm"..side] = lo.rel end
        local tu = first("leg"..side.."U"); local tl = first("leg"..side.."L"); local tf = first("foot"..side)
        if tu then S.pivot["hip"..side] = tu.p0 + Vector3.new(0, tu.part.Size.Y*0.46, 0) end
        if tl then S.pivot["knee"..side] = tl.p0 + Vector3.new(0, tl.part.Size.Y*0.46, 0) end
        if tf then S.pivot["ankle"..side] = tf.p0 + Vector3.new(0, tf.part.Size.Y*0.35, 0) end
    end
    if not S.pivot.hipL or not S.pivot.hipR then
        local minX, maxX = math.huge, -math.huge
        for _, e in ipairs(S.entries) do
            if e.tag == "torso" then minX=math.min(minX,e.p0.X); maxX=math.max(maxX,e.p0.X) end
        end
        local width = math.max(maxX-minX, 1)
        local buckets = {L={}, R={}}
        for _, e in ipairs(S.entries) do
            if e.tag == "torso" and math.abs(e.p0.X) > width*0.15 and e.p0.Y < h*0.60 then
                local sd = (e.p0.X >= 0) and "R" or "L"
                buckets[sd][#buckets[sd]+1] = e
            end
        end
        for sd, list in pairs(buckets) do
            if #list >= 2 and not S.pivot["hip"..sd] then
                table.sort(list, function(a,b) return a.p0.Y > b.p0.Y end)
                local thigh, foot = list[1], list[#list]
                thigh.tag = "leg"..sd.."U"
                if #list >= 3 then list[2].tag = "leg"..sd.."L"; S.pivot["knee"..sd] = list[2].p0 end
                foot.tag = "foot"..sd
                S.pivot["hip"..sd] = thigh.p0 + Vector3.new(0, thigh.part.Size.Y*0.46, 0)
                S.pivot["ankle"..sd] = foot.p0 + Vector3.new(0, foot.part.Size.Y*0.35, 0)
            end
        end
    end
    for _, e in ipairs(S.entries) do e.restUp = (S.yawCF * e.rel).UpVector end
    local function dirOf(tagName) local g = S.groups[tagName]; return (g and g[1] and g[1].restUp) or nil end
    S.boneDir = {
        thighL=dirOf("legLU"), shinL=dirOf("legLL"), footL=dirOf("footL"),
        thighR=dirOf("legRU"), shinR=dirOf("legRL"), footR=dirOf("footR"),
        uaL=dirOf("armLU"), laL=dirOf("armLL"), handL=dirOf("handL"),
        uaR=dirOf("armRU"), laR=dirOf("armRL"), handR=dirOf("handR"),
    }
    local hg = S.groups.head
    if #hg > 0 then
        local cx, cy, cz, cn, hmin = 0, 0, 0, 0, math.huge
        for _, e in ipairs(hg) do
            cx=cx+e.p0.X; cy=cy+e.p0.Y; cz=cz+e.p0.Z; cn=cn+1
            hmin = math.min(hmin, e.p0.Y - e.part.Size.Y*0.5)
        end
        S.headCenter = Vector3.new(cx/cn, cy/cn, cz/cn)
        S.neck = Vector3.new(S.headCenter.X, math.max(hmin, h*0.55), S.headCenter.Z)
        S.headR = math.max(S.headCenter.Y - S.neck.Y, 1.4)
    end
    local pk = first("pumpkin")
    if pk then
        S.pumpkinRel = pk.rel
        S.pumpkinPivot = pk.p0 + Vector3.new(0, -pk.part.Size.Y*0.18, 0)
    else S.pumpkinPivot = S.headCenter end
    for _, side in ipairs({"L","R"}) do
        local pv = S.pivot["arm"..side]; local rel = S.handRel["arm"..side]
        if pv and rel then
            local rest = (S.yawCF * rel).Position
            local testCF = CFrame.new(pv) * CFrame.Angles(1.0, 0, 0) * CFrame.new(-pv)
            local test = (testCF * (S.yawCF * rel)).Position
            S.armSign[side] = (test.Z < rest.Z) and 1 or -1
        else S.armSign[side] = 1 end
    end
end

-- ============================================================
--  SOUL ANIMATION KEYS
-- ============================================================
local REST = {
    armL=0.05, armR=0.05, armYawL=0, armYawR=0, rollL=-0.06, rollR=0.06,
    elbowL=0.08, elbowR=0.08, elbowYawL=0, elbowYawR=0,
    wristL=0, wristR=0, wristRollL=0, wristRollR=0,
    legL=0, legR=0, legRollL=0, legRollR=0, kneeL=0, kneeR=0, ankleL=0, ankleR=0,
    head=0, headYaw=0, headRoll=0, mouth=0, pitch=0, bodyYaw=0, bodyRoll=0, y=0, z=0,
}
local function K(t, values, easing)
    local k = {t=t, e=easing}
    for name, value in pairs(REST) do k[name] = value end
    for name, value in pairs(values or {}) do k[name] = value end
    return k
end
local RIP_KEYS = {
    K(0.00),
    K(0.35,{pitch=-0.15,z=-0.6,armR=0.95,armYawR=0.1,elbowR=0.25,wristR=0.25,head=-0.3},"out"),
    K(0.65,{pitch=-0.32,z=-1.4,y=-0.35,armR=1.35,armYawR=0.15,elbowR=0.15,wristR=0.35,head=-0.45,kneeL=-0.35,kneeR=-0.35},"in"),
    K(1.10,{pitch=-0.05,z=-0.4,armR=1.25,armYawR=0.28,elbowR=1.15,wristR=-0.2,head=-0.15},"out"),
    K(1.40,{headYaw=0.35,headRoll=0.12,armR=1.18,armYawR=0.32,elbowR=1.45,wristRollR=0.45,head=-0.1},"smooth"),
    K(1.70,{headYaw=-0.35,headRoll=-0.12,armR=1.18,armYawR=0.32,elbowR=1.45,wristRollR=-0.45,head=-0.1},"smooth"),
    K(2.00,{head=-0.2,armR=1.2,armYawR=0.4,elbowR=1.5,armL=1.3,armYawL=-0.35,elbowL=1.3,wristL=0.2},"out"),
    K(2.25,{pitch=0.2,z=0.4,armR=1.4,armYawR=-0.3,elbowR=0.6,armL=1.6,armYawL=0.5,elbowL=0.5,head=0.3},"in"),
    K(2.60,{pitch=0.05,armR=0.7,elbowR=0.4,armL=0.6,elbowL=0.4},"out"),
    K(3.10,{},"out"),
}
local SLAM_DRAIN_KEYS = {
    K(0.00),
    K(0.35,{pitch=-0.15,z=-0.6,armR=0.95,armYawR=0.1,elbowR=0.25,wristR=0.25,head=-0.3},"out"),
    K(0.65,{pitch=-0.32,z=-1.4,y=-0.35,armR=1.35,armYawR=0.15,elbowR=0.15,wristR=0.35,head=-0.45,kneeL=-0.35,kneeR=-0.35},"in"),
    K(1.10,{pitch=-0.05,z=-0.4,armR=1.25,armYawR=0.28,elbowR=1.15,wristR=-0.2,head=-0.15},"out"),
    K(2.00,{pitch=-0.05,z=-0.4,armR=1.28,armYawR=0.30,elbowR=1.20,wristR=-0.22,head=-0.18},"smooth"),
    K(60.0,{pitch=-0.05,z=-0.4,armR=1.28,armYawR=0.30,elbowR=1.20,wristR=-0.22,head=-0.18},"smooth"),
}
local SLAM_KEYS = {
    K(0.00),
    K(0.35,{pitch=-0.25,z=-1.2,y=-0.3,armR=1.3,elbowR=0.2,head=-0.35},"out"),
    K(0.60,{pitch=-0.4,z=-1.6,y=-0.5,armR=1.45,elbowR=0.1,head=-0.45,kneeL=-0.4,kneeR=-0.4},"in"),
    K(0.85,{pitch=0.25,y=0.3,armR=2.4,elbowR=0.35,head=0.2},"out"),
    K(1.05,{pitch=-0.65,y=-0.8,z=-1.8,armR=-0.1,elbowR=0.05,head=-0.45,kneeL=-0.7,kneeR=-0.7},"in"),
    K(1.30,{pitch=0.2,y=0.25,armR=2.2,elbowR=0.3,head=0.15},"out"),
    K(1.50,{pitch=-0.65,y=-0.8,z=-1.8,armR=-0.1,elbowR=0.05,head=-0.45,kneeL=-0.7,kneeR=-0.7},"in"),
    K(1.75,{pitch=0.22,y=0.28,armR=2.3,elbowR=0.32,head=0.18},"out"),
    K(1.95,{pitch=-0.7,y=-0.85,z=-1.9,armR=-0.12,elbowR=0.05,head=-0.5,kneeL=-0.75,kneeR=-0.75},"in"),
    K(2.45,{pitch=-0.3,y=-0.3,armR=0.4,elbowR=0.2},"out"),
    K(3.10,{},"out"),
}
local DEVOUR_KEYS = {
    K(0.00),
    K(0.40,{pitch=-0.22,z=-1.0,y=-0.25,armR=1.25,elbowR=0.2,head=-0.3},"out"),
    K(0.70,{pitch=-0.38,z=-1.5,y=-0.5,armR=1.45,elbowR=0.12,head=-0.4,kneeL=-0.4,kneeR=-0.4},"in"),
    K(1.15,{pitch=-0.05,z=-0.3,armR=1.25,armYawR=0.35,elbowR=1.55,wristR=-0.25,head=-0.1},"out"),
    K(1.45,{armR=1.15,armYawR=0.42,elbowR=1.95,wristR=-0.45,head=-0.25},"in"),
    K(1.70,{armR=1.20,armYawR=0.38,elbowR=1.85,wristR=-0.35,head=0.05},"out"),
    K(1.95,{armR=1.15,armYawR=0.42,elbowR=1.95,wristR=-0.45,head=-0.25},"in"),
    K(2.20,{armR=1.20,armYawR=0.38,elbowR=1.85,wristR=-0.35,head=0.05},"out"),
    K(2.45,{armR=1.15,armYawR=0.42,elbowR=1.95,wristR=-0.45,head=-0.25},"in"),
    K(2.70,{armR=1.20,armYawR=0.38,elbowR=1.85,wristR=-0.35,head=0.05},"out"),
    K(2.95,{armR=1.15,armYawR=0.42,elbowR=1.95,wristR=-0.45,head=-0.25},"in"),
    K(3.30,{pitch=0.15,head=0.35,armR=0.5,elbowR=0.4},"out"),
    K(3.85,{},"out"),
}
local SWIPE_KEYS = {
    K(0.00),
    K(0.20,{pitch=0.1,bodyYaw=-0.35,armR=1.5,armYawR=-0.55,rollR=0.35,elbowR=0.9,head=0.1},"out"),
    K(0.42,{pitch=-0.24,bodyYaw=0.35,z=-0.8,armR=0.35,armYawR=0.65,rollR=-0.2,elbowR=0.1,head=-0.1},"in"),
    K(0.65,{pitch=-0.05,bodyYaw=0.1,armR=0.15,elbowR=0.1},"out"),
    K(0.80,{},"out"),
}
local HEAD_BITE_KEYS = {
    K(0.00),
    K(0.30,{pitch=-0.35,z=-0.6,armR=1.25,elbowR=0.35,head=-0.35},"out"),
    K(0.78,{pitch=-0.12,z=-0.15,armR=1.85,armYawR=0.42,elbowR=1.45,wristR=-0.35,armL=0.85,armYawL=-0.32,elbowL=1.05,head=-0.25,mouth=0.55},"out"),
    K(1.12,{pitch=-0.06,armR=1.72,armYawR=0.46,elbowR=1.72,wristR=-0.48,armL=0.92,armYawL=-0.36,elbowL=1.18,head=-0.42,mouth=1.0},"in"),
    K(1.28,{pitch=-0.18,armR=1.55,armYawR=0.40,elbowR=1.35,armL=0.75,elbowL=0.85,head=-0.72,mouth=0.12},"in"),
    K(1.62,{pitch=0.05,armR=1.05,armYawR=0.28,elbowR=0.95,head=-0.15,mouth=0.55},"out"),
    K(1.95,{head=0.08,mouth=0.30,armR=0.55,elbowR=0.45},"out"),
    K(2.35,{},"out"),
}
local CURSE_KEYS = {
    K(0.00),
    K(0.45,{pitch=0.25,head=0.45,armL=2.1,armR=2.1,rollL=-0.35,rollR=0.35,elbowL=0.3,elbowR=0.3},"out"),
    K(0.85,{pitch=-0.65,y=-0.6,z=-1.2,head=-0.4,armL=0.2,armR=0.2,elbowL=0.1,elbowR=0.1,kneeL=-0.5,kneeR=-0.5},"in"),
    K(1.40,{pitch=-0.15,armL=0.4,armR=0.4},"out"),
    K(2.00,{},"out"),
}
local ROAR_KEYS = {
    K(0.00),
    K(0.35,{pitch=0.25,head=0.7,armL=0.6,armR=0.6,rollL=-0.7,rollR=0.7,elbowL=0.45,elbowR=0.45},"out"),
    K(1.20,{pitch=0.25,head=0.75,armL=0.65,armR=0.65,rollL=-0.75,rollR=0.75,elbowL=0.5,elbowR=0.5},"smooth"),
    K(1.65,{},"out"),
}
local function playKeys(keys, at, P)
    local n = #keys
    if n == 0 then return end
    local function apply(k)
        for f, v in pairs(k) do if f ~= "t" and f ~= "e" then P[f] = v end end
    end
    if at <= keys[1].t then apply(keys[1]); return end
    if at >= keys[n].t then apply(keys[n]); return end
    for i = 1, n-1 do
        local a, b = keys[i], keys[i+1]
        if at >= a.t and at < b.t then
            local raw = (at - a.t) / math.max(b.t - a.t, 0.001)
            local e = b.e or "smooth"
            local k = (e == "in") and easeIn(raw) or ((e == "out") and easeOut(raw) or smooth(raw))
            for f, v in pairs(b) do
                if f ~= "t" and f ~= "e" then P[f] = lerp(a[f] or 0, v, k) end
            end
            return
        end
    end
end
local function basePose(t)
    local P = {}
    for n, v in pairs(REST) do P[n] = v end
    local mv = S.walk; local q = S.quadBlend; local two = 1 - q
    P.y += math.sin(t*1.3)*0.06*two
    P.pitch += math.sin(t*1.3)*0.015*two
    P.armL += math.sin(t*1.1)*0.045*two
    P.armR += math.sin(t*1.1+1.5)*0.045*two
    P.head += math.sin(t*0.6)*0.04*two
    P.headYaw += math.sin(t*0.35)*0.06*two
    if mv > 0.01 and two > 0.05 then
        local c = S.gait; local s = math.sin(c)
        local liftL = math.max(0, math.sin(c+1.2))
        local liftR = math.max(0, math.sin(c+1.2+math.pi))
        P.legL += s*0.5*mv*two; P.legR -= s*0.5*mv*two
        P.kneeL -= (0.08+liftL*0.75)*mv*two; P.kneeR -= (0.08+liftR*0.75)*mv*two
        P.ankleL += liftL*0.22*mv*two; P.ankleR += liftR*0.22*mv*two
        P.armL -= s*0.32*mv*two; P.armR += s*0.32*mv*two
        P.elbowL += (0.12+math.max(0,-s)*0.15)*mv*two
        P.elbowR += (0.12+math.max(0,s)*0.15)*mv*two
        P.bodyRoll += s*0.035*mv*two; P.bodyYaw += s*0.05*mv*two
        P.y += (math.abs(math.cos(c))*0.14-0.07)*mv*two
    end
    if q > 0.01 then
        local mv2 = S.walk; local g = S.quadGait
        local breath = math.sin(os.clock()*1.45)*0.5 + 0.5
        local stepL = math.sin(g); local stepR = math.sin(g+math.pi)
        local plantL = math.max(0, -stepL); local plantR = math.max(0, -stepR)
        local pull = math.max(0, stepL) + math.max(0, stepR)
        P.pitch = lerp(P.pitch, -0.62 + breath*0.022, q)
        P.y = lerp(P.y, -0.62 + breath*0.035, q)
        P.z = lerp(P.z, -0.12 - pull*0.10*mv2, q)
        P.bodyRoll = lerp(P.bodyRoll, (stepL-stepR)*0.045*mv2, q)
        P.bodyYaw = lerp(P.bodyYaw, (stepL-stepR)*0.075*mv2, q)
        P.head = lerp(P.head, 0.72 + breath*0.025, q)
        P.headYaw = lerp(P.headYaw, (stepL-stepR)*0.10*mv2, q)
        local signR = (S.armSign and S.armSign.R) or 1
        local signL = (S.armSign and S.armSign.L) or 1
        local wantWorld = -1.30
        local baseR = (wantWorld - P.pitch)/signR
        local baseL = (wantWorld - P.pitch)/signL
        P.armL = lerp(P.armL, baseL + stepL*0.30*mv2, q)
        P.armR = lerp(P.armR, baseR + stepR*0.30*mv2, q)
        P.elbowL = lerp(P.elbowL, 0.62 + plantL*0.30*mv2, q)
        P.elbowR = lerp(P.elbowR, 0.62 + plantR*0.30*mv2, q)
        P.wristL = lerp(P.wristL, -0.28 - plantL*0.10*mv2, q)
        P.wristR = lerp(P.wristR, -0.28 - plantR*0.10*mv2, q)
        P.rollL = lerp(P.rollL, -0.12 + stepL*0.12*mv2, q)
        P.rollR = lerp(P.rollR, 0.12 + stepR*0.12*mv2, q)
        P.legL = lerp(P.legL, 0.34 + stepR*0.14*mv2, q)
        P.legR = lerp(P.legR, 0.34 + stepL*0.14*mv2, q)
        P.kneeL = lerp(P.kneeL, -0.58 + plantR*0.16*mv2, q)
        P.kneeR = lerp(P.kneeR, -0.58 + plantL*0.16*mv2, q)
        P.ankleL = lerp(P.ankleL, 0.24, q); P.ankleR = lerp(P.ankleR, 0.24, q)
    end
    return P
end
local function feetOffset()
    local hum, hrp = S.humanoid, S.hrp
    if not (hum and hrp) then return 3 end
    if hum.RigType == Enum.HumanoidRigType.R15 then return hum.HipHeight + hrp.Size.Y/2 end
    return 3
end
local function stickToHand(rec)
    local hand = S.handR or S.handL
    if not hand then return end
    local hang = math.clamp(rec.size.Y*0.4, 1.2, 3.2)
    local face = CFrame.lookAt(Vector3.zero, -S.flat).Rotation
    local sway = CFrame.Angles(math.sin(os.clock()*6)*0.06, 0, math.sin(os.clock()*4.5)*0.05)
    local targetCF = CFrame.new(hand + S.flat*0.35 - UP*hang*0.7) * face * sway
    vSet(rec, vGet(rec):Lerp(targetCF, 0.35))
end
local function holdAtMaw(rec)
    local maw = S.mawWorld
    if not maw then return end
    local hang = math.clamp(rec.size.Y*0.38, 1.1, 2.8)
    local face = CFrame.lookAt(Vector3.zero, -S.flat).Rotation
    local targetCF = CFrame.new(maw - S.flat*0.2 - UP*hang*0.55) * face
    vSet(rec, vGet(rec):Lerp(targetCF, 0.22))
end
local function holdOnGround(rec)
    local guess = S.hrp.Position - Vector3.new(0, feetOffset(), 0) + S.flat*6.5
    local g = groundAt(guess, 6, 20)
    local gp = g and g.Position or guess
    local face = CFrame.lookAt(Vector3.zero, -S.flat).Rotation
    local targetCF = CFrame.new(gp + UP*0.4) * face * CFrame.Angles(-1.2, 0, 0)
    vSet(rec, vGet(rec):Lerp(targetCF, 0.30))
end
local function canAct(name)
    if not S.mounted or S.atk or menuOpen or S.busy then return false end
    return true
end
local function finishAttack()
    if S.victim and (S.victim.state == "held") then restoreVictim(S.victim, true) end
    S.atk, S.victim, S.target = nil, nil, nil
end
local function waitForHandContact(at, deadline)
    if S.victim then return S.victim end
    if not S.target or not S.target.Parent then return nil end
    local rec = captureOnContact()
    if rec then rec.carryStart = os.clock(); sfx(SND.flesh, 2.2, 1); return rec end
    if at > deadline then
        local m = S.target
        local hp = targetHeadPosition(m)
        if m and hp and S.hrp then
            local flatD = Vector3.new(hp.X-S.hrp.Position.X, 0, hp.Z-S.hrp.Position.Z)
            local inFront = flatD.Magnitude < CONFIG.GRAB_RANGE and flatD.Unit:Dot(S.flat) > 0.25
            if inFront then
                local forced = capture(m)
                if forced then
                    forced.carryStart = os.clock()
                    S.victim = forced; S.target = nil; S.ev.contact = true
                    sfx(SND.flesh, 2.2, 1); return forced
                end
            end
        end
        finishAttack()
    end
    return nil
end

-- ===== SOUL ABILITIES =====
actRip = function()
    if not canAct("rip") then return end
    local target = findTarget(CONFIG.GRAB_RANGE, S.hrp.Position + S.flat*6)
    if not target then return end
    S.atk, S.atkStart, S.ev, S.target = "rip", os.clock(), {}, target
    S.atkDur = 3.10; sfx(SND.whoosh, 1.8, 0.95)
end
actSlam = function()
    if S.atk == "slam_grab" and S.victim and not S.ev.slamPhase then
        S.ev.slamPhase = "slam"; sfx(SND.whoosh, 2.4, 1.3); return
    end
    if not canAct("slam") then return end
    local target = findTarget(CONFIG.SLAM_RANGE, S.hrp.Position + S.flat*6)
    if not target then return end
    S.atk, S.atkStart, S.ev, S.target = "slam_grab", os.clock(), {}, target
    S.atkDur = 60; sfx(SND.whoosh, 1.8, 0.9)
end
actDevour = function()
    if not canAct("devour") then return end
    local target = findTarget(CONFIG.GRAB_RANGE, S.hrp.Position + S.flat*6)
    if not target then return end
    S.atk, S.atkStart, S.ev, S.target = "devour", os.clock(), {}, target
    S.atkDur = 3.85; sfx(SND.whoosh, 1.8, 0.9)
end
actSwipe = function()
    if not canAct("swipe") then return end
    S.atk, S.atkStart, S.ev = "swipe", os.clock(), {}
    S.atkDur = 0.80; sfx(SND.slash, 2.0, 1.1)
end
actHeadEat = function()
    if not canAct("head") then return end
    local target = findTarget(CONFIG.GRAB_RANGE, S.hrp.Position + S.flat*6)
    if not target then return end
    S.atk, S.atkStart, S.ev, S.target = "head", os.clock(), {}, target
    S.atkDur = 2.60; sfx(SND.whoosh, 2.2, 0.85)
end
actRoar = function()
    if not canAct("roar") then return end
    S.atk, S.atkStart, S.ev = "roar", os.clock(), {}
    S.atkDur = 1.65; sfx(SND.roar, 3.2, 0.95)
    task.delay(0.35, function()
        if S.hrp then
            local feet = S.hrp.Position - UP*feetOffset()
            ring(feet, UP, S.height*1.5, CONFIG.NEON_A, 0.6)
            lightFlash(S.mawWorld, CONFIG.NEON_A, 12, 45, 0.5)
            S.shake = math.max(S.shake, 2.2); impactTint(0.8)
        end
    end)
end
local function startCurse(model)
    local root = getRoot(model)
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    if not (root and hum) then return end
    local rec = capture(model)
    if not rec then return end
    freezeVictim(rec)
    local centerPos = root.Position
    task.spawn(function()
        local t0 = os.clock(); local dur = CONFIG.CURSE_TIME
        while os.clock() - t0 < dur do
            task.wait(0.5)
            if not model or not model.Parent or not hum.Parent then break end
            freezeVictim(rec)
            hum.Health = math.max(0, hum.Health - hum.MaxHealth/dur)
            mist(centerPos + UP*2, 4, 3, CONFIG.NEON_B)
        end
        if model and model.Parent then
            killVictim(rec, false, UP*8)
            carnage(centerPos + UP*2, UP, 25, {spread=1.1, vmin=18, vmax=50})
            mist(centerPos + UP*2, 35, 9, CONFIG.NEON_B)
        end
    end)
    mist(centerPos + UP*0.5, 26, 7, CONFIG.NEON_A)
    ring(centerPos, UP, 12, CONFIG.NEON_A, 0.7)
    sfx(SND.scare, 2.0, 1.0)
end
actCurse = function()
    if not canAct("curse") then return end
    local target = findTarget(CONFIG.CURSE_RANGE)
    if not target then return end
    S.atk, S.atkStart, S.ev, S.target = "curse", os.clock(), {}, target
    S.atkDur = 2.00; sfx(SND.amb, 1.8, 0.9)
end

toggleSoulInstinct = function()
    soulInstinct = not soulInstinct
    if soulInstinct then
        sfx(SND.ui, 0.9, 1.3)
        task.spawn(function()
            while soulInstinct and S.mounted do
                task.wait(0.12)
                if S.mounted and not S.atk and not menuOpen and not S.busy and S.hrp then
                    local target = findTarget(CONFIG.GRAB_RANGE, S.hrp.Position + S.flat*6)
                    if target then actRip() end
                end
            end
        end)
    end
    if instinctLabelUI and not Gojo.mounted then
        instinctLabelUI.Text = soulInstinct and "INSTINCT: ON" or "INSTINCT: OFF"
        instinctLabelUI.TextColor3 = soulInstinct and CONFIG.NEON_D or CONFIG.NEON_C
    end
end

local function updateAttack(at, t)
    local rec = S.victim
    if rec and not rec.model.Parent then S.victim = nil; rec = nil end
    if S.atk == "slam_grab" then
        if not S.victim and S.target then
            rec = waitForHandContact(at, 1.60)
            if rec then S.ev.grabbed = true; S.ev.grabAt = at; S.shake = math.max(S.shake, 0.6) end
        end
        if S.victim then
            local vrec = S.victim
            local vhum = vrec.hum
            if not vhum or not vhum.Parent or vrec.state == "dead" then
                S.victim = nil; finishAttack(); return
            end
            if S.ev.slamPhase == "slam" then
                local ground = S.hrp.Position - Vector3.new(0, feetOffset(), 0) + S.flat*6.5
                local g = groundAt(ground, 6, 20)
                local gp = g and g.Position or ground
                local gn = g and g.Normal or UP
                holdOnGround(vrec)
                vhum.Health = 0
                carnage(gp + UP, UP, 50, {spread=1.3, vmin=25, vmax=75, bone=0.35})
                mist(gp + UP, 50, 14, Color3.fromRGB(110,60,35))
                puddle(gp, gn, 14, 30); cracks(gp, gn, 18, 14)
                ring(gp, gn, 28, CONFIG.NEON_A, 0.7)
                lightFlash(gp + UP*2, CONFIG.NEON_A, 16, 55, 0.7)
                sfx(SND.thud, 3.5, 0.75); sfx(SND.splat, 3.2, 0.9); sfx(SND.gore, 2.8, 1)
                S.shake = 4.0; impactTint(1); fovPunch(15)
                killVictim(vrec, false, S.flat*12 + UP*8)
                S.victim = nil; finishAttack(); return
            end
            stickToHand(vrec)
            if not S.ev.lastDrain then S.ev.lastDrain = t end
            if t - S.ev.lastDrain >= 0.30 then
                S.ev.lastDrain = t
                local dmg = math.max(vhum.MaxHealth * 0.05, 1)
                vhum.Health = math.max(0, vhum.Health - dmg)
                carnage(vrec.root.Position, UP, 5, {spread=0.8, vmin=8, vmax=22})
                mist(vrec.root.Position, 8, 3, CONFIG.NEON_B)
                sfx(SND.flesh, 1.5, 1.2); S.shake = math.max(S.shake, 0.4)
                if vhum.Health <= 0 then
                    killVictim(vrec, true, S.flat*12 + UP*8)
                    S.victim = nil; finishAttack(); return
                end
            end
        end
        return
    end
    if not rec and S.target and (S.atk == "rip" or S.atk == "devour" or S.atk == "head") then
        local deadline = (S.atk == "rip" and 2.10) or (S.atk == "devour" and 1.80) or 1.20
        rec = waitForHandContact(at, deadline)
        if rec then
            S.ev.grab = true; S.ev.grabAt = at
            carnage(rec.root.Position, UP, 6, {spread=0.9, vmin=6, vmax=18})
            mist(rec.root.Position, 10, 3.5, CONFIG.NEON_B)
            S.shake = math.max(S.shake, 0.6)
        end
    end
    if S.atk == "rip" then
        if rec then
            if at < 2.25 then
                if not S.ev.grab then
                    S.ev.grab = true
                    carnage(rec.root.Position, UP, 8, {spread=1.0, vmin=8, vmax=22})
                    sfx(SND.flesh, 2.4, 1); S.shake = math.max(S.shake, 1.2)
                end
                stickToHand(rec)
            else
                if not S.ev.rip then
                    S.ev.rip = true
                    local handPos = S.handR or rec.root.Position
                    sfx(SND.snap, 3.2, 0.9); sfx(SND.gore, 3.0, 1)
                    carnage(handPos, UP, 30, {spread=1.2, vmin=22, vmax=55, bone=0.25})
                    mist(handPos, 45, 8, CONFIG.NEON_B)
                    killVictim(rec, true, S.flat*12 + UP*8)
                    S.victim = nil; S.shake = 2.4
                    impactTint(1); fovPunch(10)
                end
            end
        end
    elseif S.atk == "devour" then
        if rec then
            if at < 1.15 then
                if not S.ev.grab then S.ev.grab = true; sfx(SND.flesh, 2.2, 1) end
                stickToHand(rec)
            else
                holdAtMaw(rec)
                for i, biteTime in ipairs({1.45, 1.95, 2.45, 2.95}) do
                    if at >= biteTime and not S.ev["bite"..i] then
                        S.ev["bite"..i] = true
                        local maw = S.mawWorld
                        carnage(maw, S.flat*0.5 + UP*0.3, 14, {spread=0.9, vmin=14, vmax=35, bone=0.2})
                        mist(maw, 15, 5, CONFIG.NEON_B)
                        sfx(SND.bite, 2.8, 1.0); sfx(SND.crunch, 2.4, 0.95)
                        S.shake = math.max(S.shake, 1.2)
                        applyDamage(rec, 25, i == 4, -S.flat*4)
                        if i == 4 then sfx(SND.chomp, 3.0, 0.9); S.victim = nil end
                    end
                end
            end
        end
    elseif S.atk == "swipe" then
        if at >= 0.42 and not S.ev.hit then
            S.ev.hit = true
            local center = S.hrp.Position + S.flat*6
            local target = findTarget(CONFIG.SWIPE_RANGE, center)
            if target then
                local r = capture(target)
                if r then
                    carnage(r.root.Position, S.flat, 12, {spread=1.0, vmin=14, vmax=36})
                    sfx(SND.hit, 2.8, 0.8); sfx(SND.splat, 2.4, 1)
                    S.shake = 1.6
                    applyDamage(r, CONFIG.SWIPE_DAMAGE, true, S.flat*24 + UP*8)
                    if r.state ~= "dead" then restoreVictim(r, false) end
                end
            end
        end
    elseif S.atk == "head" then
        if rec then
            local grabAt = S.ev.grabAt or at
            local rel = at - grabAt
            if rel < 0.34 then stickToHand(rec)
            else
                local maw = S.mawWorld
                if maw then
                    local hang = math.clamp(rec.size.Y*0.38, 1.1, 2.8)
                    local face = CFrame.lookAt(Vector3.zero, -S.flat).Rotation
                    local sway = CFrame.Angles(math.sin(os.clock()*5)*0.06, 0, math.sin(os.clock()*4)*0.05)
                    local targetCF = CFrame.new(maw - S.flat*0.25 - UP*hang*0.5) * face * sway
                    local carryK = math.clamp((rel-0.34)/0.80, 0, 1)
                    vSet(rec, vGet(rec):Lerp(targetCF, 0.10 + carryK*0.85))
                end
                if rel >= 1.18 and not S.ev.bite then
                    S.ev.bite = true
                    local maw2 = S.mawWorld
                    if maw2 then
                        sfx(SND.bite, 3.2, 0.85); sfx(SND.crunch, 2.8, 0.9); sfx(SND.snap, 3.0, 0.95)
                        carnage(maw2, UP, 34, {spread=1.1, vmin=18, vmax=50, bone=0.3})
                        mist(maw2, 46, 8, CONFIG.NEON_B)
                        lightFlash(maw2, CONFIG.NEON_B, 9, 34, 0.45)
                    end
                    killVictim(rec, true, S.flat*6 + UP*4)
                    S.victim = nil; S.shake = 2.6
                    impactTint(1); fovPunch(9)
                end
            end
        end
    elseif S.atk == "curse" then
        if S.target and S.target.Parent and at >= 0.85 and not S.ev.cast then
            S.ev.cast = true
            startCurse(S.target)
            S.target = nil; S.victim = nil
        end
    end
    if at >= S.atkDur then finishAttack() end
end

local function step(dt)
    local hum, hrp = S.humanoid, S.hrp
    if not (S.mounted and hum and hrp and hrp.Parent) then return end
    local t = os.clock()
    local v = hrp.AssemblyLinearVelocity
    local spd = Vector3.new(v.X, 0, v.Z).Magnitude
    S.walk += (((spd > 1.5) and 1 or 0) - S.walk) * math.min(1, dt*8)
    local wantQuad = (S.quad and not S.atk) and 1 or 0
    S.quadBlend += (wantQuad - S.quadBlend) * math.min(1, dt*5.5)
    if S.quadBlend < 0.004 then S.quadBlend = 0 end
    S.gait = (S.gait + dt*lerp(3.5,6.0,S.walk)*(0.3+0.7*S.walk)) % (math.pi*2)
    S.quadGait = (S.quadGait + dt*lerp(4.0,14.0,S.quadBlend)*(0.3+0.7*S.walk)) % (math.pi*2)
    local lk = hrp.CFrame.LookVector
    local fl = Vector3.new(lk.X, 0, lk.Z)
    if fl.Magnitude > 0.01 then S.flat = fl.Unit end
    local feetY = hrp.Position.Y - feetOffset()
    local g = groundAt(hrp.Position, 4, 16)
    if g then feetY = math.max(feetY, g.Position.Y) end
    local feetPos = Vector3.new(hrp.Position.X, feetY, hrp.Position.Z)
    local base = CFrame.lookAt(feetPos, feetPos + S.flat)
    local P = basePose(t)
    local at = S.atk and ((t - S.atkStart) * ANIM) or 0
    if S.atk == "rip" then playKeys(RIP_KEYS, at, P)
    elseif S.atk == "slam_grab" then playKeys(SLAM_DRAIN_KEYS, at, P)
    elseif S.atk == "slam" then playKeys(SLAM_KEYS, at, P)
    elseif S.atk == "devour" then playKeys(DEVOUR_KEYS, at, P)
    elseif S.atk == "swipe" then playKeys(SWIPE_KEYS, at, P)
    elseif S.atk == "head" then playKeys(HEAD_BITE_KEYS, at, P)
    elseif S.atk == "curse" then playKeys(CURSE_KEYS, at, P)
    elseif S.atk == "roar" then playKeys(ROAR_KEYS, at, P) end
    local hsF = S.height / 16.5
    local bodyCF = base * CFrame.new(0, P.y*hsF, P.z*hsF) * CFrame.Angles(P.pitch, P.bodyYaw or 0, P.bodyRoll or 0)
    if S.atk and S.target and not S.victim and S.target.Parent then
        local headPos = targetHeadPosition(S.target)
        local shoulder = S.pivot.armR
        if headPos and shoulder then
            local localP = bodyCF:PointToObjectSpace(headPos)
            local rigP = (S.yawCF:Inverse() * CFrame.new(localP)).Position
            local delta = rigP - shoulder
            local rawPitch = math.atan2(-delta.Z, math.max(0.12, -delta.Y))
            local rawYaw = math.atan2(delta.X, math.max(0.20, math.abs(delta.Z)))
            local sign = S.armSign.R or 1
            P.armR = lerp(P.armR, math.clamp(rawPitch*sign, -0.25, 2.20), 0.82)
            P.armYawR = lerp(P.armYawR, math.clamp(rawYaw, -0.55, 0.55), 0.72)
            local reach = math.clamp(delta.Magnitude / math.max(S.height*0.42, 2), 0, 1)
            P.elbowR = lerp(P.elbowR, 0.18 + (1-reach)*1.05, 0.72)
            P.wristR = lerp(P.wristR, -0.12, 0.5)
            P.head = lerp(P.head, -0.22, 0.35)
        end
    end
    local function atPivot(p, x, y, z)
        if not p then return CFrame.new() end
        return CFrame.new(p) * CFrame.Angles(x or 0, y or 0, z or 0) * CFrame.new(-p)
    end
    local chain = {}
    for _, side in ipairs({"L","R"}) do
        local sign = S.armSign[side] or 1
        local U = atPivot(S.pivot["arm"..side], (P["arm"..side] or 0)*sign, P["armYaw"..side], P["roll"..side])
        local E = atPivot(S.pivot["elbow"..side], (P["elbow"..side] or 0)*sign, P["elbowYaw"..side], 0)
        local W = atPivot(S.pivot["wrist"..side], P["wrist"..side], 0, P["wristRoll"..side])
        chain["arm"..side.."U"] = U
        chain["arm"..side.."L"] = U * E
        chain["hand"..side] = U * E * W
        local Hip = atPivot(S.pivot["hip"..side], P["leg"..side], 0, P["legRoll"..side])
        local Knee = atPivot(S.pivot["knee"..side], P["knee"..side], 0, 0)
        local Ankle = atPivot(S.pivot["ankle"..side], P["ankle"..side], 0, 0)
        chain["leg"..side.."U"] = Hip
        chain["leg"..side.."L"] = Hip * Knee
        chain["foot"..side] = Hip * Knee * Ankle
    end
    local H = CFrame.new(S.neck) * CFrame.Angles(P.head, P.headYaw or 0, P.headRoll) * CFrame.new(-S.neck)
    local mouthA = math.clamp(P.mouth or 0, -0.25, 1.0) * 0.42
    local MJ = CFrame.new(S.pumpkinPivot or S.headCenter) * CFrame.Angles(mouthA, 0, 0) * CFrame.new(-(S.pumpkinPivot or S.headCenter))
    local cfs, entries = S.cfs, S.entries
    for i = 1, #entries do
        local e = entries[i]
        local r = S.yawCF * e.rel
        local g2 = e.tag
        if chain[g2] then r = chain[g2] * r
        elseif g2 == "pumpkin" then r = H * MJ * r
        elseif g2 == "head" then r = H * r end
        cfs[i] = bodyCF * r
    end
    do
        local ray = groundAt(S.hrp.Position, 10, 48)
        if ray then
            local minY = math.huge
            for i, e in ipairs(entries) do
                local cf = cfs[i]; local sz = e.part.Size
                local ey = math.abs(cf.RightVector.Y)*sz.X*0.5 + math.abs(cf.UpVector.Y)*sz.Y*0.5 + math.abs(cf.LookVector.Y)*sz.Z*0.5
                minY = math.min(minY, cf.Position.Y - ey)
            end
            local wanted = ray.Position.Y + 0.06
            local dy = wanted - minY
            if S.quadBlend > 0.35 then
                dy = math.clamp(dy, (S.walk > 0.3) and -1.4 or -9, 9)
            else dy = math.max(dy, 0) end
            S.groundLift = S.groundLift or 0
            S.groundLift = S.groundLift + (dy - S.groundLift)*math.min(1, dt*14)
            if math.abs(S.groundLift) > 0.003 then
                local lift = CFrame.new(0, S.groundLift, 0)
                for i = 1, #cfs do cfs[i] = lift * cfs[i] end
                bodyCF = lift * bodyCF
            end
        end
    end
    workspace:BulkMoveTo(S.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
    for _, side in ipairs({"L","R"}) do
        local rel = S.handRel["arm"..side]
        local hc = chain["hand"..side] or chain["arm"..side.."L"]
        if rel and hc then
            local w = (bodyCF * (hc * (S.yawCF * rel))).Position
            if side == "L" then S.handL = w else S.handR = w end
        end
    end
    if S.pumpkinRel then
        S.mawWorld = (bodyCF * (H * (S.yawCF * S.pumpkinRel))).Position + S.flat*1.8
    else
        S.mawWorld = (bodyCF * (H * (S.yawCF * CFrame.new(S.headCenter)))).Position + S.flat*1.8
    end
    if S.atk then updateAttack(at, t) end
    S.shake *= math.exp(-dt*4)
    if S.shake < 0.01 then S.shake = 0 end
    hum.CameraOffset = S.camBase + Vector3.new(rnd(-1,1)*S.shake, rnd(-1,1)*S.shake, 0)
end

local function hideInst(d)
    if d:IsA("BasePart") or d:IsA("Decal") then
        if S.origTransp[d] == nil then S.origTransp[d] = d.Transparency end
        if d.Transparency ~= 1 then d.Transparency = 1 end
    end
end
local nextHide = 0
local function heart()
    local hum, hrp = S.humanoid, S.hrp
    if not (S.mounted and hum and hrp and hrp.Parent) then return end
    local t = os.clock()
    local mul = S.atk and 0.28 or 1
    local baseSpd = (S.quadBlend > 0.4) and CONFIG.QUAD_SPEED or CONFIG.NORMAL_SPEED
    hum.WalkSpeed = baseSpd * mul
    hum.JumpPower = (S.quadBlend > 0.4) and 0 or CONFIG.JUMP_POWER
    if t > nextHide then
        nextHide = t + 0.5
        for _, d in ipairs(S.character:GetDescendants()) do hideInst(d) end
    end
end
local savedLighting
local function mount()
    if S.mounted or S.busy then return end
    if Gojo.mounted then unmountGojo() end
    S.busy = true
    warn("[Soul] Mounting...")
    local tpl = loadTemplate()
    if not tpl then S.busy = false; return end
    local model = tpl:Clone()
    local entries, parts, h = buildEntries(model)
    if not entries then S.busy = false; return end
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid", 10)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not (hum and hrp) then S.busy = false; return end
    S.character, S.humanoid, S.hrp = char, hum, hrp
    S.entries, S.parts, S.height, S.model, S.cfs = entries, parts, h, model, {}
    S.origWalk, S.origJump = hum.WalkSpeed, hum.JumpPower
    S.origMin, S.origMax = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
    S.atk, S.cd = nil, {}
    refreshFilter(); analyze()
    for _, d in ipairs(char:GetDescendants()) do hideInst(d) end
    mtrack(char.DescendantAdded:Connect(function(d) task.defer(hideInst, d) end))
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    S.camBase = Vector3.new(0, math.max(0, (h-5)*0.45), 0)
    pcall(function()
        player.CameraMinZoomDistance = h*0.55
        player.CameraMaxZoomDistance = math.max(S.origMax, h*3.5)
    end)
    tint = Instance.new("ColorCorrectionEffect")
    tint.Name = "SoulTint"
    tint.TintColor = Color3.fromRGB(255,230,225)
    tint.Saturation = 0.1; tint.Contrast = 0.12
    tint.Parent = Lighting
    savedLighting = {Ambient=Lighting.Ambient, FogColor=Lighting.FogColor, FogEnd=Lighting.FogEnd}
    Lighting.Ambient = Lighting.Ambient:Lerp(Color3.fromRGB(60,25,8), 0.45)
    Lighting.FogColor = Color3.fromRGB(25,10,5)
    Lighting.FogEnd = math.min(Lighting.FogEnd, 600)
    model.Name = "HalloweenSoulMorph"
    model.Parent = fxFolder
    S.mounted = true
    step(0.016)
    mtrack(RunService.RenderStepped:Connect(step))
    mtrack(RunService.Heartbeat:Connect(heart))
    mtrack(hum.Died:Connect(function() if S.atk then finishAttack() end end))
    local feet = hrp.Position - Vector3.new(0, feetOffset(), 0)
    mist(feet + UP*2, 50, 10, CONFIG.NEON_A)
    ring(feet, UP, 22, CONFIG.NEON_A, 0.7)
    lightFlash(feet + UP*3, CONFIG.NEON_A, 10, 40, 0.7)
    sfx(SND.scare, 2.5, 0.9)
    S.busy = false
    warn("[Soul] ✔ Mounted")
end
local function unmount()
    if not S.mounted then return end
    if S.atk then finishAttack() end
    soulInstinct = false
    S.mounted = false
    for _, c in ipairs(morphConns) do pcall(function() c:Disconnect() end) end
    morphConns = {}
    for inst, v in pairs(S.origTransp) do pcall(function() if inst.Parent then inst.Transparency = v end end) end
    S.origTransp = setmetatable({}, {__mode="k"})
    local hum = S.humanoid
    if hum and hum.Parent then
        pcall(function()
            hum.WalkSpeed = S.origWalk or 16
            hum.JumpPower = S.origJump or 50
            hum.CameraOffset = Vector3.zero
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
        end)
    end
    pcall(function()
        player.CameraMinZoomDistance = S.origMin or 0.5
        player.CameraMaxZoomDistance = S.origMax or 128
    end)
    if S.model then S.model:Destroy(); S.model = nil end
    if tint then tint:Destroy(); tint = nil end
    if savedLighting then
        for k, v in pairs(savedLighting) do pcall(function() Lighting[k] = v end) end
        savedLighting = nil
    end
    S.quad = false; S.quadBlend = 0
end

-- ============================================================
--  GOJO MODULE (from deobfuscated Gojo script)
-- ============================================================
mountGojo = function()
    if Gojo.mounted then return end
    if S.mounted then unmount() end

    if typeof(getcustomasset) ~= "function" then
        warn("[Gojo] ✘ getcustomasset required — executor blocks it")
        StarterGui:SetCore("SendNotification", { Title = "Gojo", Text = "Executor blocks getcustomasset", Duration = 5 })
        return
    end
    if typeof(writefile) ~= "function" then
        warn("[Gojo] ✘ writefile required — executor blocks it")
        return
    end

    Gojo.mounted = true
    warn("[Gojo] Mounting...")

    -- Download files
    local function dl(name, url)
        if isfile and isfile(name) then
            local ok, c = pcall(readfile, name)
            if ok and type(c) == "string" and #c > 100 then return true end
        end
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and #body > 100 then
            pcall(writefile, name, body)
            return true
        end
        return false
    end

    local okModel = dl("Gojo.rbxmx", "https://github.com/ian49972/RBXMS/raw/refs/heads/main/Gojo.rbxmx")
    dl("Purple.mp3", "https://github.com/ian49972/smth/raw/refs/heads/main/Purple.mp3")
    dl("UnlimitedPurple.mp3", "https://github.com/ian49972/smth/raw/refs/heads/main/UnlimitedPurple.mp3")
    dl("ImaginaryPurple.mp3", "https://github.com/ian49972/smth/raw/refs/heads/main/ImaginaryPurple.mp3")
    dl("Domain.mp3", "https://github.com/ian49972/smth/raw/refs/heads/main/Domain.mp3")
    dl("Honored.mp3", "https://github.com/ian49972/smth/raw/refs/heads/main/Honored.mp3")

    if not okModel then
        warn("[Gojo] ✘ Model download failed")
        Gojo.mounted = false
        return
    end

    -- Create dmg lib (f1 from original)
    local g = getgenv()
    local lp = Players.LocalPlayer
    local dmgLib = {
        Config = {
            HitPlayers = true, HitNPCs = true, IgnoreForceField = true,
            ShowDamageNumbers = true, EraseVisual = true, Debug = false,
            Whitelist = {},
            HollowPurple = { HitRadius = 20, Lethal = true, DirectFraction = 1, ShockwaveRadius = 30, ShockwaveFraction = 0.5 },
            ImaginaryPurple = { HitRadius = 18, Lethal = true, DirectFraction = 1, ShockwaveRadius = 26, ShockwaveFraction = 0.6 },
            UnlimitedPurple = {
                BlueContactRadius = 10, BlueContactLethal = true, BlueContactFraction = 1, BlueContactCooldown = 0.6,
                RedPulseRadius = 25, RedPulseLethal = true, RedPulseFraction = 1,
                ExplosionLethalRadius = 400, ExplosionMaxRadius = 400, ExplosionEdgeFraction = 0.35, ExplosionExpandTime = 0.45,
            },
            InfiniteVoid = {
                Radius = 220, TickInterval = 0.5, TotalDamageFraction = 1,
                Paralyze = true, FreezeInPlace = true, InstantEraseOnOpen = true, KillOnCollapse = true,
            },
            HonoredOne = { SelfHeal = true },
        },
        Colors = {
            Purple = Color3.fromRGB(176, 84, 255), Blue = Color3.fromRGB(80, 160, 255),
            Red = Color3.fromRGB(255, 80, 80), Void = Color3.fromRGB(235, 235, 255),
            Heal = Color3.fromRGB(120, 255, 160),
        },
        _humanoids = {},
        _hurtPatched = false,
    }
    local v10 = dmgLib._humanoids

    local function f3(h) if h:IsA("Humanoid") then v10[h] = true end end
    for _, d in ipairs(workspace:GetDescendants()) do f3(d) end
    workspace.DescendantAdded:Connect(f3)

    function dmgLib.GetTargets()
        local out = {}
        local char = lp.Character
        for h in pairs(v10) do
            if not h:IsDescendantOf(workspace) then
                v10[h] = nil
            else
                local p = h.Parent
                if p and p:IsA("Model") and p ~= char and h.Health > 0 then
                    local plr = Players:GetPlayerFromCharacter(p)
                    if (plr and dmgLib.Config.HitPlayers and plr ~= lp) or (not plr and dmgLib.Config.HitNPCs) then
                        local root = h.RootPart or p:FindFirstChild("HumanoidRootPart") or p:FindFirstChildWhichIsA("BasePart")
                        if root then
                            out[#out+1] = { Humanoid = h, Character = p, Root = root, Head = p:FindFirstChild("Head") }
                        end
                    end
                end
            end
        end
        return out
    end

    local function distTo(t, pos)
        local d = (t.Root.Position - pos).Magnitude
        if t.Head and t.Head:IsA("BasePart") then
            d = math.min(d, (t.Head.Position - pos).Magnitude)
        end
        return d - 2
    end

    local function popup(t, text, color)
        if not dmgLib.Config.ShowDamageNumbers then return end
        local head = (t.Head and t.Head:IsA("BasePart") and t.Head) or t.Root
        if not head then return end
        local bb = Instance.new("BillboardGui")
        bb.AlwaysOnTop = true; bb.LightInfluence = 0
        bb.Size = UDim2.new(0, 220, 0, 56)
        bb.StudsOffset = Vector3.new(math.random(-8,8)/10, 2.6, 0)
        bb.Adornee = head; bb.Parent = head
        local tl = Instance.new("TextLabel")
        tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1,1)
        tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.Text = text
        tl.TextColor3 = color or dmgLib.Colors.Purple
        tl.TextStrokeColor3 = Color3.new(0,0,0); tl.TextStrokeTransparency = 0.15
        tl.Parent = bb
        TweenService:Create(bb, TweenInfo.new(1), {StudsOffset = bb.StudsOffset + Vector3.new(0,3,0)}):Play()
        TweenService:Create(tl, TweenInfo.new(1), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
        Debris:AddItem(bb, 1.05)
    end

    local function eraseVisual(char)
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") or d:IsA("Decal") then
                TweenService:Create(d, TweenInfo.new(0.45), {Transparency = 1}):Play()
            elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d.Enabled = false
            end
        end
    end

    function dmgLib.Hurt(target, amount, label, color, erase)
        local hum = target.Humanoid
        if not hum or hum.Health <= 0 then return false, false end
        local lethal = amount == math.huge or amount >= hum.Health
        local char = target.Character
        local isNPC = not Players:GetPlayerFromCharacter(char)

        if lethal then
            hum.Health = 0
        elseif dmgLib.Config.IgnoreForceField then
            hum.Health = math.max(0, hum.Health - amount)
        else
            hum:TakeDamage(amount)
        end

        popup(target, lethal and (label or "☠") or "-"..tostring(math.floor(amount+0.5)), color or dmgLib.Colors.Purple)

        if lethal and erase and dmgLib.Config.EraseVisual then
            eraseVisual(char)
        end

        -- ★ VOID KILL for NPCs (same as Soul) ★
        if lethal and isNPC and char and char.Parent then
            task.spawn(function()
                task.wait(0.4)  -- let erase visual play
                pcall(voidKill, char)
            end)
        end

        return true, lethal
    end

    function dmgLib.Sweep(opts)
        local part = opts.Part
        if not part then return { Stop = function() end } end
        local radius = opts.Radius or math.max(part.Size.X, part.Size.Y, part.Size.Z)/2
        local shockR = opts.ShockRadius
        local lethal = opts.Lethal ~= false
        local directFrac = opts.DirectFraction or 1
        local shockFrac = opts.ShockFraction or 0.5
        local duration = opts.Duration
        local hits = {}
        local t0 = os.clock()
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if not part.Parent or (duration and os.clock() - t0 >= duration) then
                conn:Disconnect(); return
            end
            for _, t in ipairs(dmgLib.GetTargets()) do
                local prev = hits[t.Humanoid]
                if prev ~= "direct" then
                    local d = distTo(t, part.Position)
                    if d <= radius then
                        hits[t.Humanoid] = "direct"
                        dmgLib.Hurt(t, lethal and math.huge or t.Humanoid.MaxHealth * directFrac, "ERASED", dmgLib.Colors.Purple, lethal)
                    elseif shockR and not prev and d <= shockR then
                        hits[t.Humanoid] = "shock"
                        dmgLib.Hurt(t, t.Humanoid.MaxHealth * shockFrac, nil, dmgLib.Colors.Purple)
                    end
                end
            end
        end)
        return { Stop = function() if conn then conn:Disconnect() end end }
    end

    function dmgLib.Contact(opts)
        local part = opts.Part
        if not part then return { Stop = function() end } end
        local radius = opts.Radius or 6
        local lethal = opts.Lethal ~= false
        local frac = opts.Fraction or 1
        local cd = opts.Cooldown or 0.5
        local hits = {}
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if not part.Parent then conn:Disconnect(); return end
            local now = os.clock()
            for _, t in ipairs(dmgLib.GetTargets()) do
                if distTo(t, part.Position) <= radius then
                    local last = hits[t.Humanoid]
                    if not last or now - last >= cd then
                        hits[t.Humanoid] = now
                        dmgLib.Hurt(t, lethal and math.huge or t.Humanoid.MaxHealth * frac, lethal and "ERASED" or nil, opts.Color or dmgLib.Colors.Blue, lethal)
                    end
                end
            end
        end)
        return { Stop = function() if conn then conn:Disconnect() end end }
    end

    function dmgLib.Pulse(opts)
        local pos = opts.Position
        local radius = opts.Radius or 10
        local lethal = opts.Lethal ~= false
        local frac = opts.Fraction or 1
        for _, t in ipairs(dmgLib.GetTargets()) do
            if distTo(t, pos) <= radius then
                dmgLib.Hurt(t, lethal and math.huge or t.Humanoid.MaxHealth * frac, lethal and "ERASED" or nil, opts.Color or dmgLib.Colors.Red, lethal)
            end
        end
    end

    function dmgLib.Explosion(opts)
        local pos = opts.Position
        local maxR = opts.MaxRadius or opts.LethalRadius or 200
        local expand = opts.ExpandTime or 0
        local hits = {}
        local t0 = os.clock()
        local function doHit(r)
            for _, t in ipairs(dmgLib.GetTargets()) do
                if not hits[t.Humanoid] and distTo(t, pos) <= r then
                    hits[t.Humanoid] = true
                    dmgLib.Hurt(t, math.huge, "ERASED", dmgLib.Colors.Purple, true)
                end
            end
        end
        if expand <= 0 then doHit(maxR); return { Hits = hits } end
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local k = math.clamp((os.clock() - t0) / expand, 0, 1)
            doHit(maxR * k)
            if k >= 1 then conn:Disconnect() end
        end)
        return { Hits = hits }
    end

    function dmgLib.Mark() end
    function dmgLib.Log() end
    function dmgLib.SelfHeal()
        local c = lp.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if h then h.Health = h.MaxHealth end
    end

    Gojo.dmgLib = dmgLib
    g.GojoDamage = dmgLib

    -- Pose-based animation helper
    local tweenService = TweenService
    local runService = RunService
    local function poseAnimator(character, animFolder, speedMult)
        if not character or not animFolder then return nil end
        local styleMap = {
            [Enum.PoseEasingStyle.Linear] = Enum.EasingStyle.Linear,
            [Enum.PoseEasingStyle.Bounce] = Enum.EasingStyle.Bounce,
            [Enum.PoseEasingStyle.Cubic] = Enum.EasingStyle.Cubic,
            [Enum.PoseEasingStyle.Elastic] = Enum.EasingStyle.Elastic,
            [Enum.PoseEasingStyle.Constant] = Enum.EasingStyle.Linear,
        }
        local dirMap = {
            [Enum.PoseEasingDirection.In] = Enum.EasingDirection.In,
            [Enum.PoseEasingDirection.Out] = Enum.EasingDirection.Out,
            [Enum.PoseEasingDirection.InOut] = Enum.EasingDirection.InOut,
        }
        local kfs = {}
        for _, kf in ipairs(animFolder:GetKeyframes()) do
            table.insert(kfs, {Time = kf.Time, KF = kf})
        end
        table.sort(kfs, function(a,b) return a.Time < b.Time end)
        if #kfs == 0 then return nil end
        local jointCache, boneCache = {}, {}
        local tracks = {}
        local function findJoint(pose)
            local name = pose.Name
            if jointCache[name] then return jointCache[name] end
            if boneCache[name] then return boneCache[name] end
            for _, d in ipairs(character:GetDescendants()) do
                if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == name then
                    jointCache[name] = d; return d
                end
                if d:IsA("Bone") and d.Name == name then
                    boneCache[name] = d; return d
                end
            end
            return nil
        end
        for _, kf in ipairs(kfs) do
            for _, pose in ipairs(kf.KF:GetDescendants()) do
                if pose:IsA("Pose") and pose.Weight > 0 then
                    local j = findJoint(pose)
                    if j then
                        tracks[pose.Name] = tracks[pose.Name] or {}
                        table.insert(tracks[pose.Name], {
                            t = kf.Time, cf = pose.CFrame, style = pose.EasingStyle,
                            dir = pose.EasingDirection, joint = j,
                        })
                    end
                end
            end
        end
        local len = kfs[#kfs].Time / (speedMult or 1)
        local running, t0, conn = true, os.clock(), nil
        conn = runService.Heartbeat:Connect(function()
            if not running or not character.Parent then conn:Disconnect(); return end
            local t = (os.clock() - t0) * (speedMult or 1) % len
            for _, arr in pairs(tracks) do
                local a, b = arr[1], arr[1]
                for i = 1, #arr - 1 do
                    if t >= arr[i].t and t < arr[i+1].t then
                        a, b = arr[i], arr[i+1]; break
                    end
                end
                if t >= arr[#arr].t then a, b = arr[#arr], arr[#arr] end
                local p = b.t > a.t and (t - a.t) / (b.t - a.t) or 0
                local v = tweenService:GetValue(p, styleMap[b.style] or Enum.EasingStyle.Linear, dirMap[b.dir] or Enum.EasingDirection.InOut)
                if a.joint then
                    pcall(function() a.joint.Transform = a.cf:Lerp(b.cf, v) end)
                end
            end
        end)
        return {
            Length = len,
            Play = function() t0 = os.clock() end,
            Stop = function() running = false; if conn then conn:Disconnect() end end,
        }
    end

    -- Tool creators (from original f13, f28, f31, f35)
    local function createTool(name, requiresHandle)
        local t = Instance.new("Tool")
        t.Name = name
        t.RequiresHandle = requiresHandle or false
        return t
    end

    -- Download & create all 4 tools
    local function safeGetObjects(path)
        local ok, res = pcall(function()
            local url = typeof(getcustomasset) == "function" and getcustomasset(path) or path
            return game:GetObjects(url)
        end)
        if ok and res and res[1] then return res[1] end
        return nil
    end

    -- ★ HOLLOW PURPLE TOOL ★
    local hpTool = createTool("Hollow Purple")
    hpTool.Activated:Connect(function()
        local char = lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        local origWalk = hum.WalkSpeed
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then animator.Parent = nil end
        hum.WalkSpeed = 0

        local rbx = safeGetObjects("Gojo.rbxmx")
        if not rbx then
            warn("[Gojo] rbxmx load failed for Hollow Purple")
            hum.WalkSpeed = origWalk
            if animator then animator.Parent = hum end
            return
        end
        rbx.Parent = ReplicatedStorage

        local clone = rbx:FindFirstChild("Effects"):FindFirstChild("HollowPurple"):Clone()
        local blueOrb = clone:FindFirstChild("BlueOrb") or clone:FindFirstChild("Blue Orb")
        local redOrb = clone:FindFirstChild("RedOrb") or clone:FindFirstChild("Red Orb")
        local purple = clone:FindFirstChild("Purple")
        local purple2 = clone:FindFirstChild("Purple2")

        if blueOrb then
            blueOrb.CFrame = hrp.CFrame * CFrame.new(-5, 0, 8)
            blueOrb.Anchored = true; blueOrb.Parent = workspace
        end
        if redOrb then
            redOrb.CFrame = hrp.CFrame * CFrame.new(5, 0, 8)
            redOrb.Anchored = true; redOrb.Parent = workspace
        end

        local s = Instance.new("Sound")
        s.SoundId = typeof(getcustomasset) == "function" and getcustomasset("Purple.mp3") or ""
        s.Volume = 1; s.Parent = workspace
        pcall(function() s:Play() end)

        task.wait(6)
        if blueOrb then blueOrb:Destroy() end
        if redOrb then redOrb:Destroy() end

        if purple then
            purple.CFrame = hrp.CFrame * CFrame.new(0, 10, -20)
            purple.Anchored = true; purple.Parent = workspace
            task.wait(7)
            purple:Destroy()
        end

        if purple2 then
            purple2.Anchored = true
            for _, d in ipairs(purple2:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
            end
            local lv = hrp.CFrame.LookVector
            purple2.CFrame = hrp.CFrame * CFrame.new(0, 10, -8)
            purple2.Rotation = Vector3.new(0, math.deg(math.atan2(lv.X, lv.Z)), 0)
            purple2.Parent = workspace

            local cf = purple2.CFrame
            local start = os.clock()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if os.clock() - start >= 15 or not purple2.Parent then conn:Disconnect(); return end
                cf = cf + lv * 280 * 0.016
                purple2.CFrame = cf
            end)
            Debris:AddItem(purple2, 15)

            local cfg = dmgLib.Config.HollowPurple
            dmgLib.Sweep({
                Part = purple2, Radius = cfg.HitRadius, Lethal = cfg.Lethal,
                DirectFraction = cfg.DirectFraction, ShockRadius = cfg.ShockwaveRadius,
                ShockFraction = cfg.ShockwaveFraction, Duration = 15,
            })
        end

        task.wait(1)
        if animator then animator.Parent = hum end
        hum.WalkSpeed = origWalk
        clone:Destroy()
    end)
    Gojo.tools.hp = hpTool

    -- ★ UNLIMITED PURPLE TOOL ★
    local upTool = createTool("Unlimited Hollow Purple")
    upTool.Activated:Connect(function()
        local char = lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        local origWalk = hum.WalkSpeed
        local origHip = hum.HipHeight
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then animator.Parent = nil end
        hum.WalkSpeed = 0

        local rbx = safeGetObjects("Gojo.rbxmx")
        if not rbx then
            hum.WalkSpeed = origWalk
            if animator then animator.Parent = hum end
            return
        end
        rbx.Parent = ReplicatedStorage

        local cfg = dmgLib.Config.UnlimitedPurple
        local effects = rbx:FindFirstChild("Effects"):FindFirstChild("UnlimitedPurple")

        local blue = effects:FindFirstChild("Blue") and effects:FindFirstChild("Blue"):Clone()
        local red = effects:FindFirstChild("Red") and effects:FindFirstChild("Red"):Clone()
        local purple = effects:FindFirstChild("Purple") and effects:FindFirstChild("Purple"):Clone()
        local explode = effects:FindFirstChild("PurpleExplode") and effects:FindFirstChild("PurpleExplode"):Clone()

        local s = Instance.new("Sound")
        s.SoundId = typeof(getcustomasset) == "function" and getcustomasset("UnlimitedPurple.mp3") or ""
        s.Volume = 1; s.Parent = workspace
        pcall(function() s:Play() end)

        task.wait(3)

        if blue then
            blue.Anchored = true; blue.CanCollide = false
            blue.CFrame = hrp.CFrame * CFrame.new(0, 0, -5)
            blue.Parent = workspace
            local startPos = blue.CFrame
            local start = os.clock()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() - start) * 3.8
                blue.CFrame = hrp.CFrame * CFrame.new(math.cos(t)*32, 4, math.sin(t)*32) * CFrame.Angles(0, t*1.6, 0)
            end)
            local contact = dmgLib.Contact({
                Part = blue, Radius = cfg.BlueContactRadius, Lethal = cfg.BlueContactLethal,
                Fraction = cfg.BlueContactFraction, Cooldown = cfg.BlueContactCooldown,
            })
            task.wait(2.5)
            if red then
                red.Anchored = true; red.CanCollide = false
                red.CFrame = hrp.CFrame * CFrame.new(0, 6, -6)
                red.Parent = workspace
                TweenService:Create(red, TweenInfo.new(1), {CFrame = red.CFrame * CFrame.new(0, 100, 0)}):Play()
                dmgLib.Pulse({
                    Position = hrp.Position, Radius = cfg.RedPulseRadius,
                    Lethal = cfg.RedPulseLethal, Fraction = cfg.RedPulseFraction,
                })
            end
            task.wait(3)
            TweenService:Create(hum, TweenInfo.new(9), {HipHeight = origHip + 90}):Play()
            task.wait(5)
            if conn then conn:Disconnect() end
            if contact then contact.Stop() end
            if blue then TweenService:Create(blue, TweenInfo.new(1.2), {CFrame = hrp.CFrame * CFrame.new(0, 18, 0)}):Play() end
            if red then TweenService:Create(red, TweenInfo.new(1.2), {CFrame = hrp.CFrame * CFrame.new(0, 18, 0)}):Play() end
            task.wait(2)
            if blue then blue:Destroy() end
            if red then red:Destroy() end
            if purple then
                purple.Anchored = true
                purple.CFrame = hrp.CFrame * CFrame.new(0, 22, 0)
                purple.Parent = workspace
                task.wait(2.3)
                purple:Destroy()
            end
            if explode then
                explode.Anchored = true
                explode.CFrame = hrp.CFrame * CFrame.new(0, 22, 0)
                explode.Parent = workspace
                dmgLib.Explosion({
                    Position = explode.Position, LethalRadius = cfg.ExplosionLethalRadius,
                    MaxRadius = cfg.ExplosionMaxRadius, EdgeFraction = cfg.ExplosionEdgeFraction,
                    ExpandTime = cfg.ExplosionExpandTime,
                })
                Debris:AddItem(explode, 8)
            end
        end

        task.wait(2)
        if animator then animator.Parent = hum end
        hum.WalkSpeed = origWalk
        hum.HipHeight = origHip
        rbx:Destroy()
    end)
    Gojo.tools.up = upTool

    -- ★ IMAGINARY PURPLE TOOL ★
    local ipTool = createTool("Imaginary Hollow Purple")
    ipTool.Activated:Connect(function()
        local char = lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        local origWalk = hum.WalkSpeed
        hum.WalkSpeed = 0

        local rbx = safeGetObjects("Gojo.rbxmx")
        if not rbx then hum.WalkSpeed = origWalk; return end
        rbx.Parent = ReplicatedStorage

        local cfg = dmgLib.Config.ImaginaryPurple
        local effects = rbx:FindFirstChild("Effects"):FindFirstChild("ImaginaryPurple")

        local s = Instance.new("Sound")
        s.SoundId = typeof(getcustomasset) == "function" and getcustomasset("ImaginaryPurple.mp3") or ""
        s.Volume = 1; s.Parent = workspace
        pcall(function() s:Play() end)

        task.wait(9)

        local shoot = effects:FindFirstChild("PurpleShoot")
        if shoot then
            local clone = shoot:Clone()
            clone.Anchored = true; clone.CanCollide = false
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
            end
            clone.CFrame = hrp.CFrame * CFrame.new(0, 6, 0)
            clone.Parent = workspace
            local lv = hrp.CFrame.LookVector
            local cf = clone.CFrame
            local start = os.clock()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if os.clock() - start >= 15 or not clone.Parent then conn:Disconnect(); return end
                cf = cf + lv * 275 * 0.016
                clone.CFrame = cf
            end)
            Debris:AddItem(clone, 15)
            dmgLib.Sweep({
                Part = clone, Radius = cfg.HitRadius, Lethal = cfg.Lethal,
                DirectFraction = cfg.DirectFraction, ShockRadius = cfg.ShockwaveRadius,
                ShockFraction = cfg.ShockwaveFraction, Duration = 15,
            })
        end

        hum.WalkSpeed = origWalk
        rbx:Destroy()
    end)
    Gojo.tools.ip = ipTool

    -- ★ INFINITE VOID TOOL ★
    local ivTool = createTool("Infinite Void")
    ivTool.Activated:Connect(function()
        local char = lp.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        local origWalk = hum.WalkSpeed
        hum.WalkSpeed = 0

        local cfg = dmgLib.Config.InfiniteVoid
        local domain = dmgLib.Domain({
            Position = hrp.Position, Radius = cfg.Radius,
            TickInterval = cfg.TickInterval, Duration = 24,
            TotalFraction = cfg.TotalDamageFraction, Paralyze = cfg.Paralyze,
            FreezeInPlace = cfg.FreezeInPlace, KillOnCollapse = cfg.KillOnCollapse,
        })

        local s = Instance.new("Sound")
        s.SoundId = typeof(getcustomasset) == "function" and getcustomasset("Domain.mp3") or ""
        s.Volume = 1; s.Parent = workspace
        pcall(function() s:Play() end)

        task.wait(24)
        if domain then domain.Collapse() end
        hum.WalkSpeed = origWalk
    end)
    Gojo.tools.iv = ivTool

    -- Domain method (needed for ivTool)
    function dmgLib.Domain(opts)
        local pos = opts.Position
        local radius = opts.Radius or 200
        local tick = opts.TickInterval or 0.5
        local dur = opts.Duration or 24
        local totalFrac = opts.TotalFraction or 1
        local paralyze = opts.Paralyze ~= false
        local freeze = opts.FreezeInPlace ~= false
        local killOnCollapse = opts.KillOnCollapse ~= false
        local instant = opts.InstantEraseOnOpen ~= false
        local victims = {}
        local t0 = os.clock()
        local nextTick = t0
        local numTicks = instant and 0 or math.max(1, math.floor(dur / tick + 0.5))
        local perTick = instant and 0 or totalFrac / numTicks
        local tickCount = 0
        local conn

        local function catch(eraseNow)
            for _, t in ipairs(dmgLib.GetTargets()) do
                if not victims[t.Humanoid] then
                    if distTo(t, pos) <= radius then
                        victims[t.Humanoid] = { Target = t, Saved = {
                            WalkSpeed = t.Humanoid.WalkSpeed,
                            JumpPower = t.Humanoid.JumpPower,
                            AutoRotate = t.Humanoid.AutoRotate,
                            Anchored = t.Root.Anchored,
                        }}
                        if paralyze then
                            pcall(function()
                                t.Humanoid.WalkSpeed = 0; t.Humanoid.JumpPower = 0
                                t.Humanoid.AutoRotate = false
                                if freeze then t.Root.Anchored = true end
                            end)
                        end
                        if eraseNow then dmgLib.Hurt(t, math.huge, "VOID", dmgLib.Colors.Void, true) end
                    end
                end
            end
        end

        if instant then catch(true) end

        conn = RunService.Heartbeat:Connect(function()
            local now = os.clock()
            if instant then
                catch(true)
                if now - t0 >= dur then conn:Disconnect() end
                return
            end
            while tickCount < numTicks and now >= nextTick do
                tickCount = tickCount + 1
                nextTick = nextTick + tick
                catch(false)
                for h, v in pairs(victims) do
                    if h.Health > 0 then dmgLib.Hurt(v.Target, h.MaxHealth * perTick, nil, dmgLib.Colors.Void) end
                end
            end
            if tickCount >= numTicks then conn:Disconnect() end
        end)

        return {
            Collapse = function()
                if conn then conn:Disconnect() end
                for h, v in pairs(victims) do
                    if killOnCollapse and h.Health > 0 then dmgLib.Hurt(v.Target, math.huge, "VOID", dmgLib.Colors.Void) end
                    if paralyze then
                        pcall(function()
                            h.WalkSpeed = v.Saved.WalkSpeed; h.JumpPower = v.Saved.JumpPower
                            h.AutoRotate = v.Saved.AutoRotate
                            v.Target.Root.Anchored = v.Saved.Anchored
                        end)
                    end
                end
            end,
        }
    end

    -- Give tools to backpack
    local bp = lp:WaitForChild("Backpack")
    for _, tool in pairs(Gojo.tools) do
        tool.Parent = bp
    end

    warn("[Gojo] ✔ Mounted — 4 tools in backpack")

    -- Gojo cleanup
    Gojo.cleanup = function()
        for name, tool in pairs(Gojo.tools) do
            pcall(function() tool:Destroy() end)
        end
        Gojo.tools = {}
    end
end

unmountGojo = function()
    if not Gojo.mounted then return end
    Gojo.instinct = false
    if Gojo.cleanup then pcall(Gojo.cleanup) end
    Gojo.cleanup = nil
    Gojo.mounted = false
    sfx(SND.ui, 0.7, 0.9)
end

toggleGojoInstinct = function()
    Gojo.instinct = not Gojo.instinct
    if instinctLabelUI then
        instinctLabelUI.Text = Gojo.instinct and "INSTINCT: ON" or "INSTINCT: OFF"
        instinctLabelUI.TextColor3 = Gojo.instinct and CONFIG.NEON_D or CONFIG.NEON_C
    end
    if Gojo.instinct then
        sfx(SND.ui, 0.9, 1.3)
        task.spawn(function()
            while Gojo.instinct and Gojo.mounted do
                task.wait(0.25)
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local best, bestDist = nil, 30
                    for _, m in ipairs(workspace:GetDescendants()) do
                        if m:IsA("Model") and m ~= char then
                            local h = m:FindFirstChildOfClass("Humanoid")
                            if h and h.Health > 0 and not Players:GetPlayerFromCharacter(m) then
                                local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
                                if root and root:IsA("BasePart") then
                                    local d = (root.Position - hrp.Position).Magnitude
                                    if d < bestDist then best, bestDist = m, d end
                                end
                            end
                        end
                    end
                    if best then pcall(voidKill, best) end
                end
            end
        end)
    end
end

gtrack(player.CharacterAdded:Connect(function()
    if S.mounted then
        unmount()
        task.wait(0.6)
        task.spawn(mount)
    end
    if Gojo.mounted then
        unmountGojo()
        task.wait(0.6)
        task.spawn(mountGojo)
    end
end))

-- ============================================================
--  UI
-- ============================================================
local function setupUI()
    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props or {}) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(p, r) return new("UICorner", {CornerRadius = r or UDim.new(0,10)}, p) end
    local function stroke(p, col, th, tr)
        return new("UIStroke", {Color=col, Thickness=th or 2, Transparency=tr or 0, ApplyStrokeMode=Enum.ApplyStrokeMode.Border}, p)
    end

    local gui = new("ScreenGui", {
        Name = "HalloweenSoul_v3", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    do
        local ok, hui = pcall(function() return gethui and gethui() end)
        gui.Parent = (ok and hui) or player:WaitForChild("PlayerGui")
    end
    local FONT = Enum.Font.Bangers
    pcall(function() FONT = Enum.Font.Creepster end)

    local CIRCLE_SIZE = 56
    local HUB_GAP = 8
    local HUB_W = 190
    local HUB_H = 280

    local circle = new("TextButton", {
        Name = "HubToggleCircle",
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18),
        Size = UDim2.fromOffset(CIRCLE_SIZE, CIRCLE_SIZE),
        BackgroundColor3 = Color3.fromRGB(15, 8, 18), BackgroundTransparency = 0.1,
        AutoButtonColor = false, Text = "☰", Font = FONT, TextColor3 = CONFIG.NEON_A,
        TextScaled = true, ZIndex = 96,
    }, gui)
    corner(circle, UDim.new(1, 0))
    local cStroke = stroke(circle, CONFIG.NEON_A, 2.5)
    new("UIPadding", {PaddingTop=UDim.new(0,12), PaddingBottom=UDim.new(0,12),
        PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,12)}, circle)

    local hub = new("Frame", {
        Name = "SimpleHub", AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 18 + CIRCLE_SIZE + HUB_GAP),
        Size = UDim2.fromOffset(HUB_W, HUB_H),
        BackgroundColor3 = Color3.fromRGB(10, 5, 15), BackgroundTransparency = 0.15,
        BorderSizePixel = 0, ZIndex = 95,
    }, gui)
    corner(hub, UDim.new(0, 14))
    stroke(hub, CONFIG.NEON_A, 2.5)
    new("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,0,0,4), Size=UDim2.new(1,0,0,18),
        Font=FONT, Text="HUB", TextScaled=true, TextColor3=CONFIG.NEON_A, ZIndex=96}, hub)

    local hubClose = new("TextButton", {AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,-8,0,2),
        Size=UDim2.fromOffset(20,20), BackgroundColor3=Color3.fromRGB(30,12,16),
        AutoButtonColor=false, Text="", ZIndex=97}, hub)
    corner(hubClose, UDim.new(1,0))
    stroke(hubClose, CONFIG.NEON_B, 1.5)
    for _, r in ipairs({45,-45}) do
        new("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
            Size=UDim2.fromOffset(10,2), Rotation=r, BackgroundColor3=CONFIG.NEON_B, BorderSizePixel=0, ZIndex=98}, hubClose)
    end

    local tabBar = new("Frame", {
        Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 28),
        BackgroundColor3 = Color3.fromRGB(20, 10, 25), BackgroundTransparency = 0.3,
        BorderSizePixel = 0, ZIndex = 96,
    }, hub)
    corner(tabBar, UDim.new(0, 8))

    local tabSoulBtn, tabGojoBtn

    local function makeTabBtn(label, xPos, initialPos)
        local btn = new("TextButton", {
            Position = initialPos or UDim2.new(xPos, 0, 0, 2), Size = UDim2.new(0.5, -3, 1, -4),
            BackgroundColor3 = Color3.fromRGB(30, 15, 35), AutoButtonColor = false,
            Text = "", BorderSizePixel = 0, ZIndex = 97,
        }, tabBar)
        corner(btn, UDim.new(0, 6))
        stroke(btn, CONFIG.NEON_A, 1.5, 0.5)
        local tl = new("TextLabel", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1),
            Font=FONT, Text=label, TextScaled=true, TextColor3=Color3.fromRGB(150,140,150), ZIndex=98}, btn)
        new("UIPadding", {PaddingTop=UDim.new(0,3), PaddingBottom=UDim.new(0,3)}, tl)
        return btn
    end

    tabSoulBtn = makeTabBtn("SOUL", 0)
    tabGojoBtn = makeTabBtn("GOJO", 0.5, UDim2.new(0.5, 3, 0, 2))

    local lblMorph, lblInstinct

    local function switchTab(which)
        activeTab = which
        local function setActive(btn, on)
            btn.BackgroundColor3 = on and Color3.fromRGB(60, 30, 15) or Color3.fromRGB(30, 15, 35)
            btn:FindFirstChildOfClass("TextLabel").TextColor3 = on and CONFIG.NEON_A or Color3.fromRGB(150,140,150)
        end
        if which == "soul" then
            setActive(tabSoulBtn, true); setActive(tabGojoBtn, false)
            if lblMorph then
                lblMorph.Text = S.mounted and "UNMORPH" or "MORPH"
                lblMorph.TextColor3 = S.mounted and CONFIG.NEON_B or CONFIG.NEON_A
            end
            if lblInstinct then
                lblInstinct.Text = soulInstinct and "INSTINCT: ON" or "INSTINCT: OFF"
                lblInstinct.TextColor3 = soulInstinct and CONFIG.NEON_D or CONFIG.NEON_C
            end
        else
            setActive(tabSoulBtn, false); setActive(tabGojoBtn, true)
            if lblMorph then
                lblMorph.Text = Gojo.mounted and "UNMORPH" or "MORPH"
                lblMorph.TextColor3 = Gojo.mounted and CONFIG.NEON_B or CONFIG.NEON_A
            end
            if lblInstinct then
                lblInstinct.Text = Gojo.instinct and "INSTINCT: ON" or "INSTINCT: OFF"
                lblInstinct.TextColor3 = Gojo.instinct and CONFIG.NEON_D or CONFIG.NEON_C
            end
        end
        if buildMobilePad then buildMobilePad(which) end
    end

    tabSoulBtn.Activated:Connect(function() sfx(SND.ui, 0.4, 1.1); switchTab("soul") end)
    tabGojoBtn.Activated:Connect(function() sfx(SND.ui, 0.4, 1.1); switchTab("gojo") end)

    local function hubBtn(label, col, yPos, size, cb)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, yPos),
            Size = size, BackgroundColor3 = Color3.fromRGB(15, 8, 18),
            AutoButtonColor = false, Text = "", BorderSizePixel = 0, ZIndex = 96,
        }, hub)
        corner(b, UDim.new(0, 8))
        local s = stroke(b, col, 2)
        local tl = new("TextLabel", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1),
            Font=FONT, Text=label, TextScaled=true, TextColor3=col, ZIndex=97}, b)
        new("UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4)}, tl)
        b.MouseEnter:Connect(function() tw(s, 0.15, {Thickness=3.5}) tw(tl, 0.15, {TextColor3=Color3.new(1,1,1)}) end)
        b.MouseLeave:Connect(function() tw(s, 0.15, {Thickness=2}) tw(tl, 0.15, {TextColor3=col}) end)
        b.Activated:Connect(function() sfx(SND.ui, 0.5, 0.9); cb() end)
        return b, tl
    end

    local btnMorph
    btnMorph, lblMorph = hubBtn("MORPH", CONFIG.NEON_A, 62, UDim2.new(1, -20, 0, 46), function()
        if activeTab == "soul" then
            if S.mounted then
                unmount(); lblMorph.Text = "MORPH"; lblMorph.TextColor3 = CONFIG.NEON_A
            else
                task.spawn(function()
                    mount()
                    if S.mounted then lblMorph.Text = "UNMORPH"; lblMorph.TextColor3 = CONFIG.NEON_B end
                end)
            end
        else
            if Gojo.mounted then
                unmountGojo(); lblMorph.Text = "MORPH"; lblMorph.TextColor3 = CONFIG.NEON_A
            else
                task.spawn(function()
                    mountGojo()
                    if Gojo.mounted then lblMorph.Text = "UNMORPH"; lblMorph.TextColor3 = CONFIG.NEON_B end
                end)
            end
        end
    end)

    hubBtn("REVERT", CONFIG.NEON_B, 114, UDim2.new(1, -20, 0, 42), function()
        if activeTab == "soul" then unmount() else unmountGojo() end
        lblMorph.Text = "MORPH"; lblMorph.TextColor3 = CONFIG.NEON_A
    end)

    local btnShift, lblShift = hubBtn("SHIFTLOCK: OFF", CONFIG.NEON_C, 162, UDim2.new(1, -20, 0, 42), function()
        setShiftlock(not shiftlockOn)
        lblShift.Text = shiftlockOn and "SHIFTLOCK: ON" or "SHIFTLOCK: OFF"
        lblShift.TextColor3 = shiftlockOn and CONFIG.NEON_D or CONFIG.NEON_C
    end)

    local btnInstinct
    btnInstinct, lblInstinct = hubBtn("INSTINCT: OFF", CONFIG.NEON_C, 210, UDim2.new(1, -20, 0, 42), function()
        if activeTab == "soul" then
            toggleSoulInstinct()
            lblInstinct.Text = soulInstinct and "INSTINCT: ON" or "INSTINCT: OFF"
            lblInstinct.TextColor3 = soulInstinct and CONFIG.NEON_D or CONFIG.NEON_C
        else
            toggleGojoInstinct()
            lblInstinct.Text = Gojo.instinct and "INSTINCT: ON" or "INSTINCT: OFF"
            lblInstinct.TextColor3 = Gojo.instinct and CONFIG.NEON_D or CONFIG.NEON_C
        end
    end)
    instinctLabelUI = lblInstinct

    local function syncCircle()
        if hub.Visible then
            circle.Text = "✕"; circle.TextColor3 = CONFIG.NEON_B; cStroke.Color = CONFIG.NEON_B
        else
            circle.Text = "☰"; circle.TextColor3 = CONFIG.NEON_A; cStroke.Color = CONFIG.NEON_A
        end
    end
    local function openHub()
        local cx = circle.Position.X; local cy = circle.Position.Y
        hub.Position = UDim2.new(cx.Scale, cx.Offset, cy.Scale, cy.Offset + CIRCLE_SIZE + HUB_GAP)
        hub.Visible = true; syncCircle()
    end
    local function closeHub() hub.Visible = false; syncCircle() end
    local function toggleHub() if hub.Visible then closeHub() else openHub() end end

    hubClose.Activated:Connect(function() sfx(SND.ui, 0.5, 0.9); closeHub() end)
    openMenu = function() end
    closeMenu = function() end

    local cDragging, cDragStart, cStartPos, cMoved = false, nil, nil, 0
    local lastTapTime = 0
    circle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            cDragging = true; cMoved = 0
            cDragStart = input.Position; cStartPos = circle.Position
        end
    end)
    gtrack(UserInputService.InputChanged:Connect(function(input)
        if not cDragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - cDragStart
            cMoved = math.max(cMoved, delta.Magnitude)
            if cMoved > 8 then
                local cam = workspace.CurrentCamera
                local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
                local newX = math.clamp(cStartPos.X.Offset + delta.X, -(vp.X - (CIRCLE_SIZE + 8)), -8)
                local newY = math.clamp(cStartPos.Y.Offset + delta.Y, 8, vp.Y - (CIRCLE_SIZE + 8))
                circle.Position = UDim2.new(1, newX, 0, newY)
                if hub.Visible then
                    hub.Position = UDim2.new(1, newX, 0, newY + CIRCLE_SIZE + HUB_GAP)
                end
            end
        end
    end))
    gtrack(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not cDragging then return end
        cDragging = false
        if cMoved < 8 then
            local now = tick()
            local isDoubleTap = (now - lastTapTime) < 0.4
            lastTapTime = now
            sfx(SND.ui, 0.5, 1.0)
            if isDoubleTap then
                if not hub.Visible then openHub() end
            else toggleHub() end
        end
    end))

    local mobilePad
    buildMobilePad = function(mode)
        if not UserInputService.TouchEnabled then return end
        if mobilePad then mobilePad:Destroy() end
        mobilePad = new("Frame", {
            AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -30),
            Size = UDim2.fromOffset(230, 340), BackgroundTransparency = 1, Visible = false, ZIndex = 85,
        }, gui)
        local function mBtn(label, col, x, y, d, cb, onRelease)
            local b = new("TextButton", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromOffset(x,y),
                Size=UDim2.fromOffset(d,d), BackgroundColor3=Color3.fromRGB(15,8,18), BackgroundTransparency=0.25,
                AutoButtonColor=false, Text="", ZIndex=86}, mobilePad)
            corner(b, UDim.new(1,0))
            local st = stroke(b, col, 2, 0.2)
            local tl = new("TextLabel", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1),
                Font=FONT, Text=label, TextScaled=true, TextColor3=col, ZIndex=87}, b)
            new("UIPadding", {PaddingTop=UDim.new(0,math.floor(d*0.22)), PaddingBottom=UDim.new(0,math.floor(d*0.22))}, tl)
            b.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                    st.Thickness=3.5; b.BackgroundTransparency=0.05
                    if cb then cb() end
                end
            end)
            b.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                    st.Thickness=2; b.BackgroundTransparency=0.25
                    if onRelease then onRelease() end
                end
            end)
        end
        if mode == "soul" then
            mBtn("RIP",   CONFIG.NEON_A, 180, 210, 56, actRip)
            mBtn("SLAM",  CONFIG.NEON_A, 120, 245, 56, actSlam)
            mBtn("EAT",   CONFIG.NEON_A, 110, 180, 56, actDevour)
            mBtn("SWIPE", CONFIG.NEON_C, 175, 140, 54, actSwipe)
            mBtn("HEAD",  CONFIG.NEON_B, 48, 235, 54, actHeadEat)
            mBtn("CURSE", CONFIG.NEON_D, 44, 160, 50, actCurse)
            mBtn("ROAR",  CONFIG.NEON_A, 175, 75, 48, actRoar)
            mBtn("DUMMY", CONFIG.NEON_C, 48, 90, 48, spawnDummy)
            mBtn("QUAD",  CONFIG.NEON_C, 112, 85, 58, function() S.quad = true end, function() S.quad = false end)
        else
            -- Gojo: just show a hint (tools are in backpack)
            local hint = new("TextLabel", {BackgroundTransparency=0.5, BackgroundColor3=Color3.new(0,0,0),
                Size=UDim2.fromOffset(220, 60), Position=UDim2.fromOffset(5, 100),
                Font=FONT, Text="USE TOOLS IN BACKPACK\n(tap tool icon)", TextScaled=true,
                TextColor3=CONFIG.NEON_A, ZIndex=87}, mobilePad)
            corner(hint, UDim.new(0, 8))
        end
    end
    buildMobilePad("soul")

    gtrack(RunService.RenderStepped:Connect(function()
        if mobilePad then mobilePad.Visible = (S.mounted or Gojo.mounted) and not menuOpen end
    end))
    gtrack(RunService.Heartbeat:Connect(checkRespawns))
end

gtrack(UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == CONFIG.MENU_KEY then return end
    if gp or menuOpen then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if Gojo.mounted then return end
        if not S.mounted then return end
        if S.ctrlHeld then actHeadEat() else actSwipe() end
        return
    end
    if input.KeyCode == CONFIG.INSTINCT_KEY then
        if activeTab == "soul" then toggleSoulInstinct() else toggleGojoInstinct() end
        return
    end
    if not S.mounted then return end
    if input.KeyCode == Enum.KeyCode.Z then actRip()
    elseif input.KeyCode == Enum.KeyCode.X then actSlam()
    elseif input.KeyCode == Enum.KeyCode.C then actDevour()
    elseif input.KeyCode == Enum.KeyCode.V then
        if S.ctrlHeld then actHeadEat() else actSwipe() end
    elseif input.KeyCode == Enum.KeyCode.G then actHeadEat()
    elseif input.KeyCode == Enum.KeyCode.F then actCurse()
    elseif input.KeyCode == Enum.KeyCode.H then actRoar()
    elseif input.KeyCode == Enum.KeyCode.R then finishAttack()
    elseif input.KeyCode == Enum.KeyCode.T then spawnDummy()
    elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        S.ctrlHeld = true; S.quad = true
    end
end))

gtrack(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        S.ctrlHeld = false; S.quad = false
    end
end))

local function cleanup()
    unmount()
    unmountGojo()
    setShiftlock(false)
    soulInstinct = false
    Gojo.instinct = false
    for _, c in ipairs(globalConns) do pcall(function() c:Disconnect() end) end
    for _, rec in pairs(victims) do pcall(restoreVictim, rec, true) end
    local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HalloweenSoul_v3")
    if gui then pcall(function() gui:Destroy() end) end
    pcall(function() fxFolder:Destroy() end)
    if genv.__HALLOWEEN_SOUL_V3 == cleanup then genv.__HALLOWEEN_SOUL_V3 = nil end
end
genv.__HALLOWEEN_SOUL_V3 = cleanup

warn("[Init] Building UI...")
local ok_ui, err_ui = pcall(setupUI)
if not ok_ui then warn("[Init] setupUI crashed: " .. tostring(err_ui)) end

warn("[Init] Preloading Soul template...")
task.spawn(function() pcall(loadTemplate) end)

warn("[Init] Ready. Click ☰ top-right.")
