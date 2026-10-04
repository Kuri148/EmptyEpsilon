-- Name: Pilot Bob's nemesis
-- Description: An old piloting school classmate has resurfaced for the class reunion, and there's still bad blood between the infamous BAD_LED and the renowned Pilot Bob of the USS Sunday (NCC-67).
---
--- After storming off over pizza and apple beer, BAD_LED rallied his gang, seized a set of asteroid mining rings, stole a warp jammer and hijacked the planetary comms system to blast taunts at Bob on every channel.
---
--- Navigate the belts and patrols, settle the dispute, and restore the mining industry and the planetary comms. The gang only attacks if you get too close. Destroy BAD_LED to win. Lose the USS Sunday and you lose the game. Friendly stations outside the rings are ignored by the gang, so you can dock there to repair and restock.
---
--- But why such an extravagant retaliation over an Enterprise banana pudding tray? Is there something else in the asteroid mines?
-- Type: Basic
-- Setting[Enemies]: Configures how many patrol ships circle in each ring.
-- Enemies[Empty]: No patrols. Only BAD_LED waits at the center.
-- Enemies[Easy]: Few patrols. Recommended for inexperienced crews.
-- Enemies[Normal|Default]: Normal amount of patrols. Recommended for a normal crew.
-- Enemies[Hard]: More patrols. Recommended if you have multiple player-controlled ships.
-- Enemies[Extreme]: Many patrols. Inexperienced player crews will pretty surely be overwhelmed.
-- Setting[Time]: Sets up how much time the players have for the scenario
-- Time[Unlimited|Default]: No time limit
-- Time[20min]: Automatic loss after 20 minutes
-- Time[30min]: Automatic loss after 30 minutes
-- Time[60min]: Automatic loss after 60 minutes
-- Setting[PlayerShip]: Sets the default player ship
-- PlayerShip[Atlantis|Default]: Powerful ship with sidewards missile tubes. Requires more advanced play.
-- PlayerShip[Phobos M3P]: Simpler, less powerful ship. But easier to handle. Recommended for new crews.

--- Scenario
-- @script scenario_67_theNemesisOfCaptainBob

require("utils.lua")
-- For this scenario, utils.lua provides:
--   vectorFromAngle(angle, length)
--      Returns a relative vector (x, y coordinates)
--   setCirclePos(obj, x, y, angle, distance)
--      Returns the object with its position set to the resulting coordinates.
--   distance(a, b, c, d)
--      Returns the distance between two objects/coordinates
--   angleRotation(a, b, c, d)
--      Returns the bearing between first object/coordinate and second object/coordinate.

-- Global variables for this scenario
local patrolList        -- Each entry: {ship = CpuShip, radius = ring radius, direction = 1 or -1, state = "patrol" or "attack"}
local stationList
local playerList
local bad_led
local jammer

local gametimeleft = nil -- Maximum game time in seconds.
local timewarning = nil -- Used for checking when to give a warning, and to update it so the warning happens once.

local order_timer = 0       -- Patrol orders are refreshed on this interval instead of every frame.
local taunt_timer = 20      -- Seconds until BAD_LED's next taunt.
local taunt_count = 0       -- Every third taunt is broadcast to every main screen over the hijacked planetary comms.
local chatter_timer = 75    -- Seconds until the next station chatter message.
local chatter_index = 0
local game_over = false
local half_hull_taunted = false
local first_aggro_taunted = false

-- Patrols attack a player ship that comes within aggro_range,
-- and return to their ring once it gets beyond disengage_range.
local aggro_range = 5000
local disengage_range = 12000

-- Rings from the inside out. Patrols fly in the clear lane at `radius`,
-- between two asteroid bands at `radius +/- lane_half_width`.
local lane_half_width = 1600
local rings = {
    {radius = 10000, direction = 1,  templates = {"Nirvana R5", "Stalker Q7"}},
    {radius = 17000, direction = -1, templates = {"Phobos T3", "Piranha F12"}},
    {radius = 24000, direction = 1,  templates = {"MT52 Hornet", "Adder MK5"}},
}
local station_radius = 33000

-- A warp/jump jammer at the center covers all rings, so the players have to
-- fly in on impulse. It must stay smaller than station_radius.
local jammer_range = 27000

--- Creates the central jammer. Called again if it gets destroyed.
local function spawnJammer()
    jammer = WarpJammer():setFaction("Kraylor"):setRange(jammer_range):setPosition(0, 0)
    jammer:setCallSign("Stolen Warp Jammer")
    jammer:setDescription("A warp jammer stolen by BAD_LED. Blocks warp and jump drives inside the mining rings.")
