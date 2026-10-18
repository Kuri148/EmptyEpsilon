-- Name: Unstable 235
-- Description: The sequel to Kralien Cursive. The asteroid rings have shifted, leaving eight straight lanes out from the center, and the two deposits of unstable 235 sit in the middle. BAD_LED got there first. He has taken one deposit for himself and promised every gram to the Interplanetary Directorate. The other one is yours, if you can take it and get away.
---
--- Unstable 235 powers planets and builds weapons that can destroy galaxies. The moment you take it aboard, the Directorate locks the rings under a huge one-way warp jammer and floods the area with mines, warships and rotating barrage stations.
---
--- Escape the jamming field under impulse, then deliver the unstable 235 to the Intergalactic Symposium by docking there. Lose the ship carrying it, or let it collapse into a black hole, and you lose the game.
-- Type: Basic
-- Setting[Enemies]: Configures how dangerous the jamming field is.
-- Enemies[Easy]: Fewer mines, barrage stations and warships. Recommended for inexperienced crews.
-- Enemies[Normal|Default]: Recommended for a normal crew.
-- Enemies[Hard]: A dense field with frequent reinforcements.
-- Setting[PlayerShip]: Sets the default player ship
-- PlayerShip[Atlantis|Default]: Powerful ship with sidewards missile tubes. Requires more advanced play.
-- PlayerShip[Phobos M3P]: Simpler, less powerful ship. But easier to handle. Recommended for new crews. Gets a jump drive for this mission.

--- Scenario
-- @script scenario_69_unstable235

require("utils.lua")
-- For this scenario, utils.lua provides:
--   vectorFromAngle(angle, length, angle_is_heading)
--   setCirclePos(obj, x, y, angle, distance)
--   distance(a, b, c, d)

-- The object layout is copied from Kralien Cursive (scenario_68_kralienCursive.lua).

-- The mining rings from Pilot Bob's nemesis, centered on 0, 0.
local lane_half_width = 1600
local ring_radii = {10000, 17000, 24000}
local station_radius = 33000

-- Mining Central and the four clusters around it.
local central_x, central_y = 0, -53000
local cluster_distance = 15000
local cluster_radius = 5000

-- The Scriptorium, about 50U from Mining Central.
local secret_base_distance = 48000
local secret_base_angle = -115

-- The rings have shifted: every band now has the same eight gaps, so eight straight,
-- clear lanes run out from the center.
local lane_count = 8
local lane_width = 3000
local lane_clear_radius = 27000 -- Mines are kept out of the lanes inside this radius.

-- The two unstable 235 deposits sit on opposite sides of the ring center. BAD_LED is
-- parked on the one he has already taken; the other is still there for the players.
local sample_distance = 4000    -- From the ring center to each deposit.
-- The player ship starts in one of the lanes, just outside the outermost asteroid band
-- (25.6U) and inside the ring stations (33U), facing the center.
local player_start_distance = 30000
local pickup_range = 800        -- Ship center to sample center.

-- BAD_LED
local bad_led_brag_range = 25000 -- He hails the players when they get this close.
local bad_led_flee_range = 5000  -- "Firing range": he warps away when a player gets this close...
local bad_led_min_brag_time = 20 -- ...but not until his speech has been up this many seconds.

-- The Messenger leaves this many seconds after its warning.
local messenger_stay_time = 40

-- The Intergalactic Symposium, outside the jamming field.
local symposium_distance = 125000
local symposium_angle = 60

-- Full power is the top of the engineering slider, 300%.
local full_power = 3.0
local boosted_systems = {"reactor", "maneuver", "impulse"}

-- The Directorate's jamming field, centered on the ring center.
local field_radius = 100000     -- Players must get this far from the center to escape.
local start_clear_radius = 8000 -- No scattered mines or supply drops this close to the center.
local turret_fire_range = 12000 -- Barrage stations fire only when a player is this close.
local turret_muzzle_offset = 800 -- HVLIs spawn this far from the station center.
local hvli_lifetime = 10
local wave_spawn_distance = {5000, 12000} -- Wave warships warp in this far from the player.
local mine_drop_distance = 6000 -- Each wave also drops mines this far ahead of the player.
local sector_size = 20000       -- The game's map grid squares ("F5" and so on).
-- Mine rings around the field center, each `rows` staggered rows deep. The inner one
-- sits between the outermost asteroid band (25.6U) and the ring stations (33U); the
-- outer one is a single line of mines near the edge of the field.
local mine_rings = {
    {radius = 29000, rows = 4},
    {radius = 59000, rows = 4},
    {radius = 87000, rows = 1},
}
local mine_ring_row_spacing = 650 -- Distance between the rows.
-- Each ring's exits are turned this far from the previous ring's, give or take
-- `mine_ring_exit_jitter`, so no exit lines up with the next one out. With two exits
-- 180 degrees apart, 90 degrees is as far apart as they can get.
local mine_ring_exit_turn = 90
local mine_ring_exit_jitter = 10
local mine_ring_spacing = 800   -- Distance between mines along a row.
local mine_ring_exit_width = 15000 -- Each ring has two exits this wide...
local mine_ring_exit_count = 2
local mine_ring_exit_spacing = 180 -- ...on opposite sides of the ring.
local hull_kit_repair = 0.4     -- A hull repair kit restores this share of the maximum hull.
local garrison_min_distance = 3000 -- Garrison ships never warp in closer than this to a player.
-- Some warships warp in across the player's path instead: this far ahead...
local path_distance = {7000, 18000}
local path_spread = 3500        -- ...and up to this far to either side of the course.
local path_share = 0.4          -- Share of each garrison and wave sent to the path.
local ship_spacing = 2500       -- New warships warp in at least this far from every other one.
local enemy_speed_factor = 0.9  -- Directorate ships fly at 90% of the fastest player ship's speed.
local enemy_min_speed = 40      -- ...but never slower than this.

-- House music that starts when the jammer goes up, and loops through the list.
--
-- Put the files in resources/music/house/ (not ambient/ or combat/, which the game
-- picks its own music from). The game can't tell the script when a track ends, so
-- each track needs its length in seconds. Music plays on the host PC only, through
-- its sound volume setting, and a track can't be stopped once it starts.
local house_music = {
    -- Plays top to bottom, in the order of the number at the start of each file name.
    {file = "music/house/1_Daft Punk - Touch It Technologic (Live 2007 - Official Audio).ogg", length = 330},
    {file = "music/house/2_Daft Punk - Television Rules the Nation Crescendolls (Live 2007 - Official Audio).ogg", length = 291},
    {file = "music/house/3_Daft Punk - Too Long Steam Machine (Live 2007 - Official Audio).ogg", length = 422},
    {file = "music/house/4_Daft Punk - Around the World Harder, Better, Faster, Stronger (Live 2007 - Official Audio).ogg", length = 343},
    {file = "music/house/5_Daft Punk - Robot Rock Oh Yeah (Live 2007 - Official Audio).ogg", length = 388},
    {file = "music/house/6_Psychoseptember.ogg", length = 155},
}
-- Music after escaping the jamming field, on repeat. It starts when the house track
-- that is playing finishes, because a track can't be cut off.
local journey_music = {
    {file = "music/journey/daft punk - veridis quo (slowed + reverb).ogg", length = 488},
}
local music_gap = 1             -- Seconds of silence between tracks.

local playerList
local mining_central
local clusters
local dig_site
local caravan = {}
local secret_base
local symposium
local game_over = false

-- Unstable 235 samples. Each entry is {obj = WarpJammer, shot = bool, gone = bool}.
local samples = {}
-- Ships that have picked up a sample, mapped to true.
local boosted = {}
-- The player ship carrying the unstable 235.
local carrier = nil

-- BAD_LED: "waiting", "bragging", then "gone".
local bad_led
local bad_led_state = "waiting"
local bad_led_brag_timer = 0
local bad_led_hit = false

local messenger
local messenger_timer = nil
local escaped = false

-- The playlist that is playing (house_music, then journey_music after the escape).
local music_playlist = house_music
-- Music: the index of the track playing (nil before the music starts), and the
-- seconds until the next one.
local music_index = nil
local music_timer = 0

