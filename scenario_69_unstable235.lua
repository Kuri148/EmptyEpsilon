-- Name: Unstable 235
-- Description: An escape mission on the Kralien Cursive map. Your ship starts beside the Scriptorium, next to two canisters of unstable 235: shoot one and it collapses into a black hole, fly into one and your hull doubles in strength and your reactor, maneuvering and impulse run at full power with no overheating and no extra energy drain.
---
--- Unstable 235 powers planets and builds weapons that can destroy galaxies. It is one of the most tightly controlled elements there is, and the local government has been hiding it. The neighboring Interplanetary Directorate has found out. They will lock the area under a huge one-way warp jammer and flood it with mines, warships and rotating barrage stations.
---
--- Escape the jamming field to win. Lose your ship and you lose the game.
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

-- Unstable 235 samples sit east of the Scriptorium; the player starts west of it,
-- so a black hole (5U pull radius) doesn't catch the ship at the start.
local sample_distance = 4000    -- From the Scriptorium to the samples.
local sample_spread = 1500      -- Distance between the two samples.
local player_start_distance = 1500 -- From the Scriptorium to the player ship.
local pickup_range = 800        -- Ship center to sample center.

-- Full power is the top of the engineering slider, 300%.
local full_power = 3.0
local boosted_systems = {"reactor", "maneuver", "impulse"}

-- The Directorate's jamming field.
local deploy_delay = 90         -- Seconds after the start before the field deploys anyway.
local field_radius = 70000      -- Players must get this far from the center to escape.
local field_center_offset = 4000 -- The jammer core appears this far from the player ship.
local start_clear_radius = 5000 -- No mines or barrage stations this close to the center.
local turret_fire_range = 12000 -- Barrage stations fire only when a player is this close.
local turret_muzzle_offset = 800 -- HVLIs spawn this far from the station center.
local hvli_lifetime = 10
local wave_spawn_distance = {3500, 5500} -- Warships warp in this far from the player.
local mine_drop_distance = 6000 -- Each wave also drops mines this far ahead of the player.
local sector_size = 20000       -- The game's map grid squares ("F5" and so on).
local mine_ring_radii = {25000, 59000} -- Two dense mine rings around the field center.
local mine_ring_rows = 4        -- Staggered rows of mines in each ring.
local mine_ring_row_spacing = 650 -- Distance between the rows.
local mine_ring_spacing = 800   -- Distance between mines along a row.
local mine_ring_exit_width = 15000 -- Each ring has three exits this wide, 60 degrees apart.
local hull_kit_repair = 0.4     -- A hull repair kit restores this share of the maximum hull.
local garrison_distance = {3000, 8000} -- Garrisons warp in this far from the player when they can.
local enemy_speed_factor = 0.9  -- Directorate ships fly at 90% of the fastest player ship's speed.
local enemy_min_speed = 40      -- ...but never slower than this.

local playerList
local mining_central
local clusters
local dig_site
local caravan = {}
local secret_base
local game_over = false
local start_timer = 0

-- Unstable 235 samples. Each entry is {obj = WarpJammer, shot = bool, gone = bool}.
local samples = {}
-- Ships that have picked up a sample, mapped to true.
local boosted = {}

-- Escape phase
local directorate_faction
local field_deployed = false
local field_x, field_y
local jammer_core
local turrets = {}  -- Each entry is {obj, angle, spin, barrels, interval, timer}.
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

--- Finds a free spot for a feature of radius `r` around sx, sy, and reserves it.
-- Returns nil if no spot was found.
local function reserveSpot(sx, sy, r)
    for attempt = 1, 60 do
        local dx, dy = vectorFromAngle(random(0, 360), random(terrain_inner + r, terrain_outer - r))
        local x, y = sx + dx, sy + dy
        if clearOfBodies(x, y, r + 3000) then
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
local function createPlanetSystem(sx, sy, info, moons)
    local reach = info.radius
    for idx_, moon in ipairs(moons) do
        reach = math.max(reach, moon.orbit + moon.radius)
    end
    local x, y = reserveSpot(sx, sy, reach)
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

    -- From here on, `bodies` is only used to keep mines and ships out of solid terrain,
    -- so drop the entries that were only there to space out the terrain.
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
        "Unstable 235. Any weapons fire will collapse it into a black hole. Fly into it to take it aboard: it will double the hull strength and drive the reactor, maneuvering and impulse to full power without overheating or draining energy."
    )
    jammer:onTakingDamage(onSampleShot)
    jammer:onDestruction(onSampleShot)
    table.insert(samples, {obj = jammer, shot = false, gone = false})
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

