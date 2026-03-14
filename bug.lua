if not game:IsLoaded() then game.Loaded:Wait() end

math.randomseed(tick())

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService") 
local vim = game:GetService("VirtualInputManager")
local guiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local PathfindingService = game:GetService("PathfindingService")
-- RunService ถูกลบออกแล้ว เพราะ Heartbeat ถูกเปลี่ยนเป็น task.wait loop

local player = Players.LocalPlayer
local playerName = player.DisplayName or player.Name
local playerUserId = tostring(player.UserId)
local camera = Workspace.CurrentCamera

-- ==========================================
-- Anti-AFK (ป้องกันโดนเตะ 20 นาที เปิดอัตโนมัติ)
-- ==========================================
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local parentGui = player:WaitForChild("PlayerGui")
local playerGui = parentGui
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    if CoreGui then
        parentGui = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or CoreGui
    end
end)

local TextChatService
pcall(function() TextChatService = game:GetService("TextChatService") end)

-- [PERF] Cache GuiInset — ค่านี้แทบไม่เปลี่ยน เรียกทุก click (20-60x/วินาที) ทำให้แลค
-- รีเฟรชทุก 5 วินาทีเผื่อเปลี่ยน layout (เช่น rotate มือถือ)
local _cachedInset = guiService:GetGuiInset()
local _insetRefreshTime = tick()
local function getCachedInset()
    if tick() - _insetRefreshTime > 5 then
        _cachedInset = guiService:GetGuiInset()
        _insetRefreshTime = tick()
    end
    return _cachedInset
end

-- [PERF] ใช้ local table แทน _G._actionBGSample เพราะ _G access ช้ากว่า upvalue
local _actionBGSample = {}

-- [PERF] Cache mainUI — FindFirstChild ทุก 0.3 วินาทีไม่จำเป็น
-- ต้องนิยามก่อนทุก function ที่ใช้ getCachedMainUI()
local _cachedMainUI = nil
local function getCachedMainUI()
    if _cachedMainUI and _cachedMainUI.Parent then
        return _cachedMainUI
    end
    _cachedMainUI = playerGui:FindFirstChild("MainInterface")
    return _cachedMainUI
end

-- [FIX] httpRequest: ห่อด้วย pcall กัน error ตอน assign ถ้า executor ไม่มี request บางตัว
local httpRequest = nil
pcall(function()
    httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
end)

-- ==========================================
-- ตัวแปรระบบหลัก (Main System)
-- ==========================================
local CustomWebAPIUrl = "https://www.rng-check.xyz/api.php"
local Webhooks = {
    Mari = { Url = "", Enabled = false },
    Rin = { Url = "", Enabled = false },
    Jester = { Url = "", Enabled = false },
    Biome = { Url = "", Enabled = false }
}
local lastDetectedNPC = ""

local enableAuraDetect = true
local minAuraRarity = 1000
local maxAuraRarity = 5000000000

local AuraQueue = {}
local lastAuraRollJson = "[]"

local CurrentBiomeCache = "Normal"
local NPCHistoryList = {}

local CurrentCraftTarget = ""
local IsCraftReady = false
local CurrentCraftMaterials = {}
local CraftSessionCount = 0
local CraftLogs = {}
local LastMaterialsState = {}

local enableAutoHop = false
local targetBiome = "Heaven"
local isHopping = false
local visitedServers = {}
local hopFileName = "HopBlocklist.json"

local masterAutoEnabled = false
local autoIsOn = false
local nextActionTime = 0

local ScannedItemsList = {}
local ScannedItemPaths = {}
local ScannedItemBaseNames = {} 
local SelectedMultiItems = {}
local CachedTargetButtons = {} 
local multiCraftIndex = 1
local multiCraftState = "SELECT"

local isIncognitoMode = false
local incognitoFakeName = "Hidden_" .. string.sub(playerUserId, -4)

local saveIntervalSeconds = 60
local isInfoWebhookEnabled = false
local scanCooldown = 2.5 

-- ==========================================
-- ตัวแปรระบบตกปลา (Auto Fish / Auto Sell)
-- ==========================================
local TARGET_FISH_POS = CFrame.new(51.72, 99.00, -282.40).Position
local TARGET_SELL_POS = CFrame.new(97.78, 107.50, -296.86).Position
local RESET_FISH_POS = CFrame.new(62.43, 99.00, -279.61).Position

local autoFarmEnabled = false
local autoSellEnabled = false
local isAtTarget = false 
local isSellingProcess = false
local isResettingUI = false
local hasArrivedAtSell = false 
local fishingStep = 0
local hasMinigameMoved = false 

local targetFishCount = 50 
local totalSellCount = 0
local fishingRoundCount = 0
local DetectFish_ON = false
local DetectMinigame_ON = false
local DetectAction_ON = false

local cachedSafeZone, cachedDiamond = nil, nil
local cachedExtraBtn, cachedFishBtn = nil, nil

-- ==========================================
-- รายชื่อ Biome และ Config
-- ==========================================
local BiomeList = {
    ["Windy"] = {"windy", "wind"},
    ["Snowy"] = {"snowy", "snow"},
    ["Rainy"] = {"rainy", "rain"},
    ["Sand storm"] = {"sand storm", "sand"},
    ["Hell"] = {"hell"},
    ["Starfall"] = {"starfall", "star"},
    ["Heaven"] = {"heaven"},
    ["Corruption"] = {"corruption", "corrupt"},
    ["Null"] = {"null"},
    ["GLITCHED"] = {"glitched", "glitch"},
    ["DREAMSPACE"] = {"dreamspace", "dream"},
    ["CYBERSPACE"] = {"cyberspace", "cyber"}
}

local biomeNames = {}
for k, _ in pairs(BiomeList) do table.insert(biomeNames, k) end
table.sort(biomeNames) 

if isfile and isfile(hopFileName) then
    pcall(function() visitedServers = HttpService:JSONDecode(readfile(hopFileName)) end)
end
if #visitedServers > 200 then visitedServers = {} end
table.insert(visitedServers, game.JobId)
if writefile then pcall(function() writefile(hopFileName, HttpService:JSONEncode(visitedServers)) end) end

local Colors = {
    Panel = Color3.fromRGB(25, 28, 43),
    TextMain = Color3.fromRGB(255, 255, 255),
    Mari = Color3.fromRGB(46, 204, 113),
    Rin = Color3.fromRGB(243, 156, 18),
    Jester = Color3.fromRGB(155, 89, 182)
}

local ConfigFileName = "SolsHub_" .. playerName .. ".json"
local HubConfig = {
    AutoCraft = false, HopBiome = "Heaven", AutoHop = false,
    MariUrl = "", MariOn = false, RinUrl = "", RinOn = false, JesterUrl = "", JesterOn = false,
    WhInterval = 60, WhOn = false, Incognito = false, ScanDelay = 2.5,
    AutoFish = false, AutoSell = false, MaxFish = 50,
    BiomeUrl = "", BiomeOn = false, BiomeTarget = "Heaven"
}

local function LoadConfig()
    if isfile and isfile(ConfigFileName) then
        pcall(function()
            local data = HttpService:JSONDecode(readfile(ConfigFileName))
            for k, v in pairs(data) do HubConfig[k] = v end
        end)
    end
    
    masterAutoEnabled = false
    enableAutoHop = false
    HubConfig.AutoCraft = false
    HubConfig.AutoHop = false
    
    autoFarmEnabled = false 
    autoSellEnabled = false
    HubConfig.AutoFish = false
    HubConfig.AutoSell = false
    targetFishCount = tonumber(HubConfig.MaxFish) or 50
    
    targetBiome = HubConfig.HopBiome
    Webhooks.Mari.Url = HubConfig.MariUrl
    Webhooks.Mari.Enabled = HubConfig.MariOn
    Webhooks.Rin.Url = HubConfig.RinUrl
    Webhooks.Rin.Enabled = HubConfig.RinOn
    Webhooks.Jester.Url = HubConfig.JesterUrl
    Webhooks.Jester.Enabled = HubConfig.JesterOn
    
    saveIntervalSeconds = tonumber(HubConfig.WhInterval) or 60
    isInfoWebhookEnabled = HubConfig.WhOn
    isIncognitoMode = HubConfig.Incognito
    scanCooldown = tonumber(HubConfig.ScanDelay) or 2.5
    Webhooks.Biome.Url = HubConfig.BiomeUrl or ""
    Webhooks.Biome.Enabled = HubConfig.BiomeOn or false
end

local function SaveConfig()
    if writefile then
        pcall(function() writefile(ConfigFileName, HttpService:JSONEncode(HubConfig)) end)
    end
end
LoadConfig()

local ApiQueue = {}
local isApiSending = false

local function ProcessApiQueue()
    if isApiSending then return end
    isApiSending = true
    task.spawn(function()
        while #ApiQueue > 0 do
            local payload = ApiQueue[#ApiQueue]
            ApiQueue = {} 

            local success, err = pcall(function() 
                local encodedBody = HttpService:JSONEncode(payload)
                local response = httpRequest({ 
                    Url = CustomWebAPIUrl, 
                    Method = "POST", 
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["User-Agent"] = "Roblox/SolRNG-Script"
                    }, 
                    Body = encodedBody 
                }) 
            end)
            
            task.wait(5)
        end
        isApiSending = false
    end)
end

local WebhookQueue = {}
local isWebhookSending = false

local function ProcessWebhookQueue()
    if isWebhookSending then return end
    isWebhookSending = true
    task.spawn(function()
        while #WebhookQueue > 0 do
            local taskData = table.remove(WebhookQueue, 1)
            pcall(function() 
                httpRequest({ 
                    Url = taskData.Url, 
                    Method = "POST", 
                    Headers = {["Content-Type"] = "application/json"}, 
                    Body = HttpService:JSONEncode(taskData.Body) 
                }) 
            end)
            task.wait(4)
        end
        isWebhookSending = false
    end)
end

task.spawn(function()
    -- [PERF] เพิ่ม 300s — รอบ 180s เดิมทำให้ต้อง re-scan recipe/craft ทุก 3 นาที
    -- ScannedItemPaths เคลียร์เองเมื่อ scan ใหม่ ไม่ต้องล้างบ่อย
    while task.wait(300) do
        -- เคลียร์เฉพาะ scan cache ขนาดใหญ่ที่โต unbounded
        if #ScannedItemsList > 100 then
            ScannedItemPaths = {}
            ScannedItemBaseNames = {}
            ScannedItemsList = {}
        end
        if #CachedTargetButtons > 20 then CachedTargetButtons = {} end
        -- cachedButtons และ cachedRecipeHolder เคลียร์เองเมื่อ parent nil
        -- ไม่ต้อง wipe ที่นี่ — ถ้า wipe จะ force rescan ทุก 5 นาที

        if #AuraQueue > 50 then AuraQueue = {} end
        if #ApiQueue > 10 then ApiQueue = {} end
        if #WebhookQueue > 10 then WebhookQueue = {} end
        
        if #NPCHistoryList > 10 then 
            local newList = {}
            for i = 1, 10 do table.insert(newList, NPCHistoryList[i]) end
            NPCHistoryList = newList
        end
    end
end)

local function AddCraftLog(msg)
    local timeStr = os.date("%H:%M:%S")
    table.insert(CraftLogs, 1, "[" .. timeStr .. "] " .. msg)
    if #CraftLogs > 15 then table.remove(CraftLogs, 16) end
end

local function StripRichText(str) return tostring(str or ""):gsub("<[^>]+>", "") end
local function CleanAuraName(str) local cleaned = str:gsub(":[%w_]+:%s*:%s*", ""); return cleaned:match("^%s*(.-)%s*$") or cleaned end
local function FormatNumber(number) number = tonumber(number) or 0; return tostring(number):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function TrimString(str) return tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function IsInvalidItemName(nameLower)
    local blacklist = {"inventory","collection","auras","delete","lock","unlock","equip","unequip","search","rolls","luck","settings","close","open","back","confirm","equipped","unequipped","select","all","auto","filter", "index", "storage"}
    for _, word in ipairs(blacklist) do if nameLower == word then return true end end
    return false
end

local function AddInventoryItem(itemsDict, name, count)
    name = TrimString(name)
    if name == "" or tonumber(name) or #name < 2 or IsInvalidItemName(name:lower()) then return end
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    itemsDict[name] = (itemsDict[name] or 0) + count
end

local function GetRealBiomeText()
    local PlayerGui = player:FindFirstChild("PlayerGui")
    if not PlayerGui then return nil end
    local MainInterface = PlayerGui:FindFirstChild("MainInterface")
    if not MainInterface then return nil end

    for _, child in ipairs(MainInterface:GetChildren()) do
        if child.Name == "TextLabel" and child:IsA("TextLabel") then
            for _, innerChild in ipairs(child:GetChildren()) do
                if innerChild.Name == "TextLabel" and innerChild:IsA("TextLabel") then
                    local text = innerChild.Text
                    if text and string.match(text, "^%[.*%]$") then return text end
                end
            end
        end
    end
    return nil
end

local CurrentBiomeLabel
local HopStatusLabel
local CraftTargetLabel
local CraftStatusLabel

local function ServerHop()
    if isHopping then return end
    isHopping = true
    if HopStatusLabel then HopStatusLabel:SetDesc("Searching for a new server...") end
    if not httpRequest then
        if HopStatusLabel then HopStatusLabel:SetDesc("Executor does not support HTTP requests") end
        return
    end

    local placeId = game.PlaceId
    local cursor = nil
    local targetServer = nil

    for i = 1, 5 do
        local url = "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Desc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end
        local success, response = pcall(function() return httpRequest({Url = url, Method = "GET"}) end)
        
        if success and response.StatusCode == 200 then
            local data = HttpService:JSONDecode(response.Body)
            for _, server in pairs(data.data) do
                local function hasVisited(id)
                    for _, v in ipairs(visitedServers) do if v == id then return true end end
                    return false
                end
                if server.playing < server.maxPlayers and server.id ~= game.JobId and not hasVisited(server.id) then
                    targetServer = server.id
                    break
                end
            end
            if targetServer then break end
            cursor = data.nextPageCursor
            if not cursor then break end
        end
        task.wait(2)
    end

    if targetServer then
        if HopStatusLabel then HopStatusLabel:SetDesc("Teleporting to new server...") end
        TeleportService:TeleportToPlaceInstance(placeId, targetServer, player)
    else
        -- [FIX] เปลี่ยนจาก recursive call เป็น reset แล้วให้ loop ข้างนอกลองใหม่เอง
        -- ป้องกัน stack overflow กรณี server เต็มทุก round
        if HopStatusLabel then HopStatusLabel:SetDesc("Server not found. Resetting blocklist...") end
        visitedServers = {game.JobId}
        task.wait(3)
        isHopping = false
        -- ไม่เรียก ServerHop() ซ้ำอีก — loop biome scan จะเรียกใหม่เองในรอบถัดไป
    end
end

pcall(function() if parentGui:FindFirstChild("MerchantPro_PopupOnly") then parentGui.MerchantPro_PopupOnly:Destroy() end end)

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local function ShowGameNotification(entityName)
    local targetData = Webhooks[entityName]
    if not targetData or not targetData.Enabled then return end
    
    Fluent:Notify({
        Title = "NPC Spawned!",
        Content = entityName .. " has spawned on the map.",
        Duration = 6
    })
end

local function SendMerchantWebhook(entityName, isTestMessage, isDespawn)
    local targetData = Webhooks[entityName]
    if not targetData or not targetData.Enabled or targetData.Url == "" or not httpRequest then return end
    
    local embedColor = 3066993
    if entityName == "Rin" then embedColor = 15105570
    elseif entityName == "Jester" then embedColor = 10181046 end
    
    if isDespawn then embedColor = 16711680 end 
    
    local titleTxt = isTestMessage and "Test Notification" or (isDespawn and ("NPC Despawn Alert: " .. entityName) or ("NPC Alert: " .. entityName))
    local descTxt = isTestMessage and "Webhook system is online!" or (isDespawn and string.format("**%s** has despawned / left the map!", entityName) or string.format("**%s** has spawned on the map!\nWill despawn in 3 minutes.", entityName))
    
    local payload = {
        content = (isTestMessage or isDespawn) and "" or "@everyone",
        embeds = {{
            title = titleTxt,
            description = descTxt,
            color = embedColor,
            fields = {
                {name = "Detected By", value = "```" .. playerName .. "```", inline = true},
                {name = "NPC Name", value = "```" .. entityName .. "```", inline = true},
                {name = "Current Biome", value = "```" .. CurrentBiomeCache .. "```", inline = false}
            },
            footer = {text = "XT-HUB [1.3]"}
        }}
    }
    
    table.insert(WebhookQueue, {Url = targetData.Url, Body = payload})
    ProcessWebhookQueue()
end

local Cache = { RollsObj = nil, RollsAttr = nil, LuckObj = nil, LuckAttr = nil, LuckUI = nil, AuraObj = nil, AuraAttr = nil }

local function SendBiomeWebhook(biomeName)
    local targetData = Webhooks.Biome
    if not targetData or not targetData.Enabled or targetData.Url == "" or not httpRequest then return end

    local payload = {
        embeds = {{
            title = "🌍 Biome Alert: " .. biomeName,
            description = string.format("**%s** biome has appeared on this server!", biomeName),
            color = 3447003,
            fields = {
                {name = "Detected By", value = "```" .. playerName .. "```", inline = true},
                {name = "Biome", value = "```" .. biomeName .. "```", inline = true},
                {name = "Server", value = "```" .. tostring(game.JobId):sub(1,8) .. "...```", inline = false}
            },
            footer = {text = "XT-HUB [1.3]"}
        }}
    }
    table.insert(WebhookQueue, {Url = targetData.Url, Body = payload})
    ProcessWebhookQueue()
end

function GetPlayerRolls()
    if Cache.RollsObj and Cache.RollsObj.Parent then return Cache.RollsObj.Value end
    if Cache.RollsAttr then return player:GetAttribute(Cache.RollsAttr) or 0 end
    local totalRolls = 0
    pcall(function()
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local exactRolls = leaderstats:FindFirstChild("Rolls")
            if exactRolls and (exactRolls:IsA("IntValue") or exactRolls:IsA("NumberValue")) then
                Cache.RollsObj = exactRolls; totalRolls = exactRolls.Value; return
            end
            for _, v in pairs(leaderstats:GetChildren()) do
                if (v:IsA("IntValue") or v:IsA("NumberValue")) and (v.Name:lower():find("roll") or v.Name:lower():find("spin")) then
                    Cache.RollsObj = v; totalRolls = v.Value; return
                end
            end
        end
        for name, val in pairs(player:GetAttributes()) do
            if (name:lower():find("roll") or name:lower():find("spin")) and type(val) == "number" then
                Cache.RollsAttr = name; totalRolls = val; return
            end
        end
    end)
    return totalRolls
end

function GetPlayerLuck()
    if Cache.LuckObj and Cache.LuckObj.Parent then return Cache.LuckObj.Value end
    if Cache.LuckAttr then return player:GetAttribute(Cache.LuckAttr) or 1.00 end
    if Cache.LuckUI and Cache.LuckUI.Parent then
        local match = Cache.LuckUI.Text:match("%d+%.?%d*")
        return match and tonumber(match) or 1.00
    end
    local totalLuck = 1.00
    pcall(function()
        for _, v in pairs(player:GetChildren()) do
            if v:IsA("Folder") or v:IsA("Configuration") then
                local luckObj = v:FindFirstChild("Luck") or v:FindFirstChild("Multiplier")
                if luckObj and (luckObj:IsA("NumberValue") or luckObj:IsA("IntValue")) then
                    Cache.LuckObj = luckObj; totalLuck = luckObj.Value; return
                end
            end
        end
        if player:GetAttribute("Luck") then Cache.LuckAttr = "Luck"; totalLuck = player:GetAttribute("Luck"); return end
        if player:GetAttribute("LuckMultiplier") then Cache.LuckAttr = "LuckMultiplier"; totalLuck = player:GetAttribute("LuckMultiplier"); return end
        -- [PERF] scan mainUI เท่านั้น (เล็กกว่า playerGui 10x)
        local _mUI = getCachedMainUI() or playerGui
        for _, gui in ipairs(_mUI:GetDescendants()) do
            if gui:IsA("TextLabel") then
                if gui.Name:lower():find("luck") or gui.Text:lower():find("luck:") then
                    local match = gui.Text:match("%d+%.?%d*")
                    if match and tonumber(match) then Cache.LuckUI = gui; totalLuck = tonumber(match); return end
                end
            end
        end
    end)
    return totalLuck