-- Escape phase
local directorate_faction
local field_deployed = false
local field_x, field_y
local jammer_core
-- Barrage and lance platforms. Each entry is {obj, angle, spin, barrels, interval, timer};
-- lance platforms have spin 0 and one barrel.
local turrets = {}
local warships = {}
-- Sectors of the field, each with a garrison that warps in once a player ship is in
-- that sector or one next to it. Each entry is {col, row, spawned}.
local field_sectors = {}
local wave_timer = 0
local wave_count = 0
local turret_index = 0
-- Mines, in a grid of `mine_cell_size` cells so nearby mines can be found quickly.
-- Keys are "column,row"; values are lists of mines.
local mines = {}
local mine_cell_size = 2000
-- The exits of each mine ring: {radius, first, half_angle}.
local mine_ring_exits = {}
-- Solid or dangerous terrain (planets, stars, black holes) that mines and ships must
-- not appear inside. Each entry is {x, y, r}.
local bodies = {}
local speed_timer = 0
-- Angle of the first of the eight lanes through the asteroid rings.
local lane_offset = 0
-- Stations that mines and warships must not appear on. Each entry is {x, y, r}.
local station_spots = {}

local pirate_names = {
    "Rust Jackal", "Grim Ledger", "Hollow Pike", "Sable Wrench", "Gutter Comet",
    "Slag Viper", "Black Tally", "Cinder Rat", "Broken Oath", "Red Lantern",
}
local pirate_name_index = 0

local warship_names = {
    "Edict", "Mandate", "Verdict", "Statute", "Sanction", "Writ", "Decree", "Tribunal",
    "Censure", "Embargo", "Warrant", "Charter", "Covenant", "Quorum", "Ordinance", "Accord",
}
local warship_name_index = 0

--- Returns the value for the current Enemies setting.
local function byDifficulty(easy, normal, hard)
    local values = {["Easy"] = easy, ["Normal"] = normal, ["Hard"] = hard}
    local value = values[getScenarioSetting("Enemies")]
    assert(value, "unknown enemies setting: " .. getScenarioSetting("Enemies"))
    return value
end