--- Spawns black holes for shot samples, and handles pickups.
--
-- Shooting or picking up a sample tips off the Directorate, which deploys the field.
local function updateSamples()
    for idx_, sample in ipairs(samples) do
        if not sample.gone then
            local obj = sample.obj
            if not obj:isValid() then
                -- Destroyed without the damage callback reaching us first.
                sample.gone = true
            elseif sample.shot then
                sample.gone = true
                local x, y = obj:getPosition()
                obj:destroy()
                BlackHole():setPosition(x, y)
                logPlayers(string.format("Unstable 235 collapsed into a black hole in sector %s!", getSectorName(x, y)), "Red")
                deployField(closestPlayer(x, y))
            else
                for idx2_, p in ipairs(playerList) do
                    if not sample.gone and p:isValid() and distance(p, obj) < pickup_range then
                        sample.gone = true
                        obj:destroy()
                        boostShip(p)
                        deployField(p)
                    end
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

--- Flashes a warp-in effect at x, y.
local function warpInEffect(x, y, size)
    ElectricExplosionEffect():setPosition(x, y):setSize(size):setOnRadar(true)
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
        if math.abs(d - ring.radius) < mine_ring_rows * mine_ring_row_spacing / 2 + 3000 then
            for e = 0, 2 do
                if math.abs((a - (ring.first + e * 60) + 180) % 360 - 180) < ring.half_angle then
                    return true
                end
            end
        end
    end
    return false
end

--- Lays a dense ring of mines around the field center, with exits.
--
-- The ring is `mine_ring_rows` staggered rows deep, close enough together that any
-- path through it crosses several trigger ranges. It has three exits
-- `mine_ring_exit_width` wide, 60 degrees apart, starting at a random angle.
local function createMineRing(radius)
    local first_exit = random(0, 360)
    local exit_half_angle = math.deg(mine_ring_exit_width / radius) / 2
    table.insert(mine_ring_exits, {radius = radius, first = first_exit, half_angle = exit_half_angle})
    for row = 0, mine_ring_rows - 1 do
        local r = radius + (row - (mine_ring_rows - 1) / 2) * mine_ring_row_spacing
        local count = math.floor(2 * math.pi * r / mine_ring_spacing)
        for n = 1, count do
            -- Every other row is shifted by half a step, so the rows don't line up.
            local a = (n + (row % 2) * 0.5) * 360 / count
            local in_exit = false
            for e = 0, 2 do
                if math.abs((a - (first_exit + e * 60) + 180) % 360 - 180) < exit_half_angle then
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