end

function GetEquippedAura()
    if Cache.AuraAttr then return player:GetAttribute(Cache.AuraAttr) or "Normal" end
    if Cache.AuraObj and Cache.AuraObj.Parent then return Cache.AuraObj.Value end
    local currentAura = "Normal"
    pcall(function()
        for name, val in pairs(player:GetAttributes()) do
            if name:lower():find("aura") then Cache.AuraAttr = name; currentAura = val; return end
        end
        -- [PERF] player:GetDescendants() แพง ใช้ depth 2 แทน
        for _, child in ipairs(player:GetChildren()) do
            if child:IsA("StringValue") and child.Name:lower():find("aura") and child.Value ~= "" then
                Cache.AuraObj = child; currentAura = child.Value; return
            end
            for _, grand in ipairs(child:GetChildren()) do
                if grand:IsA("StringValue") and grand.Name:lower():find("aura") and grand.Value ~= "" then
                    Cache.AuraObj = grand; currentAura = grand.Value; return
                end
            end
        end
    end)
    return currentAura
end

local function ParseInventoryEntry(entryObj)
    local bestName, bestLen = nil, 0
    for _, node in ipairs(entryObj:GetDescendants()) do
        if node:IsA("TextLabel") or node:IsA("TextButton") then
            local textValue = TrimString(node.Text)
            if textValue ~= "" and not tonumber(textValue) and #textValue >= 2 then
                local nodeName = node.Name:lower()
                local weight = (nodeName == "auraname" and 50) or (nodeName:find("name") and 30) or (nodeName:find("title") and 20) or 0
                local scoreLen = #textValue + weight
                if scoreLen > bestLen and not IsInvalidItemName(textValue:lower()) then
                    bestLen = scoreLen; bestName = textValue
                end
            end
        end
    end
    if not bestName then return nil, nil end
    local bestCount = 1
    for _, node in ipairs(entryObj:GetDescendants()) do
        if node:IsA("TextLabel") or node:IsA("TextButton") then
            local lowerText = TrimString(node.Text):lower()
            local foundCount = lowerText:match("^x(%d+)") or lowerText:match("owned: ") or lowerText:match("owned:%s*(%d+)") or lowerText:match("^(%d+) ") or lowerText:match("owned:") or lowerText:match("(%d+)/%d+")
            if foundCount and tonumber(foundCount) then
                bestCount = tonumber(foundCount)
                local n = node.Name:lower()
                if n:find("count") or n:find("amount") or n:find("owned") then break end
            end
        end
    end
    return bestName, bestCount
end

function ScanPotions()
    local potionItems = {}
    pcall(function()
        local bankUI = playerGui:FindFirstChild("BankRework")
        if not bankUI then return end
        local materialsUI = bankUI:FindFirstChild("BankFrame") and bankUI.BankFrame:FindFirstChild("Materials")
        if not materialsUI then return end
        for _, itemProgress in ipairs(materialsUI:GetChildren()) do
            if itemProgress.Name == "ItemProgress" then
                local nameLbl = itemProgress:FindFirstChild("ItemName")
                local amountLbl = itemProgress:FindFirstChild("Amount")
                if nameLbl and amountLbl then
                    local itemName = TrimString(nameLbl.Text)
                    local countStr = TrimString(amountLbl.Text):gsub(",", ""):match("(%d+)")
                    local itemCount = countStr and tonumber(countStr) or 0
                    if itemName ~= "" and itemCount > 0 and not IsInvalidItemName(itemName:lower()) then
                        potionItems[itemName] = itemCount
                    end
                end
            end
        end
    end)
    return potionItems
end

local function GetInventoryContainer()
    local mainUI = getCachedMainUI()
    if mainUI then
        local invUI = mainUI:FindFirstChild("Inventory")
        if invUI and invUI:FindFirstChild("Items") and invUI.Items:FindFirstChild("ItemGrid") then
            return invUI.Items.ItemGrid:FindFirstChild("ItemGridScrollingFrame")
        end
    end
    return nil
end

function ScanGear()
    local gearItems = {}
    pcall(function()
        local container = GetInventoryContainer()
        if container then
            for i, entry in ipairs(container:GetChildren()) do
                if entry:IsA("Frame") or entry:IsA("ImageButton") or entry:IsA("TextButton") then
                    local itemName, itemCount = ParseInventoryEntry(entry)
                    if itemName then AddInventoryItem(gearItems, itemName, itemCount) end
                end
                if i % 10 == 0 then task.wait() end 
            end
        end
    end)
    return gearItems
end

function GetAuraTableData()
    local mainUI = getCachedMainUI()
    if not mainUI then return nil end
    local auraDataDict = {}
    local totalUniqueAuras = 0
    
    -- [PERF] หา aura collection container ก่อน แล้ว scan แค่ subtree ของมัน
    -- แทนที่จะ GetDescendants() ทั้ง MainInterface ซึ่งมีพัน object
    local auraRoot = nil
    pcall(function()
        -- aura collection มักอยู่ใน UI ที่ชื่อ "Auras", "Collection", "AuraCollection"
        for _, child in ipairs(mainUI:GetChildren()) do
            local n = child.Name:lower()
            if n:find("aura") or n:find("collection") then
                auraRoot = child
                break
            end
        end
    end)
    -- fallback: scan ทั้งหมด แต่ทำ yield ทุก 25 object ป้องกัน stall
    local searchRoot = auraRoot or mainUI

    local count = 0
    for _, obj in ipairs(searchRoot:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Name == "TextLabel" then
            if obj.Parent then
                local parentName = obj.Parent.Name
                if string.match(parentName, "^0%.%d+$") then
                    local auraText = obj.Text
                    local isMultiplierText = string.match(auraText:lower():gsub("%s+", ""), "^x%d+$")
                    if auraText ~= "" and auraText ~= "Undefined" and not isMultiplierText then
                        local uiLayoutOrder = 0
                        pcall(function() uiLayoutOrder = obj.Parent.LayoutOrder end)
                        if not auraDataDict[auraText] then auraDataDict[auraText] = {count = 0, order = uiLayoutOrder} end
                        auraDataDict[auraText].count = auraDataDict[auraText].count + 1
                        if uiLayoutOrder ~= 0 then auraDataDict[auraText].order = uiLayoutOrder end
                    end
                end
            end
        end
        count = count + 1
        if count % 30 == 0 then task.wait() end -- [PERF] yield ทุก 30 แทน 25 ลด overhead
    end
    
    local sortedAuraList = {}
    for name, data in pairs(auraDataDict) do
        table.insert(sortedAuraList, {name = name, count = data.count, order = data.order})
        totalUniqueAuras = totalUniqueAuras + 1
    end
    if totalUniqueAuras == 0 then return nil end
    table.sort(sortedAuraList, function(a, b) return a.order < b.order end)
    return sortedAuraList
end

-- ==========================================
-- ระบบคลิก + ระบบเช็คว่ากดติดหรือไม่
-- ==========================================

-- isTouchDevice: true เฉพาะมือถือที่ไม่มีคีย์บอร์ด
local isTouchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ==========================================
-- _snapState: เก็บ snapshot สถานะของปุ่มก่อนกด
-- ใช้เปรียบเทียบกับหลังกดเพื่อตรวจว่า UI ตอบสนองหรือไม่
-- ==========================================
local function _snapState(element)
    local s = { valid = false }
    pcall(function()
        if not element or not element.Parent then return end
        s.valid        = true
        s.visible      = element.Visible
        s.sizeX        = element.AbsoluteSize.X
        s.sizeY        = element.AbsoluteSize.Y
        s.posX         = element.AbsolutePosition.X
        s.posY         = element.AbsolutePosition.Y
        s.bgTrans      = element.BackgroundTransparency
        s.imgTrans     = pcall(function() return element.ImageTransparency end) and element.ImageTransparency or 0
        s.parent       = element.Parent
    end)
    return s
end

-- ==========================================
-- _isClickConfirmed: เปรียบเทียบ snapshot ก่อน/หลังกด
-- คืน true ถ้า UI มีการเปลี่ยนแปลง = กดติด
-- การเปลี่ยนแปลงที่ตรวจ:
--   1. หายไป (Visible false หรือ Parent nil)
--   2. ขนาดหด (button collapsed)
--   3. Transparency เพิ่มขึ้น (fade-out animation เริ่ม)
--   4. ตำแหน่งเปลี่ยน (slide-out animation)
-- ==========================================
local function _isClickConfirmed(element, before)
    if not before or not before.valid then return true end -- ถ้า snap ไม่ได้ ถือว่า OK
    local ok = false
    pcall(function()
        -- กรณี 1: element หาย
        if not element or not element.Parent then ok = true; return end
        if not element.Visible then ok = true; return end
        if element.AbsoluteSize.X <= 0 or element.AbsoluteSize.Y <= 0 then ok = true; return end
        -- กรณี 2: parent เปลี่ยน (re-parented หรือถูก destroy)
        if element.Parent ~= before.parent then ok = true; return end
        -- กรณี 3: Transparency เพิ่มขึ้นอย่างน้อย 0.08 (animation เริ่ม)
        if element.BackgroundTransparency - before.bgTrans > 0.08 then ok = true; return end
        -- กรณี 4: ขนาดหดลงมากกว่า 20%
        if before.sizeX > 10 and element.AbsoluteSize.X < before.sizeX * 0.8 then ok = true; return end
        -- กรณี 5: ตำแหน่งเปลี่ยนเกิน 15px (slide animation)
        local dx = math.abs(element.AbsolutePosition.X - before.posX)
        local dy = math.abs(element.AbsolutePosition.Y - before.posY)
        if dx > 15 or dy > 15 then ok = true; return end
    end)
    return ok
end

-- ==========================================
-- clickVerified: คลิกปุ่ม + เช็คเร็วสุดๆว่ากดติดไหม + retry อัตโนมัติ
--
-- element   : GuiObject ที่จะกด
-- clickFn   : ฟังก์ชันที่ใช้กด (forceCraftClick / forceFishClick / forceActionClick)
-- maxRetries: จำนวน retry สูงสุด (default 3)
-- checkDelay: รอกี่วินาทีก่อนเช็ค (default 0.08 — เร็วสุดที่ UI จะ update)
-- customCheck: (optional) function(element) → bool ถ้าต้องการเงื่อนไขพิเศษ
--
-- คืน true ถ้ากดติดภายใน maxRetries
-- ==========================================
local function clickVerified(element, clickFn, maxRetries, checkDelay, customCheck)
    if not element then return false end
    maxRetries = maxRetries or 3
    checkDelay = checkDelay or 0.08
    clickFn    = clickFn    or forceCraftClick  -- default

    for attempt = 1, maxRetries do
        -- snapshot ก่อนกด
        local before = _snapState(element)

        -- กด
        clickFn(element)

        -- รอให้ UI ตอบสนอง (0.08s = เร็วที่สุดที่ RBX render จะ update)
        task.wait(checkDelay)

        -- เช็คด้วย custom function ถ้ามี
        if customCheck then
            local ok = false
            pcall(function() ok = customCheck(element) end)
            if ok then return true end
        else
            -- เช็ค state เปลี่ยนหรือไม่
            if _isClickConfirmed(element, before) then return true end
        end

        -- ยังไม่ติด — รอเพิ่มอีกนิดก่อน retry (exponential: 0.08 → 0.13 → 0.18)
        if attempt < maxRetries then
            task.wait(checkDelay * attempt * 0.6)
        end
    end

    return false -- ครบ retry แล้วยังไม่ติด
end

-- _touchId: วน 1-8 ป้องกัน stuck touch บน executor ที่ reuse ID
local _touchId = 0
local function nextTouchId()
    _touchId = (_touchId % 8) + 1
    return _touchId
end

-- _sendClick: helper ส่ง Mouse + Touch event ไปยังพิกัดที่กำหนด
-- synchronous: caller yield 0.07s (mouse) หรือ 0.18s (mouse+touch)
-- ใช้ skipTouch=true เพื่อข้าม TouchEvent (เช่น กดปุ่ม Craft/Sell ที่ไม่ต้องการ touch ซ้อน)
local function _sendClick(cx, cy, skipTouch)
    pcall(function() vim:SendMouseButtonEvent(cx, cy, 0, true,  game, 1) end)
    task.wait(0.06)
    pcall(function() vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1) end)
    if isTouchDevice and not skipTouch then
        local tid = nextTouchId()
        task.wait(0.03)
        pcall(function() vim:SendTouchEvent(tid, Vector2.new(cx, cy), true)  end)
        task.wait(0.06)
        pcall(function() vim:SendTouchEvent(tid, Vector2.new(cx, cy), false) end)
    end
end

-- _getClickPos: แปลง AbsolutePosition → screen coordinate + clamp ในจอ
local function _getClickPos(element)
    local absPos  = element.AbsolutePosition
    local absSize = element.AbsoluteSize
    if absSize.X <= 0 or absSize.Y <= 0 then return nil, nil end
    local inset = getCachedInset()
    local vp    = camera.ViewportSize
    return math.clamp(absPos.X + absSize.X * 0.5 + inset.X, 2, vp.X - 2),
           math.clamp(absPos.Y + absSize.Y * 0.5 + inset.Y, 2, vp.Y - 2)
end

-- _fireConnections: ยิง event connections โดยตรง — เร็วที่สุดถ้า executor support
-- คืน true ถ้ายิงได้อย่างน้อย 1 connection
local function _fireConnections(element)
    if not getconnections then return false end
    local fired = false
    pcall(function()
        local btn = element
        -- walk up หา GuiButton ถ้า element เป็น ImageLabel หรือ Label
        if not btn:IsA("GuiButton") then
            local p = btn.Parent
            if p and p:IsA("GuiButton") then btn = p end
        end
        if not btn:IsA("GuiButton") then return end
        local c1 = getconnections(btn.MouseButton1Click)
        local c2 = getconnections(btn.Activated)
        for _, c in ipairs(c1) do pcall(function() c:Fire() end) end
        for _, c in ipairs(c2) do pcall(function() c:Fire() end) end
        if (#c1 + #c2) > 0 then fired = true end
    end)
    return fired
end

-- ==========================================
-- forceCraftClick — กด Craft / Sell / Dialog buttons
-- ใช้สำหรับปุ่ม UI ทั่วไป ที่ต้องการ synchronous (caller รอผล)
-- ลำดับ: connections ก่อน ถ้าไม่ได้ ค่อย coordinate
-- Mobile: ส่ง TouchEvent ด้วย (ป้องกันกรณี getconnections ไม่รองรับ)
-- ==========================================
local function forceCraftClick(element)
    if not element then return false end
    -- วิธี 1: fire connections (ไม่ block เวลา)
    local fired = _fireConnections(element)
    -- วิธี 2: coordinate click — ใช้ skipTouch=false เพื่อรองรับมือถือ
    -- ถ้า connections ยิงได้แล้ว ยังส่ง coordinate ไปเพิ่มเติมเพื่อความมั่นใจ
    -- (ป้องกันกรณี connection fire แต่ UI state ไม่อัพเดท)
    local cx, cy = _getClickPos(element)
    if cx then
        pcall(function() _sendClick(cx, cy, false) end)
    end
    return fired or (cx ~= nil)
end

-- ==========================================
-- forceFishClick — กดปุ่ม Fish / ปุ่มใน fishing UI
-- ใช้ synchronous (caller รอผล) สำหรับ step-based fishing loop (0.3s)
-- Mobile: ส่ง TouchEvent ด้วย พร้อม ID วน
-- ==========================================
local function forceFishClick(element)
    if not element then return false end
    -- วิธี 1: connections
    local fired = _fireConnections(element)
    -- วิธี 2: coordinate + touch
    local cx, cy = _getClickPos(element)
    if cx then
        pcall(function() _sendClick(cx, cy, false) end)
    end
    return fired or (cx ~= nil)
end

-- ==========================================
-- forceActionClick — กด Action Button และ Confirm (มือถือ-first)
-- synchronous: caller รอผล แล้วเช็คว่าปุ่มหายหรือยัง
-- เหมือน forceFishClick แต่ใช้ชื่อแยกเพื่อความชัดเจนในโค้ด
-- ==========================================
local function forceActionClick(element)
    if not element then return false end
    local fired = _fireConnections(element)
    local cx, cy = _getClickPos(element)
    if cx then
        pcall(function() _sendClick(cx, cy, false) end)
    end
    return fired or (cx ~= nil)
end

-- ==========================================
-- clickOnce — กด screen กลางจอ (ใช้ใน minigame loop 0.07s)
-- MUST ใช้ task.spawn — fire-and-forget ห้าม block loop
-- ถ้าทำ synchronous: loop 0.07s + task.wait(0.06) = 0.13s/รอบ → คลิกช้าลงครึ่ง
-- ==========================================
local function clickOnce()
    task.spawn(function()
        local inset = getCachedInset()
        local vp = camera.ViewportSize
        local cx = vp.X * 0.5 + inset.X
        local cy = vp.Y * 0.5 + inset.Y
        pcall(function() vim:SendMouseButtonEvent(cx, cy, 0, true,  game, 1) end)
        task.wait(0.05)
        pcall(function() vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1) end)
        -- minigame ใช้ screen-center click ไม่ต้องการ TouchEvent
        -- (minigame ตรวจ mouse position ไม่ใช่ touch)
    end)
end

local function getButtonText(btn)
    if btn:IsA("TextButton") and btn.Text ~= "" then return string.lower(btn.Text) end
    for _, child in pairs(btn:GetChildren()) do
        if child:IsA("TextLabel") and child.Text ~= "" then return string.lower(child.Text) end
    end
    return ""
end

-- ==========================================
-- [PATCHED] ระบบเดิน — แก้บัคกระโดดเพี้ยน
-- ==========================================
local function walkToTarget(targetPos, locationName)
    local char = player.Character
    local hum  = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local function computeAndWalk()
        local path = PathfindingService:CreatePath({
            AgentRadius     = 2,
            AgentHeight     = 5,
            AgentCanJump    = true,
            AgentJumpHeight = 10,
            AgentMaxSlope   = 45,
            WaypointSpacing = 6
        })

        local success, _ = pcall(function()
            path:ComputeAsync(root.Position, targetPos)
        end)
        local expectedSellState = isSellingProcess

        if not (success and path.Status == Enum.PathStatus.Success) then
            hum:MoveTo(targetPos)
            task.wait(1)
            return
        end

        local waypoints = path:GetWaypoints()
        for i = 2, #waypoints do
            if not autoFarmEnabled or isSellingProcess ~= expectedSellState then break end

            local flatRoot   = Vector3.new(root.Position.X, 0, root.Position.Z)
            local flatTarget = Vector3.new(targetPos.X,     0, targetPos.Z)
            if (flatRoot - flatTarget).Magnitude < 4 then break end

            local wp = waypoints[i]

            if wp.Action == Enum.PathWaypointAction.Jump then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
                task.wait(0.15)
            end
            hum:MoveTo(wp.Position)

            local lastPos     = root.Position
            local stuckTick   = tick()
            local wpStartTick = tick()

            while autoFarmEnabled and isSellingProcess == expectedSellState do
                local distToWp = (Vector3.new(root.Position.X, 0, root.Position.Z)
                                - Vector3.new(wp.Position.X,   0, wp.Position.Z)).Magnitude
                if distToWp < 4 then break end

                if (root.Position - lastPos).Magnitude > 0.5 then
                    lastPos   = root.Position
                    stuckTick = tick()
                end
                if tick() - stuckTick > 2.5 then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.15)
                    hum:MoveTo(wp.Position)
                    stuckTick = tick()
                end

                if tick() - wpStartTick > 6.0 then break end

                task.wait(0.1)
            end
        end
    end

    computeAndWalk()

    local flatRoot   = Vector3.new(root.Position.X, 0, root.Position.Z)
    local flatTarget = Vector3.new(targetPos.X,     0, targetPos.Z)
    if autoFarmEnabled and (flatRoot - flatTarget).Magnitude > 6 then
        task.wait(0.5)
        computeAndWalk()
    end