--- Returns the next pirate callsign.
local function nextPirateName()
    pirate_name_index = pirate_name_index + 1
    return pirate_names[(pirate_name_index - 1) % #pirate_names + 1]
end

--- Returns the next Directorate warship callsign.
local function nextWarshipName()
    warship_name_index = warship_name_index + 1
    local name = warship_names[(warship_name_index - 1) % #warship_names + 1]
    if warship_name_index > #warship_names then
        name = name .. " " .. math.floor((warship_name_index - 1) / #warship_names + 1)
    end
    return name
end

--- Adds a line to every player ship's log.
local function logPlayers(text, color)
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            p:addToShipLog(text, color)
        end
    end
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

--- Returns the closest valid player ship to x, y, and its distance.
local function closestPlayer(x, y)
    local best, best_dist = nil, nil
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            local d = distance(p, x, y)
            if best_dist == nil or d < best_dist then
                best, best_dist = p, d
            end
        end
    end
    return best, best_dist
end

--- Flashes a warp-in effect at x, y.
local function warpInEffect(x, y, size)
    ElectricExplosionEffect():setPosition(x, y):setSize(size):setOnRadar(true)
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
    local points = {}
    for n = 0, 7 do
        local x, y = vectorFromAngle(n * 45, cluster_radius + 300)
        table.insert(points, cluster.x + x)
        table.insert(points, cluster.y + y)
    end
    Zone():setPoints((table.unpack or unpack)(points)):setColor(30, 30, 70):setLabel(cluster.name)
end

-------------------------------------------------------------------------------
-- Terrain around the Scriptorium
-------------------------------------------------------------------------------

local terrain_inner = 12000     -- Nothing big closer than this to the Scriptorium.
local terrain_outer = 66000     -- ...or further than this.

--- Returns true if x, y is at least `margin` outside every body in `bodies`.
local function clearOfBodies(x, y, margin)
    for idx_, body in ipairs(bodies) do
        if distance(x, y, body.x, body.y) < body.r + margin then
            return false
        end
    end
    return true
end

--- Finds a free spot for a feature of radius `r` between `inner` and `outer` from
-- sx, sy, and reserves it. `inner` and `outer` default to the Scriptorium's terrain
-- ring. Returns nil if no spot was found.
--
-- Nothing is placed across a mine ring: mines skip solid terrain, so a planet on a ring
-- would open an extra way through it.
local function reserveSpot(sx, sy, r, inner, outer)
    inner, outer = inner or terrain_inner, outer or terrain_outer
    for attempt = 1, 60 do
        local dx, dy = vectorFromAngle(random(0, 360), random(inner + r, outer - r))
        local x, y = sx + dx, sy + dy
        local on_ring = false
        for idx_, ring in ipairs(mine_rings) do
            if math.abs(distance(x, y, 0, 0) - ring.radius) < r + ring.rows * mine_ring_row_spacing / 2 + 1500 then
                on_ring = true
            end
        end
        if not on_ring and clearOfBodies(x, y, r + 3000) then
            table.insert(bodies, {x = x, y = y, r = r})
            return x, y
        end
    end
    return nil
end

--- Creates a planet. `info` has name, radius, color, and optionally surface, clouds,
-- atmosphere and rotation.
local function createPlanet(x, y, info)
    local planet = Planet():setPosition(x, y):setPlanetRadius(info.radius)
    planet:setCallSign(info.name)
    if info.surface then planet:setPlanetSurfaceTexture(info.surface) end
    if info.clouds then planet:setPlanetCloudTexture(info.clouds) end
    planet:setPlanetAtmosphereTexture(info.atmosphere or "planets/atmosphere.png")
    planet:setPlanetAtmosphereColor(info.color[1], info.color[2], info.color[3])
    if info.rotation then planet:setAxialRotationTime(info.rotation) end
    return planet
end

--- Creates a planet with moons in orbit. Reserves room for the moons' orbits too.
local function createPlanetSystem(sx, sy, info, moons, inner, outer)
    local reach = info.radius
    for idx_, moon in ipairs(moons) do
        reach = math.max(reach, moon.orbit + moon.radius)
    end
    local x, y = reserveSpot(sx, sy, reach, inner, outer)
    if x == nil then
        return
    end
    -- Only the planet itself is solid; the moons' orbits just keep other terrain away.
    bodies[#bodies].r = info.radius
    table.insert(bodies, {x = x, y = y, r = reach, terrain_only = true})
    local planet = createPlanet(x, y, info)
    for idx_, moon in ipairs(moons) do
        local m = createPlanet(0, 0, {name = moon.name, radius = moon.radius, surface = moon.surface, color = {0.6, 0.6, 0.6}})
        setCirclePos(m, x, y, random(0, 360), moon.orbit)
        m:setOrbit(planet, moon.period)
    end
end

--- Scatters an asteroid field of `count` rocks in a circle of radius `r` at x, y.
local function createAsteroidField(x, y, r, count)
    for n = 1, count do
        local ax, ay = vectorFromAngle(random(0, 360), math.sqrt(random(0, r * r)))
        Asteroid():setPosition(x + ax, y + ay):setSize(random(100, 450))
        local vx, vy = vectorFromAngle(random(0, 360), math.sqrt(random(0, r * r)))
        VisualAsteroid():setPosition(x + vx, y + vy)
    end
end

--- Fills the space around the Scriptorium with stars, planets, moons, nebulae,
-- asteroid fields and black holes.
local function createTerrain(sx, sy)
    -- Keep away from Mining Central's clusters and the mining rings.
    table.insert(bodies, {x = central_x, y = central_y, r = cluster_distance + cluster_radius, terrain_only = true})
    table.insert(bodies, {x = 0, y = 0, r = station_radius + 3000, terrain_only = true})

    -- A yellow star with its own asteroid belt.
    local star_x, star_y = reserveSpot(sx, sy, 11000)
    if star_x ~= nil then
        createPlanet(star_x, star_y, {name = "Kessa", radius = 3500, atmosphere = "planets/star-1.png", color = {1.0, 0.85, 0.5}})
        local count = 90
        for n = 1, count do
            local a = n * 360 / count + random(-1, 1)
            setCirclePos(Asteroid(), star_x, star_y, a, 9000 + random(-700, 700)):setSize(random(120, 400))
            setCirclePos(VisualAsteroid(), star_x, star_y, a + random(-2, 2), 9000 + random(-1200, 1200))
        end
        -- Only the star is solid; the belt just keeps other terrain away.
        bodies[#bodies].r = 3500
        table.insert(bodies, {x = star_x, y = star_y, r = 11000, terrain_only = true})
    end

    -- A red dwarf.
    local dwarf_x, dwarf_y = reserveSpot(sx, sy, 2000)
    if dwarf_x ~= nil then
        createPlanet(dwarf_x, dwarf_y, {name = "Ember", radius = 2000, atmosphere = "planets/star-1.png", color = {1.0, 0.35, 0.25}})
    end

    -- Planets and moons.
    createPlanetSystem(sx, sy,
        {name = "Vorr", radius = 5000, surface = "planets/gas-1.png", color = {0.9, 0.6, 0.3}, rotation = 400},
        {
            {name = "Vorr I", radius = 900, surface = "planets/moon-1.png", orbit = 8500, period = 300},
            {name = "Vorr II", radius = 1300, surface = "planets/moon-2.png", orbit = 12000, period = 480},
        })
    createPlanetSystem(sx, sy,
        {name = "Calder", radius = 3000, surface = "planets/planet-earth.png", clouds = "planets/clouds-1.png", color = {0.2, 0.4, 1.0}, rotation = 300},
        {
            {name = "Calder Moon", radius = 800, surface = "planets/moon-3.png", orbit = 6000, period = 240},
        })
    createPlanetSystem(sx, sy,
        {name = "Brask", radius = 2500, surface = "planets/planet-2.png", clouds = "planets/clouds-3.png", color = {0.8, 0.3, 0.2}, rotation = 250},
        {})
    createPlanetSystem(sx, sy,
        {name = "Hollin", radius = 3800, surface = "planets/gas-3.png", color = {0.5, 0.8, 0.9}, rotation = 350},
        {
            {name = "Hollin Minor", radius = 700, surface = "planets/moon-1.png", orbit = 6500, period = 200},
        })
    createPlanetSystem(sx, sy,
        {name = "Tesk", radius = 1500, surface = "planets/moon-3.png", color = {0.7, 0.7, 0.8}, rotation = 200},
        {})

    -- Black holes. Their pull reaches 5U, so they reserve a bit more than that.
    for n = 1, 2 do
        local x, y = reserveSpot(sx, sy, 6000)
        if x ~= nil then
            BlackHole():setPosition(x, y)
        end
    end

    -- Nebulae and asteroid fields don't block anything, so they only need open space.
    for n = 1, 10 do
        local dx, dy = vectorFromAngle(random(0, 360), random(terrain_inner, terrain_outer))
        if clearOfBodies(sx + dx, sy + dy, 5000) then
            Nebula():setPosition(sx + dx, sy + dy)
        end
    end
    for n = 1, 6 do
        local dx, dy = vectorFromAngle(random(0, 360), random(terrain_inner, terrain_outer))
        if clearOfBodies(sx + dx, sy + dy, 4000) then
            createAsteroidField(sx + dx, sy + dy, 4000, 35)
        end
    end
end

local field_terrain_inner = 40000 -- Big terrain around the jammer starts outside the ring stations...
local field_terrain_outer = 125000 -- ...and reaches past the edge of the jamming field.

--- Fills the space in and around the jamming field with planets, moons, a star,
-- black holes, nebulae and asteroid fields. Inside the asteroid rings it only adds
-- things that don't block a ship: nebulae and drifting dust.
local function createFieldTerrain()
    local inner, outer = field_terrain_inner, field_terrain_outer

    -- A blue-white star.
    local star_x, star_y = reserveSpot(0, 0, 4000, inner, outer)
    if star_x ~= nil then
        createPlanet(star_x, star_y, {name = "Aurel", radius = 4000, atmosphere = "planets/star-1.png", color = {0.6, 0.75, 1.0}})
    end

    -- Planets and moons.
    createPlanetSystem(0, 0,
        {name = "Meridian", radius = 4500, surface = "planets/gas-2.png", color = {0.7, 0.5, 0.9}, rotation = 450},
        {
            {name = "Meridian I", radius = 800, surface = "planets/moon-2.png", orbit = 8000, period = 260},
            {name = "Meridian II", radius = 1100, surface = "planets/moon-1.png", orbit = 11000, period = 420},
        }, inner, outer)
    createPlanetSystem(0, 0,
        {name = "Quill", radius = 2800, surface = "planets/planet-4.png", clouds = "planets/clouds-2.png", color = {0.4, 0.9, 0.6}, rotation = 280},
        {
            {name = "Inkwell", radius = 700, surface = "planets/moon-3.png", orbit = 5500, period = 210},
        }, inner, outer)
    createPlanetSystem(0, 0,
        {name = "Sorrow", radius = 2200, surface = "planets/planet-3.png", color = {0.6, 0.8, 1.0}, rotation = 320},
        {}, inner, outer)
    createPlanetSystem(0, 0,
        {name = "Gallow", radius = 3200, surface = "planets/planet-1.png", clouds = "planets/clouds-3.png", color = {0.9, 0.5, 0.3}, rotation = 260},
        {
            {name = "Gallow's Rope", radius = 600, surface = "planets/moon-1.png", orbit = 6000, period = 190},
        }, inner, outer)
    createPlanetSystem(0, 0,
        {name = "Pell", radius = 1800, surface = "planets/planet-5.png", color = {0.8, 0.8, 0.6}, rotation = 220},
        {}, inner, outer)

    -- Black holes. Their pull reaches 5U, so they reserve a bit more than that.
    for n = 1, 3 do
        local x, y = reserveSpot(0, 0, 6000, inner, outer)
        if x ~= nil then
            BlackHole():setPosition(x, y)
        end
    end

    -- Nebulae and asteroid fields between the rings and the edge of the field.
    for n = 1, 26 do
        local x, y = vectorFromAngle(random(0, 360), random(field_terrain_inner - 6000, field_terrain_outer))
        if clearOfBodies(x, y, 5000) then
            Nebula():setPosition(x, y)
        end
    end
    for n = 1, 16 do
        local x, y = vectorFromAngle(random(0, 360), random(field_terrain_inner - 4000, field_terrain_outer))
        local r = random(3000, 5000)
        if clearOfBodies(x, y, r) then
            createAsteroidField(x, y, r, math.floor(r / 100))
        end
    end

    -- Inside the asteroid rings: a few nebulae, which hide ships from radar but don't
    -- block the lanes, and the dust the shifting rings have thrown off.
    for n = 1, 3 do
        local x, y = vectorFromAngle(n * 120 + random(-30, 30), random(12000, 22000))
        Nebula():setPosition(x, y)
    end
    for n = 1, 400 do
        local x, y = vectorFromAngle(random(0, 360), math.sqrt(random(0, field_radius * field_radius)))
        VisualAsteroid():setPosition(x, y)
    end
end

--- Drops the `bodies` entries that were only there to space out the terrain.
--
-- From here on, `bodies` is only used to keep mines and ships out of solid terrain.
local function finishTerrain()
    local solid = {}
    for idx_, body in ipairs(bodies) do
        if not body.terrain_only then
            table.insert(solid, body)
        end
    end
    bodies = solid
end

-------------------------------------------------------------------------------
-- Unstable 235
-------------------------------------------------------------------------------

-- Every function handed to the engine (damage callbacks, GM buttons, new-ship hooks)
-- must reference a global before any local, or SeriousProton rejects it. The
-- math.abs(0) lines below exist for that reason.

local deployField
local spawnMessenger

--- Ends the game with a win for `faction`, and shows `text` to everyone.
local function endGame(faction, text)
    game_over = true
    victory(faction)
    globalMessage(text)
    setBanner(text)
end

--- Marks a sample as shot. The black hole is spawned from update(), not from
-- inside the engine's damage callback.
local function onSampleShot(jammer)
    math.abs(0) -- Provides global context for SeriousProton
    for idx_, sample in ipairs(samples) do
        if sample.obj == jammer then
            sample.shot = true
        end
    end
end

--- Creates an unstable 235 sample at x, y.
--
-- A WarpJammer is used because it can be targeted and shot, and reports damage to
-- the script. Its jamming range is 0, so it doesn't block jumps or warps.
local function createSample(x, y)
    local jammer = WarpJammer():setFaction("Independent"):setPosition(x, y)
    jammer:setRange(0):setHull(20)
    jammer:setCallSign("Unstable 235")
    jammer:setDescriptions(
        "A small, faintly glowing canister.",
        "Unstable 235, the last deposit. Any weapons fire will collapse it into a black hole. Fly into it to take it aboard: it will double the hull strength and drive the reactor, maneuvering and impulse to full power without overheating or draining energy."
    )
    jammer:onTakingDamage(onSampleShot)
    jammer:onDestruction(onSampleShot)
    table.insert(samples, {obj = jammer, x = x, y = y, shot = false, gone = false})
end

--- Gives a player ship the unstable 235 boost.
local function boostShip(p)
    if not boosted[p] then
        boosted[p] = true
        -- Double the hull, both the maximum and what's left of it. Only the first
        -- canister does this; a second one doesn't double it again.
        p:setHullMax(p:getHullMax() * 2)
        p:setHull(p:getHull() * 2)
        for idx_, system in ipairs(boosted_systems) do
            -- Divide the energy cost by the power level, so 300% costs no more energy
            -- than 100%. The reactor's factor is negative (it generates energy), so its
            -- output is left alone.
            if system ~= "reactor" then
                p:setSystemPowerFactor(system, p:getSystemPowerFactor(system) / full_power)
            end
            p:setSystemHeatRate(system, 0)
        end
    end
    for idx_, system in ipairs(boosted_systems) do
        p:commandSetSystemPowerRequest(system, full_power)
        p:setSystemPower(system, full_power)
        p:setSystemHeat(system, 0)
    end
    p:addToShipLog("Unstable 235 taken aboard. Hull strength doubled. Reactor, maneuvering and impulse at full power. No overheating, no extra energy drain.", "Yellow")
end

--- Handles pickups, and fails the mission if the last sample is shot.
--
-- Picking up the sample tips off the Directorate, which deploys the field, and
-- brings the Messenger.
local function updateSamples()
    for idx_, sample in ipairs(samples) do
        if not sample.gone then
            local obj = sample.obj
            if not obj:isValid() or sample.shot then
                sample.gone = true
                local x, y = sample.x, sample.y
                if obj:isValid() then
                    obj:destroy()
                end
                BlackHole():setPosition(x, y)
                logPlayers(string.format("Unstable 235 collapsed into a black hole in sector %s!", getSectorName(x, y)), "Red")
                endGame("Directorate", _("msgMainscreen&Spectbanner", "Mission: FAILED (the last unstable 235 collapsed into a black hole)"))
                return
            end
            for idx2_, p in ipairs(playerList) do
                if not sample.gone and p:isValid() and distance(p, obj) < pickup_range then
                    sample.gone = true
                    obj:destroy()
                    boostShip(p)
                    carrier = p
                    -- The Messenger hails first, so its warning gets the comms screen
                    -- and the Directorate's message goes to the ship's log.
                    spawnMessenger(p)
                    deployField()
                end
            end
        end
    end
end

--- Keeps boosted systems cool, in case anything else adds heat.
local function updateBoosted()
    for p, idx_ in pairs(boosted) do
        if p:isValid() then
            for idx2_, system in ipairs(boosted_systems) do
                p:setSystemHeat(system, 0)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- BAD_LED
-------------------------------------------------------------------------------

local bad_led_brag = [[Well, well, well. The USS Sunday, right on schedule. And Pilot Bob! Bob, buddy, I owe you one.

All that flying around the clusters, the pirates, the secret base, the old calligrapher squinting at my note... You did all the hard work of finding these coordinates, and all I had to do was listen in. Thank you, crew. Especially you, Bob.

See that glow? That's an unstable 235 deposit, and it is in my reactor now. My reactor, my jump drive, my impulse engines, my maneuvering thrusters: all of it SUPER powerful. You should see this thing turn.

Full disclosure: I promised the Directorate ALL the unstable 235 in these rings, for a very, very large amount of cash. Turns out there were only two deposits. HA!

So here's the deal. The other one's yours, if you can keep the Directorate busy while I make my exit. Call it a reunion present.]]

local bad_led_decoy = [[Ah ah ah, not so close, Bob.

You really thought you could catch me? You couldn't even catch me last time! That BAD_LED you blew up in the mining rings? A decoy. An empty ship playing my recorded messages on a loop. You spent a whole mission arguing with an answering machine! HAHAHAHA!

Enjoy the Directorate. BAD_LED out.]]

local bad_led_replies = {
    "Can't talk, Bob. Busy being rich.",
    "You're still here? The Directorate is on its way, you know.",
    "Do you hear that? That's the sound of my reactor running at three hundred percent.",
    "Bob, you still parallel park like a drunk space cow.",
}

--- Comms for BAD_LED.
local function commsBadLed()
    math.abs(0) -- Provides global context for SeriousProton
    setCommsMessage(bad_led_replies[irandom(1, #bad_led_replies)])
end

--- Notes that BAD_LED has been shot at, so he leaves.
local function onBadLedHit()
    math.abs(0) -- Provides global context for SeriousProton
    bad_led_hit = true
end

--- Creates BAD_LED's ship, parked on the deposit he has already taken.
local function createBadLed(x, y)
    bad_led = CpuShip():setTemplate("Atlantis X23"):setFaction("Kraylor"):setCallSign("BAD_LED")
    bad_led:setPosition(x, y):setRotation(random(0, 360)):orderIdle()
    bad_led:setCanBeDestroyed(false)
    bad_led:setDescriptions(
        "BAD_LED, infamous piloting school classmate and sworn nemesis of Pilot Bob.",
        "BAD_LED's ship. Its engines glow with the unmistakable light of unstable 235."
    )
    bad_led:setCommsScript(""):setCommsFunction(commsBadLed)
    bad_led:onTakingDamage(onBadLedHit)
end

--- BAD_LED brags when the players get close, and warps away when they reach firing
-- range or shoot at him.
local function updateBadLed(delta)
    if bad_led_state == "gone" or not bad_led:isValid() then
        return
    end
    local p, d = closestPlayer(bad_led:getPosition())
    if bad_led_state == "waiting" then
        if p ~= nil and (d < bad_led_brag_range or bad_led_hit) then
            bad_led_state = "bragging"
            hailPlayers(bad_led, bad_led_brag, "#ff8040")
        end
    elseif bad_led_state == "bragging" then
        bad_led_brag_timer = bad_led_brag_timer + delta
        if bad_led_hit or (p ~= nil and d < bad_led_flee_range and bad_led_brag_timer > bad_led_min_brag_time) then
            bad_led_state = "gone"
            hailPlayers(bad_led, bad_led_decoy, "#ff8040")
            local x, y = bad_led:getPosition()
            warpInEffect(x, y, 1500)
            bad_led:destroy()
            logPlayers("BAD_LED's ship has warped away. Its 235-powered drive left no trail to follow.", "#ff8040")
        end
    end
end

-------------------------------------------------------------------------------
-- The Messenger
-------------------------------------------------------------------------------

--- Returns the Messenger's warning about the field and the way to the Symposium.
local function messengerWarning()
    local x, y = symposium:getPosition()
    return string.format([[This is the Messenger. You have it? Good. Now listen, and don't argue.

High-tail it out of there. Take the unstable 235 to the Intergalactic Symposium in sector %s. They are the only ones who can take care of it peacefully. Whatever happens, it must not fall into the hands of the Directorate. Not at any cost.

They are switching on a one-way warp jammer at the center of the rings, right behind you. Anything can warp or jump into its %dU field. Nothing warps or jumps out. Your jump drive is useless until you are clear of it.

Run on impulse. The rings have shifted: there are eight straight lanes out from the center. Past the rings they have laid three belts of mines. Each has only two gaps, and no gap lines up with the next one, so expect a long way around between them. They will have warships, spinning barrage platforms and lance platforms that fire in a straight line in every sector. Once you are more than %dU from the jammer, jump for the Symposium and dock there.]],
        getSectorName(x, y), math.floor(field_radius / 1000), math.floor(field_radius / 1000))
end

--- Comms for the Messenger, in case the players hail it again.
local function commsMessenger()
    math.abs(0) -- Provides global context for SeriousProton
    setCommsMessage(messengerWarning())
end

--- Brings in the Messenger near player ship `p`, with its warning.
spawnMessenger = function(p)
    if messenger ~= nil or p == nil or not p:isValid() then
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
    hailPlayers(messenger, messengerWarning(), "#c0a0ff")
    local sx, sy = symposium:getPosition()
    for idx_, ship in ipairs(playerList) do
        if ship:isValid() then
            ship:commandAddWaypoint(sx, sy)
        end
    end
    logPlayers(string.format("Deliver the unstable 235 to the Intergalactic Symposium in sector %s. Waypoint added.", getSectorName(sx, sy)), "Yellow")
    messenger_timer = messenger_stay_time
end

--- Sends the Messenger away after its warning.
local function updateMessenger(delta)
    if messenger_timer == nil then
        return
    end
    messenger_timer = messenger_timer - delta
    if messenger_timer <= 0 then
        messenger_timer = nil
        if messenger:isValid() then
            local x, y = messenger:getPosition()
            warpInEffect(x, y, 800)
            messenger:destroy()
            logPlayers("The Messenger has slipped away. Nobody knows how it gets through a one-way jammer.", "#c0a0ff")
        end
    end
end

-------------------------------------------------------------------------------
-- The Directorate's jamming field
-------------------------------------------------------------------------------

--- Returns a random point inside the field, between min_r and max_r from its center.
local function randomFieldPoint(min_r, max_r)
    -- Square root keeps the points evenly spread over the area, not bunched at the center.
    local x, y = vectorFromAngle(random(0, 360), math.sqrt(random(min_r * min_r, max_r * max_r)))
    return field_x + x, field_y + y
end

--- Returns true if x, y is at least `clearance` away from every barrage station.
local function clearOfTurrets(x, y, clearance)
    for idx_, turret in ipairs(turrets) do
        if distance(turret.obj, x, y) < clearance then
            return false
        end
    end
    return true
end

--- Returns the `mines` grid cell key for x, y.
local function mineCell(cx, cy)
    return cx .. "," .. cy
end

--- Returns true if x, y is at least `clearance` away from every mine, so ships
-- don't warp in on top of one. `clearance` must not exceed `mine_cell_size`.
local function clearOfMines(x, y, clearance)
    local cx, cy = math.floor(x / mine_cell_size), math.floor(y / mine_cell_size)
    for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
            for idx_, mine in ipairs(mines[mineCell(gx, gy)] or {}) do
                if mine:isValid() and distance(mine, x, y) < clearance then
                    return false
                end
            end
        end
    end
    return true
end

--- Places a mine at x, y if it is inside the field and clear of the barrage stations.
local function placeMine(x, y)
    if distance(x, y, field_x, field_y) < field_radius - 500 and clearOfTurrets(x, y, 1500) and clearOfBodies(x, y, 500) then
        local key = mineCell(math.floor(x / mine_cell_size), math.floor(y / mine_cell_size))
        mines[key] = mines[key] or {}
        table.insert(mines[key], Mine():setPosition(x, y))
    end
end

--- Returns true if x, y is in one of the mine rings' exits, or just inside or outside one.
local function inRingExit(x, y)
    local d = distance(x, y, field_x, field_y)
    -- Same convention as vectorFromAngle. math.atan2 is gone in newer Lua versions.
    local a = math.deg((math.atan2 or math.atan)(y - field_y, x - field_x)) % 360
    for idx_, ring in ipairs(mine_ring_exits) do
        if math.abs(d - ring.radius) < ring.rows * mine_ring_row_spacing / 2 + 3000 then
            for e = 0, mine_ring_exit_count - 1 do
                if math.abs((a - (ring.first + e * mine_ring_exit_spacing) + 180) % 360 - 180) < ring.half_angle then
                    return true
                end
            end
        end
    end
    return false
end

--- Returns true if x, y is in one of the eight clear lanes through the asteroid rings.
-- The lanes run straight out from the ring center at 0, 0.
local function inLane(x, y)
    local d = distance(x, y, 0, 0)
    if d > lane_clear_radius then
        return false
    end
    local a = math.deg((math.atan2 or math.atan)(y, x)) % 360
    for n = 0, lane_count - 1 do
        local diff = math.abs((a - (lane_offset + n * 360 / lane_count) + 180) % 360 - 180)
        -- Distance from the lane's center line, plus a little margin.
        if diff < 90 and d * math.sin(math.rad(diff)) < lane_width / 2 + 500 then
            return true
        end
    end
    return false
end

--- Lays a ring of mines around the field center, with exits.
--
-- The ring is `ring.rows` staggered rows deep, close enough together that any path
-- through it crosses a trigger range. It has `mine_ring_exit_count` exits
-- `mine_ring_exit_width` wide, `mine_ring_exit_spacing` degrees apart, the first at
-- `first_exit` degrees.
local function createMineRing(ring, first_exit)
    local radius = ring.radius
    local exit_half_angle = math.deg(mine_ring_exit_width / radius) / 2
    table.insert(mine_ring_exits, {radius = radius, rows = ring.rows, first = first_exit, half_angle = exit_half_angle})
    for row = 0, ring.rows - 1 do
        local r = radius + (row - (ring.rows - 1) / 2) * mine_ring_row_spacing
        local count = math.floor(2 * math.pi * r / mine_ring_spacing)
        for n = 1, count do
            -- Every other row is shifted by half a step, so the rows don't line up.
            local a = (n + (row % 2) * 0.5) * 360 / count
            local in_exit = false
            for e = 0, mine_ring_exit_count - 1 do
                if math.abs((a - (first_exit + e * mine_ring_exit_spacing) + 180) % 360 - 180) < exit_half_angle then
                    in_exit = true
                end
            end
            if not in_exit then
                local x, y = vectorFromAngle(a, r)
                placeMine(field_x + x, field_y + y)
            end
        end
    end
end

--- Repairs part of the hull of the ship that picks up a hull repair kit.
local function onHullKitPickup(drop, ship)
    math.abs(0) -- Provides global context for SeriousProton
    local max_hull = ship:getHullMax()
    ship:setHull(math.min(max_hull, ship:getHull() + max_hull * hull_kit_repair))
    ship:addToShipLog(string.format("Hull repair kit recovered: hull restored by %d%%.", math.floor(hull_kit_repair * 100)), "#80c0ff")
end

--- Starts the house music playlist, unless it is already playing or empty.
local function startMusic()
    if music_index == nil and #house_music > 0 then
        music_index = 0
        music_timer = 0
    end
end

--- Switches to the journey music. The current track plays out first, then the
--- journey list loops from its first track.
local function startJourneyMusic()
    music_playlist = journey_music
    if music_index == nil then
        music_timer = 0
    end
    music_index = 0
end

--- Plays the next track in the playlist when the current one has finished.
local function updateMusic(delta)
    if music_index == nil then
        return
    end
    music_timer = music_timer - delta
    if music_timer <= 0 then
        music_index = music_index % #music_playlist + 1
        local track = music_playlist[music_index]
        playSoundFile(track.file)
        music_timer = track.length + music_gap
    end
end

--- Scatters supply drops through the field, clear of terrain and mines.
local function createSupplyDrops()
    local kinds = {
        {name = "Hull Repair Kit", count = byDifficulty(32, 24, 16)},
        {name = "Mine Cache", count = byDifficulty(20, 16, 12), weapon = "Mine", amount = 4},
        {name = "Homing Missile Cache", count = byDifficulty(36, 28, 20), weapon = "Homing", amount = 6},
    }
    for idx_, kind in ipairs(kinds) do
        for n = 1, kind.count do
            for attempt = 1, 20 do
                local x, y = randomFieldPoint(start_clear_radius, field_radius - 2000)
                if clearOfBodies(x, y, 1000) and clearOfMines(x, y, 1500) then
                    local drop = SupplyDrop():setFaction("Human Navy"):setPosition(x, y)
                    drop:setCallSign(kind.name)
                    if kind.weapon then
                        drop:setWeaponStorage(kind.weapon, kind.amount)
                        drop:setDescriptions("A supply canister.", string.format("%s: %d %s.", kind.name, kind.amount, kind.weapon == "Mine" and "mines" or "homing missiles"))
                    else
                        drop:onPickUp(onHullKitPickup)
                        drop:setDescriptions("A supply canister.", string.format("Hull Repair Kit: restores %d%% of the hull.", math.floor(hull_kit_repair * 100)))
                    end
                    break
                end
            end
        end
    end
end

--- Creates a barrage station at x, y.
--
-- With no `aim`, it is a rotating Barrage Platform that fires in every direction as it
-- turns. With an `aim` in degrees, it is a Lance Platform: it never turns, and fires
-- one fast stream of HVLIs in a straight line along that bearing.
local function createTurret(x, y, aim)
    turret_index = turret_index + 1
    local station = SpaceStation():setTemplate("Small Station"):setFaction("Directorate")
    station:setPosition(x, y)
    if aim == nil then
        station:setCallSign(string.format("Barrage Platform %d", turret_index))
        station:setDescriptions(
            "A Directorate weapons platform.",
            "A rotating Directorate barrage platform. Its HVLI barrels fire in every direction as it turns."
        )
    else
        station:setCallSign(string.format("Lance Platform %d", turret_index))
        station:setDescriptions(
            "A Directorate weapons platform.",
            string.format("A fixed Directorate lance platform. It fires a single stream of HVLIs in a straight line, on heading %d. Stay out of that line.", math.floor((aim + 90) % 360))
        )
    end
    station:setCommsScript(""):setCommsFunction(function()
        math.abs(0) -- Provides global context for SeriousProton
        setCommsMessage("This platform does not negotiate.")
    end)
    if aim == nil then
        local spin = random(15, 35)
        if random(0, 1) < 0.5 then
            spin = -spin
        end
        table.insert(turrets, {
            obj = station,
            angle = random(0, 360),
            spin = spin,
            barrels = byDifficulty(2, 3, 4),
            interval = byDifficulty(0.8, 0.6, 0.45),
            timer = random(0, 1),
        })
    else
        table.insert(turrets, {
            obj = station,
            angle = aim % 360,
            spin = 0,
            barrels = 1,
            interval = byDifficulty(0.5, 0.35, 0.25),
            timer = random(0, 1),
        })
    end
    warpInEffect(x, y, 800)
end

--- Returns a Directorate warship template, tougher as more waves arrive.
local function warshipTemplate()
    local templates = {"MT52 Hornet", "Adder MK5", "Phobos T3", "Nirvana R5"}
    return templates[math.min(#templates, irandom(1, 2 + math.floor(wave_count / 2)))]
end

--- Returns the direction player ship `p` is heading, in degrees: its direction of
-- travel when it is moving, otherwise straight out from the field center.
local function travelAngle(p)
    local atan2 = math.atan2 or math.atan
    local vx, vy = p:getVelocity()
    if vx * vx + vy * vy > 100 then
        return math.deg(atan2(vy, vx))
    end
    local px, py = p:getPosition()
    if distance(px, py, field_x, field_y) > 1000 then
        return math.deg(atan2(py - field_y, px - field_x))
    end
    return p:getRotation()
end

--- Returns true if x, y is at least `ship_spacing` from every ship in `ships`.
local function clearOfShips(x, y, ships)
    for idx_, ship in ipairs(ships) do
        if ship:isValid() and distance(ship, x, y) < ship_spacing then
            return false
        end
    end
    return true
end

--- Returns true if x, y is a good place for a warship to warp in: inside the field,
-- clear of mines, terrain and the other ships in `ships`.
local function goodShipSpot(x, y, ships)
    return distance(x, y, field_x, field_y) < field_radius - 1000 and clearOfMines(x, y, 1200)
        and clearOfBodies(x, y, 1000) and clearOfShips(x, y, ships)
end

--- Returns a spot ahead of player ship `p`, across the course it is flying, or nil.
local function pathSpot(p, ships)
    local px, py = p:getPosition()
    local heading = travelAngle(p)
    for attempt = 1, 15 do
        local ax, ay = vectorFromAngle(heading, random(path_distance[1], path_distance[2]))
        local ox, oy = vectorFromAngle(heading + 90, random(-path_spread, path_spread))
        local x, y = px + ax + ox, py + ay + oy
        if goodShipSpot(x, y, ships) then
            return x, y
        end
    end
    return nil
end

--- Creates a Directorate warship at x, y.
local function createWarship(x, y, description)
    local ship = CpuShip():setTemplate(warshipTemplate()):setFaction("Directorate"):setPosition(x, y)
    ship:setCallSign(nextWarshipName())
    ship:setDescription(description)
    warpInEffect(x, y, 500)
    table.insert(warships, ship)
    return ship
end

--- Warps a wave of Directorate warships in around the player ship, and drops mines ahead of it.
local function spawnWave()
    local p = closestPlayer(field_x, field_y)
    if p == nil then
        return
    end
    wave_count = wave_count + 1
    local alive = 0
    for idx_, ship in ipairs(warships) do
        if ship:isValid() then
            alive = alive + 1
        end
    end
    local count = math.min(byDifficulty(3, 5, 8), byDifficulty(12, 20, 30) - alive)
    local px, py = p:getPosition()
    for n = 1, count do
        -- Some ships cut across the player's course; the rest come from every side.
        -- Warships only warp into the field, never outside it, so near the edge a
        -- ship may find no spot and not come.
        local x, y = nil, nil
        if n <= math.ceil(count * path_share) then
            x, y = pathSpot(p, warships)
        end
        for attempt = 1, 10 do
            local dx, dy = vectorFromAngle(random(0, 360), random(wave_spawn_distance[1], wave_spawn_distance[2]))
            if x == nil and goodShipSpot(px + dx, py + dy, warships) then
                x, y = px + dx, py + dy
            end
        end
        if x ~= nil then
            local ship = createWarship(x, y, "A Directorate warship sent to recover the unstable 235.")
            ship:orderAttack(p)
        end
    end
    -- A line of mines across the player's course, but never in a mine ring exit or a lane.
    local heading = p:getRotation()
    local ax, ay = vectorFromAngle(heading, mine_drop_distance)
    for n = -2, 2 do
        local ox, oy = vectorFromAngle(heading + 90, n * 700)
        if not inRingExit(px + ax + ox, py + ay + oy) and not inLane(px + ax + ox, py + ay + oy) then
            placeMine(px + ax + ox, py + ay + oy)
        end
    end
end

--- Deploys the one-way warp jammer at the center of the asteroid rings, with mines
-- and barrage stations.
deployField = function()
    if field_deployed then
        return
    end
    field_deployed = true
    field_x, field_y = 0, 0

    -- The jammer core. The WarpJammer object does the actual jamming; the station is
    -- what the players see, and can't be destroyed.
    jammer_core = SpaceStation():setTemplate("Huge Station"):setFaction("Directorate")
    jammer_core:setCallSign("One-Way Warp Jammer"):setPosition(field_x, field_y)
    jammer_core:setCanBeDestroyed(false)
    jammer_core:setDescriptions(
        "An enormous Directorate installation.",
        string.format("A one-way warp jammer. Ships can warp into its %dU field, but no warp or jump drive can work inside it. The only way out is under impulse.", math.floor(field_radius / 1000))
    )
    jammer_core:setCommsScript(""):setCommsFunction(function()
        math.abs(0) -- Provides global context for SeriousProton
        setCommsMessage("Surrender the unstable 235 and power down your engines. There is no other way out of this field.")
    end)
    WarpJammer():setFaction("Directorate"):setPosition(field_x, field_y):setRange(field_radius):setHull(1000000)
    warpInEffect(field_x, field_y, 3000)

    -- The field outline.
    local points = {}
    for n = 0, 71 do
        local x, y = vectorFromAngle(n * 5, field_radius)
        table.insert(points, field_x + x)
        table.insert(points, field_y + y)
    end
    Zone():setPoints((table.unpack or unpack)(points)):setColor(90, 10, 10):setLabel("Jamming Field")

    -- Rings of mines, each with two exits. The inner ring's exits sit halfway between
    -- two of the asteroid lanes, and each ring after that is turned about 90 degrees
    -- from the one inside it, so every exit leads into a long run around the ring.
    local exit_angle = lane_offset + 360 / lane_count * (irandom(0, lane_count - 1) + 0.5)
    for idx_, ring in ipairs(mine_rings) do
        if idx_ > 1 then
            exit_angle = exit_angle + mine_ring_exit_turn + random(-mine_ring_exit_jitter, mine_ring_exit_jitter)
        end
        createMineRing(ring, exit_angle % 360)
    end

    -- Scattered mines, kept out of the ring exits so the exits stay clear.
    for n = 1, byDifficulty(700, 1200, 1800) do
        local x, y = randomFieldPoint(start_clear_radius, field_radius)
        if not inRingExit(x, y) and not inLane(x, y) and clearOfMines(x, y, 1500) then
            placeMine(x, y)
        end
    end

    createSupplyDrops()
    startMusic()

    -- Every map sector that overlaps the field gets a garrison.
    for col = math.floor((field_x - field_radius) / sector_size), math.floor((field_x + field_radius) / sector_size) do
        for row = math.floor((field_y - field_radius) / sector_size), math.floor((field_y + field_radius) / sector_size) do
            -- The closest point of the sector square to the field center.
            local cx = math.max(col * sector_size, math.min(field_x, (col + 1) * sector_size))
            local cy = math.max(row * sector_size, math.min(field_y, (row + 1) * sector_size))
            if distance(cx, cy, field_x, field_y) < field_radius then
                table.insert(field_sectors, {col = col, row = row, spawned = false})
            end
        end
    end

    wave_timer = byDifficulty(25, 15, 10)

    local text = string.format([[This is the Interplanetary Directorate.

Unstable 235 is the most tightly controlled element in known space. It powers worlds, and it builds weapons that end them. Your local government swore to us that none existed in this system. They lied, and you are carrying the proof.

A one-way warp jammer now covers %dU around the rings. Ships can warp in. Nothing warps out. Surrender the unstable 235, or be stopped.]], math.floor(field_radius / 1000))
    -- The Messenger has just hailed, so this usually lands in the ship's log.
    hailPlayers(jammer_core, text, "#ff4040")
    logPlayers(string.format("Warp and jump drives jammed. Escape the jamming field under impulse: get more than %dU from the One-Way Warp Jammer.", math.floor(field_radius / 1000)), "Yellow")
end

--- Returns a random spot anywhere in the sector and inside the field, at least
-- `min_dist` from every player ship and clear of `ships`. Returns nil if there is none.
local function garrisonSpot(sector, min_dist, ships)
    local x0, y0 = sector.col * sector_size, sector.row * sector_size
    for attempt = 1, 30 do
        local x, y = x0 + random(0, sector_size), y0 + random(0, sector_size)
        local p_, d = closestPlayer(x, y)
        if (d == nil or d > min_dist) and goodShipSpot(x, y, ships) then
            return x, y
        end
    end
    return nil
end

--- Warps in the garrison of one field sector: warships spread over the sector, some
-- of them across the nearest player's course, spinning barrage platforms and fixed
-- lance platforms.
--
-- Each warship guards the spot it warped in at, so the garrison stays spread out
-- instead of gathering in the middle of the sector.
local function spawnGarrison(sector)
    sector.spawned = true
    local cx, cy = (sector.col + 0.5) * sector_size, (sector.row + 0.5) * sector_size
    local p = closestPlayer(cx, cy)
    local count = byDifficulty(3, 5, 7)
    for n = 1, count do
        local x, y = nil, nil
        if p ~= nil and n <= math.ceil(count * path_share) then
            x, y = pathSpot(p, warships)
        end
        if x == nil then
            x, y = garrisonSpot(sector, garrison_min_distance, warships)
        end
        if x ~= nil then
            local ship = createWarship(x, y, "A Directorate warship guarding the jamming field.")
            ship:orderDefendLocation(x, y)
        end
    end
    -- Platforms keep a little more distance, since they open fire straight away.
    for n = 1, byDifficulty(1, 1, 2) do
        local x, y = garrisonSpot(sector, garrison_min_distance + 1000, warships)
        if x ~= nil then
            createTurret(x, y)
        end
    end
    -- Lance platforms fire across the nearest player's course, give or take a little.
    for n = 1, byDifficulty(1, 2, 2) do
        local x, y = garrisonSpot(sector, garrison_min_distance + 1000, warships)
        if x ~= nil then
            local aim = random(0, 360)
            if p ~= nil then
                aim = travelAngle(p) + (random(0, 1) < 0.5 and 90 or -90) + random(-25, 25)
            end
            createTurret(x, y, aim)
        end
    end
end

--- Warps in the garrison of every field sector that is next to a player ship's sector.
local function updateGarrisons()
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            local px, py = p:getPosition()
            local col, row = math.floor(px / sector_size), math.floor(py / sector_size)
            for idx2_, sector in ipairs(field_sectors) do
                if not sector.spawned and math.abs(sector.col - col) <= 1 and math.abs(sector.row - row) <= 1 then
                    spawnGarrison(sector)
                end
            end
        end
    end
end

--- Keeps every Directorate warship a little slower than the fastest player ship.
--
-- A player ship's real top speed is its impulse speed times the impulse power level
-- (300% with unstable 235 aboard) and the impulse system's health.
local function updateEnemySpeed()
    local fastest = 0
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            local speed = p:getImpulseMaxSpeed() * p:getSystemPower("impulse") * math.max(0, math.min(1, p:getSystemHealth("impulse")))
            fastest = math.max(fastest, speed)
        end
    end
    local speed = math.max(enemy_min_speed, fastest * enemy_speed_factor)
    for idx_, ship in ipairs(warships) do
        if ship:isValid() then
            ship:setImpulseMaxSpeed(speed)
        end
    end
end

--- Turns the barrage stations and fires their HVLIs.
local function updateTurrets(delta)
    for idx_, turret in ipairs(turrets) do
        local station = turret.obj
        if station:isValid() then
            turret.angle = (turret.angle + turret.spin * delta) % 360
            station:setRotation(turret.angle)
            local x, y = station:getPosition()
            local p, d = closestPlayer(x, y)
            turret.timer = turret.timer - delta
            if p ~= nil and d < turret_fire_range and turret.timer <= 0 then
                turret.timer = turret.interval
                for b = 0, turret.barrels - 1 do
                    local a = turret.angle + b * 360 / turret.barrels
                    local mx, my = vectorFromAngle(a, turret_muzzle_offset)
                    HVLI():setPosition(x + mx, y + my):setRotation(a):setLifetime(hvli_lifetime)
                end
            end
        end
    end
end

--- Sends reinforcement waves, and checks whether a player ship has escaped.
local function updateField(delta)
    wave_timer = wave_timer - delta
    if wave_timer <= 0 then
        wave_timer = byDifficulty(60, 45, 35)
        spawnWave()
    end
    if not escaped and carrier ~= nil and carrier:isValid() and distance(carrier, field_x, field_y) > field_radius then
        escaped = true
        startJourneyMusic()
        logPlayers("Clear of the jamming field. The jump drive is working again. Get to the Intergalactic Symposium and dock.", "Yellow")
    end
end

--- Wins the game when the ship carrying the unstable 235 docks at the Symposium.
local function updateDelivery()
    if carrier ~= nil and carrier:isValid() and carrier:isDocked(symposium) then
        local text = string.format([[Welcome to the Intergalactic Symposium, %s.

The unstable 235 is in safe hands now. It will be taken care of peacefully, and the Directorate will never touch it.

As for BAD_LED... the Symposium has a very long memory.]], carrier:getCallSign())
        symposium:sendCommsMessage(carrier, text)
        endGame("Human Navy", _("msgMainscreen&Spectbanner", "Mission: SUCCESS (the unstable 235 reached the Intergalactic Symposium)"))
    end
end

-------------------------------------------------------------------------------
-- GM
-------------------------------------------------------------------------------

function gmButtons()
    clearGMFunctions()
    addGMFunction(_("buttonGM", "Deploy jammer"), function()
        math.abs(0) -- Provides global context for SeriousProton
        deployField()
    end)
    addGMFunction(_("buttonGM", "BAD_LED warps out"), function()
        math.abs(0) -- Provides global context for SeriousProton
        bad_led_hit = true
        if bad_led_state == "waiting" then
            bad_led_state = "bragging"
        end
    end)
    addGMFunction(_("buttonGM", "Start music"), function()
        math.abs(0) -- Provides global context for SeriousProton
        startMusic()
    end)
    addGMFunction(_("buttonGM", "Send wave"), function()
        math.abs(0) -- Provides global context for SeriousProton
        if field_deployed then spawnWave() end
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

    local pirates_faction = FactionInfo():setName("Pirates"):setLocaleName("Pirates")
    pirates_faction:setGMColor(255, 96, 0)
    pirates_faction:setDescription("Pirates working the outer asteroid clusters.")
    pirates_faction:setEnemy(getFactionInfo("Human Navy"))

    local scavengers_faction = FactionInfo():setName("Scavengers"):setLocaleName("Scavengers")
    scavengers_faction:setGMColor(160, 128, 64)
    scavengers_faction:setDescription("Salvage crews who pick over wreckage.")

    local couriers = FactionInfo():setName("Couriers"):setLocaleName("Couriers")
    couriers:setGMColor(192, 160, 255)
    couriers:setDescription("Nobody knows who the Couriers work for.")

    -- The neighboring government. Hostile only to the Navy ship carrying the 235.
    directorate_faction = FactionInfo():setName("Directorate"):setLocaleName("Interplanetary Directorate")
    directorate_faction:setGMColor(255, 40, 40)
    directorate_faction:setDescription("The neighboring interplanetary government. It controls unstable 235 across known space, and does not forgive anyone who hides it.")
    directorate_faction:setEnemy(getFactionInfo("Human Navy"))

    -- The mining rings have shifted: every band has the same eight gaps, so eight
    -- straight lanes lead out from the center.
    lane_offset = random(0, 360 / lane_count)
    local gaps = {}
    for n = 0, lane_count - 1 do
        table.insert(gaps, lane_offset + n * 360 / lane_count)
    end
    for idx_, radius in ipairs(ring_radii) do
        createAsteroidBand(radius - lane_half_width, gaps, lane_width)
        createAsteroidBand(radius + lane_half_width, gaps, lane_width)
    end
    local stations = {
        {"Medium Station", "Mining Guild Depot",    "Headquarters of the asteroid miners."},
        {"Large Station",  "Reunion Hall",          "Host of the piloting school class reunion."},
        {"Medium Station", "Planetary Comms Relay", "The planetary comms hub."},
        {"Small Station",  "Academy Annex",         "An outpost of the piloting school."},
    }
    for n, info in ipairs(stations) do
        local station = SpaceStation():setTemplate(info[1]):setFaction("Human Navy"):setRotation(random(0, 360))
        station:setCallSign(info[2]):setDescription(info[3])
        setCirclePos(station, 0, 0, -90 + (n - 1) * 90, station_radius)
        -- Keep mines and warships from appearing on top of the stations.
        local x, y = station:getPosition()
        table.insert(station_spots, {x = x, y = y, r = 1500})
    end

    mining_central = SpaceStation():setTemplate("Large Station"):setFaction("Independent")
    mining_central:setCallSign("Mining Central"):setPosition(central_x, central_y)
    mining_central:setDescription("The hub of the outer mining clusters.")
    mining_central:setCanBeDestroyed(false)
    table.insert(station_spots, {x = central_x, y = central_y, r = 2000})

    clusters = {
        {name = "Cluster 1", angle = -45},
        {name = "Cluster 2", angle = -135},
        {name = "Cluster 3", angle = 135},
        {name = "Cluster 4", angle = 45},
    }
    for idx_, cluster in ipairs(clusters) do
        local x, y = vectorFromAngle(cluster.angle, cluster_distance)
        cluster.x, cluster.y = central_x + x, central_y + y
    end
    for n = 1, 3 do
        createAsteroidCluster(clusters[n])
    end
    createAsteroidCluster(clusters[4], {central_x, central_y, clusters[4].x, clusters[4].y})

    -- Cluster 1: a stranded hauler.
    local hauler = CpuShip():setTemplate("Transport1x3"):setFaction("Independent"):setCallSign("Ore Hauler Kestrel")
    hauler:setPosition(clusters[1].x, clusters[1].y):orderIdle()

    -- Cluster 2: Twisted Transistor meeting a pirate contact. Both stay idle.
    local transistor = CpuShip():setTemplate("Stalker Q7"):setFaction("Kraylor"):setCallSign("Twisted Transistor")
    transistor:setPosition(clusters[2].x - 300, clusters[2].y):setRotation(0):orderIdle()
    local contact = CpuShip():setTemplate("Adder MK5"):setFaction("Pirates"):setCallSign(nextPirateName())
    contact:setPosition(clusters[2].x + 300, clusters[2].y):setRotation(180):orderIdle()

    -- Cluster 3: salvage, wreckage and scavengers.
    local salvage = {
        "Mining Drill Head", "Ore Scanner Array", "Tractor Coupling", "Survey Drone Core",
        "Cargo Manifest Recorder", "Refinery Valve Assembly", "Grav Anchor", "Laser Cutter Lens",
    }
    for idx_, name in ipairs(salvage) do
        local item = Artifact():setCallSign(name)
        setCirclePos(item, clusters[3].x, clusters[3].y, random(0, 360), random(600, cluster_radius - 600))
        item:setDescriptions("Debris from an attack.", string.format("%s, stamped with the mining guild's mark.", name))
        item:allowPickup(true)
    end
    for n = 1, 6 do
        local debris = Artifact():setCallSign("Wreckage")
        setCirclePos(debris, clusters[3].x, clusters[3].y, random(0, 360), random(500, cluster_radius))
        debris:setDescriptions("Debris from an attack.", "Twisted hull plating from a mining ship.")
    end
    for n = 1, 2 do
        local scav = CpuShip():setTemplate(n == 1 and "Adder MK5" or "MT52 Hornet"):setFaction("Scavengers")
        scav:setCallSign(n == 1 and "Scrapper Mags" or "Scrapper Twitch")
        setCirclePos(scav, clusters[3].x, clusters[3].y, random(0, 360), cluster_radius * 0.6)
        scav:orderIdle()
    end

    -- Cluster 4: the dig site and the ore caravan.
    dig_site = SpaceStation():setTemplate("Small Station"):setFaction("Independent"):setCallSign("Dig Site Four")
    dig_site:setPosition(clusters[4].x, clusters[4].y)
    dig_site:setCanBeDestroyed(false)
    table.insert(station_spots, {x = clusters[4].x, y = clusters[4].y, r = 1500})
    local caravan_names = {"Ore Hauler Magpie", "Ore Hauler Bramble", "Ore Hauler Tumbler", "Ore Hauler Fennec"}
    for n, name in ipairs(caravan_names) do
        local ship = CpuShip():setTemplate("Transport" .. irandom(1, 5) .. "x" .. irandom(2, 4)):setFaction("Independent")
        ship:setCallSign(name)
        local t = n / (#caravan_names + 1)
        ship:setPosition(central_x + (clusters[4].x - central_x) * t, central_y + (clusters[4].y - central_y) * t)
        local entry = {ship = ship, dest = (n % 2 == 0) and mining_central or dig_site, wait = 0}
        ship:orderDock(entry.dest)
        table.insert(caravan, entry)
    end

    -- The Scriptorium.
    local sx, sy = vectorFromAngle(secret_base_angle, secret_base_distance)
    sx, sy = central_x + sx, central_y + sy
    secret_base = SpaceStation():setTemplate("Small Station"):setFaction("Couriers"):setCallSign("The Scriptorium")
    secret_base:setPosition(sx, sy)
    secret_base:setDescription("A quiet station far from the shipping lanes. Its hull is etched with looping script.")
    secret_base:setCanBeDestroyed(false)

    createTerrain(sx, sy)
    for idx_, spot in ipairs(station_spots) do
        table.insert(bodies, spot)
    end

    -- The two deposits at the center of the rings. BAD_LED sits on the one he took,
    -- across the center from the one that's left.
    local dx, dy = vectorFromAngle(random(0, 360), sample_distance)
    createSample(dx, dy)
    createBadLed(-dx, -dy)

    -- The Intergalactic Symposium, well outside the jamming field.
    local yx, yy = vectorFromAngle(symposium_angle, symposium_distance)
    symposium = SpaceStation():setTemplate("Large Station"):setFaction("Independent"):setCallSign("Intergalactic Symposium")
    symposium:setPosition(yx, yy)
    symposium:setDescription("A neutral meeting place for every government in known space. It handles the matters nobody else can be trusted with.")
    symposium:setCanBeDestroyed(false)

    -- Terrain around the jammer, kept clear of the Symposium and the Scriptorium.
    table.insert(bodies, {x = yx, y = yy, r = 5000, terrain_only = true})
    table.insert(bodies, {x = sx, y = sy, r = 5000, terrain_only = true})
    createFieldTerrain()
    finishTerrain()

    -- The player ship starts at the mouth of a random lane, outside the asteroid rings.
    local player = PlayerSpaceship():setFaction("Human Navy"):setTemplate(getScenarioSetting("PlayerShip"))
    player:setCallSign("USS-SUNDAY NCC-67")
    local start_angle = lane_offset + irandom(0, lane_count - 1) * 360 / lane_count
    setCirclePos(player, 0, 0, start_angle, player_start_distance)
    player:setRotation(start_angle + 180)
    if not player:hasJumpDrive() then
        player:setJumpDrive(true)
        player:setJumpDriveRange(5000, 50000)
    end
    playerList = {player}
    onNewPlayerShip(function(ship)
        math.abs(0) -- Provides global context for SeriousProton
        table.insert(playerList, ship)
    end)

    gmButtons()

    player:commandAddWaypoint(0, 0)
    secret_base:sendCommsMessage(player, string.format([[The Calligrapher again. Something has changed in the mining belt.

The asteroid rings have shifted. Every band has opened in the same eight places, so there are now eight clear lanes running straight out from the center, and the two deposits of unstable 235 have settled right in the middle, in sector %s. Your nav screen has the waypoint.

Remember what I told you: someone has been listening to every coordinate you received. Expect company at the center.

And do not fire on the 235. One shot, and it collapses into a black hole.]], getSectorName(0, 0)))
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

function update(delta)
    -- The music keeps going after the mission ends.
    updateMusic(delta)
    if game_over then
        return
    end

    local alive = false
    for idx_, p in ipairs(playerList) do
        if p:isValid() then
            alive = true
        end
    end
    if not alive then
        endGame("Directorate", _("msgMainscreen&Spectbanner", "Mission: FAILED (the USS-SUNDAY NCC-67 was destroyed)"))
        return
    end
    if carrier ~= nil and not carrier:isValid() then
        endGame("Directorate", _("msgMainscreen&Spectbanner", "Mission: FAILED (the unstable 235 fell into the hands of the Directorate)"))
        return
    end

    updateSamples()
    if game_over then
        return
    end
    updateBoosted()
    updateCaravan(delta)
    updateBadLed(delta)
    updateMessenger(delta)

    if field_deployed then
        updateTurrets(delta)
        updateGarrisons()
        speed_timer = speed_timer - delta
        if speed_timer <= 0 then
            speed_timer = 1
            updateEnemySpeed()
        end
        updateField(delta)
    end
    updateDelivery()
end
