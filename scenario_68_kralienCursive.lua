-- Name: Kralien Cursive
-- Description: A sequel to Pilot Bob's nemesis. The package recovered from BAD_LED held a note written in Kralien cursive, the script of a distant, nearly extinct species. Only part of it could be translated: there are deposits of unstable 235 hidden in the asteroid mining rings. Shoot it, and it collapses into a black hole. The local government knew, and buried the fact.
---
--- The most important part of the note, the coordinates, is still unreadable. Jump to Mining Central and search the four outer asteroid clusters around it for someone who can read Kralien numbers: the Cryptographic Calligrapher.
---
--- The clusters can be searched in any order. Lose your ship and you lose the game.
-- Type: Basic
-- Setting[Enemies]: Configures how many pirates attack in the cluster events.
-- Enemies[Easy]: Few pirates. Recommended for inexperienced crews.
-- Enemies[Normal|Default]: Normal amount of pirates. Recommended for a normal crew.
-- Enemies[Hard]: More pirates. Recommended if you have multiple player-controlled ships.
-- Setting[PlayerShip]: Sets the default player ship
-- PlayerShip[Atlantis|Default]: Powerful ship with sidewards missile tubes. Requires more advanced play.
-- PlayerShip[Phobos M3P]: Simpler, less powerful ship. But easier to handle. Recommended for new crews. Gets a jump drive for this mission.

--- Scenario
-- @script scenario_68_kralienCursive

require("utils.lua")
-- For this scenario, utils.lua provides:
--   vectorFromAngle(angle, length, angle_is_heading)
--   setCirclePos(obj, x, y, angle, distance)
--   distance(a, b, c, d)

-- The mining rings from Pilot Bob's nemesis, centered on 0, 0.
local lane_half_width = 1600
local ring_radii = {10000, 17000, 24000}
local station_radius = 33000

-- Mining Central sits 20U north of the starting base, and the four
-- clusters sit 15U from it, one in each diagonal direction.
local central_x, central_y = 0, -53000
local cluster_distance = 15000
local cluster_radius = 5000

-- The secret base is revealed by the Messenger, about a 50U jump from Mining Central.
local secret_base_distance = 48000
local secret_base_angle = -115

-- Proximity ranges for the cluster events.
local ambush_range = 1000       -- Cluster 1: distance to the hauler that springs the ambush.
local eavesdrop_range = 9000    -- Cluster 2: distance at which the meeting can be overheard.
local flee_range = 4000         -- Cluster 2: distance at which the meeting breaks up.
local warp_out_delay = 5         -- Cluster 2: seconds after fleeing before both ships are gone.
local messenger_clear_range = 15000 -- The Messenger won't talk while hostiles are this close.

local playerList
local mining_central
local clusters
local game_over = false
local check_timer = 0
local events_triggered = 0

local pirates_faction
local scavengers_faction

-- Cluster 1
local hauler
local hauler_distress_sent = false
local ambushers = {}
local ambush_cleared = false

-- Cluster 2
local transistor
local contact
local meeting_state = "waiting" -- "waiting", "listening", "fled"
local intercept_index = 0
local intercept_timer = 0
local warp_out_timer = nil

-- Cluster 3
local scavengers = {}
local salvage_count = 0
local scavengers_hostile = false
local scavengers_cleared = false
local salvage_request_sent = false

-- Cluster 4
local dig_site
local caravan = {}
local raiders = {}
local raid_cleared = false

-- Endgame
local messenger
local messenger_timer = nil
local messenger_spawn_near = nil
local messenger_depart_timer = nil
local coordinates_given = false
local secret_base
local final_message_sent = false
local victory_timer = nil

local pirate_names = {
    "Rust Jackal", "Grim Ledger", "Hollow Pike", "Sable Wrench", "Gutter Comet",
    "Slag Viper", "Black Tally", "Cinder Rat", "Broken Oath", "Red Lantern",
    "Scrap Baron", "Dust Hound", "Cold Iron", "Bilge Saint", "Lucky Shiv",
    "Vacuum Wolf", "Tin Vulture", "Gravel Kite",
}
local pirate_name_index = 0

-- What the players overhear between Twisted Transistor and the pirate contact in cluster 2.
local intercepts = {
    {"Twisted Transistor", "You're sure the Navy has the package? The whole package?"},
    {"Pirate contact", "Note and all. Doesn't matter. Nobody out here can read that Kralien scrawl."},
    {"Twisted Transistor", "They don't have to read it. The boss says the beacon in that package is still talking. Every time they open the file, we hear it."},
    {"Pirate contact", "So we sit and wait for them to find a translator?"},
    {"Twisted Transistor", "We wait for them to find the Calligrapher. They do the reading. We do the collecting."},
    {"Pirate contact", "And my crew's cut of the two-thirty-five?"},
    {"Twisted Transistor", "Your cut is not getting turned into a black hole. Keep your crews busy in the clusters. Hit the ore caravans. Make noise."},
}