end

local taunts = {
    "Bob! BOB! Enjoying the class reunion? I'm enjoying my new asteroid mines.",
    "Remember piloting school, Bob? I do. I remember EVERYTHING.",
    "You took the last slice of pizza, Bob. The LAST. SLICE.",
    "I was drinking APPLE BEER, Bob. A man should be able to enjoy his apple beer in peace.",
    "You KNEW that Enterprise banana pudding tray was mine, Bob. You KNEW.",
    "Attention all channels: this is BAD_LED. Pilot Bob still parallel parks like a drunk space cow.",
    "This planetary comms system is now property of BAD_LED. Hi Bob!",
    "Hello, USS Sunday! Is it Sunday? Good, because it's about to be your day of rest. Permanently.",
    "NCC-67? More like 67th out of 67 in our graduating class, Bob.",
    "My rings, my rules, Bob. The mining guild can send their complaints to my gang.",
    "Every asteroid out here is named after one of your failures, Bob. I ran out of asteroids.",
    "Nice warp drive, Bob. Shame about my warp jammer.",
    "Class superlatives, Bob: 'Most Likely To Get Jammed'. That's you.",
    "Keep circling, Bob. My gang does it better.",
    "Go on, run back to the reunion, Bob. Grab some pizza before I blow you up.",
    "You'll never reach the center, Bob. Nobody reaches the center.",
    "Stay out of the mines, Bob. There is nothing in the mines. Stop thinking about the mines.",
    "Blink, blink, Bob. That's me, the last light you'll ever see.",
}

local hail_replies = {
    "You called, Bob? Calling to surrender?",
    "Bob, Bob, Bob. Talking won't save you.",
    "BAD_LED is busy plotting your doom. Leave a message after the explosion.",
    "Oh, it's YOU again. Come closer, Bob. I dare you.",
    "Is this Bob? Did you bring back my banana pudding tray? No? Then goodbye.",
}

-- Callsigns for BAD_LED's gang, shuffled each game. There are more names than
-- the maximum number of patrols (9 per ring on Extreme), so no name repeats.
local gang_names = {
    "Shorted Fuse", "Blown Capacitor", "Fried Resistor", "Cold Solder Joint", "Floating Ground",
    "Leaky Diode", "Burnt Transistor", "Cracked Crystal", "Loose Wire", "Stuck Relay",
    "Bent Pin", "Frayed Cable", "Dead Pixel", "Ground Loop", "Brownout",
    "Power Surge", "Static Shock", "Magic Smoke", "Reversed Polarity", "Swollen Battery",
    "Tripped Breaker", "Overvolt", "Arc Flash", "Dim Bulb", "Melted Jumper",
    "Noisy Pot", "Dead Short", "Rusty Terminal", "Flickering Filament", "Crossed Wires",
}

-- Messages from the friendly stations, sent in order to the ship logs.
local station_chatter = {
    {2, "Our miners are stranded outside the rings. Please get BAD_LED and his gang out of there so we can get back to work."},
    {3, "We have lost admin access to planetary comms. We apologize for the... content currently playing on every channel."},
    {1, "The reunion committee would like to remind everyone that the pizza was shared equally. Mostly."},
    {4, "Academy records confirm BAD_LED and Pilot Bob shared a training simulator. It has never been the same since."},
    {2, "Odd. The survey logs for the inner mining ring were wiped the day before the reunion. Right before BAD_LED showed up."},
    {3, "We traced the comms hijack to BAD_LED's ship at the center of the rings. Take him out and we get our channels back."},
    {1, "Update from the reunion: someone found an empty Enterprise banana pudding tray. Nobody is admitting anything."},
    {2, "Our sensors keep picking up an unregistered object near the center of the rings. It is not on any mining manifest."},
}