end

local function isCacheValid(element)
    if not element then return false end
    if not element.Parent then return false end
    if not element:IsDescendantOf(playerGui) then return false end
    local ok, visible = pcall(function() return element.Visible end)
    if not ok then return false end
    return true
end

-- ==========================================
-- [PERF] getExtraButton — ไม่ใช้ GetDescendants() fallback อีกต่อไป
-- Action Button อยู่ที่ depth 3 เสมอ: mainUI → ImageLabel → ImageLabel → ImageButton
-- scan แค่ 3 levels ด้วย GetChildren() = O(children) ไม่ใช่ O(descendants)
-- ==========================================
local function getExtraButton(mainUI)
    if cachedExtraBtn and cachedExtraBtn.Parent and cachedExtraBtn:IsDescendantOf(playerGui) then
        local ok, vis = pcall(function() return cachedExtraBtn.Visible end)
        if ok and vis and cachedExtraBtn.AbsoluteSize.X > 0 then
            return cachedExtraBtn
        end
    end
    cachedExtraBtn = nil

    -- Pass 1: exact path mainUI→ImageLabel→ImageLabel→ImageButton (depth 3)
    pcall(function()
        for _, lv1 in ipairs(mainUI:GetChildren()) do
            if lv1:IsA("ImageLabel") then
                for _, lv2 in ipairs(lv1:GetChildren()) do
                    if lv2:IsA("ImageLabel") then
                        for _, lv3 in ipairs(lv2:GetChildren()) do
                            if lv3:IsA("ImageButton") and lv3.Visible and lv3.AbsoluteSize.X > 0 then
                                cachedExtraBtn = lv3
                                return
                            end
                        end
                    end
                end
            end
        end
    end)
    if cachedExtraBtn then return cachedExtraBtn end

    -- Pass 2: depth-4 fallback (mainUI→*→ImageLabel→ImageLabel→ImageButton)
    -- [PERF] ยังคงใช้ GetChildren() เท่านั้น ไม่ใช้ GetDescendants()
    pcall(function()
        for _, lv0 in ipairs(mainUI:GetChildren()) do
            for _, lv1 in ipairs(lv0:GetChildren()) do
                if lv1:IsA("ImageLabel") then
                    for _, lv2 in ipairs(lv1:GetChildren()) do
                        if lv2:IsA("ImageLabel") then
                            for _, lv3 in ipairs(lv2:GetChildren()) do
                                if lv3:IsA("ImageButton") and lv3.Visible
                                   and lv3.AbsoluteSize.X > 20 and lv3.AbsoluteSize.Y > 20 then
                                    cachedExtraBtn = lv3
                                    return
                                end
                            end
                        end
                    end
                end
                if cachedExtraBtn then return end
            end
            if cachedExtraBtn then return end
        end
    end)

    return cachedExtraBtn
end

-- ==========================================
-- [PERF] getFishButton — แทน GetDescendants() ด้วย BFS depth-limited
-- Fish button อยู่ตื้นมาก: mainUI → Frame/ImageLabel → ImageButton[TextLabel "Fish"]
-- scan แค่ 3 levels ด้วย GetChildren() เท่านั้น
-- ==========================================
local function getFishButton(mainUI)
    if cachedFishBtn and cachedFishBtn.Parent and cachedFishBtn:IsDescendantOf(playerGui) then
        return cachedFishBtn
    end
    cachedFishBtn = nil

    local function isFishBtn(btn)
        if not (btn:IsA("ImageButton") or btn:IsA("TextButton") or btn:IsA("GuiButton")) then return false end
        -- ตรวจ Text ตรงบน btn
        if btn:IsA("TextButton") and (btn.Text == "Fish" or btn.Text:lower() == "fish") then return true end
        -- ตรวจ TextLabel ลูกของ btn
        for _, child in ipairs(btn:GetChildren()) do
            if child:IsA("TextLabel") and (child.Text == "Fish" or child.Text:lower() == "fish") then
                return true
            end
        end
        return false
    end

    -- scan depth 1-3 ด้วย GetChildren() ไม่ใช้ GetDescendants()
    for _, lv1 in ipairs(mainUI:GetChildren()) do
        if isFishBtn(lv1) then cachedFishBtn = lv1; break end
        for _, lv2 in ipairs(lv1:GetChildren()) do
            if isFishBtn(lv2) then cachedFishBtn = lv2; break end
            for _, lv3 in ipairs(lv2:GetChildren()) do
                if isFishBtn(lv3) then cachedFishBtn = lv3; break end
            end
            if cachedFishBtn then break end
        end
        if cachedFishBtn then break end
    end
    return cachedFishBtn
end