--- Scatters supply drops through the field, clear of terrain and mines.
local function createSupplyDrops()
    local kinds = {
        {name = "Hull Repair Kit", count = byDifficulty(16, 12, 8)},
        {name = "Mine Cache", count = byDifficulty(10, 8, 6), weapon = "Mine", amount = 4},
        {name = "Homing Missile Cache", count = byDifficulty(18, 14, 10), weapon = "Homing", amount = 6},
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

--- Creates a rotating barrage station at x, y.
local function createTurret(x, y)
    turret_index = turret_index + 1
    local station = SpaceStation():setTemplate("Small Station"):setFaction("Directorate")
    station:setCallSign(string.format("Barrage Platform %d", turret_index)):setPosition(x, y)
    station:setDescriptions(
        "A Directorate weapons platform.",
        "A rotating Directorate barrage platform. Its HVLI barrels fire in every direction as it turns."
    )
    station:setCommsScript(""):setCommsFunction(function()
        math.abs(0) -- Provides global context for SeriousProton
        setCommsMessage("This platform does not negotiate.")
    end)
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
    warpInEffect(x, y, 800)
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
        -- Warships only warp into the field, never outside it. Near the edge, try a
        -- few directions; if none of them is inside, this ship doesn't come.
        local x, y = nil, nil
        for attempt = 1, 10 do
            local dx, dy = vectorFromAngle(random(0, 360), random(wave_spawn_distance[1], wave_spawn_distance[2]))
            if x == nil and distance(px + dx, py + dy, field_x, field_y) < field_radius - 1000 and clearOfMines(px + dx, py + dy, 1200) and clearOfBodies(px + dx, py + dy, 1000) then
                x, y = px + dx, py + dy
            end
        end
        if x == nil then
            break
        end
        local ship = CpuShip():setTemplate(warshipTemplate()):setFaction("Directorate"):setPosition(x, y)
        ship:setCallSign(nextWarshipName())
        ship:setDescription("A Directorate warship sent to recover the unstable 235.")
        ship:orderAttack(p)
        warpInEffect(x, y, 500)
        table.insert(warships, ship)
    end
    -- A line of mines across the player's course, but never in a mine ring exit.
    local heading = p:getRotation()
    local ax, ay = vectorFromAngle(heading, mine_drop_distance)
    for n = -2, 2 do
        local ox, oy = vectorFromAngle(heading + 90, n * 700)
        if not inRingExit(px + ax + ox, py + ay + oy) then
            placeMine(px + ax + ox, py + ay + oy)
        end
    end
end

--- Deploys the one-way warp jammer around player ship `p`, with mines and barrage stations.
deployField = function(p)
    if field_deployed then
        return
    end
    if p == nil or not p:isValid() then
        p = closestPlayer(secret_base:getPosition())
        if p == nil then
            return
        end
    end
    field_deployed = true
    local px, py = p:getPosition()
    local ox, oy = vectorFromAngle(random(0, 360), field_center_offset)
    field_x, field_y = px + ox, py + oy

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

    -- Dense rings of mines, each with its own three exits.
    for idx_, radius in ipairs(mine_ring_radii) do
        createMineRing(radius)
    end

    -- Scattered mines, kept out of the ring exits so the exits stay clear.
    for n = 1, byDifficulty(350, 600, 900) do
        local x, y = randomFieldPoint(start_clear_radius, field_radius)
        if not inRingExit(x, y) and clearOfMines(x, y, 1500) then
            placeMine(x, y)
        end
    end

    createSupplyDrops()

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

A one-way warp jammer now covers %dU around you. Ships can warp in. Nothing warps out. Surrender, or be stopped.]], math.floor(field_radius / 1000))
    hailPlayers(jammer_core, text, "#ff4040")
    logPlayers(string.format("Warp and jump drives jammed. Escape the jamming field under impulse: get more than %dU from the One-Way Warp Jammer.", math.floor(field_radius / 1000)), "Yellow")
    for idx_, ship in ipairs(playerList) do
        if ship:isValid() then
            ship:commandAddWaypoint(field_x, field_y)
        end
    end
end