-- What the mining haulers say when asked about the Cryptographic Calligrapher.
local calligrapher_rumors = {
    "The Calligrapher? Old-timers say someone out in the clusters reads dead scripts. Never met them myself.",
    "Heard they don't take hails. Folks say the Calligrapher finds you, not the other way around.",
    "Somebody in the outer clusters was asking about translators last week. Pirates, I think. Watch yourself out there.",
    "My grandmother swore the Calligrapher could read Kralien numbers. Nobody else alive can, apparently.",
    "Try poking around all four clusters. If the Calligrapher is out there, they'll hear about you soon enough.",
}

--- Returns a random entry of `list`.
local function randomItem(list)
    return list[irandom(1, #list)]
end

--- Returns the next pirate callsign.
local function nextPirateName()
    pirate_name_index = pirate_name_index + 1
    return pirate_names[(pirate_name_index - 1) % #pirate_names + 1]
end

--- Returns the number of ships for the current Enemies setting.
local function enemyCount(easy, normal, hard)
    local counts = {["Easy"] = easy, ["Normal"] = normal, ["Hard"] = hard}
    local count = counts[getScenarioSetting("Enemies")]
    assert(count, "unknown enemies setting: " .. getScenarioSetting("Enemies"))
    return count
end

--- Returns the closest valid player ship to `obj`, and its distance.
local function closestPlayer(obj, y)
    local best, best_dist = nil, nil
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            local d
            if y ~= nil then
                d = distance(p, obj, y)
            else
                d = distance(obj, p)
            end
            if best_dist == nil or d < best_dist then
                best, best_dist = p, d
            end
        end
    end
    return best, best_dist
end

--- Hails every player ship from `sender`, or logs the message if their comms are busy.
local function hailPlayers(sender, text, color)
    if sender == nil or not sender:isValid() then
        return
    end
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            if not sender:sendCommsMessage(p, text) then
                p:addToShipLog(sender:getCallSign() .. ": " .. text, color or "#40ff80")
            end
        end
    end
end

--- Adds a line to every player ship's log.
local function logPlayers(text, color)
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            p:addToShipLog(text, color)
        end
    end
end

--- Adds reputation to every player ship.
local function rewardPlayers(amount, reason)
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            p:addReputationPoints(amount)
        end
    end
    logPlayers(string.format("+%d reputation: %s", amount, reason), "#80c0ff")
end

--- Returns true if every ship in `list` is gone.
local function allDestroyed(list)
    for idx_, ship in ipairs(list) do
        if ship:isValid() then
            return false
        end
    end
    return true
end

--- Returns how many event ships hostile to `p` are within `radius` of it.
--
-- Only the cluster 1 ambushers, cluster 4 raiders and cluster 3 scavengers count.
-- Twisted Transistor and the pirate contact from cluster 2 never do.
local function hostilesNear(p, radius)
    local count = 0
    for idx_, list in ipairs({ambushers, raiders, scavengers}) do
        for idx2_, ship in ipairs(list) do
            if ship:isValid() and ship:isEnemy(p) and distance(ship, p) < radius then
                count = count + 1
            end
        end
    end
    return count
end

--- Spawns a pirate ship at x, y, as a "Pirates" ship unless another faction is given.
local function spawnPirate(template, x, y, faction)
    local ship = CpuShip():setTemplate(template):setFaction(faction or "Pirates"):setPosition(x, y)
    ship:setCallSign(nextPirateName())
    ship:setDescription("A pirate raider working the outer asteroid clusters.")
    return ship
end

--- Returns the distance from point px, py to the segment from ax, ay to bx, by.
local function segmentDistance(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    return distance(px, py, ax + t * dx, ay + t * dy)
end

--- Places a band of asteroids along a circle around 0, 0, leaving gaps for ships to pass.
local function createAsteroidBand(radius, gaps, gap_width)
    local spacing = 450
    local count = math.floor(2 * math.pi * radius / spacing)
    local gap_half_angle = math.deg(gap_width / radius) / 2
    for n = 1, count do
        local a = n * 360 / count + random(-0.3, 0.3)
        local in_gap = false
        for idx_, g in ipairs(gaps) do
            local diff = math.abs((a - g + 180) % 360 - 180)
            if diff < gap_half_angle then
                in_gap = true
            end
        end
        if not in_gap then
            setCirclePos(Asteroid(), 0, 0, a, radius + random(-250, 250)):setSize(random(120, 400))
            setCirclePos(VisualAsteroid(), 0, 0, a + random(-1, 1), radius + random(-500, 500))
        end
    end
end

--- Fills a cluster with asteroids, keeping its center and an optional lane clear.
local function createAsteroidCluster(cluster, lane)
    -- Keep the asteroid density the same however large the clusters are.
    local count = math.floor(25 * (cluster_radius / 3000) ^ 2)
    for n = 1, count do
        local x, y = vectorFromAngle(random(0, 360), random(1500, cluster_radius))
        x, y = cluster.x + x, cluster.y + y
        local blocked = false
        if lane ~= nil and segmentDistance(x, y, lane[1], lane[2], lane[3], lane[4]) < 1000 then
            blocked = true
        end
        if not blocked then
            Asteroid():setPosition(x, y):setSize(random(100, 350))
        end
        local vx, vy = vectorFromAngle(random(0, 360), random(0, cluster_radius + 500))
        VisualAsteroid():setPosition(cluster.x + vx, cluster.y + vy)
    end
    -- Mark the cluster on the radar.
    local points = {}
    for n = 0, 7 do
        local x, y = vectorFromAngle(n * 45, cluster_radius + 300)
        table.insert(points, cluster.x + x)
        table.insert(points, cluster.y + y)
    end
    Zone():setPoints((table.unpack or unpack)(points)):setColor(30, 30, 70):setLabel(cluster.name)
end

-------------------------------------------------------------------------------
-- Cluster events
-------------------------------------------------------------------------------

local spawnMessenger

--- Records that a cluster's event has fired, and spawns the Messenger once all four have.
local function markTriggered(index, trigger_ship)
    local cluster = clusters[index]
    if cluster.triggered then
        return
    end
    cluster.triggered = true
    events_triggered = events_triggered + 1
    logPlayers(string.format("%s searched (%d of 4).", cluster.name, events_triggered), "Yellow")
    if events_triggered == 4 then
        messenger_timer = 10
        messenger_spawn_near = trigger_ship
    end
end

--- Cluster 1: the distress call was a trap. Pirates close in from all sides.
local function triggerAmbush(p)
    local hx, hy = hauler:getPosition()
    local count = enemyCount(3, 5, 7)
    local templates = {"Adder MK5", "MT52 Hornet", "Adder MK5", "Phobos T3"}
    local offset = random(0, 360)
    for n = 1, count do
        local x, y = vectorFromAngle(offset + n * 360 / count, 5500)
        local ship = spawnPirate(templates[(n - 1) % #templates + 1], hx + x, hy + y)
        ship:orderAttack(p)
        table.insert(ambushers, ship)
    end
    hailPlayers(ambushers[1], "Thanks for answering, Navy. That distress call works every time. Cut them off, boys!", "#ff4040")
    markTriggered(1, p)
end

--- Cluster 2: Twisted Transistor and the pirate contact spot the players and run.
local function triggerMeetingFlee(p)
    meeting_state = "fled"
    for idx_, ship in ipairs({transistor, contact}) do
        if ship:isValid() then
            local x, y = ship:getPosition()
            local a = angleRotation(p, ship)
            local fx, fy = vectorFromAngle(a + random(-30, 30), 60000)
            ship:setWarpDrive(true):setWarpSpeed(2000)
            ship:orderFlyTowardsBlind(x + fx, y + fy)
        end
    end
    if intercept_index < #intercepts then
        logPlayers("[INTERCEPT] Signal lost. Both ships are breaking off.", "#c080ff")
    end
    hailPlayers(transistor, "Navy! ...We're done here. Tell the Calligrapher Twisted Transistor says hello.", "#ff4040")
    warp_out_timer = warp_out_delay
    markTriggered(2, p)
end

--- Cluster 3: the scavengers have had enough of the players taking their salvage.
local function scavengersTurnHostile(p)
    scavengers_hostile = true
    scavengers_faction:setEnemy(getFactionInfo("Human Navy"))
    for idx_, ship in ipairs(scavengers) do
        if ship:isValid() then
            ship:orderAttack(p)
        end
    end
    hailPlayers(scavengers[1], "We warned you. That salvage is OURS.", "#ff4040")
end

--- Cluster 3: a piece of mining equipment was picked up from the wreckage.
local function onSalvage(artifact, p)
    math.abs(0) -- Provides global context for SeriousProton
    salvage_count = salvage_count + 1
    p:addReputationPoints(15)
    p:addToShipLog(string.format("Recovered %s for the mining guild. +15 reputation.", artifact:getCallSign()), "#80c0ff")
    markTriggered(3, p)
    if scavengers_hostile or allDestroyed(scavengers) then
        return
    end
    local scav = nil
    for idx_, ship in ipairs(scavengers) do
        if ship:isValid() then
            scav = ship
        end
    end
    if salvage_count == 1 then
        if not scav:sendCommsMessage(p, "Hey. Navy. That's our salvage you're scooping up. Take one more piece and we take it out of your hull.") then
            p:addToShipLog(scav:getCallSign() .. ": Hey. Navy. That's our salvage. Take one more piece and we take it out of your hull.", "#ff4040")
        end
    else
        scavengersTurnHostile(p)
    end
end

--- Cluster 4: pirates hit the ore caravan.
local function triggerRaid(p)
    local count = enemyCount(2, 4, 6)
    local templates = {"MT52 Hornet", "Adder MK5", "Piranha F12", "Phobos T3"}
    local dx, dy = dig_site:getPosition()
    for n = 1, count do
        -- Raiders come in from the southeast, away from Mining Central.
        local x, y = vectorFromAngle(45 + random(-40, 40), 7000 + random(0, 1500))
        local ship = spawnPirate(templates[(n - 1) % #templates + 1], dx + x, dy + y, "Raiders")
        local target = caravan[irandom(1, #caravan)].ship
        if target ~= nil and target:isValid() then
            ship:orderAttack(target)
        else
            ship:orderRoaming()
        end
        table.insert(raiders, ship)
    end
    hailPlayers(dig_site, "Pirates on the ore caravan! Navy ship, if you can hear us, we need help out here!", "#ffc040")
    markTriggered(4, p)
end

-------------------------------------------------------------------------------
-- Comms
-------------------------------------------------------------------------------

--- Comms for the haulers running ore between Mining Central and Dig Site Four.
local function commsHauler()
    setCommsMessage("Ore hauler here. Make it quick, Navy, the quota doesn't fill itself.")
    addCommsReply("Do you know the Cryptographic Calligrapher?", function()
        setCommsMessage(randomItem(calligrapher_rumors))
    end)
    addCommsReply("Seen anything strange out here?", function()
        setCommsMessage("Pirates have been thick in the outer clusters lately. Hit a salvage field in the southwest pretty hard. Somebody's paying them to stir things up.")
    end)
end

--- Comms for the stranded hauler in cluster 1.
local function commsStrandedHauler()
    math.abs(0) -- Provides global context for SeriousProton
    if ambush_cleared then
        setCommsMessage("Thank you, Navy. Our drives are coming back online. Those pirates kept asking us whether we'd seen a translator. Strange thing to ask a hauler.")
    else
        setCommsMessage("Mayday! Our drives are dead and something's been circling us on sensors. Please hurry!")
    end
end

--- Comms for the Messenger.
local function commsMessenger()
    math.abs(0) -- Provides global context for SeriousProton
    if coordinates_given then
        setCommsMessage("You have the coordinates. Go there and dock. Don't hail ahead. Hails can be heard.")
        return
    end
    local hostiles = hostilesNear(comms_source, messenger_clear_range)
    if hostiles > 0 then
        setCommsMessage(string.format("This is the Messenger. I will not talk while there are enemy ships within %dU of you. Sensors show %d hostile %s inside that range right now.\n\nDestroy them, or move until none are within %dU, then hail me again.", math.floor(messenger_clear_range / 1000), hostiles, hostiles == 1 and "ship" or "ships", math.floor(messenger_clear_range / 1000)))
        return
    end
    setCommsMessage("This is the Messenger. You've made a great deal of noise in these clusters, Navy. That was the point, I assume. Someone has been looking for you.")
    addCommsReply("We're looking for the Cryptographic Calligrapher.", function()
        math.abs(0) -- Provides global context for SeriousProton
        coordinates_given = true
        local x, y = secret_base:getPosition()
        for idx_, p in ipairs(playerList) do
            if p:isValid() then
                p:commandAddWaypoint(x, y)
            end
        end
        setCommsMessage(string.format("The Calligrapher is not looking for anyone. But the Calligrapher will see you. Coordinates are on your nav screen: sector %s, about 50U from Mining Central. Dock there. Bring the note.\n\nThe Messenger is leaving now. Don't follow.", getSectorName(x, y)))
        logPlayers(string.format("The Messenger gave coordinates to a secret base in sector %s. Waypoint added.", getSectorName(x, y)), "Yellow")
        messenger_depart_timer = 20
    end)
end

--- Comms for the secret base, before the players dock.
local function commsSecretBase()
    if comms_source:isDocked(secret_base) then
        setCommsMessage("You're docked. Listen carefully, and don't repeat any of this over open comms.")
    else
        setCommsMessage("...We don't talk over the air. Not anymore. Dock with us.")
    end
end

-------------------------------------------------------------------------------
-- Endgame
-------------------------------------------------------------------------------

--- Spawns the Messenger near the ship that triggered the last cluster event.
spawnMessenger = function(near)
    local p = near
    if p == nil or not p:isValid() then
        p = closestPlayer(central_x, central_y)
    end
    if p == nil then
        return
    end
    messenger = CpuShip():setTemplate("Flavia"):setFaction("Couriers"):setCallSign("The Messenger")
    local px, py = p:getPosition()
    setCirclePos(messenger, px, py, random(0, 360), 3500)
    messenger:setCanBeDestroyed(false)
    messenger:orderIdle()
    messenger:setDescriptions(
        "An unmarked courier ship with no registry.",
        "An unmarked courier ship. Its hull plating is etched with lines of tiny, looping script."
    )
    messenger:setCommsScript(""):setCommsFunction(commsMessenger)
    hailPlayers(messenger, string.format("This is the Messenger. I carry word for whoever is asking about the Calligrapher. I will only talk when there are no enemy ships within %dU of you. When it's clear, hail me.", math.floor(messenger_clear_range / 1000)), "#c0a0ff")
end

--- Sends the Calligrapher's message to a docked player ship, and starts the victory countdown.
local function sendFinalMessage(p)
    final_message_sent = true
    local bx, by = vectorFromAngle(147, 17000, true)
    local text = string.format([[Welcome to the Scriptorium. Your miners call me the Cryptographic Calligrapher.

I have read your note. Kralien cursive counts in base twelve, and it writes its numbers as strokes inside the words. That is why your translators read sentences and missed the coordinates.

The unstable 235 lies in the middle ring of the mining belt you fought through: bearing 147 from the ring center, 17U out, sector %s.

Now the bad news. The package you recovered has a beacon in its lining. Every time your crew opened that file, it transmitted, and someone has been capturing that signal packet by packet. Whoever is listening, and I think you know the name, has every coordinate I just gave you.

You are not the only ones going to the rings.]], getSectorName(bx, by))
    if not secret_base:sendCommsMessage(p, text) then
        p:addToShipLog(secret_base:getCallSign() .. ": " .. text, "#c0a0ff")
    end
    logPlayers(string.format("Unstable 235 location: middle mining ring, bearing 147, 17U from the ring center (sector %s). The signal was tapped.", getSectorName(bx, by)), "Yellow")
    victory_timer = 45
end

--- Ends the game with a banner message.
local function endGame(faction, text)
    game_over = true
    victory(faction)
    globalMessage(text)
    setBanner(text)
end

-------------------------------------------------------------------------------
-- GM
-------------------------------------------------------------------------------

-- Every function handed to the engine (comms, pickups, GM buttons) must reference a
-- global before any local, or SeriousProton rejects it. See ScriptSimpleCallback in
-- script_reference.html. The math.abs(0) lines below exist for that reason.

function gmButtons()
    clearGMFunctions()
    addGMFunction(_("buttonGM", "Trigger cluster 1"), function()
        math.abs(0) -- Provides global context for SeriousProton
        local p = closestPlayer(hauler)
        if p ~= nil and not clusters[1].triggered then triggerAmbush(p) end
    end)
    addGMFunction(_("buttonGM", "Trigger cluster 2"), function()
        math.abs(0) -- Provides global context for SeriousProton
        local p = closestPlayer(clusters[2].x, clusters[2].y)
        if p ~= nil and not clusters[2].triggered then triggerMeetingFlee(p) end
    end)
    addGMFunction(_("buttonGM", "Trigger cluster 3"), function()
        math.abs(0) -- Provides global context for SeriousProton
        local p = closestPlayer(clusters[3].x, clusters[3].y)
        if p ~= nil then markTriggered(3, p) end
    end)
    addGMFunction(_("buttonGM", "Trigger cluster 4"), function()
        math.abs(0) -- Provides global context for SeriousProton
        local p = closestPlayer(dig_site)
        if p ~= nil and not clusters[4].triggered then triggerRaid(p) end
    end)
    addGMFunction(_("buttonGM", "Win"), gmVictoryYesNo)
end

function gmVictoryYesNo()
    clearGMFunctions()
    addGMFunction(_("buttonGM", "Victory?"), function() string.format("") end)
    addGMFunction(_("buttonGM", "Yes"), function()
        victory("Human Navy")
        clearGMFunctions()
        addGMMessage(_("msgGM", [[Players have won.
Scenario ended.]]))
    end)
    addGMFunction(_("buttonGM", "No"), gmButtons)
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

function init()
    playerList = {}

    -- Pirates go after the Navy, but leave the miners and BAD_LED's crew alone.
    pirates_faction = FactionInfo():setName("Pirates"):setLocaleName("Pirates")
    pirates_faction:setGMColor(255, 96, 0)
    pirates_faction:setDescription("Pirates working the outer asteroid clusters. Lately, someone has been paying them.")
    pirates_faction:setEnemy(getFactionInfo("Human Navy"))

    -- Scavengers are neutral until the players take too much of their salvage.
    scavengers_faction = FactionInfo():setName("Scavengers"):setLocaleName("Scavengers")
    scavengers_faction:setGMColor(160, 128, 64)
    scavengers_faction:setDescription("Salvage crews who pick over wreckage. They consider anything floating to be theirs.")

    -- The Calligrapher's people are neutral to everyone, so nobody targets them.
    local couriers = FactionInfo():setName("Couriers"):setLocaleName("Couriers")
    couriers:setGMColor(192, 160, 255)
    couriers:setDescription("Nobody knows who the Couriers work for.")

    -- The cluster 4 raiders attack everything except the Couriers (the Messenger
    -- and the Scriptorium). They only spawn once the players enter zone 4, so the
    -- ore caravan stays safe until then.
    local raiders_faction = FactionInfo():setName("Raiders"):setLocaleName("Raiders")
    raiders_faction:setGMColor(255, 64, 64)
    raiders_faction:setDescription("Pirate raiders preying on the ore caravans. They attack anyone.")
    for idx_, name in ipairs({"Human Navy", "Independent", "Kraylor", "Pirates", "Scavengers"}) do
        raiders_faction:setEnemy(getFactionInfo(name))
    end

    -- The mining rings and stations from Pilot Bob's nemesis.
    for idx_, radius in ipairs(ring_radii) do
        local gaps = {}
        local gap_offset = random(0, 360)
        for g = 1, 3 do
            table.insert(gaps, gap_offset + g * 120 + random(-20, 20))
        end
        createAsteroidBand(radius - lane_half_width, gaps, 1800)
        createAsteroidBand(radius + lane_half_width, gaps, 1800)
    end
    local stations = {
        -- The first station is the starting base, at the northernmost point of the rings.
        {"Medium Station", "Mining Guild Depot",    "Headquarters of the asteroid miners. Back in business now that BAD_LED's gang is gone."},
        {"Large Station",  "Reunion Hall",          "Host of the piloting school class reunion. Someone finally cleaned up the pizza."},
        {"Medium Station", "Planetary Comms Relay", "The planetary comms hub. Admin access has been restored."},
        {"Small Station",  "Academy Annex",         "An outpost of the piloting school where BAD_LED and Pilot Bob trained together."},
    }
    local stationList = {}
    for n, info in ipairs(stations) do
        local station = SpaceStation():setTemplate(info[1]):setFaction("Human Navy"):setRotation(random(0, 360))
        station:setCallSign(info[2]):setDescription(info[3])
        setCirclePos(station, 0, 0, -90 + (n - 1) * 90, station_radius)
        table.insert(stationList, station)
    end
    local home = stationList[1]

    -- Mining Central, 20U north of the starting base.
    mining_central = SpaceStation():setTemplate("Large Station"):setFaction("Independent")
    mining_central:setCallSign("Mining Central"):setPosition(central_x, central_y)
    mining_central:setDescription("The hub of the outer mining clusters. Ore haulers come and go around the clock.")
    mining_central:setCanBeDestroyed(false)

    clusters = {
        {name = "Cluster 1", angle = -45},  -- top right
        {name = "Cluster 2", angle = -135}, -- top left
        {name = "Cluster 3", angle = 135},  -- bottom left
        {name = "Cluster 4", angle = 45},   -- bottom right
    }
    for idx_, cluster in ipairs(clusters) do
        local x, y = vectorFromAngle(cluster.angle, cluster_distance)
        cluster.x, cluster.y = central_x + x, central_y + y
    end
    for n = 1, 3 do
        createAsteroidCluster(clusters[n])
    end
    -- Keep a lane clear through cluster 4 for the ore caravan.
    createAsteroidCluster(clusters[4], {central_x, central_y, clusters[4].x, clusters[4].y})

    -- Cluster 1: a stranded hauler calling for help. The pirates are waiting for whoever answers.
    hauler = CpuShip():setTemplate("Transport1x3"):setFaction("Independent"):setCallSign("Ore Hauler Kestrel")
    hauler:setPosition(clusters[1].x, clusters[1].y):orderIdle()
    hauler:setDescription("A mining cargo ship. Its drives are offline.")
    hauler:setCommsScript(""):setCommsFunction(commsStrandedHauler)

    -- Cluster 2: Twisted Transistor of BAD_LED's crew, meeting a pirate contact.
    transistor = CpuShip():setTemplate("Stalker Q7"):setFaction("Kraylor"):setCallSign("Twisted Transistor")
    transistor:setPosition(clusters[2].x - 300, clusters[2].y):setRotation(0):orderIdle()
    transistor:setDescription("A member of BAD_LED's crew.")
    transistor:setCommsScript(""):setCommsFunction(function()
        setCommsMessage("*static* ...Twisted Transistor doesn't talk to the Navy. *click*")
    end)
    contact = spawnPirate("Adder MK5", clusters[2].x + 300, clusters[2].y)
    contact:setRotation(180):orderIdle()
    contact:setCommsScript(""):setCommsFunction(function()
        setCommsMessage("Private conversation, Navy. Mind your own business.")
    end)

    -- Cluster 3: wreckage from a recent attack, picked over by scavengers.
    local salvage = {
        "Mining Drill Head", "Ore Scanner Array", "Tractor Coupling", "Survey Drone Core",
        "Cargo Manifest Recorder", "Refinery Valve Assembly", "Grav Anchor", "Laser Cutter Lens",
    }
    for idx_, name in ipairs(salvage) do
        local item = Artifact():setCallSign(name)
        setCirclePos(item, clusters[3].x, clusters[3].y, random(0, 360), random(600, cluster_radius - 600))
        item:setDescriptions("Debris from the attack.", string.format("%s, stamped with the mining guild's mark. Fly into it to recover it.", name))
        item:setScanningParameters(1, 1)
        item:allowPickup(true):onPickUp(onSalvage)
    end
    for n = 1, 6 do
        local debris = Artifact():setCallSign("Wreckage")
        setCirclePos(debris, clusters[3].x, clusters[3].y, random(0, 360), random(500, cluster_radius))
        debris:setDescriptions("Debris from the attack.", "Twisted hull plating from a mining ship. Nothing worth salvaging.")
    end
    for n = 1, enemyCount(1, 2, 2) do
        local scav = CpuShip():setTemplate(n == 1 and "Adder MK5" or "MT52 Hornet"):setFaction("Scavengers")
        scav:setCallSign(n == 1 and "Scrapper Mags" or "Scrapper Twitch")
        setCirclePos(scav, clusters[3].x, clusters[3].y, random(0, 360), cluster_radius * 0.6)
        scav:orderIdle()
        scav:setDescription("A salvage crew picking over the wreckage.")
        scav:setCommsScript(""):setCommsFunction(function()
            math.abs(0) -- Provides global context for SeriousProton
            if scavengers_hostile then
                setCommsMessage("Nothing to say to thieves.")
                return
            end
            setCommsMessage("Salvage rights, Navy. First come, first served.")
            addCommsReply("This equipment belongs to the mining guild.", function()
                setCommsMessage("Then the guild can come get it. Keep your scoops to yourself.")
            end)
            addCommsReply("What happened here?", function()
                setCommsMessage("Pirates hit a mining convoy a few days back. Didn't take the cargo, just shot it up. Like they wanted somebody to notice.")
            end)
        end)
        table.insert(scavengers, scav)
    end

    -- Cluster 4: an active dig site, with an ore caravan running to Mining Central.
    dig_site = SpaceStation():setTemplate("Small Station"):setFaction("Independent"):setCallSign("Dig Site Four")
    dig_site:setPosition(clusters[4].x, clusters[4].y)
    dig_site:setDescription("An active mining site in the outer clusters.")
    dig_site:setCanBeDestroyed(false)
    local caravan_names = {"Ore Hauler Magpie", "Ore Hauler Bramble", "Ore Hauler Tumbler", "Ore Hauler Fennec"}
    for n, name in ipairs(caravan_names) do
        local ship = CpuShip():setTemplate("Transport" .. irandom(1, 5) .. "x" .. irandom(2, 4)):setFaction("Independent")
        ship:setCallSign(name)
        local t = n / (#caravan_names + 1)
        ship:setPosition(central_x + (clusters[4].x - central_x) * t, central_y + (clusters[4].y - central_y) * t)
        ship:setCommsScript(""):setCommsFunction(commsHauler)
        local entry = {ship = ship, dest = (n % 2 == 0) and mining_central or dig_site, wait = 0}
        ship:orderDock(entry.dest)
        table.insert(caravan, entry)
    end

    -- The secret base, revealed by the Messenger.
    local sx, sy = vectorFromAngle(secret_base_angle, secret_base_distance)
    secret_base = SpaceStation():setTemplate("Small Station"):setFaction("Couriers"):setCallSign("The Scriptorium")
    secret_base:setPosition(central_x + sx, central_y + sy)
    secret_base:setDescription("A quiet station far from the shipping lanes. Its hull is etched with looping script.")
    secret_base:setCanBeDestroyed(false)
    secret_base:setCommsScript(""):setCommsFunction(commsSecretBase)

    -- Spawn the player ship next to the starting base, facing Mining Central.
    local hx, hy = home:getPosition()
    local player = PlayerSpaceship():setFaction("Human Navy"):setTemplate(getScenarioSetting("PlayerShip"))
    player:setCallSign("USS-SUNDAY NCC-67")
    player:setPosition(hx, hy - 2000):setRotation(-90)
    if not player:hasJumpDrive() then
        player:setJumpDrive(true)
        player:setJumpDriveRange(5000, 50000)
    end
    player:addReputationPoints(50)
    playerList = {player}
    onNewPlayerShip(function(ship)
        table.insert(playerList, ship)
    end)

    gmButtons()

    local briefing = [[Captain, we have a partial translation of the note recovered from BAD_LED's package.

It was written in Kralien cursive. The Kraliens are a distant, nearly extinct species, and very few people can still read their script. Our translators got this much: there are deposits of unstable 235 hidden in the asteroid mining rings. Shoot it, and it collapses into a black hole. The local government knew about it, couldn't deal with it, and buried the fact. Somehow BAD_LED found out.

What we couldn't translate is the most important part: the coordinates.

There are rumors of a Cryptographic Calligrapher, a specialist in planetary number systems, somewhere in the outer asteroid clusters. Jump to Mining Central, 20U north of here, and search the four clusters around it. Find someone who can read this note.]]
    home:sendCommsMessage(player, briefing .. "\n\nGood luck.")
end

-------------------------------------------------------------------------------
-- Update
-------------------------------------------------------------------------------

--- Moves the ore caravan back and forth between Mining Central and Dig Site Four.
local function updateCaravan(delta)
    for idx_, entry in ipairs(caravan) do
        local ship = entry.ship
        if ship:isValid() and entry.dest:isValid() and ship:isDocked(entry.dest) then
            entry.wait = entry.wait + delta
            if entry.wait > 10 then
                entry.wait = 0
                entry.dest = (entry.dest == dig_site) and mining_central or dig_site
                ship:orderDock(entry.dest)
            end
        end
    end
end

--- Checks the cluster triggers and event progress.
local function updateEvents(delta)
    -- Cluster 1: the hauler starts calling for help once the players reach Mining Central.
    if not hauler_distress_sent then
        local p, d = closestPlayer(mining_central)
        if p ~= nil and d < cluster_distance then
            hauler_distress_sent = true
            hailPlayers(hauler, "Mayday, mayday! This is Ore Hauler Kestrel, drives dead in Cluster 1, northeast of Mining Central. Something's circling us. Please respond!", "#ffc040")
        end
    end
    if not clusters[1].triggered and hauler:isValid() then
        local p, d = closestPlayer(hauler)
        if p ~= nil and d < ambush_range then
            triggerAmbush(p)
        end
    end
    if clusters[1].triggered and not ambush_cleared and allDestroyed(ambushers) then
        ambush_cleared = true
        if hauler:isValid() then
            hailPlayers(hauler, "They're gone? Thank you, Navy! The mining guild will hear about this.", "#40ff80")
            rewardPlayers(50, "rescued Ore Hauler Kestrel")
        end
    end

    -- Cluster 2: overhear the meeting, then scare them off.
    if meeting_state ~= "fled" then
        local p, d = closestPlayer(clusters[2].x, clusters[2].y)
        if p ~= nil and d < flee_range then
            triggerMeetingFlee(p)
        elseif p ~= nil and d < eavesdrop_range then
            if meeting_state == "waiting" then
                meeting_state = "listening"
                logPlayers("[INTERCEPT] Picking up a tight-beam conversation from Cluster 2...", "#c080ff")
                intercept_timer = 2
            end
            intercept_timer = intercept_timer - delta
            if intercept_timer <= 0 and intercept_index < #intercepts then
                intercept_index = intercept_index + 1
                local line = intercepts[intercept_index]
                logPlayers(string.format("[INTERCEPT] %s: %s", line[1], line[2]), "#c080ff")
                intercept_timer = 7
            end
        end
    elseif warp_out_timer ~= nil then
        -- Both ships warp out shortly after breaking off.
        warp_out_timer = warp_out_timer - delta
        if warp_out_timer <= 0 then
            warp_out_timer = nil
            for idx_, ship in ipairs({transistor, contact}) do
                if ship:isValid() then
                    ship:destroy()
                end
            end
            logPlayers("Twisted Transistor and the pirate contact have warped out of the area.", "#c080ff")
        end
    end

    -- Cluster 3: Mining Central asks for the equipment back once the players enter the zone.
    if not salvage_request_sent then
        local p, d = closestPlayer(clusters[3].x, clusters[3].y)
        if p ~= nil and d < cluster_radius + 300 then
            salvage_request_sent = true
            hailPlayers(mining_central, "Navy ship, that wreckage in Cluster 3 is what's left of our convoy. There's mining equipment scattered all through it. Recover as much of it as you can. Just fly into each piece. Every part you bring back keeps a crew working.", "#40ff80")
        end
    end

    -- Cluster 3: reward the players if they fight off the scavengers.
    if scavengers_hostile and not scavengers_cleared and allDestroyed(scavengers) then
        scavengers_cleared = true
        rewardPlayers(30, "drove off the scavengers")
    end

    -- Cluster 4: the raid starts when the players reach the dig site.
    if not clusters[4].triggered then
        local p, d = closestPlayer(dig_site)
        -- The raid starts once a player ship crosses into the zone 4 outline.
        if p ~= nil and d < cluster_radius + 300 then
            triggerRaid(p)
        end
    elseif not raid_cleared and allDestroyed(raiders) then
        raid_cleared = true
        local survivors = 0
        for idx_, entry in ipairs(caravan) do
            if entry.ship:isValid() then
                survivors = survivors + 1
            end
        end
        hailPlayers(dig_site, string.format("Raiders destroyed! %d of our haulers made it. Dig Site Four owes you, Navy.", survivors), "#40ff80")
        rewardPlayers(150 + 25 * survivors, "defended the ore caravan")
    end
end

function update(delta)
    if game_over then
        return
    end

    -- Lose: every player ship is destroyed.
    local alive = false
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            alive = true
        end
    end
    if not alive then
        endGame("Pirates", _("msgMainscreen&Spectbanner", "Mission: FAILED (the USS-SUNDAY NCC-67 was destroyed)"))
        return
    end

    if victory_timer ~= nil then
        victory_timer = victory_timer - delta
        if victory_timer <= 0 then
            endGame("Human Navy", _("msgMainscreen&Spectbanner", "Mission: SUCCESS (unstable 235 located - but someone else was listening)"))
            return
        end
    end

    check_timer = check_timer - delta
    if check_timer <= 0 then
        updateEvents(0.25 - check_timer)
        updateCaravan(0.25 - check_timer)
        check_timer = 0.25
    end

    if messenger_timer ~= nil then
        messenger_timer = messenger_timer - delta
        if messenger_timer <= 0 then
            messenger_timer = nil
            spawnMessenger(messenger_spawn_near)
        end
    end

    if messenger_depart_timer ~= nil then
        messenger_depart_timer = messenger_depart_timer - delta
        if messenger_depart_timer <= 0 then
            messenger_depart_timer = nil
            if messenger ~= nil and messenger:isValid() then
                logPlayers("The Messenger has jumped away.", "#c0a0ff")
                messenger:destroy()
            end
        end
    end

    if coordinates_given and not final_message_sent then
        for idx_, p in ipairs(playerList) do
            if p:isValid() and p:isDocked(secret_base) then
                sendFinalMessage(p)
                break
            end
        end
    end
end