-- ==========================================
-- [PERF] getExactMinigameElements — แทน GetDescendants() ด้วย path walk
-- Minigame bar อยู่ที่ depth 4: mainUI→IL→IL→IL→IL(container)
-- เดิน path 4 levels ด้วย GetChildren() = O(children×4) แทน O(descendants)
-- ==========================================
local lastMinigameScanTime = 0
local function getExactMinigameElements()
    if isCacheValid(cachedSafeZone) and isCacheValid(cachedDiamond) then
        return cachedSafeZone, cachedDiamond
    end

    if tick() - lastMinigameScanTime < 1 then return nil, nil end
    lastMinigameScanTime = tick()

    local mainUI = getCachedMainUI()
    if not mainUI then return nil, nil end

    -- [PERF] walk path 4 levels deep ด้วย GetChildren() เท่านั้น
    -- path: mainUI → ImageLabel(lv1) → ImageLabel(lv2) → ImageLabel(lv3) → ImageLabel(container)
    -- container มี ImageLabel children ที่เป็น safezone + diamond
    for _, lv1 in ipairs(mainUI:GetChildren()) do
        if not lv1:IsA("ImageLabel") then continue end
        for _, lv2 in ipairs(lv1:GetChildren()) do
            if not lv2:IsA("ImageLabel") then continue end
            for _, lv3 in ipairs(lv2:GetChildren()) do
                if not lv3:IsA("ImageLabel") then continue end
                for _, container in ipairs(lv3:GetChildren()) do
                    if not container:IsA("ImageLabel") then continue end
                    -- ตรวจว่า container นี้มี ImageLabel children เพียงพอ
                    local validChildren = {}
                    for _, child in ipairs(container:GetChildren()) do
                        if child:IsA("ImageLabel") then
                            table.insert(validChildren, child)
                        end
                    end
                    if #validChildren >= 2 then
                        table.sort(validChildren, function(a, b) return a.AbsoluteSize.X > b.AbsoluteSize.X end)
                        cachedSafeZone = (#validChildren >= 3) and validChildren[2] or validChildren[1]
                        cachedDiamond  = validChildren[#validChildren]
                        return cachedSafeZone, cachedDiamond
                    end
                end
            end
        end
    end
    return nil, nil
end

local function isOverlapping(diamond, safezone)
    return (diamond.AbsolutePosition.X + diamond.AbsoluteSize.X >= safezone.AbsolutePosition.X) and 
           (diamond.AbsolutePosition.X <= safezone.AbsolutePosition.X + safezone.AbsoluteSize.X)
end

local vpSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
local uiWidth = math.clamp(vpSize.X - 50, 300, 580)
local uiHeight = math.clamp(vpSize.Y - 50, 250, 460)
local tabWidth = uiWidth < 450 and 120 or 160

local Window = Fluent:CreateWindow({
    Title = "XT-HUB [1.3]",
    SubTitle = "Sol's RNG",
    TabWidth = tabWidth,
    Size = UDim2.fromOffset(uiWidth, uiHeight),
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local function CreateMobileToggle()
    local ToggleGui = Instance.new("ScreenGui")
    ToggleGui.Name = "XT_MobileToggle"
    ToggleGui.ResetOnSpawn = false
    
    pcall(function()
        local core = game:GetService("CoreGui")
        if gethui then ToggleGui.Parent = gethui()
        elseif core then ToggleGui.Parent = player:WaitForChild("PlayerGui") end
    end)

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
    ToggleBtn.Position = UDim2.new(0.1, 0, 0.1, 0)
    ToggleBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 43)
    ToggleBtn.Text = "XT"
    ToggleBtn.TextColor3 = Color3.fromRGB(46, 204, 113)
    ToggleBtn.TextSize = 24
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.Parent = ToggleGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = ToggleBtn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(46, 204, 113)
    stroke.Thickness = 2
    stroke.Parent = ToggleBtn

    local dragging = false
    local dragInput, mousePos, framePos
    local startPos

    ToggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = input.Position
            mousePos = input.Position
            framePos = ToggleBtn.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    ToggleBtn.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            ToggleBtn.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
        end
    end)

    ToggleBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if startPos and (input.Position - startPos).Magnitude < 10 then
                vim:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
                task.wait()
                vim:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
            end
        end
    end)
end
CreateMobileToggle()

local Tabs = {
    Main = Window:AddTab({ Title = "Dashboard", Icon = "home" }),
    Craft = Window:AddTab({ Title = "Auto Craft", Icon = "hammer" }),
    Fishing = Window:AddTab({ Title = "Auto Fish", Icon = "anchor" }),
    Hop = Window:AddTab({ Title = "Auto Hop", Icon = "globe" }),
    Merchant = Window:AddTab({ Title = "NPC Alerts", Icon = "bell" }),
    Webhook = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local RollsLabel = Tabs.Main:AddParagraph({ Title = "Total Rolls : --" })
local LuckLabel = Tabs.Main:AddParagraph({ Title = "Current Luck : --" })
local AuraLabel = Tabs.Main:AddParagraph({ Title = "Equipped Aura : --" })

Tabs.Craft:AddParagraph({ Title = "Instructions", Content = "1. Open NPC\n2. Click 'Scan Available Items'\n3. Select up to 3 items\n4. Enable Auto Craft" })

local ScanBtn = Tabs.Craft:AddButton({
    Title = "Scan Available Items (Open NPC First)",
    Description = "Scans Gear or Item lists dynamically.",
    Callback = function()
        ScannedItemsList = {}
        ScannedItemPaths = {}
        ScannedItemBaseNames = {} 
        CachedTargetButtons = {} 
        local foundCount = 0
        local rawItems = {} 
        
        pcall(function()
            for _, gui in ipairs(player.PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") then
                    for _, desc in ipairs(gui:GetDescendants()) do
                        if (desc.Name == "Item" or desc.Name == "Gear" or desc.Name == "Lantern") and desc:IsA("GuiObject") then
                            if desc.AbsoluteSize.Y > 0 then
                                for _, child in ipairs(desc:GetChildren()) do
                                    if child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIGridLayout" and child.Name ~= "UIPadding" and child.Name ~= "Frame" then
                                        
                                        local targetBtn = nil
                                        if child:IsA("ImageButton") or child:IsA("TextButton") then
                                            targetBtn = child
                                        else
                                            targetBtn = child:FindFirstChildWhichIsA("ImageButton", true) or child:FindFirstChildWhichIsA("TextButton", true)
                                        end

                                        if targetBtn then
                                            table.insert(rawItems, {
                                                baseName = child.Name,
                                                btn = targetBtn,
                                                x = child.AbsolutePosition.X,
                                                y = child.AbsolutePosition.Y,
                                                order = child.LayoutOrder or 0
                                            })
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        
        table.sort(rawItems, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            if math.abs(a.y - b.y) > 10 then return a.y < b.y end
            return a.x < b.x
        end)

        for _, itemData in ipairs(rawItems) do
            local baseName = itemData.baseName
            local suffix = 1
            local itemName = baseName
            
            while ScannedItemPaths[itemName] do
                suffix = suffix + 1
                itemName = baseName .. " (" .. suffix .. ")"
            end

            table.insert(ScannedItemsList, itemName)
            ScannedItemPaths[itemName] = itemData.btn
            ScannedItemBaseNames[itemName] = baseName
            foundCount = foundCount + 1
        end

        if foundCount > 0 then
            if _G.MultiCraftDropdown then _G.MultiCraftDropdown:SetValues(ScannedItemsList) end
            Fluent:Notify({ Title = "Scanner", Content = "Found " .. tostring(foundCount) .. " items.", Duration = 3 })
        else
            Fluent:Notify({ Title = "Scanner", Content = "No items found. Please open NPC first.", Duration = 3 })
        end
    end
})

_G.MultiCraftDropdown = Tabs.Craft:AddDropdown("MultiCraftDropdown", {
    Title = "Select Items to Craft (Max 3)",
    Values = {},
    Multi = true,
    Default = {},
})

_G.MultiCraftDropdown:OnChanged(function(Value)
    -- [FIX] ไม่ล้าง ScannedItemPaths / ScannedItemBaseNames ที่นี่
    -- เพราะทำให้ Craft loop หาปุ่มไม่เจอ โดยเฉพาะ Item ที่มีชื่อซ้ำ (เช่น Gear (2))
    -- ล้างแค่ CachedTargetButtons ที่เป็น positional cache เท่านั้น
    CachedTargetButtons = {}

    SelectedMultiItems = {}
    local count = 0
    for k, v in pairs(Value) do
        if v then
            count = count + 1
            if count <= 3 then
                table.insert(SelectedMultiItems, k)
            else
                Fluent:Notify({ Title = "Warning", Content = "You can only select up to 3 items.", Duration = 3 })
            end
        end
    end
    multiCraftIndex = 1
    multiCraftState = "SELECT"
    _G.PopupAddAttempts = 0
end)

CraftTargetLabel = Tabs.Craft:AddParagraph({ Title = "Target", Content = "None (Recipe Closed)" })
CraftStatusLabel = Tabs.Craft:AddParagraph({ Title = "Status", Content = "Waiting" })

local AutoCraftToggle = Tabs.Craft:AddToggle("AutoCraftToggle", { Title = "Enable Auto Craft", Default = false }) 
AutoCraftToggle:OnChanged(function(Value)
    if Value and #SelectedMultiItems == 0 then
        Fluent:Notify({ Title = "Error", Content = "Please select items before enabling Auto Craft.", Duration = 3 })
        if AutoCraftToggle then AutoCraftToggle:SetValue(false) end
        masterAutoEnabled = false
        HubConfig.AutoCraft = false
        SaveConfig()
        return
    end

    masterAutoEnabled = Value
    HubConfig.AutoCraft = Value
    SaveConfig()
end)

Tabs.Fishing:AddParagraph({ Title = "⚠️ Important", Content = "Please close the Chat Box before enabling Auto Fish to prevent accidental clicks." })
local FishStatusLabel = Tabs.Fishing:AddParagraph({ Title = "Status", Content = "Idle" })
local FishBagLabel = Tabs.Fishing:AddParagraph({ Title = "Fish Status", Content = "Rounds: " .. fishingRoundCount .. " / " .. targetFishCount })

local DetectDebugLabel = Tabs.Fishing:AddParagraph({
    Title = "🔍 Real-Time UI Diagnostics",
    Content = "Diagnostics hidden. Enable 'Show Detect Overlay' to view real-time data."
})

local showDetectOverlay = false

local ShowDetectToggle = Tabs.Fishing:AddToggle("ShowDetectToggle", {
    Title = "Show Detect Overlay",
    Default = false
})
ShowDetectToggle:OnChanged(function(Value)
    showDetectOverlay = Value
end)

task.spawn(function()
    -- [PERF] diagnostics loop ช้าลงเป็น 0.5s — เป็นแค่ debug overlay ไม่ต้องถี่
    while task.wait(0.5) do
        if not DetectDebugLabel then continue end
        if not showDetectOverlay then continue end

        pcall(function()
            local mainUI = getCachedMainUI()
            if not mainUI then
                DetectDebugLabel:SetTitle("🔍 Detection Diagnostics [ERROR]")
                DetectDebugLabel:SetDesc("System Error: MainInterface not found. Are you fully loaded into the game?")
                return
            end

            local function checkUIState(targetXOff, targetXScl)
                for _, child in ipairs(mainUI:GetChildren()) do
                    if child:IsA("GuiObject") and child.Visible then
                        local xOff = child.Size.X.Offset
                        local xScl = child.Size.X.Scale
                        if math.abs(xOff - targetXOff) <= 2 or math.abs(xScl - targetXScl) <= 0.005 then
                            local bg = child.BackgroundTransparency
                            return bg <= 0.6 and "Active ✅" or "Standby ⏳"
                        end
                    end
                end
                return "Not Detected ❌"
            end

            local function checkActionState()
                for _, child in ipairs(mainUI:GetChildren()) do
                    if child:IsA("GuiObject") and child.Visible then
                        local xOff = child.Size.X.Offset
                        local xScl = child.Size.X.Scale
                        if math.abs(xOff - 250) <= 2 or math.abs(xScl - 0.185) <= 0.005 then
                            local bg1 = child.BackgroundTransparency
                            -- [PERF] ลบ task.wait(0.08) ออกจาก loop
                            -- diagnostics ไม่ต้องการ realtime anim check แค่แสดง state ปัจจุบัน
                            local isActive = bg1 <= 0.6
                            if isActive then
                                return "Ready to Click ✅"
                            else
                                return "Standby ⏳"
                            end
                        end
                    end
                end
                return "Not Detected ❌"
            end

            local fishStatus  = checkUIState(201, 0.122)
            local miniStatus  = checkUIState(230, 0.140)
            local actStatus   = checkActionState()

            local actionPosStatus = "Unavailable"
            pcall(function()
                for _, lv1 in ipairs(mainUI:GetChildren()) do
                    if lv1:IsA("ImageLabel") then
                        for _, lv2 in ipairs(lv1:GetChildren()) do
                            if lv2:IsA("ImageLabel") then
                                for _, lv3 in ipairs(lv2:GetChildren()) do
                                    if lv3:IsA("ImageButton") and lv3.Visible then
                                        local pos = lv3.Position
                                        local xScaleOK = math.abs(pos.X.Scale - 1) < 0.05
                                        local xOffOK   = math.abs(pos.X.Offset)    < 5
                                        local yOK      = math.abs(pos.Y.Scale)      < 0.05 and math.abs(pos.Y.Offset) < 5
                                        local ready = xScaleOK and xOffOK and yOK
                                        actionPosStatus = ready and "In Position ✅" or "Moving... 🔄"
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end)

            DetectDebugLabel:SetTitle("🔍 Real-Time UI Diagnostics")
            DetectDebugLabel:SetDesc(
                "▶ Fishing Interface    :  " .. fishStatus .. "\n" ..
                "▶ Minigame Event       :  " .. miniStatus .. "\n" ..
                "▶ Action Button        :  " .. actStatus .. "\n" ..
                "▶ Button Alignment     :  " .. actionPosStatus .. "\n\n" ..
                "Current Sequence Step  :  " .. tostring(fishingStep)
            )
        end)
    end
end)


local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "DetectOverlayGui"
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlayGui.DisplayOrder = 999
pcall(function()
    overlayGui.Parent = (gethui and gethui()) or playerGui
end)
if not overlayGui.Parent then overlayGui.Parent = playerGui end

local function makeBox(name, color)
    local box = {}
    local sides = {"Top","Bottom","Left","Right"}
    for _, side in ipairs(sides) do
        local f = Instance.new("Frame")
        f.Name = name .. "_" .. side
        f.BackgroundColor3 = color
        f.BorderSizePixel = 0
        f.ZIndex = 1000
        f.Parent = overlayGui
        box[side] = f
    end
    return box
end

local function updateBox(box, ax, ay, aw, ah, thickness)
    thickness = thickness or 2
    box.Top.Position    = UDim2.new(0, ax,           0, ay)
    box.Top.Size        = UDim2.new(0, aw,            0, thickness)
    box.Bottom.Position = UDim2.new(0, ax,           0, ay + ah - thickness)
    box.Bottom.Size     = UDim2.new(0, aw,            0, thickness)
    box.Left.Position   = UDim2.new(0, ax,           0, ay)
    box.Left.Size       = UDim2.new(0, thickness,     0, ah)
    box.Right.Position  = UDim2.new(0, ax + aw - thickness, 0, ay)
    box.Right.Size      = UDim2.new(0, thickness,     0, ah)
end

local function setBoxVisible(box, visible)
    for _, f in pairs(box) do f.Visible = visible end
end

local boxFish     = makeBox("Fish",     Color3.fromRGB(80,  200, 120))
local boxMini     = makeBox("Minigame", Color3.fromRGB(80,  160, 255))
local boxAction   = makeBox("Action",   Color3.fromRGB(255, 180,  50))
local boxConfirm  = makeBox("Confirm",  Color3.fromRGB(255,  80,  80))

local function makeLabel(name, color)
    local lbl = Instance.new("TextLabel")
    lbl.Name = name .. "_Label"
    lbl.BackgroundColor3 = color
    lbl.BackgroundTransparency = 0.3
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.Size = UDim2.new(0, 60, 0, 16)
    lbl.ZIndex = 1001
    lbl.Text = name
    lbl.Parent = overlayGui
    return lbl
end

local lblFish    = makeLabel("Fish",     Color3.fromRGB(80,  200, 120))
local lblMini    = makeLabel("Minigame", Color3.fromRGB(80,  160, 255))
local lblAction  = makeLabel("Action",   Color3.fromRGB(255, 180,  50))
local lblConfirm = makeLabel("Confirm",  Color3.fromRGB(255,  80,  80))

local inset = getCachedInset()

-- [FIX] ช้าลงจาก 0.1s → 0.25s ลด CPU ลงครึ่งนึง
-- และ skip งานทั้งหมดทันทีถ้า overlay ปิด (เดิมยังวน loop hide ทุก 0.1s อยู่)
task.spawn(function()
    local overlayWasVisible = false
    -- [PERF] 0.35s แทน 0.25s — visual overlay ไม่ต้องอัพเดท 4x/วินาที, 3x พอ
    while task.wait(0.35) do
        if not showDetectOverlay then
            if overlayWasVisible then
                overlayWasVisible = false
                setBoxVisible(boxFish, false)
                setBoxVisible(boxMini, false)
                setBoxVisible(boxAction, false)
                setBoxVisible(boxConfirm, false)
                lblFish.Visible, lblMini.Visible, lblAction.Visible, lblConfirm.Visible = false, false, false, false
            end
            continue
        end
        overlayWasVisible = true

        pcall(function()
            local mainUI = getCachedMainUI()
            if not mainUI then
                setBoxVisible(boxFish, false); setBoxVisible(boxMini, false)
                setBoxVisible(boxAction, false); setBoxVisible(boxConfirm, false)
                lblFish.Visible, lblMini.Visible, lblAction.Visible, lblConfirm.Visible = false, false, false, false
                return
            end

            -- [PERF] รวม 4 passes GetChildren() เป็น pass เดียว
            local fishFound, miniFound = false, false
            for _, child in ipairs(mainUI:GetChildren()) do
                if not (child:IsA("GuiObject") and child.Visible) then continue end
                local xOff, xScl = child.Size.X.Offset, child.Size.X.Scale
                if not fishFound and (math.abs(xOff - 201) <= 2 or math.abs(xScl - 0.122) <= 0.005) then
                    local ap, as = child.AbsolutePosition, child.AbsoluteSize
                    updateBox(boxFish, ap.X, ap.Y + inset.Y, as.X, as.Y)
                    setBoxVisible(boxFish, true)
                    lblFish.Position = UDim2.new(0, ap.X, 0, ap.Y + inset.Y - 16)
                    lblFish.Visible = true
                    fishFound = true
                end
                if not miniFound and (math.abs(xOff - 230) <= 2 or math.abs(xScl - 0.140) <= 0.005) then
                    local ap, as = child.AbsolutePosition, child.AbsoluteSize
                    updateBox(boxMini, ap.X, ap.Y + inset.Y, as.X, as.Y)
                    setBoxVisible(boxMini, true)
                    lblMini.Position = UDim2.new(0, ap.X, 0, ap.Y + inset.Y - 16)
                    lblMini.Visible = true
                    miniFound = true
                end
                if fishFound and miniFound then break end
            end
            if not fishFound then setBoxVisible(boxFish, false); lblFish.Visible = false end
            if not miniFound then setBoxVisible(boxMini, false); lblMini.Visible = false end

            local actionFound = false
            for _, lv1 in ipairs(mainUI:GetChildren()) do
                if not lv1:IsA("ImageLabel") then continue end
                for _, lv2 in ipairs(lv1:GetChildren()) do
                    if not lv2:IsA("ImageLabel") then continue end
                    for _, lv3 in ipairs(lv2:GetChildren()) do
                        if lv3:IsA("ImageButton") and lv3.Visible and lv3.AbsoluteSize.X > 0 then
                            local ap, as = lv3.AbsolutePosition, lv3.AbsoluteSize
                            updateBox(boxAction, ap.X, ap.Y + inset.Y, as.X, as.Y, 2)
                            setBoxVisible(boxAction, true)
                            lblAction.Position = UDim2.new(0, ap.X, 0, ap.Y + inset.Y - 16)
                            lblAction.Visible = true
                            actionFound = true

                            local confirmFound = false
                            for _, child in ipairs(lv3:GetChildren()) do
                                if child:IsA("ImageLabel") and child.Visible and child.AbsoluteSize.X > 0 then
                                    local cap, cas = child.AbsolutePosition, child.AbsoluteSize
                                    updateBox(boxConfirm, cap.X, cap.Y + inset.Y, cas.X, cas.Y, 2)
                                    setBoxVisible(boxConfirm, true)
                                    lblConfirm.Position = UDim2.new(0, cap.X, 0, cap.Y + inset.Y - 16)
                                    lblConfirm.Visible = true
                                    confirmFound = true
                                    break
                                end
                            end
                            if not confirmFound then setBoxVisible(boxConfirm, false); lblConfirm.Visible = false end
                            break
                        end
                    end
                    if actionFound then break end
                end
                if actionFound then break end
            end
            if not actionFound then
                setBoxVisible(boxAction, false); lblAction.Visible = false
                setBoxVisible(boxConfirm, false); lblConfirm.Visible = false
            end
        end)
    end
end)

local AutoFishToggle = Tabs.Fishing:AddToggle("AutoFishToggle", { Title = "Enable Auto Fish", Default = HubConfig.AutoFish })
AutoFishToggle:OnChanged(function(Value)
    autoFarmEnabled = Value
    HubConfig.AutoFish = Value
    SaveConfig()
    
    if not Value then
        FishStatusLabel:SetDesc("Status: Idle")
        isAtTarget = false
        hasArrivedAtSell = false
        isResettingUI = false 
        fishingStep = 0
        hasMinigameMoved = false
        
        cachedSafeZone, cachedDiamond, cachedExtraBtn, cachedFishBtn = nil, nil, nil, nil

        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid:MoveTo(player.Character.HumanoidRootPart.Position)
        end
    else
        FishStatusLabel:SetDesc("Initializing Farm...")
    end
end)

local AutoSellToggle = Tabs.Fishing:AddToggle("AutoSellToggle", { Title = "Enable Auto Sell", Default = HubConfig.AutoSell })
AutoSellToggle:OnChanged(function(Value)
    autoSellEnabled = Value
    HubConfig.AutoSell = Value
    SaveConfig()
    if not Value then
        isSellingProcess = false
    end
end)

local FishLimitInput = Tabs.Fishing:AddInput("FishLimitInput", {
    Title = "Max Rounds Before Sell",
    Default = tostring(HubConfig.MaxFish),
    Placeholder = "50",
    Numeric = true,
    Finished = true,
    Callback = function(Value)
        local num = tonumber(Value)
        if num and num > 0 then
            targetFishCount = num
            HubConfig.MaxFish = num
            SaveConfig()
            if FishBagLabel then FishBagLabel:SetDesc("Rounds: " .. fishingRoundCount .. " / " .. targetFishCount) end
        end
    end
})

CurrentBiomeLabel = Tabs.Hop:AddParagraph({ Title = "Current Biome", Content = "Scanning..." })
HopStatusLabel = Tabs.Hop:AddParagraph({ Title = "Status", Content = "Idle" })

local HopDropdown = Tabs.Hop:AddDropdown("HopBiomeDropdown", { Title = "Select Target Biome", Values = biomeNames, Multi = false, Default = HubConfig.HopBiome })
HopDropdown:OnChanged(function(Value)
    targetBiome = Value
    HubConfig.HopBiome = Value
    SaveConfig()
end)

local AutoHopToggle = Tabs.Hop:AddToggle("AutoHopToggle", { Title = "Enable Auto Server Hop", Default = false }) 
AutoHopToggle:OnChanged(function(Value)
    enableAutoHop = Value
    HubConfig.AutoHop = Value
    SaveConfig()
end)

local MariInput = Tabs.Merchant:AddInput("MariUrlInput", { Title = "Mari Webhook URL", Default = HubConfig.MariUrl, Placeholder = "Webhook URL...", Numeric = false, Finished = true })
MariInput:OnChanged(function(Value) Webhooks.Mari.Url = Value; HubConfig.MariUrl = Value; SaveConfig() end)
local MariToggle = Tabs.Merchant:AddToggle("MariToggle", { Title = "Enable Mari Alert", Default = HubConfig.MariOn })
MariToggle:OnChanged(function(Value) Webhooks.Mari.Enabled = Value; HubConfig.MariOn = Value; SaveConfig() end)
Tabs.Merchant:AddButton({
    Title = "Test Mari Webhook",
    Callback = function()
        local oldState = Webhooks.Mari.Enabled
        Webhooks.Mari.Enabled = true
        SendMerchantWebhook("Mari", true, false)
        Webhooks.Mari.Enabled = oldState
        Fluent:Notify({ Title = "Webhook Test", Content = "Test payload sent for Mari.", Duration = 3 })
    end
})

local RinInput = Tabs.Merchant:AddInput("RinUrlInput", { Title = "Rin Webhook URL", Default = HubConfig.RinUrl, Placeholder = "Webhook URL...", Numeric = false, Finished = true })
RinInput:OnChanged(function(Value) Webhooks.Rin.Url = Value; HubConfig.RinUrl = Value; SaveConfig() end)
local RinToggle = Tabs.Merchant:AddToggle("RinToggle", { Title = "Enable Rin Alert", Default = HubConfig.RinOn })
RinToggle:OnChanged(function(Value) Webhooks.Rin.Enabled = Value; HubConfig.RinOn = Value; SaveConfig() end)
Tabs.Merchant:AddButton({
    Title = "Test Rin Webhook",
    Callback = function()
        local oldState = Webhooks.Rin.Enabled
        Webhooks.Rin.Enabled = true
        SendMerchantWebhook("Rin", true, false)
        Webhooks.Rin.Enabled = oldState
        Fluent:Notify({ Title = "Webhook Test", Content = "Test payload sent for Rin.", Duration = 3 })
    end
})

local JesterInput = Tabs.Merchant:AddInput("JesterUrlInput", { Title = "Jester Webhook URL", Default = HubConfig.JesterUrl, Placeholder = "Webhook URL...", Numeric = false, Finished = true })
JesterInput:OnChanged(function(Value) Webhooks.Jester.Url = Value; HubConfig.JesterUrl = Value; SaveConfig() end)
local JesterToggle = Tabs.Merchant:AddToggle("JesterToggle", { Title = "Enable Jester Alert", Default = HubConfig.JesterOn })
JesterToggle:OnChanged(function(Value) Webhooks.Jester.Enabled = Value; HubConfig.JesterOn = Value; SaveConfig() end)
Tabs.Merchant:AddButton({
    Title = "Test Jester Webhook",
    Callback = function()
        local oldState = Webhooks.Jester.Enabled
        Webhooks.Jester.Enabled = true
        SendMerchantWebhook("Jester", true, false)
        Webhooks.Jester.Enabled = oldState
        Fluent:Notify({ Title = "Webhook Test", Content = "Test payload sent for Jester.", Duration = 3 })
    end
})

local WhIntervalSlider = Tabs.Webhook:AddSlider("WhInterval", { Title = "Send Interval (Seconds)", Description = "Time between saves", Default = HubConfig.WhInterval, Min = 10, Max = 60, Rounding = 1 })
WhIntervalSlider:OnChanged(function(Value) 
    saveIntervalSeconds = tonumber(Value) or 60
    HubConfig.WhInterval = saveIntervalSeconds
    SaveConfig() 
end)

local ScanDelaySlider = Tabs.Webhook:AddSlider("ScanDelay", { 
    Title = "Scanner Cooldown (Reduce Lag)", 
    Description = "Increase this if your game is lagging (Seconds)", 
    Default = HubConfig.ScanDelay or 2.5, 
    Min = 0.5, 
    Max = 5.0, 
    Rounding = 1 
})
ScanDelaySlider:OnChanged(function(Value) 
    scanCooldown = tonumber(Value) or 2.5
    HubConfig.ScanDelay = scanCooldown
    SaveConfig() 
end)

local WebhookToggle = Tabs.Webhook:AddToggle("WebhookToggle", { Title = "Enable Auto-Save Data to Web", Default = HubConfig.WhOn })
WebhookToggle:OnChanged(function(Value) isInfoWebhookEnabled = Value; HubConfig.WhOn = Value; SaveConfig() end)

local WebNameLabel = Tabs.Webhook:AddParagraph({ Title = "Web Display Name", Content = (isIncognitoMode and incognitoFakeName or playerName) })
local IncognitoToggle = Tabs.Webhook:AddToggle("IncognitoToggle", { Title = "Enable Incognito Mode (Hide Name)", Default = HubConfig.Incognito })
IncognitoToggle:OnChanged(function(Value)
    isIncognitoMode = Value
    HubConfig.Incognito = Value
    SaveConfig()
    if Value then
        WebNameLabel:SetDesc(incognitoFakeName)
    else
        WebNameLabel:SetDesc(playerName)
    end
end)

Tabs.Webhook:AddParagraph({ Title = "Information", Content = "Developed by XT-HUB [1.3]" })

-- ==========================================
-- [ADD] Biome Webhook UI
-- ==========================================
Tabs.Merchant:AddParagraph({ Title = "── Biome Alert ──", Content = "แจ้งเตือนผ่าน Webhook เมื่อ Biome ที่ต้องการปรากฏบนเซิร์ฟเวอร์นี้" })

local BiomeInput = Tabs.Merchant:AddInput("BiomeUrlInput", {
    Title = "Biome Alert Webhook URL",
    Default = HubConfig.BiomeUrl or "",
    Placeholder = "Webhook URL...",
    Numeric = false,
    Finished = true
})
BiomeInput:OnChanged(function(Value)
    Webhooks.Biome.Url = Value
    HubConfig.BiomeUrl = Value
    SaveConfig()
end)

local BiomeWhDropdown = Tabs.Merchant:AddDropdown("BiomeWhDropdown", {
    Title = "Target Biome to Alert",
    Values = biomeNames,
    Multi = false,
    Default = HubConfig.BiomeTarget or "Heaven"
})
BiomeWhDropdown:OnChanged(function(Value)
    HubConfig.BiomeTarget = Value
    SaveConfig()
end)

local BiomeToggle = Tabs.Merchant:AddToggle("BiomeToggle", {
    Title = "Enable Biome Alert",
    Default = HubConfig.BiomeOn or false
})
BiomeToggle:OnChanged(function(Value)
    Webhooks.Biome.Enabled = Value
    HubConfig.BiomeOn = Value
    SaveConfig()
end)

Tabs.Merchant:AddButton({
    Title = "Test Biome Webhook",
    Callback = function()
        local oldState = Webhooks.Biome.Enabled
        Webhooks.Biome.Enabled = true
        SendBiomeWebhook(CurrentBiomeCache ~= "" and CurrentBiomeCache or "Normal")
        Webhooks.Biome.Enabled = oldState
        Fluent:Notify({ Title = "Webhook Test", Content = "Test Biome payload sent.", Duration = 3 })
    end
})

Window:SelectTab(1)

task.spawn(function()
    local lastBiomeForWebhook = ""
    while task.wait(scanCooldown) do
        local currentText = GetRealBiomeText()
        if currentText then
            local cleanBiome = currentText:gsub("%[", ""):gsub("%]", ""):match("^%s*(.-)%s*$")
            cleanBiome = cleanBiome:lower():gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest:lower() end)
            CurrentBiomeCache = cleanBiome

            -- [ADD] Biome Webhook: แจ้งเตือนเมื่อ Biome เปลี่ยนเป็น target ที่ตั้งไว้
            if Webhooks.Biome.Enabled and Webhooks.Biome.Url ~= "" then
                local biomeTarget = HubConfig.BiomeTarget or "Heaven"
                if cleanBiome == biomeTarget and lastBiomeForWebhook ~= biomeTarget then
                    SendBiomeWebhook(cleanBiome)
                    Fluent:Notify({ Title = "Biome Alert!", Content = biomeTarget .. " biome detected! Webhook sent.", Duration = 6 })
                end
            end
            lastBiomeForWebhook = cleanBiome
        else
            CurrentBiomeCache = "Normal"
            lastBiomeForWebhook = "Normal"
        end

        if CurrentBiomeLabel then CurrentBiomeLabel:SetDesc(CurrentBiomeCache) end

        if not enableAutoHop or isHopping then continue end
        if currentText then
            local lowerText = string.lower(currentText)
            local keywords = BiomeList[targetBiome] or {"heaven"} 
            local isFound = false
            for _, kw in ipairs(keywords) do
                if string.find(lowerText, kw) then isFound = true; break end
            end
            
            if isFound then
                if HopStatusLabel then HopStatusLabel:SetDesc("Found Biome: " .. currentText) end
            else
                if HopStatusLabel then HopStatusLabel:SetDesc("Skipping: " .. currentText) end
                task.wait(1)
                ServerHop()
            end
        else
            if HopStatusLabel then HopStatusLabel:SetDesc("Scanning...") end
        end
    end
end)

local DetectQueue = {}
local isProcessingDetect = false

local function ProcessDetectQueue()
    if isProcessingDetect then return end
    isProcessingDetect = true
    task.spawn(function()
        while #DetectQueue > 0 do
            local entityName = table.remove(DetectQueue, 1)
            
            table.insert(NPCHistoryList, 1, {
                name = entityName,
                biome = CurrentBiomeCache,
                timestamp = os.time()
            })
            if #NPCHistoryList > 20 then table.remove(NPCHistoryList, 21) end
            
            SendMerchantWebhook(entityName, false, false)
            ShowGameNotification(entityName)
            
            -- [PERF] task.delay ไม่ leak coroutine ต่างจาก task.spawn(task.wait(180))
            task.delay(180, function()
                SendMerchantWebhook(entityName, false, true)
            end)

            task.wait(3)
        end
        isProcessingDetect = false
    end)
end

local function HandleNPCDetection(entityName)
    if entityName and entityName ~= lastDetectedNPC then
        lastDetectedNPC = entityName
        table.insert(DetectQueue, entityName)
        ProcessDetectQueue()
        task.delay(10, function() lastDetectedNPC = "" end)
    end
end

function SendToWebAPI(combinedItems, aurasTable, auraRollJson)
    if CustomWebAPIUrl == "" then return end
    if not httpRequest then 
        return 
    end
    
    local success, payload = pcall(function()
        return {
            roblox_id = player.UserId,
            username = playerName,
            is_incognito = isIncognitoMode,
            rolls = tonumber(GetPlayerRolls()) or 0, 
            luck = tonumber(GetPlayerLuck()) or 1, 
		    equipped_aura = GetEquippedAura() or "Normal", 
            auto_fish = autoFarmEnabled,                   
            auto_sell = autoSellEnabled,                   
            fish_limit = targetFishCount,                  
            sell_count = totalSellCount,                   
            inventory = combinedItems or {},
            auras = aurasTable or {}, 
            aura_roll = auraRollJson or "[]",
            current_biome = CurrentBiomeCache,
            craft_target = CurrentCraftTarget,
            craft_ready = IsCraftReady,
            craft_materials = CurrentCraftMaterials, 
            craft_count = CraftSessionCount,
            craft_logs = CraftLogs,
            auto_craft_enabled = masterAutoEnabled, 
            npc_history = HttpService:JSONEncode(NPCHistoryList)
        }
    end)

    if not success then return end
    
    table.insert(ApiQueue, payload)
    ProcessApiQueue()
end

if TextChatService then
    TextChatService.MessageReceived:Connect(function(message)
        if not message.Text then return end
        
        if not enableAuraDetect and not string.find(message.Text, "merchant") then return end

        local cleanText = StripRichText(message.Text)
        local lowerMsg = cleanText:lower()

        if lowerMsg:find("%[merchant%]") then
            if lowerMsg:find("mari") then HandleNPCDetection("Mari")
            elseif lowerMsg:find("rin") then HandleNPCDetection("Rin")
            elseif lowerMsg:find("jester") then HandleNPCDetection("Jester") end
        end

        if enableAuraDetect then
            local playerPart, auraPart, chancePart = cleanText:match("^(.-)%s*HAS FOUND(.-), CHANCE OF 1 IN (.+)")
            if playerPart and chancePart then
                if playerPart:find(player.Name) or playerPart:find(player.DisplayName) then
                    local cleanNumStr = chancePart:gsub("%D", "") 
                    local rarity = tonumber(cleanNumStr) or 0
                    
                    if rarity >= minAuraRarity and rarity <= maxAuraRarity then
                        local finalAuraName = CleanAuraName(auraPart)
                        table.insert(AuraQueue, {name = finalAuraName, rarity = rarity, timestamp = os.time()})
                    end
                end
            end
        end
    end)
end

-- [FIX] ChildAdded ตรวจแค่ลูกตรงๆ ของ Workspace
-- ถ้า NPC อยู่ใน folder จะไม่ถูก detect เลย
-- เพิ่ม DescendantAdded + scan loop เป็น backup

local npcNames = {Mari = true, Rin = true, Jester = true}

-- [PERF] NPC tracking ด้วย events แทน GetDescendants() loop
-- GetDescendants() บน Workspace มีพัน object — เรียกทุก 5s กิน CPU มาก
-- ใช้ DescendantAdded/DescendantRemoving แทน: O(1) ต่อเหตุการณ์
local _npcPresent = {}  -- track NPC ที่อยู่ใน workspace ตอนนี้

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") and npcNames[obj.Name] then
        task.wait(0.1)
        if obj.Parent and not _npcPresent[obj.Name] then
            _npcPresent[obj.Name] = obj
            HandleNPCDetection(obj.Name)
        end
    end
end)

Workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("Model") and npcNames[obj.Name] then
        if _npcPresent[obj.Name] == obj then
            _npcPresent[obj.Name] = nil
        end
    end
end)

-- backup scan: ทุก 15s (ไม่ใช่ 5s) เฉพาะกรณี event miss
-- [PERF] ใช้ GetChildren() ของแต่ละ folder ใน Workspace แทน GetDescendants()
-- ถ้าไม่เจอใน children ระดับแรก ค่อย scan descendants แค่ folder ที่น่าสงสัย
task.spawn(function()
    while task.wait(15) do
        pcall(function()
            -- เคลียร์ NPC ที่ event อาจ miss
            for name, obj in pairs(_npcPresent) do
                if not obj or not obj.Parent then
                    _npcPresent[name] = nil
                end
            end
            -- scan เฉพาะ direct children + 1 level deep (ไม่ full descendants)
            for _, child in ipairs(Workspace:GetChildren()) do
                if child:IsA("Model") and npcNames[child.Name] and child.Parent then
                    if not _npcPresent[child.Name] then
                        _npcPresent[child.Name] = child
                        HandleNPCDetection(child.Name)
                    end
                    continue
                end
                -- folder/model ที่อาจห่อ NPC ไว้ข้างใน
                if child:IsA("Folder") or child:IsA("Model") then
                    for _, inner in ipairs(child:GetChildren()) do
                        if inner:IsA("Model") and npcNames[inner.Name] and inner.Parent then
                            if not _npcPresent[inner.Name] then
                                _npcPresent[inner.Name] = inner
                                HandleNPCDetection(inner.Name)
                            end
                        end
                    end
                end
            end
        end)
    end
end)

local function AutoSaveToWebAPI()
    task.spawn(function()
        local combinedItems = {}
        for k, v in pairs(ScanGear()) do combinedItems[k] = v end
        task.wait(0.2)
        for k, v in pairs(ScanPotions()) do combinedItems[k] = (combinedItems[k] or 0) + v end
        task.wait(0.2)
        local aurasData = GetAuraTableData()
        
        SendToWebAPI(combinedItems, aurasData, "[]")
    end)
end

task.spawn(function()
    while task.wait(5) do
        if #AuraQueue > 0 then
            local aurasToProcess = {}
            for _, v in ipairs(AuraQueue) do table.insert(aurasToProcess, v) end
            AuraQueue = {}
            
            local success, jsonStr = pcall(function() return HttpService:JSONEncode(aurasToProcess) end)
            if success then
                lastAuraRollJson = jsonStr
                task.spawn(function()
                    local inv = {}
                    for k, v in pairs(ScanGear()) do inv[k] = v end
                    task.wait(0.2)
                    for k, v in pairs(ScanPotions()) do inv[k] = (inv[k] or 0) + v end
                    task.wait(0.2)
                    SendToWebAPI(inv, GetAuraTableData(), lastAuraRollJson)
                end)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(15) do
        pcall(function()
            if RollsLabel then RollsLabel:SetTitle("Total Rolls : " .. FormatNumber(GetPlayerRolls())) end
            if LuckLabel then LuckLabel:SetTitle("Current Luck : x" .. string.format("%.2f", tonumber(GetPlayerLuck()) or 1)) end
            if AuraLabel then AuraLabel:SetTitle("Equipped Aura : " .. tostring(GetEquippedAura())) end
        end)
    end
end)

local lastWebhookSendTick = tick()
task.spawn(function()
    while task.wait(5) do
        local safeInterval = tonumber(saveIntervalSeconds) or 60
        if isInfoWebhookEnabled and (tick() - lastWebhookSendTick >= safeInterval) then
            lastWebhookSendTick = tick()
            task.spawn(AutoSaveToWebAPI)
        end
    end
end)

local function ProcessPopupIngredients(popupRoot)
    local scrollingFrame = nil
    for _, child in pairs(popupRoot:GetDescendants()) do
        if child:IsA("ScrollingFrame") then
            scrollingFrame = child
            break
        end
    end

    local allReady = true
    local clickedAdd = false

    local addButtons = {}
    for _, btn in pairs(popupRoot:GetDescendants()) do
        if btn:IsA("GuiButton") and btn.Visible then
            local txt = string.lower(TrimString(getButtonText(btn)))
            if txt == "add" then
                table.insert(addButtons, btn)
            end
        end
    end

    table.sort(addButtons, function(a, b)
        return a.AbsolutePosition.Y < b.AbsolutePosition.Y
    end)

    for _, addBtn in ipairs(addButtons) do
        local foundRatioOrCheck = false
        local isComplete = false
        
        local function checkNodeForCompletion(node)
            local _found = false
            local _complete = false
            for _, lbl in pairs(node:GetDescendants()) do
                if lbl:IsA("TextLabel") then
                    local rawTxt = lbl.Text
                    pcall(function() if lbl.ContentText and lbl.ContentText ~= "" then rawTxt = lbl.ContentText end end)
                    local txt = string.gsub(StripRichText(rawTxt), ",", "")
                    local c, r = string.match(txt, "(%d+)%s*/%s*(%d+)")
                    if c and r then
                        _found = true
                        if tonumber(c) >= tonumber(r) then _complete = true end
                        break
                    end
                end
            end
            if not _found then
                for _, img in pairs(node:GetDescendants()) do
                    if img:IsA("ImageLabel") then
                        local imgName = string.lower(img.Name)
                        if string.find(imgName, "check") or string.find(imgName, "tick") or string.find(imgName, "success") or img.ImageColor3 == Color3.fromRGB(0, 255, 0) or img.ImageColor3 == Color3.fromRGB(85, 255, 0) then
                            _found = true
                            _complete = true
                            break
                        end
                    end
                end
            end
            return _found, _complete
        end

        foundRatioOrCheck, isComplete = checkNodeForCompletion(addBtn.Parent)
        if not foundRatioOrCheck and addBtn.Parent and addBtn.Parent.Parent then
            foundRatioOrCheck, isComplete = checkNodeForCompletion(addBtn.Parent.Parent)
        end
        if not foundRatioOrCheck and addBtn.Parent and addBtn.Parent.Parent and addBtn.Parent.Parent.Parent then
            foundRatioOrCheck, isComplete = checkNodeForCompletion(addBtn.Parent.Parent.Parent)
        end

        if not foundRatioOrCheck then
            isComplete = false
        end

        if not isComplete then
            allReady = false
            
            if scrollingFrame then
                local maxCanvasY = 99999
                pcall(function()
                    if scrollingFrame.AbsoluteCanvasSize and scrollingFrame.AbsoluteCanvasSize.Y > 0 then
                        maxCanvasY = math.max(0, scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y)
                    elseif scrollingFrame.CanvasSize.Y.Offset > 0 then
                        maxCanvasY = math.max(0, scrollingFrame.CanvasSize.Y.Offset - scrollingFrame.AbsoluteWindowSize.Y)
                    end
                end)

                local btnY = addBtn.AbsolutePosition.Y
                local scrollY = scrollingFrame.AbsolutePosition.Y
                local scrollHeight = scrollingFrame.AbsoluteWindowSize and scrollingFrame.AbsoluteWindowSize.Y or scrollingFrame.AbsoluteSize.Y
                
                if btnY < scrollY - 10 or btnY + addBtn.AbsoluteSize.Y > scrollY + scrollHeight + 10 then
                    local targetCanvasY = scrollingFrame.CanvasPosition.Y + (btnY - scrollY) - (scrollHeight / 2)
                    targetCanvasY = math.clamp(targetCanvasY, 0, maxCanvasY)
                    
                    scrollingFrame.CanvasPosition = Vector2.new(0, targetCanvasY)
                    task.wait(0.3) 
                end
            end

            forceCraftClick(addBtn) 
            clickedAdd = true
            task.wait(0.4) 
        end
    end

    return allReady, clickedAdd
end

local cachedRecipeHolder = nil
local cachedButtons = { open = nil, auto = nil, craft = nil }

local function isObjectActuallyVisible(obj)
    local current = obj
    while current and current ~= game do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end
    return true
end

_G.IsCraftingExpected = false

task.spawn(function()
    while task.wait(scanCooldown) do
        if not masterAutoEnabled then
            if CraftStatusLabel then CraftStatusLabel:SetDesc("Idle (Auto Craft Off)") end
            continue
        end

        local isRecipeOpen = false
        local holder = nil
        local currentItemName = "Unknown Item"
        local isReadyToCraft = true 
        local hasIngredients = false
        local tempMaterialsArray = {}

        pcall(function()
            if not cachedRecipeHolder or not cachedRecipeHolder.Parent then
                -- [PERF] scan mainUI เท่านั้น ไม่ scan playerGui:GetDescendants()
                local mainUI2 = getCachedMainUI()
                local searchRoot = mainUI2 or playerGui
                for _, h in ipairs(searchRoot:GetDescendants()) do
                    if h.Name == "indexIngredientsHolder" and h:IsA("GuiObject") then
                        cachedRecipeHolder = h
                        break
                    end
                end
            end

            if cachedRecipeHolder then
                holder = cachedRecipeHolder
                if holder.AbsoluteSize.Y > 20 and holder.Visible then
                    isRecipeOpen = true
                    
                    local uiRoot = holder.Parent.Parent.Parent
                    local largestTextSize = 0
                    -- [PERF] scan depth 3 ด้วย GetChildren() แทน GetDescendants()
                    local function checkLabel(obj)
                        if obj:IsA("TextLabel") and obj.Text ~= "" and obj.Visible then
                            local t = obj.Text
                            if not string.find(t, "/") and not string.find(t, "%- Recipe %-")
                               and t ~= "Open Recipe" and t ~= "Auto" and t ~= "Craft" then
                                if obj.TextSize > largestTextSize then
                                    largestTextSize = obj.TextSize
                                    currentItemName = t
                                end
                            end
                        end
                    end
                    for _, c1 in ipairs(uiRoot:GetChildren()) do
                        checkLabel(c1)
                        for _, c2 in ipairs(c1:GetChildren()) do
                            checkLabel(c2)
                            for _, c3 in ipairs(c2:GetChildren()) do
                                checkLabel(c3)
                            end
                        end
                    end

                    for _, itemFrame in pairs(holder:GetChildren()) do
                        if itemFrame:IsA("Frame") or itemFrame:IsA("GuiButton") then
                            hasIngredients = true
                            local matName = "Unknown"
                            local matCur = 0
                            local matReq = 0
                            local addBtn = nil
                            
                            -- [PERF] GetDescendants() → depth 2 GetChildren() (itemFrame ไม่ลึก)
                            local function scanIngredientNode(label)
                                if label:IsA("TextLabel") and label.Text ~= "" then
                                    local txtStr = label.Text
                                    if string.find(txtStr, "/") and string.find(txtStr, "%(") then
                                        local cleanTxt = string.gsub(txtStr, "[%s%,%(%)]", "")
                                        local splitData = string.split(cleanTxt, "/")
                                        if #splitData == 2 then
                                            matCur = tonumber(splitData[1]) or 0
                                            matReq = tonumber(splitData[2]) or 0
                                            if matCur < matReq then isReadyToCraft = false end
                                        end
                                    elseif not tonumber(txtStr) and txtStr:lower() ~= "add" and not string.find(txtStr:lower(), "everything") then
                                        if label.Parent and not label.Parent:IsA("GuiButton") then
                                            matName = TrimString(txtStr)
                                        end
                                    end
                                end
                                if label:IsA("GuiButton") then
                                    if getButtonText(label) == "add" then addBtn = label end
                                end
                            end
                            for _, c1 in ipairs(itemFrame:GetChildren()) do
                                scanIngredientNode(c1)
                                for _, c2 in ipairs(c1:GetChildren()) do
                                    scanIngredientNode(c2)
                                end
                            end
                            
                            if not addBtn then addBtn = itemFrame end
                            
                            if matReq > 0 then
                                table.insert(tempMaterialsArray, {
                                    name = matName,
                                    current = matCur,
                                    required = matReq,
                                    btn = addBtn
                                })
                            end
                        end
                    end
                end
            end
        end)

        if not hasIngredients then isReadyToCraft = false end

        pcall(function()
            local btnCacheMissing = (not cachedButtons.auto or not cachedButtons.auto.Parent or not cachedButtons.auto.Visible) 
                                 or (not cachedButtons.craft or not cachedButtons.craft.Parent or not cachedButtons.craft.Visible)
                                 or (not cachedButtons.open or not cachedButtons.open.Parent or not cachedButtons.open.Visible)
            
            if btnCacheMissing then
                -- [PERF] scan ใน mainUI เท่านั้น ไม่ scan playerGui:GetDescendants() ทั้งหมด
                -- craft UI อยู่ใน MainInterface เสมอ
                cachedButtons = { open = nil, auto = nil, craft = nil }
                local mainUI2 = getCachedMainUI()
                local searchRoot = mainUI2 or playerGui
                for _, obj in ipairs(searchRoot:GetDescendants()) do
                    if obj:IsA("GuiButton") and obj.AbsoluteSize.X > 0 and isObjectActuallyVisible(obj) then 
                        local txt = getButtonText(obj)
                        txt = txt:gsub("^%s+", ""):gsub("%s+$", "") 
                        
                        if txt == "open recipe" then 
                            cachedButtons.open = obj
                        elseif txt == "auto" then 
                            cachedButtons.auto = obj
                        elseif txt == "craft" then 
                            cachedButtons.craft = obj
                        end
                        -- early exit ถ้าได้ครบสามปุ่มแล้ว
                        if cachedButtons.open and cachedButtons.auto and cachedButtons.craft then break end
                    end
                end
            end
        end)

        local realBtns = cachedButtons

        if isRecipeOpen then
            if CurrentCraftTarget ~= currentItemName then
                CraftSessionCount = 0
                CraftLogs = {}
                LastMaterialsState = {}
                CurrentCraftTarget = currentItemName
                _G.IsCraftingExpected = false
                AddCraftLog("Started tracking: " .. currentItemName)
            end

            local didCraft = false
            local isFirstScan = (next(LastMaterialsState) == nil)
            local materialDecreased = false
            
            for _, mat in ipairs(tempMaterialsArray) do
                local lastCount = LastMaterialsState[mat.name] or 0
                
                if not isFirstScan then
                    if mat.current < lastCount then
                        materialDecreased = true 
                    end
                end
                LastMaterialsState[mat.name] = mat.current
            end

            if materialDecreased and _G.IsCraftingExpected then
                didCraft = true
            end

            if didCraft then
                AddCraftLog("Crafted " .. currentItemName .. "!")
                CraftSessionCount = CraftSessionCount + 1
                _G.IsCraftingExpected = false 
            end

            IsCraftReady = isReadyToCraft
            CurrentCraftMaterials = tempMaterialsArray
            local readyText = isReadyToCraft and "[ READY ]" or "[ WAITING ]"
            if CraftTargetLabel then CraftTargetLabel:SetDesc(currentItemName) end
            if CraftStatusLabel then CraftStatusLabel:SetDesc(readyText) end
        else
            if CurrentCraftTarget ~= "" then
                CurrentCraftTarget = ""
                IsCraftReady = false
                CurrentCraftMaterials = {}
                LastMaterialsState = {}
                CraftLogs = {}
                CraftSessionCount = 0
                _G.IsCraftingExpected = false
            end
            if CraftTargetLabel then CraftTargetLabel:SetDesc("None (Recipe Closed)") end
            if CraftStatusLabel then CraftStatusLabel:SetDesc("Waiting") end
        end

        if masterAutoEnabled and tick() > nextActionTime then
            if #SelectedMultiItems > 0 then
                local targetItemName = SelectedMultiItems[multiCraftIndex]
                local realName = ScannedItemBaseNames[targetItemName] or string.gsub(targetItemName, " %(Button%)$", "")
                
                local occurrenceTarget = 1
                if ScannedItemBaseNames[targetItemName] then
                    local extractNum = string.match(targetItemName, " %((%d+)%)$")
                    if extractNum then
                        occurrenceTarget = tonumber(extractNum)
                    end
                end

                local targetBtn = CachedTargetButtons[targetItemName]
                
                if not targetBtn or not targetBtn.Parent then
                    local potentialTargets = {}
                    pcall(function()
                        for _, gui in ipairs(player.PlayerGui:GetChildren()) do
                            if gui:IsA("ScreenGui") then
                                for _, desc in ipairs(gui:GetDescendants()) do
                                    if (desc.Name == "Item" or desc.Name == "Gear" or desc.Name == "Lantern") and desc:IsA("GuiObject") then
                                        if desc.AbsoluteSize.Y > 0 then
                                            for _, child in ipairs(desc:GetChildren()) do
                                                if child.Name == realName then
                                                    local tempBtn = nil
                                                    if child:IsA("ImageButton") or child:IsA("TextButton") then
                                                        tempBtn = child
                                                    else
                                                        tempBtn = child:FindFirstChildWhichIsA("ImageButton", true) or child:FindFirstChildWhichIsA("TextButton", true)
                                                    end
                                                    
                                                    if tempBtn and tempBtn.AbsoluteSize.Y > 0 then
                                                        table.insert(potentialTargets, {
                                                            btn = tempBtn,
                                                            x = child.AbsolutePosition.X,
                                                            y = child.AbsolutePosition.Y,
                                                            order = child.LayoutOrder or 0
                                                        })
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    
                    table.sort(potentialTargets, function(a, b)
                        if a.order ~= b.order then return a.order < b.order end
                        if math.abs(a.y - b.y) > 10 then return a.y < b.y end
                        return a.x < b.x
                    end)

                    if #potentialTargets >= occurrenceTarget then
                        targetBtn = potentialTargets[occurrenceTarget].btn
                    elseif #potentialTargets > 0 then
                        targetBtn = potentialTargets[#potentialTargets].btn
                    end
                    
                    if not targetBtn or not targetBtn.Parent then
                        targetBtn = ScannedItemPaths[targetItemName]
                    end
                    
                    if targetBtn then
                        CachedTargetButtons[targetItemName] = targetBtn
                    end
                end

                local isUIOpen = false
                if isRecipeOpen then
                    isUIOpen = true
                elseif targetBtn then
                    local isVisible = true
                    local p = targetBtn
                    while p and p:IsA("GuiObject") do
                        if not p.Visible then isVisible = false break end
                        p = p.Parent
                    end
                    if isVisible and targetBtn.AbsoluteSize.Y > 0 and targetBtn.AbsolutePosition.X > 0 then
                        isUIOpen = true
                    end
                end

                if not isUIOpen then
                    if AutoCraftToggle then AutoCraftToggle:SetValue(false) end
                    masterAutoEnabled = false
                    HubConfig.AutoCraft = false
                    
                    if _G.MultiCraftDropdown then _G.MultiCraftDropdown:SetValues({}) end
                    SelectedMultiItems = {}
                    CachedTargetButtons = {} 
                    
                    if CraftStatusLabel then CraftStatusLabel:SetDesc("NPC UI closed. Auto Craft Disabled.") end
                    Fluent:Notify({ Title = "Auto Craft", Content = "UI closed or item missing. Disabled & Unselected.", Duration = 4 })
                else
                    if multiCraftState == "SELECT" then
                        _G.PopupAddAttempts = 0
                        if targetBtn and targetBtn.Parent and targetBtn.AbsoluteSize.Y > 0 then
                            local scrollFrame = targetBtn:FindFirstAncestorOfClass("ScrollingFrame")
                            if scrollFrame then
                                local maxCanvasY = 99999
                                pcall(function()
                                    if scrollFrame.AbsoluteCanvasSize and scrollFrame.AbsoluteCanvasSize.Y > 0 then
                                        maxCanvasY = math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteWindowSize.Y)
                                    elseif scrollFrame.CanvasSize.Y.Offset > 0 then
                                        maxCanvasY = math.max(0, scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteWindowSize.Y)
                                    end
                                end)
                                
                                local btnY = targetBtn.AbsolutePosition.Y
                                local scrollY = scrollFrame.AbsolutePosition.Y
                                local scrollHeight = scrollFrame.AbsoluteWindowSize and scrollFrame.AbsoluteWindowSize.Y or scrollFrame.AbsoluteSize.Y
                                
                                local margin = 20
                                if btnY < scrollY + margin or btnY + targetBtn.AbsoluteSize.Y > scrollY + scrollHeight - margin then
                                    local targetY = scrollFrame.CanvasPosition.Y + (btnY - scrollY) - (scrollHeight / 2)
                                    scrollFrame.CanvasPosition = Vector2.new(0, math.clamp(targetY, 0, maxCanvasY))
                                    task.wait(0.5)
                                end
                            end
                            
                            if forceCraftClick(targetBtn) then
                                multiCraftState = "OPEN_RECIPE"
                                nextActionTime = tick() + 1.0 
                            else
                                CachedTargetButtons[targetItemName] = nil
                                _G.SelectFailCount = (_G.SelectFailCount or 0) + 1
                                if _G.SelectFailCount > 4 then
                                    _G.SelectFailCount = 0
                                    multiCraftState = "NEXT"
                                end
                                nextActionTime = tick() + 0.5
                            end
                        else
                            multiCraftState = "NEXT"
                            nextActionTime = tick() + 0.5
                        end
                    elseif multiCraftState == "OPEN_RECIPE" then
                        _G.PopupAddAttempts = 0
                        local realName = ScannedItemBaseNames[targetItemName] or string.gsub(targetItemName, " %(Button%)$", "")
                        local targetNameLower = string.lower(realName)
                        local currentNameLower = string.lower(currentItemName)
                        local isCorrectRecipe = string.find(currentNameLower, targetNameLower, 1, true) or string.find(targetNameLower, currentNameLower, 1, true)

                        if realBtns.open and realBtns.open.Visible then
                            forceCraftClick(realBtns.open)
                            multiCraftState = "WAIT_RECIPE"
                            nextActionTime = tick() + 1.2
                        else
                            if isRecipeOpen and isCorrectRecipe then
                                multiCraftState = "WAIT_RECIPE"
                                nextActionTime = tick() + 0.1
                            else
                                _G.OpenFailCount = (_G.OpenFailCount or 0) + 1
                                if _G.OpenFailCount > 6 then
                                    _G.OpenFailCount = 0
                                    multiCraftState = "SELECT" 
                                end
                                nextActionTime = tick() + 0.5
                            end
                        end
                    elseif multiCraftState == "WAIT_RECIPE" then
                        local popupRoot = nil
                        -- [PERF] scan mainUI เท่านั้น ไม่ scan playerGui ทั้งหมด
                        local _mUI = getCachedMainUI() or playerGui
                        for _, gui in ipairs(_mUI:GetDescendants()) do
                            if gui:IsA("TextLabel") and gui.Visible and string.lower(TrimString(gui.Text)) == "add ingredients" then
                                popupRoot = gui.Parent
                                break
                            end
                        end

                        if popupRoot then
                            if (_G.PopupAddAttempts or 0) >= 2 then
                                for _, btn in pairs(popupRoot:GetDescendants()) do
                                    if btn:IsA("GuiButton") and btn.Visible then
                                        local btnTxt = string.lower(TrimString(getButtonText(btn)))
                                        if btnTxt == "x" or btnTxt == "close" then
                                            forceCraftClick(btn)
                                            task.wait(0.2)
                                            break
                                        end
                                    end
                                end
                                _G.PopupAddAttempts = 0
                                multiCraftState = "NEXT"
                                nextActionTime = tick() + 0.5
                            else
                                local allReady, clickedAdd = ProcessPopupIngredients(popupRoot)
                                
                                if allReady then
                                    local craftBtn = nil
                                    for _, btn in pairs(popupRoot:GetDescendants()) do
                                        if btn:IsA("GuiButton") and btn.Visible and string.lower(TrimString(getButtonText(btn))) == "craft" then
                                            craftBtn = btn
                                            break
                                        end
                                    end
                                    
                                    if craftBtn then
                                        forceCraftClick(craftBtn)
                                        _G.IsCraftingExpected = true
                                    elseif realBtns.craft and realBtns.craft.Visible then
                                        forceCraftClick(realBtns.craft)
                                        _G.IsCraftingExpected = true
                                    end
                                    
                                    _G.PopupAddAttempts = 0
                                    multiCraftState = "FINISH_CRAFT"
                                    nextActionTime = tick() + 2.0
                                elseif clickedAdd then
                                    _G.PopupAddAttempts = (_G.PopupAddAttempts or 0) + 1
                                    nextActionTime = tick() + 0.5
                                else
                                    for _, btn in pairs(popupRoot:GetDescendants()) do
                                        if btn:IsA("GuiButton") and btn.Visible then
                                            local btnTxt = string.lower(TrimString(getButtonText(btn)))
                                            if btnTxt == "x" or btnTxt == "close" then
                                                forceCraftClick(btn)
                                                task.wait(0.2)
                                                break
                                            end
                                        end
                                    end
                                    _G.PopupAddAttempts = 0
                                    multiCraftState = "NEXT"
                                    nextActionTime = tick() + 0.5
                                end
                            end
                        else
                            if isRecipeOpen then
                                local realName = ScannedItemBaseNames[targetItemName] or string.gsub(targetItemName, " %(Button%)$", "")
                                local targetNameLower = string.lower(realName)
                                local currentNameLower = string.lower(currentItemName)
                                local isCorrectRecipe = string.find(currentNameLower, targetNameLower, 1, true) or string.find(targetNameLower, currentNameLower, 1, true)
                                
                                if not isCorrectRecipe then
                                    multiCraftState = "SELECT"
                                    nextActionTime = tick() + 0.5
                                else
                                    if IsCraftReady and realBtns.craft and realBtns.craft.Visible then
                                         forceCraftClick(realBtns.craft)
                                         _G.IsCraftingExpected = true
                                         multiCraftState = "FINISH_CRAFT"
                                         nextActionTime = tick() + 2.0
                                    else
                                         if realBtns.open and realBtns.open.Visible then
                                             forceCraftClick(realBtns.open)
                                             nextActionTime = tick() + 1.0
                                         else
                                             _G.WaitPopupCount = (_G.WaitPopupCount or 0) + 1
                                             if _G.WaitPopupCount > 6 then
                                                 _G.WaitPopupCount = 0
                                                 _G.PopupAddAttempts = 0
                                                 multiCraftState = "NEXT"
                                             end
                                             nextActionTime = tick() + 0.5
                                         end
                                    end
                                end
                            else
                                _G.PopupAddAttempts = 0
                                multiCraftState = "OPEN_RECIPE"
                                nextActionTime = tick() + 0.5
                            end
                        end
                    elseif multiCraftState == "FINISH_CRAFT" then
                        _G.PopupAddAttempts = 0
                        local popupRoot = nil
                        local _mUI2 = getCachedMainUI() or playerGui
                        for _, gui in ipairs(_mUI2:GetDescendants()) do
                            if gui:IsA("TextLabel") and gui.Visible and string.lower(TrimString(gui.Text)) == "add ingredients" then
                                popupRoot = gui.Parent
                                break
                            end
                        end
                        if popupRoot then
                            for _, btn in pairs(popupRoot:GetDescendants()) do
                                if btn:IsA("GuiButton") and btn.Visible and (string.lower(TrimString(getButtonText(btn))) == "x" or string.lower(TrimString(getButtonText(btn))) == "close") then
                                    forceCraftClick(btn)
                                    task.wait(0.2)
                                    break
                                end
                            end
                        end
                        
                        multiCraftState = "NEXT"
                        nextActionTime = tick() + 0.5
                    
                    elseif multiCraftState == "NEXT" then
                        multiCraftIndex = multiCraftIndex + 1
                        if multiCraftIndex > #SelectedMultiItems then
                            multiCraftIndex = 1
                        end
                        multiCraftState = "SELECT"
                        nextActionTime = tick() + 0.5
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    -- [PERF] รวม 3 for-loop เป็น 1 pass + early-exit เมื่อครบ
    while task.wait(0.5) do
        if not autoFarmEnabled then
            DetectFish_ON, DetectMinigame_ON, DetectAction_ON = false, false, false
            continue
        end

        local mainUI = getCachedMainUI()
        if not mainUI then
            DetectFish_ON, DetectMinigame_ON, DetectAction_ON = false, false, false
            continue
        end
        
        local fishOn, miniOn, actOn = false, false, false

        -- Pass 1: ตรวจ Fish + Minigame ใน GetChildren() ครั้งเดียว + early-exit
        for _, child in ipairs(mainUI:GetChildren()) do
            if child:IsA("GuiObject") and child.Visible then
                local xOff = child.Size.X.Offset
                local xScl = child.Size.X.Scale
                local bg = child.BackgroundTransparency
                if math.abs(xOff - 201) <= 2 or math.abs(xScl - 0.122) <= 0.005 then
                    fishOn = (bg <= 0.6)
                elseif math.abs(xOff - 230) <= 2 or math.abs(xScl - 0.140) <= 0.005 then
                    miniOn = (bg <= 0.6)
                elseif child:IsA("ImageLabel") then
                    -- Pass 2 (inline): ตรวจ Action Button ระหว่าง loop เดียวกัน
                    for _, lv2 in ipairs(child:GetChildren()) do
                        if lv2:IsA("ImageLabel") then
                            for _, lv3 in ipairs(lv2:GetChildren()) do
                                if lv3:IsA("ImageButton") and lv3.Visible and lv3.AbsoluteSize.X > 0 then
                                    actOn = true
                                    break
                                end
                            end
                            if actOn then break end
                        end
                    end
                end
            end
            if fishOn and miniOn and actOn then break end -- early-exit เมื่อครบทั้งสาม
        end

        -- Fish fallback: ถ้ายังไม่พบผ่าน size-match ให้ลอง cached button
        if not fishOn then
            pcall(function()
                local btn = getFishButton(mainUI)
                if btn and btn.Visible and btn.AbsoluteSize.X > 0 then
                    fishOn = true
                end
            end)
        end

        DetectFish_ON = fishOn
        DetectMinigame_ON = miniOn
        DetectAction_ON = actOn
    end
end)

local recoveryLayer = {}
local function getRecovery(step)
    if not recoveryLayer[step] then recoveryLayer[step] = {layer=0, time=0} end
    return recoveryLayer[step]
end
local function resetRecovery(step)
    recoveryLayer[step] = {layer=0, time=0}
end
local function resetAllRecovery()
    recoveryLayer = {}
end

local function ClearFishingCache()
    cachedSafeZone = nil
    cachedDiamond = nil
    cachedExtraBtn = nil
    cachedFishBtn = nil
    resetAllRecovery()
end

task.spawn(function()
    local isWalking = false
    -- [PERF] 0.25s แทน 0.2s — walking loop ไม่ต้องถี่ขนาดนี้, ประหยัด CPU 20%
    while task.wait(0.25) do
        if not autoFarmEnabled then 
            isAtTarget = false
            isSellingProcess = false
            continue 
        end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        if autoSellEnabled then
            if fishingRoundCount >= targetFishCount then
                if not isSellingProcess then
                    hasArrivedAtSell = false
                    print("Round met! Initiating Sell...")
                    ClearFishingCache()
                    fishingStep = 0
                    hasMinigameMoved = false
                    
                    pcall(function()
                        local mainUI = getCachedMainUI()
                        if mainUI then
                            local extraBtn = getExtraButton(mainUI)
                            if extraBtn and extraBtn.Visible then
                                if FishStatusLabel then FishStatusLabel:SetDesc("Claiming Extra Action...") end
                                forceCraftClick(extraBtn)
                                task.wait(0.4)
                            end
                        end
                    end)

                    pcall(function()
                        if FishStatusLabel then FishStatusLabel:SetDesc("Preparing to Sell...") end
                        local mainUI = getCachedMainUI()
                        if mainUI then
                            local sideButtons = mainUI:FindFirstChild("SideButtons")
                            if sideButtons then
                                local bagBtn = nil
                                for _, btn in ipairs(sideButtons:GetChildren()) do
                                    if btn:IsA("GuiButton") or btn:IsA("ImageButton") or btn:IsA("TextButton") then
                                        local n = btn.Name:lower()
                                        if n:find("bag") or n:find("backpack") or n:find("inventory") or n:find("fish") then
                                            bagBtn = btn; break
                                        end
                                    end
                                end
                                if not bagBtn then
                                    local children = sideButtons:GetChildren()
                                    if children[8] then bagBtn = children[8] end
                                end
                                if bagBtn then forceCraftClick(bagBtn) task.wait(0.5) end
                            end
                        end

                        local btn2 = nil
                        for _, gui in ipairs(playerGui:GetChildren()) do
                            if gui:IsA("ScreenGui") and gui.Name ~= "AutoFishTesterUI" then
                                local f = gui:FindFirstChild("Frame")
                                local tl = f and f:FindFirstChild("TextLabel")
                                local b = tl and (tl:FindFirstChild("TextButton") or tl:FindFirstChildWhichIsA("TextButton"))
                                if b and b.Visible then btn2 = b; break end
                            end
                        end
                        if btn2 then forceCraftClick(btn2) task.wait(0.4) end
                    end)

                    isSellingProcess = true
                end
            end
        end

        if isSellingProcess then
            isAtTarget = false
            isResettingUI = false
            local distToSell = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(TARGET_SELL_POS.X, 0, TARGET_SELL_POS.Z)).Magnitude
            
            if distToSell > 5 then
                hasArrivedAtSell = false 
                if not isWalking then
                    isWalking = true
                    task.spawn(function()
                        pcall(function() walkToTarget(TARGET_SELL_POS, "Merchant") end)
                        isWalking = false
                    end)
                end
            else
                if not hasArrivedAtSell then
                    if char:FindFirstChild("Humanoid") then char.Humanoid:MoveTo(root.Position) end
                    task.wait(0.3)

                    -- [FIX] Cache proximity prompt ไว้ เพื่อใช้ปิด Dialog หลัง sell เสร็จ
                    local cachedSellPrompt = nil
                    pcall(function()
                        local promptFired = false
                        for _, obj in ipairs(Workspace:GetDescendants()) do
                            if obj:IsA("ProximityPrompt") then
                                local parentPart = obj.Parent
                                if parentPart and parentPart:IsA("BasePart") then
                                    if (parentPart.Position - root.Position).Magnitude <= 15 then
                                        if fireproximityprompt then
                                            fireproximityprompt(obj, 1)
                                            fireproximityprompt(obj, 0)
                                            cachedSellPrompt = obj  -- cache ไว้ใช้ตอนปิด
                                            promptFired = true
                                        end
                                    end
                                end
                            end
                        end
                        if not promptFired then
                            for i = 1, 3 do
                                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                task.wait(0.1)
                                vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                task.wait(0.15)
                            end
                        end
                    end)

                    task.wait(0.8)
                    hasArrivedAtSell = true
                end
                
                local hasCompletedSell = false
                local sellAttemptStart = tick()
                local sellDialogRetry = 0
                local MAX_SELL_RETRY = 3

                while not hasCompletedSell and autoFarmEnabled and isSellingProcess do
                    task.wait(0.15)
                    if tick() - sellAttemptStart > 45 then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Sell Timeout! Force Exit...") end
                        break
                    end

                    local mainUI = getCachedMainUI()
                    if not mainUI then task.wait(0.2); continue end
                    local dialog = mainUI:FindFirstChild("Dialog")
                
                    if dialog and dialog.Visible then
                        sellDialogRetry = 0
                        local choices = dialog:FindFirstChild("Choices")
                        if choices and choices.Visible then
                            local validChoices = {}
                            for _, child in ipairs(choices:GetChildren()) do
                                if child:IsA("GuiButton") or child:IsA("TextButton") or child:IsA("ImageButton") then
                                    table.insert(validChoices, child)
                                end
                            end
                            
                            if #validChoices >= 2 then
                                local sellChoiceBtn = nil
                                for _, btn in ipairs(validChoices) do
                                    local btnText = ""
                                    pcall(function()
                                        if btn:IsA("TextButton") then btnText = btn.Text:lower()
                                        else
                                            local lbl = btn:FindFirstChildWhichIsA("TextLabel")
                                            if lbl then btnText = lbl.Text:lower() end
                                        end
                                    end)
                                    if btnText:find("sell") or btnText:find("ขาย") then
                                        sellChoiceBtn = btn; break
                                    end
                                end
                                if not sellChoiceBtn then sellChoiceBtn = validChoices[2] end
                                forceCraftClick(sellChoiceBtn)
                                if not mainUI then break end
                                if FishStatusLabel then FishStatusLabel:SetDesc("Detecting Sell Frame...") end

                                local frameDetected = false
                                local frameDetectStart = tick()
                                local sellFrame3 = nil
                                local sellScrollFrame = nil

                                -- [PERF] เพิ่ม wait 0.35 (จาก 0.25) ลดรอบ scan จาก 48 → 34 ครั้ง
                                -- ตรวจ frame ที่ปรากฏใหม่ใน mainUI แทนการ scan ทั้งหมด
                                local function findSellScrollFrame()
                                    for _, f1 in ipairs(mainUI:GetChildren()) do
                                        if not (f1:IsA("GuiObject") and f1.Visible) then continue end
                                        for _, f2 in ipairs(f1:GetChildren()) do
                                            if not (f2:IsA("GuiObject") and f2.Visible) then continue end
                                            for _, f3 in ipairs(f2:GetChildren()) do
                                                if not (f3:IsA("GuiObject") and f3.Visible) then continue end
                                                local sf = f3:FindFirstChildWhichIsA("ScrollingFrame")
                                                if sf and sf.Visible then
                                                    local itemCount = 0
                                                    for _, c in ipairs(sf:GetChildren()) do
                                                        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
                                                            itemCount = itemCount + 1
                                                        end
                                                    end
                                                    if itemCount > 0 then
                                                        sellFrame3 = f3; sellScrollFrame = sf; frameDetected = true; return
                                                    end
                                                end
                                            end
                                            if frameDetected then return end
                                        end
                                        if frameDetected then return end
                                    end
                                end

                                while tick() - frameDetectStart < 12 do
                                    pcall(findSellScrollFrame)
                                    if frameDetected then
                                        if FishStatusLabel then FishStatusLabel:SetDesc("Sell Frame Detected! (" .. #sellScrollFrame:GetChildren() .. " items)") end
                                        break
                                    end
                                    task.wait(0.35)
                                end

                                if not frameDetected then
                                    if FishStatusLabel then FishStatusLabel:SetDesc("Sell Frame not found! Retrying...") end
                                    pcall(function()
                                        for i = 1, 3 do
                                            vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                            task.wait(0.1)
                                            vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                            task.wait(0.15)
                                        end
                                    end)
                                    task.wait(1.5)
                                    pcall(function()
                                        for _, f1 in ipairs(mainUI:GetChildren()) do
                                            if not (f1:IsA("GuiObject") and f1.Visible) then continue end
                                            for _, f2 in ipairs(f1:GetChildren()) do
                                                if not (f2:IsA("GuiObject") and f2.Visible) then continue end
                                                for _, f3 in ipairs(f2:GetChildren()) do
                                                    if not (f3:IsA("GuiObject") and f3.Visible) then continue end
                                                    local sf = f3:FindFirstChildWhichIsA("ScrollingFrame")
                                                    if sf and sf.Visible and #sf:GetChildren() > 0 then
                                                        local itemCount = 0
                                                        for _, c in ipairs(sf:GetChildren()) do
                                                            if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
                                                                itemCount = itemCount + 1
                                                            end
                                                        end
                                                        if itemCount > 0 then
                                                            sellFrame3 = f3
                                                            sellScrollFrame = sf
                                                            frameDetected = true
                                                            return
                                                        end
                                                    end
                                                end
                                                if frameDetected then return end
                                            end
                                            if frameDetected then return end
                                        end
                                    end)
                                    if not frameDetected then
                                        if FishStatusLabel then FishStatusLabel:SetDesc("No Sell Frame. Skipping...") end
                                        break
                                    end
                                end

                                -- ==========================================
                                -- [PATCHED] Inner Sell Loop — ขายจนกระเป๋าว่าง
                                -- [FIX] สุ่มเลือกเฉพาะ 4 ช่องแรก (แถวบน) ป้องกัน UI บีบมือถือจอเล็ก
                                -- ==========================================
                                local emptyBagCheck = 0
                                local innerLoopStart = tick()
                                local sellAllMissCount = 0
                                while autoFarmEnabled and isSellingProcess do
                                    if tick() - innerLoopStart > 120 then
                                        if FishStatusLabel then FishStatusLabel:SetDesc("Bag Timeout! Exiting...") end
                                        break
                                    end

                                    if sellFrame3 and (not sellFrame3.Parent or not sellFrame3.Visible) then
                                        if FishStatusLabel then FishStatusLabel:SetDesc("Sell Frame Closed") end
                                        break
                                    end

                                    local scrollFrame = (sellScrollFrame and sellScrollFrame.Parent and sellScrollFrame.Visible) and sellScrollFrame or nil
                                    if not scrollFrame and sellFrame3 and sellFrame3.Visible then
                                        pcall(function()
                                            local sf = sellFrame3:FindFirstChildWhichIsA("ScrollingFrame")
                                            if sf and sf.Visible then scrollFrame = sf; sellScrollFrame = sf end
                                        end)
                                    end
                                    if not scrollFrame then
                                        -- [PERF] scan 3 levels แทน GetDescendants()
                                        pcall(function()
                                            for _, c1 in ipairs(mainUI:GetChildren()) do
                                                if c1:IsA("ScrollingFrame") and c1.Visible and #c1:GetChildren() > 0 then scrollFrame = c1; return end
                                                for _, c2 in ipairs(c1:GetChildren()) do
                                                    if c2:IsA("ScrollingFrame") and c2.Visible and #c2:GetChildren() > 0 then scrollFrame = c2; return end
                                                    for _, c3 in ipairs(c2:GetChildren()) do
                                                        if c3:IsA("ScrollingFrame") and c3.Visible and #c3:GetChildren() > 0 then scrollFrame = c3; return end
                                                    end
                                                end
                                            end
                                        end)
                                    end

                                    if scrollFrame then
                                        local items = {}
                                        for _, v in ipairs(scrollFrame:GetChildren()) do
                                            if v:IsA("GuiObject") and v.Visible and v.AbsoluteSize.Y > 5 then
                                                local btn = v:IsA("GuiButton") and v or v:FindFirstChildWhichIsA("GuiButton", true)
                                                if btn then
                                                    table.insert(items, btn)
                                                else
                                                    table.insert(items, v)
                                                end
                                            end
                                        end

                                        if #items > 0 then
                                            emptyBagCheck = 0
                                            -- [FIX] สุ่มเลือกเฉพาะ 4 ช่องแรก (แถวบน) ป้องกัน UI บีบจอมือถือเล็ก
                                            local topRowCount = math.min(4, #items)
                                            local randomItem = items[math.random(1, topRowCount)]
                                            pcall(function() scrollFrame.CanvasPosition = Vector2.new(0, 0) end)
                                            task.wait(0.2)

                                            if FishStatusLabel then FishStatusLabel:SetDesc("Selecting Item... (" .. #items .. " left)") end
                                            forceCraftClick(randomItem)
                                            task.wait(0.4)

                                            if FishStatusLabel then FishStatusLabel:SetDesc("Clicking Sell All...") end
                                            local sellAllBtn = nil
                                            pcall(function()
                                                for _, f1 in ipairs(mainUI:GetChildren()) do
                                                    if not (f1:IsA("GuiObject") and f1.Visible) then continue end
                                                    for _, f2 in ipairs(f1:GetChildren()) do
                                                        if not (f2:IsA("GuiObject") and f2.Visible) then continue end
                                                        for _, imgBtn in ipairs(f2:GetChildren()) do
                                                            if imgBtn:IsA("ImageButton") and imgBtn.Visible then
                                                                local tl = imgBtn:FindFirstChildWhichIsA("TextLabel")
                                                                if tl then
                                                                    local txt = tl.Text:lower()
                                                                    if txt:match("sell all") or txt:match("ขายทั้งหมด") then
                                                                        sellAllBtn = imgBtn; return
                                                                    end
                                                                end
                                                                local n = imgBtn.Name:lower()
                                                                if n:match("sell") or n:match("sellall") then
                                                                    sellAllBtn = imgBtn; return
                                                                end
                                                            end
                                                        end
                                                        if sellAllBtn then return end
                                                    end
                                                    if sellAllBtn then return end
                                                end
                                            end)
                                            if not sellAllBtn then
                                                -- [PERF] scan 3 levels แทน GetDescendants()
                                                pcall(function()
                                                    local function trySellAll(node)
                                                        if not node.Visible then return end
                                                        local txt = nil
                                                        if node:IsA("TextLabel") or node:IsA("TextButton") then txt = node.Text:lower() end
                                                        if txt and txt:match("sell all") then
                                                            if node:IsA("GuiButton") or node:IsA("ImageButton") then sellAllBtn = node
                                                            elseif node.Parent and (node.Parent:IsA("GuiButton") or node.Parent:IsA("ImageButton")) then sellAllBtn = node.Parent end
                                                        end
                                                    end
                                                    for _, c1 in ipairs(mainUI:GetChildren()) do
                                                        trySellAll(c1); if sellAllBtn then return end
                                                        for _, c2 in ipairs(c1:GetChildren()) do
                                                            trySellAll(c2); if sellAllBtn then return end
                                                            for _, c3 in ipairs(c2:GetChildren()) do
                                                                trySellAll(c3); if sellAllBtn then return end
                                                            end
                                                        end
                                                    end
                                                end)
                                            end

                                            if sellAllBtn then
                                                sellAllMissCount = 0
                                                task.wait(0.2)
                                                -- [VERIFY] กด SellAll แล้วเช็คว่า popup ขึ้นมาไหม
                                                clickVerified(sellAllBtn, forceCraftClick, 3, 0.08)
                                                task.wait(0.5)

                                                local targetConfirmBtn = nil
                                                -- [PERF] scan 3 levels หา "Sell Confirm" popup แทน GetDescendants()
                                                pcall(function()
                                                    local function findSellConfirm(node)
                                                        if node:IsA("TextLabel") and node.Text == "Sell Confirm" and node.Visible then
                                                            local pf = node.Parent
                                                            if pf and pf:IsA("GuiObject") then
                                                                for _, pd in ipairs(pf:GetDescendants()) do
                                                                    if pd:IsA("TextLabel") and pd.Text == "Sell" and pd.Visible then
                                                                        local b = pd.Parent
                                                                        if b and (b:IsA("GuiButton") or b:IsA("ImageButton")) and b.Visible then
                                                                            targetConfirmBtn = b; return
                                                                        end
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                    for _, c1 in ipairs(mainUI:GetChildren()) do
                                                        findSellConfirm(c1); if targetConfirmBtn then return end
                                                        for _, c2 in ipairs(c1:GetChildren()) do
                                                            findSellConfirm(c2); if targetConfirmBtn then return end
                                                            for _, c3 in ipairs(c2:GetChildren()) do
                                                                findSellConfirm(c3); if targetConfirmBtn then return end
                                                            end
                                                        end
                                                    end
                                                end)

                                                if targetConfirmBtn then
                                                    -- [VERIFY] กด Confirm แล้วเช็คว่าหายไหม
                                                    clickVerified(targetConfirmBtn, forceCraftClick, 3, 0.08)
                                                    task.wait(0.5)
                                                    sellAllMissCount = 0
                                                    if FishStatusLabel then FishStatusLabel:SetDesc("Sold Item! Checking for more...") end
                                                else
                                                    task.wait(0.2)
                                                end
                                            else
                                                sellAllMissCount = sellAllMissCount + 1
                                                if sellAllMissCount >= 5 then
                                                    if FishStatusLabel then FishStatusLabel:SetDesc("Sell All button not found! Exiting...") end
                                                    break
                                                end
                                                task.wait(0.4)
                                            end
                                        else
                                            emptyBagCheck = emptyBagCheck + 1
                                            if FishStatusLabel then FishStatusLabel:SetDesc("Checking Bag (" .. emptyBagCheck .. "/3)...") end
                                            if emptyBagCheck >= 3 then
                                                if FishStatusLabel then FishStatusLabel:SetDesc("Bag Empty! All Items Sold.") end
                                                break
                                            end
                                            task.wait(0.5)
                                        end
                                    else
                                        task.wait(0.5)
                                    end
                                end
                                -- ==========================================

                                if FishStatusLabel then FishStatusLabel:SetDesc("Closing UI...") end
                                pcall(function()
                                    -- ==========================================
                                    -- ปิด Sell UI — 3 วิธีเรียงลำดับ
                                    -- ==========================================

                                    -- วิธี 1: path ตายตัว MainInterface.Frame.TextLabel.ImageButton
                                    -- (สำรอง) กด ImageLabel ลูกของ ImageButton ในกรณีที่ ImageButton เองรับ click ไม่ได้
                                    local targetCloseBtn = nil
                                    local targetCloseFallback = nil  -- ImageLabel สำรอง
                                    for _, frameNode in ipairs(mainUI:GetChildren()) do
                                        if frameNode.Name == "Frame" and frameNode.Visible then
                                            local textLabel = frameNode:FindFirstChild("TextLabel")
                                            if textLabel then
                                                local imgBtn = textLabel:FindFirstChild("ImageButton")
                                                if imgBtn and imgBtn.Visible then
                                                    targetCloseBtn = imgBtn
                                                    -- [FIX] เก็บ ImageLabel ลูกเป็น fallback สำหรับกรณีกดพลาด
                                                    -- Path สำรอง: MainInterface.Frame.TextLabel.ImageButton.ImageLabel
                                                    local imgLbl = imgBtn:FindFirstChildWhichIsA("ImageLabel")
                                                    if imgLbl and imgLbl.Visible then
                                                        targetCloseFallback = imgLbl
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                    end

                                    -- วิธี 2 (fallback): หา X/Close text 3 levels deep
                                    if not targetCloseBtn then
                                        -- [PERF] scan 3 levels แทน GetDescendants()
                                        for _, c1 in ipairs(mainUI:GetChildren()) do
                                            local function tryClose(node)
                                                if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Visible then
                                                    local t = node.Text:lower()
                                                    if t == "x" or t == "close" then
                                                        local b = node:IsA("GuiButton") and node or node.Parent
                                                        if b and b:IsA("GuiButton") then targetCloseBtn = b end
                                                    end
                                                end
                                            end
                                            tryClose(c1); if targetCloseBtn then break end
                                            for _, c2 in ipairs(c1:GetChildren()) do
                                                tryClose(c2); if targetCloseBtn then break end
                                                for _, c3 in ipairs(c2:GetChildren()) do
                                                    tryClose(c3); if targetCloseBtn then break end
                                                end
                                                if targetCloseBtn then break end
                                            end
                                            if targetCloseBtn then break end
                                        end
                                    end

                                    if targetCloseBtn then
                                        -- กด ImageButton หลักก่อน
                                        forceCraftClick(targetCloseBtn)
                                        task.wait(0.25)

                                        -- ตรวจว่าปิดแล้วหรือยัง
                                        local stillOpen = false
                                        pcall(function()
                                            stillOpen = targetCloseBtn.Visible and targetCloseBtn.AbsoluteSize.X > 0
                                        end)

                                        -- [FIX] ถ้ายังไม่ปิด ลอง ImageLabel สำรองก่อน (กดพลาด path)
                                        if stillOpen and targetCloseFallback then
                                            forceCraftClick(targetCloseFallback)
                                            task.wait(0.25)
                                        elseif stillOpen then
                                            -- กด ImageButton ซ้ำอีกครั้ง
                                            forceCraftClick(targetCloseBtn)
                                            task.wait(0.25)
                                        end
                                    end

                                    -- วิธี 3: ถ้าปิดไม่ได้เลย กด Escape — ทุก UI ปิดได้ด้วย Escape
                                    local dlgBack = mainUI:FindFirstChild("Dialog")
                                    local shopStillOpen = not (dlgBack and dlgBack.Visible)
                                    if shopStillOpen then
                                        vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                                        task.wait(0.15)
                                        vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
                                        task.wait(0.3)
                                    end
                                end)
                                
                                hasCompletedSell = true
                                totalSellCount = totalSellCount + 1
                                task.wait(0.5)

                                -- [FIX] กด Leave (choice ตัวที่ 3) เพื่อปิด Dialog NPC หลังปิด Sell UI
                                task.wait(0.3)
                                pcall(function()
                                    local dlg2 = mainUI:FindFirstChild("Dialog")
                                    if not (dlg2 and dlg2.Visible) then return end
                                    local choices2 = dlg2:FindFirstChild("Choices")
                                    if not choices2 then return end
                                    local btns2 = {}
                                    for _, child in ipairs(choices2:GetChildren()) do
                                        if child:IsA("GuiButton") or child:IsA("TextButton") or child:IsA("ImageButton") then
                                            table.insert(btns2, child)
                                        end
                                    end
                                    table.sort(btns2, function(a, b)
                                        return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
                                    end)
                                    local leaveBtn2 = btns2[3] or btns2[#btns2]
                                    if leaveBtn2 then forceCraftClick(leaveBtn2) end
                                end)
                                forceCraftClick(validChoices[#validChoices])
                                hasCompletedSell = true
                                totalSellCount = totalSellCount + 1
                                task.wait(0.5)
                            end
                        else
                            forceCraftClick(dialog)
                            task.wait(0.2)
                        end
                    else
                        sellDialogRetry = sellDialogRetry + 1
                        if FishStatusLabel then FishStatusLabel:SetDesc("No Dialog! Retry (" .. sellDialogRetry .. "/" .. MAX_SELL_RETRY .. ")") end

                        pcall(function()
                            local char2 = player.Character
                            local root2 = char2 and char2:FindFirstChild("HumanoidRootPart")
                            if not root2 then return end
                            local promptFired2 = false
                            for _, obj in ipairs(Workspace:GetDescendants()) do
                                if obj:IsA("ProximityPrompt") then
                                    local pp = obj.Parent
                                    if pp and pp:IsA("BasePart") and (pp.Position - root2.Position).Magnitude <= 15 then
                                        if fireproximityprompt then
                                            fireproximityprompt(obj, 1)
                                            task.wait(0.05)
                                            fireproximityprompt(obj, 0)
                                            promptFired2 = true
                                        end
                                    end
                                end
                            end
                            if not promptFired2 then
                                for i = 1, 3 do
                                    vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task.wait(0.1)
                                    vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                    task.wait(0.15)
                                end
                            end
                        end)
                        task.wait(0.8)

                        if sellDialogRetry >= MAX_SELL_RETRY then
                            if FishStatusLabel then FishStatusLabel:SetDesc("Force Exiting Sell...") end
                            hasCompletedSell = true
                            totalSellCount = totalSellCount + 1
                        end
                    end
                end

                isSellingProcess = false
                hasArrivedAtSell = false
                isResettingUI = false
                isAtTarget = false
                isWalking = false
                fishingStep = 0
                hasMinigameMoved = false
                fishingRoundCount = 0

                if FishBagLabel then FishBagLabel:SetDesc("Rounds: " .. fishingRoundCount .. " / " .. targetFishCount) end
                if FishStatusLabel then FishStatusLabel:SetDesc("Sell Done! Closing Dialog...") end

                -- [FIX] ปิด Dialog NPC หลัง sell เสร็จ
                -- path ตายตัว: MainInterface.Dialog.Choices → 3 children = [Open Shop, Sell Fish, Leave]
                -- Leave อยู่ตัวที่ 3 เสมอ แต่ต้อง sort ด้วย LayoutOrder ก่อน เพราะ GetChildren() ไม่การันตีลำดับ
                local function closeDialogSafely()
                    local mainUI2 = getCachedMainUI()
                    if not mainUI2 then return end
                    local dlg = mainUI2:FindFirstChild("Dialog")
                    if not (dlg and dlg.Visible) then return end
                    local choices = dlg:FindFirstChild("Choices")
                    if not choices then return end

                    local btns = {}
                    for _, child in ipairs(choices:GetChildren()) do
                        if child:IsA("GuiButton") or child:IsA("TextButton") or child:IsA("ImageButton") then
                            table.insert(btns, child)
                        end
                    end
                    table.sort(btns, function(a, b)
                        return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
                    end)
                    local leaveBtn = #btns >= 3 and btns[3] or btns[#btns]
                    if leaveBtn then
                        -- [VERIFY] กด Leave แล้วเช็คว่า Dialog หายไหม
                        clickVerified(leaveBtn, forceCraftClick, 3, 0.08)
                        task.wait(0.2)
                    end
                end

                closeDialogSafely()

                local dialogWaitStart = tick()
                while tick() - dialogWaitStart < 3 do
                    local mainUI = getCachedMainUI()
                    local dlg = mainUI and mainUI:FindFirstChild("Dialog")
                    if not dlg or not dlg.Visible then break end
                    closeDialogSafely()
                    task.wait(0.3)
                end

                ClearFishingCache()
                task.wait(0.3)
            end
            
        else
            if isResettingUI then
                local distToReset = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(RESET_FISH_POS.X, 0, RESET_FISH_POS.Z)).Magnitude
                if distToReset > 4 then
                    isAtTarget = false
                    if not isWalking then
                        isWalking = true
                        task.spawn(function()
                            pcall(function() walkToTarget(RESET_FISH_POS, "Reset Spot") end)
                            isWalking = false
                        end)
                    end
                else
                    isResettingUI = false 
                end
            else
                local distToFish = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(TARGET_FISH_POS.X, 0, TARGET_FISH_POS.Z)).Magnitude
                if distToFish > 5 then
                    isAtTarget = false
                    if not isWalking then
                        isWalking = true
                        task.spawn(function()
                            pcall(function() walkToTarget(TARGET_FISH_POS, "Fishing Spot") end)
                            isWalking = false
                        end)
                    end
                else
                    if not isAtTarget then
                        isAtTarget = true
                        if char:FindFirstChild("Humanoid") then char.Humanoid:MoveTo(root.Position) end
                    end
                end
            end
        end
    end
end)

local FAR_THRESHOLD, MID_THRESHOLD = 60, 25
local isMinigameActive = false
local lastClickTime = 0
local CLICK_RATE_FAR  = 0.05
local CLICK_RATE_MID  = 0.07
local CLICK_RATE_NEAR = 0.12

-- [FIX] Status label cache — เขียน UI เฉพาะตอนข้อความเปลี่ยน
-- บนมือถือ UI property write แพงมาก เขียนทุก frame FPS ตกหนัก
local _lastFishStatus = ""
local function setFishStatus(txt)
    if txt ~= _lastFishStatus then
        _lastFishStatus = txt
        if FishStatusLabel then pcall(function() FishStatusLabel:SetDesc(txt) end) end
    end
end

-- [PERF] 0.07s แทน 0.05s = 14x/วินาที (ยังเร็วพอสำหรับ minigame, กิน CPU น้อยลง 28%)
-- เพิ่ม early-exit เมื่อ autoFarm ปิดหรือ selling — ไม่ต้อง check flag ใน pcall ทุกรอบ
task.spawn(function() while task.wait(0.07) do
    if not autoFarmEnabled or not isAtTarget or isSellingProcess or isResettingUI or not DetectMinigame_ON then
        if isMinigameActive then
            isMinigameActive = false
        end
        continue
    end

    pcall(function()
        local safeZoneBar, diamondIcon = getExactMinigameElements()

        if safeZoneBar and safeZoneBar.Visible then
            isMinigameActive = true
            hasMinigameMoved = true

            if diamondIcon and diamondIcon.Visible then
                local overlapping = isOverlapping(diamondIcon, safeZoneBar)
                local distance = math.abs((diamondIcon.AbsolutePosition.X + diamondIcon.AbsoluteSize.X / 2) - (safeZoneBar.AbsolutePosition.X + safeZoneBar.AbsoluteSize.X / 2))
                local currentTime = tick()

                if overlapping then
                    setFishStatus("Target Locked")
                elseif distance > FAR_THRESHOLD then
                    setFishStatus("Distance: Far (Spamming)")
                    if currentTime - lastClickTime > CLICK_RATE_FAR then
                        clickOnce()
                        lastClickTime = currentTime
                    end
                elseif distance > MID_THRESHOLD then
                    setFishStatus("Distance: Medium")
                    if currentTime - lastClickTime > CLICK_RATE_MID then
                        clickOnce()
                        lastClickTime = currentTime
                    end
                else
                    setFishStatus("Distance: Near")
                    if currentTime - lastClickTime > CLICK_RATE_NEAR then
                        clickOnce()
                        lastClickTime = currentTime
                    end
                end
            else
                setFishStatus("Waiting for Minigame...")
            end
        else
            if isMinigameActive then
                isMinigameActive = false
                setFishStatus("Waiting for Fish...")
            end
        end
    end)
end end)

local lastFishingStepTime = tick()
local actionFirstDetected = 0
local lastLoopTick = tick()

task.spawn(function()
    while task.wait(0.3) do
        if not autoFarmEnabled or not isAtTarget or isSellingProcess or isResettingUI then
            fishingStep = 0
            hasMinigameMoved = false
            lastFishingStepTime = tick()
            lastLoopTick = tick()
            actionFirstDetected = 0
            resetAllRecovery()
            continue
        end

        lastLoopTick = tick()

        if autoSellEnabled and fishingRoundCount >= targetFishCount then
            fishingStep = 0
            lastFishingStepTime = tick()
            resetAllRecovery()
            continue
        end

        pcall(function()
            local mainUI = getCachedMainUI()
            if not mainUI then return end

            local childCount = #mainUI:GetChildren()
            if childCount < 3 then
                if FishStatusLabel then FishStatusLabel:SetDesc("Loading UI...") end
                lastFishingStepTime = tick()
                return
            end

            local fishBtn = getFishButton(mainUI)
            local isFishVisible = false
            if fishBtn then
                local ok, vis = pcall(function() return fishBtn.Visible end)
                if ok and vis then
                    local tl = fishBtn:FindFirstChildWhichIsA("TextLabel")
                    isFishVisible = tl and tl.Visible or (not tl)
                end
            end
            if isFishVisible and not DetectFish_ON then
                DetectFish_ON = true
            end

            local actionContainer = nil
            local extraBtn = nil
            if DetectAction_ON then
                pcall(function()
                    for _, lv1 in ipairs(mainUI:GetChildren()) do
                        if lv1:IsA("ImageLabel") then
                            for _, lv2 in ipairs(lv1:GetChildren()) do
                                if lv2:IsA("ImageLabel") then
                                    for _, lv3 in ipairs(lv2:GetChildren()) do
                                        if lv3:IsA("ImageButton") and lv3.Visible and lv3.AbsoluteSize.X > 0 then
                                            actionContainer = lv2
                                            extraBtn = lv3
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
                if not extraBtn then
                    extraBtn = getExtraButton(mainUI)
                end
            end

            local isActionVisible = false
            if extraBtn then
                local ok, vis = pcall(function() return extraBtn.Visible end)
                isActionVisible = ok and vis and extraBtn.AbsoluteSize.X > 0
            end

            local isActionAnimDone = true
            if actionContainer then
                -- _actionBGSample is now a local upvalue
                local key = tostring(actionContainer)
                local prev = _actionBGSample[key]
                local curBG = actionContainer.BackgroundTransparency
                isActionAnimDone = prev and math.abs(curBG - prev) < 0.05 or false
                _actionBGSample[key] = curBG
            end

            local timeInStep = tick() - lastFishingStepTime

            -- ===== STEP 0: รอปุ่ม Fish =====
            if fishingStep == 0 then
                resetRecovery(0)

                -- [FIX] ตรวจ Dialog NPC ค้างก่อนทุกอย่าง กด Leave (choice[3]) เพื่อปิด
                pcall(function()
                    local dlg = mainUI:FindFirstChild("Dialog")
                    if not (dlg and dlg.Visible) then return end
                    if FishStatusLabel then FishStatusLabel:SetDesc("Closing Dialog before Fish...") end
                    local choices = dlg:FindFirstChild("Choices")
                    if choices then
                        local btns = {}
                        for _, child in ipairs(choices:GetChildren()) do
                            if child:IsA("GuiButton") or child:IsA("TextButton") or child:IsA("ImageButton") then
                                table.insert(btns, child)
                            end
                        end
                        table.sort(btns, function(a, b)
                            return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
                        end)
                        local leaveBtn = btns[3] or btns[#btns]
                        if leaveBtn then forceCraftClick(leaveBtn) end
                    end
                    task.wait(0.4)
                    if dlg.Visible then
                        lastFishingStepTime = tick()
                        return
                    end
                end)

                if DetectFish_ON and isFishVisible then
                    if FishStatusLabel then FishStatusLabel:SetDesc("Clicking Fish Button...") end
                    cachedFishBtn = nil
                    task.wait(0.3)
                    local freshBtn = getFishButton(mainUI)
                    if not freshBtn then return end

                    -- [VERIFY] กดแล้วเช็คเลยว่าติดไหม retry อัตโนมัติ ไม่รอ 0.4s เปล่าๆ
                    local clickedOK = clickVerified(freshBtn, forceFishClick, 3, 0.08, function(btn)
                        local vis, bg = true, 0
                        pcall(function() vis = btn.Visible; bg = btn.BackgroundTransparency end)
                        return (not vis) or (bg >= 0.9)
                    end)

                    if clickedOK then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Minigame...") end
                        fishingStep = 1
                        lastFishingStepTime = tick()
                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Fish Click Failed — Retrying...") end
                        cachedFishBtn = nil
                        lastFishingStepTime = tick()
                    end

                elseif DetectFish_ON and timeInStep > 5.0 then
                    local rec = getRecovery(0)
                    if rec.layer == 0 then
                        rec.layer = 1; rec.time = tick()
                        if FishStatusLabel then FishStatusLabel:SetDesc("Re-detecting Fish UI...") end
                        cachedFishBtn = nil
                        local freshBtn = getFishButton(mainUI)
                        if freshBtn then forceFishClick(freshBtn) else clickOnce() end
                        lastFishingStepTime = tick()
                    elseif rec.layer == 1 and tick() - rec.time > 4.0 then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Clearing Cache...") end
                        ClearFishingCache()
                        local reBtn = getFishButton(mainUI)
                        if reBtn and reBtn.Visible then forceFishClick(reBtn) else clickOnce() end
                        fishingStep = 1
                        resetRecovery(0)
                        lastFishingStepTime = tick()
                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Fish Button...") end
                    end

                elseif not DetectFish_ON and timeInStep > 15.0 then
                    local rec = getRecovery(0)
                    if rec.layer == 0 then
                        rec.layer = 1; rec.time = tick()
                        clickOnce()
                        lastFishingStepTime = tick()
                        if FishStatusLabel then FishStatusLabel:SetDesc("Force Clicking...") end
                    elseif rec.layer == 1 and tick() - rec.time > 5.0 then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Skipping to Minigame...") end
                        clickOnce()
                        fishingStep = 1
                        resetRecovery(0)
                        lastFishingStepTime = tick()
                    end
                else
                    if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Fish Button...") end
                end

            -- ===== STEP 1: รอ Minigame =====
            elseif fishingStep == 1 then

                if DetectMinigame_ON and isMinigameActive and hasMinigameMoved then
                    fishingStep = 2
                    resetRecovery(1)
                    lastFishingStepTime = tick()

                elseif DetectFish_ON and isFishVisible then
                    fishingStep = 0
                    resetRecovery(1)
                    lastFishingStepTime = tick()

                elseif DetectMinigame_ON and timeInStep > 5.0 then
                    local rec = getRecovery(1)
                    if rec.layer == 0 then
                        rec.layer = 1; rec.time = tick()
                        if FishStatusLabel then FishStatusLabel:SetDesc("Retrying Minigame...") end
                        clickOnce()
                        lastFishingStepTime = tick()
                    elseif rec.layer == 1 and tick() - rec.time > 4.0 then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Skipping Minigame...") end
                        cachedSafeZone = nil; cachedDiamond = nil
                        fishingStep = 2
                        resetRecovery(1)
                        lastFishingStepTime = tick()
                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Minigame...") end
                    end

                elseif not DetectMinigame_ON and timeInStep > 12.0 then
                    fishingStep = 2
                    resetRecovery(1)
                    lastFishingStepTime = tick()
                else
                    if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Minigame...") end
                end

            -- ===== STEP 2: รอ Minigame จบ =====
            elseif fishingStep == 2 then

                if not DetectMinigame_ON or not isMinigameActive then
                    fishingStep = 3
                    resetRecovery(2)
                    lastFishingStepTime = tick()
                    actionFirstDetected = 0

                elseif timeInStep > 5.0 then
                    local rec = getRecovery(2)
                    if rec.layer == 0 then
                        rec.layer = 1; rec.time = tick()
                        if FishStatusLabel then FishStatusLabel:SetDesc("Minigame Timeout, Clicking...") end
                        clickOnce()
                        lastFishingStepTime = tick()
                    elseif rec.layer == 1 and tick() - rec.time > 4.0 then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Forcing Minigame to End...") end
                        cachedSafeZone = nil; cachedDiamond = nil
                        isMinigameActive = false
                        clickOnce()
                        fishingStep = 3
                        resetRecovery(2)
                        lastFishingStepTime = tick()
                        actionFirstDetected = 0
                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Minigame to End...") end
                    end
                else
                    if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Minigame to End...") end
                end

            -- ===== STEP 3: รอปุ่ม Action =====
            elseif fishingStep == 3 then

                if isActionVisible then
                    if actionFirstDetected == 0 then actionFirstDetected = tick() end

                    local isPositionReady = false
                    pcall(function()
                        local pos = extraBtn.Position
                        local xScaleOK = math.abs(pos.X.Scale - 1) < 0.05
                        local xOffOK   = math.abs(pos.X.Offset)    < 5
                        local yOK      = math.abs(pos.Y.Scale)      < 0.05
                                      and math.abs(pos.Y.Offset)    < 5
                        isPositionReady = xScaleOK and xOffOK and yOK
                    end)

                    -- ป้องกันกดปุ่มก่อน Animation เสร็จ
                    if isPositionReady and isActionAnimDone then
                        if FishStatusLabel then FishStatusLabel:SetDesc("Clicking Action...") end

                        -- ==========================================
                        -- [VERIFY] Action Button — ใช้ clickVerified loop
                        -- เช็คทุก 0.08s ว่าปุ่มหายหรือยัง retry จน timeout 8s
                        -- ==========================================
                        local isMainClickActive = true
                        local actionClickActive = true

                        -- Custom check สำหรับ Action Button:
                        -- ปุ่มยังอยู่ถ้า position ยัง in-place, Visible, size > 0
                        local function actionBtnGone(btn)
                            if not btn or not btn.Parent then return true end
                            if not btn.Visible or btn.AbsoluteSize.X <= 0 then return true end
                            local pos = btn.Position
                            local inPos = math.abs(pos.X.Scale - 1) < 0.05
                                       and math.abs(pos.X.Offset) < 5
                                       and math.abs(pos.Y.Scale) < 0.05
                                       and math.abs(pos.Y.Offset) < 5
                            return not inPos -- หายถ้า position เลื่อนออกไป
                        end

                        -- safety-net parallel: กดซ้ำถ้า main หยุดแต่ปุ่มยังอยู่
                        task.spawn(function()
                            task.wait(1.5)
                            while actionClickActive do
                                if not isMainClickActive then
                                    pcall(function()
                                        if extraBtn and not actionBtnGone(extraBtn) then
                                            forceActionClick(extraBtn)
                                        end
                                    end)
                                end
                                task.wait(1.2)
                            end
                        end)

                        -- Main loop: clickVerified ทุก 0.08s สูงสุด 10 ครั้ง (~8s)
                        local actionDone = false
                        local actionTimeout = tick()
                        while tick() - actionTimeout < 8 do
                            -- เช็คก่อนกดว่าปุ่มยังอยู่ไหม
                            if actionBtnGone(extraBtn) then
                                actionDone = true
                                if FishStatusLabel then FishStatusLabel:SetDesc("Action Completed!") end
                                break
                            end
                            -- กดแล้วเช็คเลย
                            local hit = clickVerified(extraBtn, forceActionClick, 1, 0.08, function(btn)
                                return actionBtnGone(btn)
                            end)
                            if hit then
                                actionDone = true
                                if FishStatusLabel then FishStatusLabel:SetDesc("Action Completed!") end
                                break
                            end
                            if FishStatusLabel then FishStatusLabel:SetDesc("Clicking Action...") end
                            task.wait(0.4) -- รอ animation ก่อน retry
                        end

                        isMainClickActive = false
                        actionClickActive = false

                        -- ==========================================
                        -- [VERIFY] Confirm Button — clickVerified 3 ครั้ง
                        -- ลอง ImageButton → ImageLabel → parent ตามลำดับ
                        -- ==========================================
                        task.wait(0.3)
                        local confirmBtn = nil
                        pcall(function()
                            for _, child in ipairs(extraBtn:GetChildren()) do
                                if child:IsA("ImageButton") and child.Visible and child.AbsoluteSize.X > 0 then
                                    confirmBtn = child; return
                                end
                            end
                            for _, child in ipairs(extraBtn:GetChildren()) do
                                if child:IsA("ImageLabel") and child.Visible and child.AbsoluteSize.X > 0 then
                                    confirmBtn = child; return
                                end
                            end
                            for _, desc in ipairs(extraBtn:GetDescendants()) do
                                if (desc:IsA("ImageButton") or desc:IsA("GuiButton")) and desc.Visible and desc.AbsoluteSize.X > 0 then
                                    confirmBtn = desc; return
                                end
                            end
                        end)

                        if confirmBtn then
                            if FishStatusLabel then FishStatusLabel:SetDesc("Confirming Action...") end
                            -- clickVerified: 3 attempts, เช็คทุก 0.08s
                            -- ถ้ายังไม่หาย ลอง parent ด้วย
                            local confirmed = clickVerified(confirmBtn, forceActionClick, 3, 0.08)
                            if not confirmed then
                                -- fallback: ลอง parent
                                local parentBtn = confirmBtn.Parent
                                if parentBtn and (parentBtn:IsA("GuiButton") or parentBtn:IsA("ImageButton")) then
                                    clickVerified(parentBtn, forceActionClick, 2, 0.08)
                                end
                            end
                        end

                        if FishStatusLabel then FishStatusLabel:SetDesc("Checking Rounds...") end
                        fishingRoundCount = fishingRoundCount + 1

                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting 0.5s for Item...") end
                        task.wait(0.5)

                        fishingStep = 4
                        lastFishingStepTime = tick()
                        actionFirstDetected = 0
                        resetAllRecovery()
                        cachedExtraBtn = nil
                        table.clear(_actionBGSample)

                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for UI Animation...") end
                    end

                else
                    actionFirstDetected = 0

                    if DetectFish_ON and isFishVisible then
                        fishingStep = 0
                        hasMinigameMoved = false
                        resetAllRecovery()
                        lastFishingStepTime = tick()

                    elseif DetectAction_ON and timeInStep > 5.0 then
                        local rec = getRecovery(3)
                        if rec.layer == 0 then
                            rec.layer = 1; rec.time = tick()
                            if FishStatusLabel then FishStatusLabel:SetDesc("Re-detecting Action UI...") end
                            cachedExtraBtn = nil
                            local freshExtra = getExtraButton(mainUI)
                            if freshExtra and freshExtra.Visible then
                                forceActionClick(freshExtra)
                                task.wait(0.35)
                                forceActionClick(freshExtra)
                            else
                                clickOnce()
                            end
                            lastFishingStepTime = tick()

                        elseif rec.layer == 1 and tick() - rec.time > 4.0 then
                            if FishStatusLabel then FishStatusLabel:SetDesc("Skipping Action Step...") end
                            ClearFishingCache()
                            table.clear(_actionBGSample)
                            local fallbackExtra = getExtraButton(mainUI)
                            if fallbackExtra then forceActionClick(fallbackExtra)
                            else clickOnce() end
                            task.wait(0.5)
                            fishingRoundCount = fishingRoundCount + 1
                            fishingStep = 4
                            hasMinigameMoved = false
                            lastFishingStepTime = tick()
                            actionFirstDetected = 0
                            resetAllRecovery()

                        else
                            if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Action Button...") end
                        end

                    elseif timeInStep > 15.0 then
                        fishingStep = 0
                        hasMinigameMoved = false
                        resetAllRecovery()
                        lastFishingStepTime = tick()
                    else
                        if FishStatusLabel then FishStatusLabel:SetDesc("Waiting for Action Button...") end
                    end
                end

            -- ===== STEP 4: เช็คจำนวนรอบ =====
            elseif fishingStep == 4 then

                if FishBagLabel then FishBagLabel:SetDesc("Rounds: " .. fishingRoundCount .. " / " .. targetFishCount) end

                if autoSellEnabled and fishingRoundCount >= targetFishCount then
                    if FishStatusLabel then FishStatusLabel:SetDesc("Target Reached! Triggering Sell...") end
                    ClearFishingCache()
                    fishingStep = 0
                    hasMinigameMoved = false
                    lastFishingStepTime = tick()
                    resetAllRecovery()
                else
                    if FishStatusLabel then FishStatusLabel:SetDesc("Round " .. fishingRoundCount .. " Complete") end
                    fishingStep = 0
                    hasMinigameMoved = false
                    lastFishingStepTime = tick()
                    resetAllRecovery()
                    isResettingUI = true
                end

            end
        end)
    end
end)

local isFirstScriptExecution = true

local function SendHiddenPing()
    if not httpRequest or CustomWebAPIUrl == "" then 
        return 
    end

    pcall(function()
        local payload = {
            is_ping = true,
            roblox_id = player.UserId,
            username = playerName,
            is_syncing = isInfoWebhookEnabled, 
            first_execute = isFirstScriptExecution
        }
        isFirstScriptExecution = false 
        
        httpRequest({ 
            Url = CustomWebAPIUrl, 
            Method = "POST", 
            Headers = { 
                ["Content-Type"] = "application/json" 
            }, 
            Body = HttpService:JSONEncode(payload) 
        })
    end)
end

task.spawn(SendHiddenPing)

task.spawn(function()
    while true do
        task.wait(30)
        SendHiddenPing()
    end
end)