--- Returns a Directorate warship template, tougher as more waves arrive.
local function warshipTemplate()
    local templates = {"MT52 Hornet", "Adder MK5", "Phobos T3", "Nirvana R5"}
    return templates[math.min(#templates, irandom(1, 2 + math.floor(wave_count / 2)))]
end

--- Returns a spot inside both the sector and the field, preferably `garrison_distance`
-- from the nearest player ship, and never closer than `min_dist`. Returns nil if there is none.
local function garrisonSpot(sector, min_dist)
    local x0, y0 = sector.col * sector_size, sector.row * sector_size
    local fallback_x, fallback_y = nil, nil
    for attempt = 1, 30 do
        local x, y = x0 + random(0, sector_size), y0 + random(0, sector_size)
        local p_, d = closestPlayer(x, y)
        if distance(x, y, field_x, field_y) < field_radius - 1000 and (d == nil or d > min_dist) and clearOfMines(x, y, 1200) and clearOfBodies(x, y, 1000) then
            if d == nil or d < garrison_distance[2] then
                return x, y
            end
            fallback_x, fallback_y = x, y
        end
    end
    return fallback_x, fallback_y
end

--- Warps in the garrison of one field sector: warships that guard the sector, and
-- spinning barrage platforms.
local function spawnGarrison(sector)
    sector.spawned = true
    local cx, cy = (sector.col + 0.5) * sector_size, (sector.row + 0.5) * sector_size
    for n = 1, byDifficulty(3, 5, 7) do
        local x, y = garrisonSpot(sector, garrison_distance[1])
        if x ~= nil then
            local ship = CpuShip():setTemplate(warshipTemplate()):setFaction("Directorate"):setPosition(x, y)
            ship:setCallSign(nextWarshipName())
            ship:setDescription("A Directorate warship guarding the jamming field.")
            ship:orderDefendLocation(cx, cy)
            warpInEffect(x, y, 500)
            table.insert(warships, ship)
        end
    end
    -- Platforms keep a little more distance, since they open fire straight away.
    for n = 1, byDifficulty(1, 1, 2) do
        local x, y = garrisonSpot(sector, garrison_distance[1] + 1000)
        if x ~= nil then
            createTurret(x, y)
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
    for idx_, p in ipairs(playerList) do
        if p:isValid() and distance(p, field_x, field_y) > field_radius then
            game_over = true
            local text = _("msgMainscreen&Spectbanner", "Mission: SUCCESS (escaped the Directorate's jamming field)")
            victory("Human Navy")
            globalMessage(text)
            setBanner(text)
            return
        end
    end
end

-------------------------------------------------------------------------------
-- GM
-------------------------------------------------------------------------------

function gmButtons()
    clearGMFunctions()
    addGMFunction(_("buttonGM", "Deploy jammer"), function()
        math.abs(0) -- Provides global context for SeriousProton
        deployField(closestPlayer(secret_base:getPosition()))
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

    -- The mining rings and stations.
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
        {"Medium Station", "Mining Guild Depot",    "Headquarters of the asteroid miners."},
        {"Large Station",  "Reunion Hall",          "Host of the piloting school class reunion."},
        {"Medium Station", "Planetary Comms Relay", "The planetary comms hub."},
        {"Small Station",  "Academy Annex",         "An outpost of the piloting school."},
    }
    for n, info in ipairs(stations) do
        local station = SpaceStation():setTemplate(info[1]):setFaction("Human Navy"):setRotation(random(0, 360))
        station:setCallSign(info[2]):setDescription(info[3])
        setCirclePos(station, 0, 0, -90 + (n - 1) * 90, station_radius)
    end

    mining_central = SpaceStation():setTemplate("Large Station"):setFaction("Independent")
    mining_central:setCallSign("Mining Central"):setPosition(central_x, central_y)
    mining_central:setDescription("The hub of the outer mining clusters.")
    mining_central:setCanBeDestroyed(false)

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

    -- Two unstable 235 samples east of the Scriptorium.
    createSample(sx + sample_distance, sy - sample_spread / 2)
    createSample(sx + sample_distance, sy + sample_spread / 2)

    -- The player ship starts west of the Scriptorium, facing the samples.
    local player = PlayerSpaceship():setFaction("Human Navy"):setTemplate(getScenarioSetting("PlayerShip"))
    player:setCallSign("USS-SUNDAY NCC-67")
    player:setPosition(sx - player_start_distance, sy):setRotation(0)
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

    secret_base:sendCommsMessage(player, [[Two canisters of unstable 235 are floating just east of the Scriptorium.

Shoot one, and it collapses into a black hole. Keep your distance if you do.

Fly into one, and it is yours. Your hull will be twice as strong, and your reactor, maneuvering and impulse will run at full power, without overheating and without draining your energy.

Be quick. Unstable 235 is the most tightly controlled element in known space, and the Interplanetary Directorate next door does not know it exists here. The moment anyone touches it, they will.]])
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
        game_over = true
        local text = _("msgMainscreen&Spectbanner", "Mission: FAILED (the USS-SUNDAY NCC-67 was destroyed)")
        victory("Directorate")
        globalMessage(text)
        setBanner(text)
        return
    end

    updateSamples()
    updateBoosted()
    updateCaravan(delta)

    if field_deployed then
        updateTurrets(delta)
        updateGarrisons()
        speed_timer = speed_timer - delta
        if speed_timer <= 0 then
            speed_timer = 1
            updateEnemySpeed()
        end
        updateField(delta)
    else
        -- The Directorate finds out on its own if nobody touches the 235.
        start_timer = start_timer + delta
        if start_timer > deploy_delay then
            deployField(closestPlayer(secret_base:getPosition()))
        end
    end
end