--- Returns a random entry of `list`.
local function randomItem(list)
    return list[irandom(1, #list)]
end

--- Sends a taunt from BAD_LED to every player ship.
--
-- Opens a comms message when the ship's comms are free, otherwise logs it to the ship's log.
-- With `broadcast`, it also takes over every main screen through the hijacked planetary comms.
function badLedTaunt(text, broadcast)
    if bad_led == nil or not bad_led:isValid() then
        return
    end
    if broadcast then
        globalMessage("[PLANETARY COMMS] BAD_LED: " .. text)
    end
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            if not bad_led:sendCommsMessage(p, text) then
                p:addToShipLog("BAD_LED: " .. text, "#ff4040")
            end
        end
    end
end

--- Sends the next station chatter message to every player ship's log.
local function stationChatter()
    chatter_index = chatter_index % #station_chatter + 1
    local entry = station_chatter[chatter_index]
    local station = stationList[entry[1]]
    if station == nil or not station:isValid() then
        return
    end
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            p:addToShipLog(station:getCallSign() .. ": " .. entry[2], "#40ff80")
        end
    end
end

--- Comms function for when the players hail BAD_LED.
function commsBadLed()
    setCommsMessage(randomItem(hail_replies))
    addCommsReply("Give up, BAD_LED!", function()
        setCommsMessage("Give up? GIVE UP? Pilot Bob, you make me laugh. Come to the center of my rings and try it.")
    end)
    addCommsReply("Can we settle this like pilots?", function()
        setCommsMessage("We'll settle it at the center of my rings, Bob. Bring pizza. Actually, don't. You'll just eat all of it again.")
    end)
    addCommsReply("Is this really about a banana pudding tray?", function()
        setCommsMessage("It was an ENTERPRISE banana pudding tray, Bob! Limited edition! That is the ONLY reason. Obviously. Nothing else. Nope.")
    end)
    addCommsReply("What's really in the asteroid mines?", function()
        setCommsMessage("Rocks, Bob. Just rocks. Very boring rocks. Stop scanning my rocks.")
    end)
    addCommsReply("Give the planetary comms back!", function()
        setCommsMessage("And lose my audience? Never! The whole planet deserves to hear about the pizza incident.")
    end)
end

--- Places a band of asteroids along a circle, leaving gaps for ships to pass.
--
-- @tparam number radius Circle radius.
-- @tparam table gaps List of gap center angles (degrees).
-- @tparam number gap_width Gap width in units along the circle.
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

--- Spawns the patrol ships of one ring, evenly spaced around the lane.
local function spawnRingPatrols(ring, count)
    local offset = random(0, 360)
    for n = 1, count do
        local a = offset + n * 360 / count
        local ship = CpuShip():setTemplate(ring.templates[(n % #ring.templates) + 1]):setFaction("Kraylor")
        ship:setCallSign(gang_names[#patrolList + 1] or string.format("LED Gang %d", #patrolList + 1))
        ship:setDescription("One of BAD_LED's gang, patrolling the stolen mining rings.")
        setCirclePos(ship, 0, 0, a, ring.radius)
        ship:setRotation(a + 90 * ring.direction)
        table.insert(patrolList, {ship = ship, radius = ring.radius, direction = ring.direction, state = "patrol"})
    end
end

--- Sends a patrol ship to a point ahead of it on its ring.
--
-- FlyTowardsBlind makes the patrol ignore everything along the way, so it
-- won't go after the friendly stations.
local function orderPatrol(entry)
    local x, y = entry.ship:getPosition()
    -- Aim a fixed 2U along the ring. A short look-ahead keeps the straight-line
    -- path close to the arc (it cuts inward by only ~50-100 units), so patrols
    -- stay in the middle of the lane instead of drifting into the inner band.
    local a = angleRotation(0, 0, x, y) + math.deg(2000 / entry.radius) * entry.direction
    local tx, ty = vectorFromAngle(a, entry.radius)
    entry.ship:orderFlyTowardsBlind(tx, ty)
end

--- Returns the closest valid player ship to `obj`, and its distance.
local function closestPlayer(obj)
    local best, best_dist = nil, nil
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            local d = distance(obj, p)
            if best_dist == nil or d < best_dist then
                best, best_dist = p, d
            end
        end
    end
    return best, best_dist
end

--- Updates every patrol: circle the ring, attack close players, and return when they get away.
local function updatePatrols()
    for idx_, entry in ipairs(patrolList) do
        if entry.ship:isValid() then
            local target, dist = closestPlayer(entry.ship)
            if entry.state == "patrol" then
                if target ~= nil and dist < aggro_range then
                    entry.state = "attack"
                    entry.target = target
                    entry.ship:orderAttack(target)
                    if not first_aggro_taunted then
                        first_aggro_taunted = true
                        badLedTaunt("Ah ah ah, Bob! You got too close to my gang. Get him, boys! For the pudding!", true)
                    end
                else
                    orderPatrol(entry)
                end
            else
                if entry.target == nil or not entry.target:isValid() or distance(entry.ship, entry.target) > disengage_range then
                    entry.state = "patrol"
                    entry.target = nil
                    orderPatrol(entry)
                end
            end
        end
    end
end

--- Initializes main GM Menu
function gmButtons()
    clearGMFunctions()
    addGMFunction(_("buttonGM", "Taunt now"), function()
        badLedTaunt(randomItem(taunts))
    end)
    -- End scenario with Human Navy (players) victorious.
    addGMFunction(_("buttonGM", "Win"), gmVictoryYesNo)
end

--- Shows Yes/No question dialogue GM submenu with question if Human Navy should win.
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

--- Initialize scenario.
function init()
    patrolList = {}
    stationList = {}

    -- Shuffle the gang names so each game hands them out differently.
    for i = #gang_names, 2, -1 do
        local j = irandom(1, i)
        gang_names[i], gang_names[j] = gang_names[j], gang_names[i]
    end

    -- Friendly stations outside the outer ring. Patrols fly blind, so they
    -- never attack these, and the players can dock to repair and restock.
    -- The order matters: station_chatter refers to these by index.
    local stations = {
        {"Large Station",  "Reunion Hall",          "Host of the piloting school class reunion. The pizza is gone and the apple beer is running low."},
        {"Medium Station", "Mining Guild Depot",    "Headquarters of the asteroid miners who were chased out of their rings by BAD_LED's gang."},
        {"Medium Station", "Planetary Comms Relay", "The planetary comms hub. BAD_LED still has admin access to every channel."},
        {"Small Station",  "Academy Annex",         "An outpost of the piloting school where BAD_LED and Pilot Bob trained together."},
    }
    local station_offset = random(0, 360)
    for n, info in ipairs(stations) do
        local station = SpaceStation():setTemplate(info[1]):setFaction("Human Navy"):setRotation(random(0, 360))
        station:setCallSign(info[2]):setDescription(info[3])
        setCirclePos(station, 0, 0, station_offset + (n - 1) * 360 / #stations, station_radius)
        table.insert(stationList, station)
    end
    stationList[1]:addReputationPoints(300.0)

    -- Spawn the player ship next to the first station.
    local sx, sy = stationList[1]:getPosition()
    player = PlayerSpaceship():setFaction("Human Navy"):setTemplate(getScenarioSetting("PlayerShip"))
    player:setCallSign("USS-SUNDAY NCC-67")
    player:setPosition(sx * 1.08, sy * 1.08)
    player:setRotation(angleRotation(player, 0, 0))
    if not player:hasWarpDrive() and not player:hasJumpDrive() then
        player:setWarpDrive(true)
    end
    playerList = {player}
    onNewPlayerShip(function(ship)
        table.insert(playerList, ship)
    end)

    -- BAD_LED waits at the center of the rings.
    bad_led = CpuShip():setTemplate("Atlantis X23"):setFaction("Kraylor"):setCallSign("BAD_LED")
    bad_led:setPosition(0, 0):orderStandGround()
    bad_led:setCommsScript(""):setCommsFunction(commsBadLed)
    bad_led:setDescription("BAD_LED, infamous piloting school classmate and sworn nemesis of Pilot Bob.")
    spawnJammer()

    -- Whatever BAD_LED is really after, hidden inside the innermost ring.
    -- Placed well inside the inner asteroid band so it doesn't block the patrol lane.
    local mystery = Artifact():setCallSign("Unregistered Object")
    setCirclePos(mystery, 0, 0, random(0, 360), 4000)
    mystery:setDescriptions(
        "An object that isn't on any mining manifest.",
        "A sealed mining core sample crate, stamped 'PROPERTY OF BAD_LED - DO NOT OPEN - ESPECIALLY YOU, BOB'. Scans show traces of banana."
    )
    mystery:setScanningParameters(2, 2)

    -- Asteroid rings: two bands per ring with a clear patrol lane between them,
    -- and a few gaps so ships can cross from one lane to the next.
    for idx_, ring in ipairs(rings) do
        local gaps = {}
        local gap_offset = random(0, 360)
        for g = 1, 3 do
            table.insert(gaps, gap_offset + g * 120 + random(-20, 20))
        end
        createAsteroidBand(ring.radius - lane_half_width, gaps, 1800)
        createAsteroidBand(ring.radius + lane_half_width, gaps, 1800)
    end

    -- Set the number of patrols per ring based on the scenario variation.
    local counts = {
        ["Extreme"] = 9,
        ["Hard"] = 6,
        ["Normal"] = 4,
        ["Easy"] = 2,
        ["Empty"] = 0
    }
    local per_ring = counts[getScenarioSetting("Enemies")]
    assert(per_ring, "unknown enemies setting: " .. getScenarioSetting("Enemies") .. " could not set patrol count")
    for idx_, ring in ipairs(rings) do
        spawnRingPatrols(ring, per_ring)
    end
    updatePatrols()

    local timesetting = {
        ["Unlimited"] = nil,
        ["20min"] = 20 * 60,
        ["30min"] = 30 * 60,
        ["60min"] = 60 * 60,
    }
    gametimeleft = timesetting[getScenarioSetting("Time")]
    if gametimeleft ~= nil then
        timewarning = gametimeleft - 5 * 60
    end

    gmButtons()

    local briefing = [[Pilot Bob, we hate to interrupt the reunion, but we have a situation.

Your old classmate BAD_LED stormed out over the pizza and apple beer, rallied his gang, and seized the asteroid mining rings. He has stolen a warp jammer and taken admin access to the planetary comms system, and he's using it to taunt you on every channel.

His gang circles through the rings. They will leave you alone if you keep your distance, but get too close and they will attack. The stolen jammer blocks warp and jump drives inside the rings, so you will have to fly in on impulse.

Settle the dispute: take out BAD_LED at the center of the rings, and restore the mining industry and the planetary comms. The gang ignores our stations, so dock with them to repair and restock.]]
    if gametimeleft ~= nil then
        briefing = briefing .. string.format("\n\nYou have %d minutes for this mission.", gametimeleft / 60)
    end
    stationList[1]:sendCommsMessage(player, briefing .. "\n\nGood luck.")
end

--- Ends the game with a banner message.
local function endGame(faction, text)
    game_over = true
    victory(faction)
    globalMessage(text)
    setBanner(text)
end

--- Update.
--
-- @tparam number delta the time delta (in seconds)
function update(delta)
    if game_over then
        return
    end

    -- Win: BAD_LED is destroyed.
    if not bad_led:isValid() then
        endGame("Human Navy", _("msgMainscreen&Spectbanner", "Mission: SUCCESS (BAD_LED defeated - mining and planetary comms restored)"))
        return
    end

    -- Lose: the player ship is destroyed.
    if not player:isValid() then
        endGame("Kraylor", _("msgMainscreen&Spectbanner", "Mission: FAILED (the USS-SUNDAY NCC-67 was destroyed)"))
        return
    end

    if gametimeleft ~= nil then
        gametimeleft = gametimeleft - delta
        if gametimeleft < 0 then
            badLedTaunt("Time's up, Bob! Too slow, as always. The mines are MINE!", true)
            endGame("Kraylor", _("msgMainscreen&Spectbanner", "Mission: FAILED (time has run out)"))
            return
        end
        if gametimeleft < timewarning then
            for idx_, p in ipairs(playerList) do
                if p:isValid() then
                    p:addToShipLog(string.format("%d minutes of mission time remaining.", math.ceil(timewarning / 60)), "Yellow")
                end
            end
            if timewarning <= 5 * 60 then
                timewarning = timewarning - 1 * 60
            else
                timewarning = timewarning - 5 * 60
            end
        end
        setBanner(string.format(_("msgSpectbanner", "Mission in progress - Time left: %d:%02d"), math.floor(gametimeleft / 60), math.floor(gametimeleft % 60)))
    end

    -- Keep the jammer up for as long as BAD_LED lives.
    if not jammer:isValid() then
        spawnJammer()
        badLedTaunt("Nice try, Bob. You think I only stole ONE warp jammer?")
    end

    order_timer = order_timer - delta
    if order_timer <= 0 then
        order_timer = 0.5
        updatePatrols()
    end

    -- BAD_LED constantly taunts Bob, and every third taunt goes out over the hijacked planetary comms.
    taunt_timer = taunt_timer - delta
    if taunt_timer <= 0 then
        taunt_timer = random(35, 60)
        taunt_count = taunt_count + 1
        badLedTaunt(randomItem(taunts), taunt_count % 3 == 0)
    end
    if not half_hull_taunted and bad_led:getHull() < bad_led:getHullMax() / 2 then
        half_hull_taunted = true
        badLedTaunt("That... that was just a scratch, Bob! Fine! FINE! It was never about the pudding! ...Forget I said that.", true)
    end

    chatter_timer = chatter_timer - delta
    if chatter_timer <= 0 then
        chatter_timer = random(90, 150)
        stationChatter()
    end
end
