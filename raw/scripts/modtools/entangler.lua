-- Utility for creating items that entangle
--@ module = true
-- Release Version: 1

local help = [====[

modtools/entangler
==================
A utility for creating items that entangle.

Required:
One of the following is required

:-item <Item token>:
	The item that will be able to entangle.
:-creature <Creature and Caste token>:
	The creature + caste whose attacks should entangle.
	Because creature attacks are inherently melee, there's no need to specify a -strike trigger or any strike-specific arguments (-strikeChance and -strikePower will be ignored in favor of the standard versions).

Trigger options:
:-throw <true / false>:
	The item will entangle units in the space it lands after being thrown.
:-shoot <true / false>:
	The item will entangle units in the space it lands after being shot from a weapon.
:-strike <true / false>:
	The item will entangle a units on a successful melee strike.

Effect options:
:-chance <0-100>:
	Percentage chance that a unit will be entangled. For thrown/shot items, this check is rolled individually for all units in the space.
	Default: 100
:-power <value>:
:-power <[ min max ]>:
	Strength of webbing applied on a successful entangle. The higher the number, the longer it takes for a unit to escape.
	Can either be represented as a set value, or a range that a value will randomly be chosen from.
	It takes 1 step to recover from 2 power of entanglement.
	
Misc options:
:-bypassImmune <true / false>:
	Whether web-immune creatures will still get entangled from the item's effect.
	Default: false
:-preserveThrown <true / false>:
	Whether a thrown version of this item will be preserved upon landing.
	Default: true
:-preserveShot <true / false>:
	Whether a shot version of this item will be preserved upon landing.
	Default: false
:-verb <2nd person verb string>:
:-verb <[ multiple ]>:
	When strike is enabled, only attacks with the given verb will entangle.
	Can either be a single verb, or a table containing multiple ones
	If this is omitted, then all attack verbs will trigger entangles.

Because melee attacks happen more often and reliably, there are a couple of additional options you can use.
If omitted, it'll use the regular versions.
:-strikeChance <0-100>:
	Percent chance that a successful melee strike will entangle.
:-strikePower <value>:
:-strikePower <[ min max ]>:
	Strength of webbing applied to a successful attack from a strike. Works the same as the regular -power argument.

You can optionally run this with a unit target and a -power to immediately entangle the given unit.
Useful if you want to test out certain durations.
:-unit <Unit ID>:
	Unit to entangle. If an ID is omitted or a unit with that ID can't be found, will attempt to default to the currently selected unit instead.
]====]

local utils = require "utils"
local validArgs = utils.invert({
	"help",
	"bypassImmune",
	"strike",
	"throw",
	"shoot",
	"chance",
	"power",
	"preserveThrown",
	"preserveShot",
	"unit",
	"item",
	"creature",
	"verb",
	"strikeChance",
	"strikePower",
})
---------------------------------------------------------------------
eventful = require "plugins.eventful"
rng = rng or dfhack.random.new(nil, 10)

registered_items = registered_items or {}
registered_creatures = registered_creatures or {}
---------------------------------------------------------------------
function register_item(item_token)
	registered_items[item_token] = {
		-- Record defaults here, or have the getters substitute in the defaults when nothing is given?
	}
end

function register_creature(creature_caste_token)
	registered_creatures[creature_caste_token] = {}
end

function register_entangler(token, entangler_type)
	if entangler_type == "item" then
		return register_item(token)
	elseif entangler_type == "creature" then
		return register_creature(token)
	end
end

function get_entangle_data(token, entangler_type)
	local entangler_type = entangler_type or "item"
	
	if entangler_type == "item" then
		return registered_items[token]
	elseif entangler_type == "creature" then
		return registered_creatures[token]
	end
end
---------------------------------------------------------------------
-- Getters
function get_is_strike(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	return entangler.strike or false
end

function get_is_throw(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	return entangler.throw or false
end

function get_is_shoot(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	return entangler.shoot or false
end

function is_valid_verb(token, entangler_type, verb)
	local entangler = get_entangle_data(token, entangler_type)
	
	-- Automatically allow any verb if there are no restrictions
	if ( entangler.verbs == nil or #entangler.verbs == 0 ) then
		return true
	end
	
	for _, current_verb in ipairs(entangler.verbs) do
		if ( current_verb == verb ) then
			return true
		end
	end
	
	-- If we get here, it's not valid
	return false
end

function get_chance(token, entangler_type, is_strike)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( is_strike and entangler.strike_chance ~= nil ) then
		return entangler.strike_chance
	else
		return entangler.chance or 100
	end
end


function roll_chance(token, entangler_type, is_strike)
	local entangler = get_entangle_data(token, entangler_type)
	
	local chance = get_chance(token, entangler_type, is_strike)
	
	-- Don't bother rolling if there's an absolute chance
	if ( chance >= 100 ) then
		return true
	elseif ( chance <= 0 ) then
		return false
	end

	local random_roll = rng:random(100) + 1 -- :random(100) will make a value of 0-99, so need to add 1
	
	return random_roll <= chance
end

function get_power_min(token, entangler_type, is_strike)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( is_strike and entangler.strike_power_min ~= nil ) then
		return entangler.strike_power_min
	else
		if ( entangler.power_min ~= nil ) then
			return entangler.power_min
		else
			return 100 -- Default
		end
	end
end

function get_power_max(token, entangler_type, is_strike)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( is_strike and entangler.strike_power_max ~= nil ) then
		return entangler.strike_power_max
	else
		if ( entangler.power_max ~= nil ) then
			return entangler.power_max
		else
			return 100 -- Default
		end
	end
end

function get_power(token, entangler_type, is_strike)
	return get_power_min(token, entangler_type, is_strike), get_power_max(token, entangler_type, is_strike)
end

-- Returns a random power value from within its power range.
function roll_power(token, entangler_type, is_strike)
	local entangler = get_entangle_data(token, entangler_type)
	
	local min_power, max_power = get_power(token, entangler_type, is_strike)
	-- If min and max are the same, don't even bother randomising
	if ( min_power == max_power ) then
		return min_power
	end
	
	-- Pick a random value between the two values (including both values)
	local difference = math.abs(max_power - min_power)
	local random_roll = rng:random(difference + 1)

	return min_power + random_roll
end

function get_preserve_thrown(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( entangler.preserve_thrown ~= nil ) then
		return entangler.preserve_thrown
	else
		return true -- Default
	end
end

function get_preserve_shot(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( entangler.preserve_shot ~= nil ) then
		return entangler.preserve_shot
	else
		return false -- Default
	end
end

function get_should_bypass_immunity(token, entangler_type)
	local entangler = get_entangle_data(token, entangler_type)
	
	if ( entangler.bypass_immune ~= nil ) then
		return  entangler.bypass_immune
	else
		return false
	end
end
---------------------------------------------------------------------
-- Setters

function set_is_strike(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.strike = enabled
end

function set_is_throw(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.throw = enabled
end

function set_is_shoot(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.shoot = enabled
end

function set_preserve_thrown(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.preserve_thrown = enabled
end

function set_preserve_shot(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.preserve_shot = enabled
end

function set_bypass_immune(token, entangler_type, enabled)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.bypass_immune = enabled
end

function set_chance(token, entangler_type, chance)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.chance = tonumber(chance)
end

-- power can either be a single number, or an array with two values ([1] is min, [2] is max)
function set_power(token, entangler_type, power)
	local entangler = get_entangle_data(token, entangler_type)
	
	if tonumber(power) then -- single number
		entangler.power_min = tonumber(power)
		entangler.power_max = tonumber(power)
	else -- Array
		entangler.power_min = tonumber(power[1])
		entangler.power_max = tonumber(power[2])
	end
end

function set_strike_chance(token, entangler_type, chance)
	local entangler = get_entangle_data(token, entangler_type)
	
	entangler.strike_chance = tonumber(chance)
end

-- power can either be a single number, or an array with two values ([1] is min, [2] is max)
function set_strike_power(token, entangler_type, power)
	local entangler = get_entangle_data(token, entangler_type)
	
	if tonumber(power) then -- single number
		entangler.strike_power_min = tonumber(power)
		entangler.strike_power_max = tonumber(power)
	else -- Array
		entangler.strike_power_min = tonumber(power[1])
		entangler.strike_power_max = tonumber(power[2])
	end
end

-- Add verbs to the list
-- Verb can be a verb string, or an array of strings
function add_verb(token, entangler_type, verb)
	local entangler = get_entangle_data(token, entangler_type)
	if ( entangler.verbs == nil ) then
		entangler.verbs = {}
	end
	
	local verbs_to_add
	if ( type(verb) == "table" ) then
		verbs_to_add = verb
	else
		verbs_to_add = {}
		table.insert(verbs_to_add, verb)
	end
	
	for _, verb in ipairs(verbs_to_add) do
		local already_exists = false
		
		for _, existing_verb in ipairs(entangler) do
			if ( existing_verb == verb ) then
				already_exists = true
				break
			end
		end
		
		if ( not already_exsits ) then
			table.insert(entangler.verbs, verb)
		end
	end
end

-- Replace existing verbs with new ones
function set_verbs(token, entangler_type, verbs)
	local entangler = get_entangle_data(token, entangler_type)
	entangler.verbs = {}
	add_verb(token, verbs, entangler_type)
end

---------------------------------------------------------------------
-- Other
-- Returns the raw-defined id (e.g. PUNCH) of a creature caste's attack given the attack index
function get_creature_caste_natural_attack_id(creature_index, caste_index, attack_index)
	local creature_raw = df.creature_raw.find(creature_index)
	local caste_raw = creature_raw.caste[caste_index]
	
	return caste_raw.body_info.attacks[attack_index].name
end

-- Returns the raw-defined id (e.g. PUNCH) of a unit's attack given the attack index
function get_unit_natural_attack_id(unit, attack_index)
	return get_creature_caste_natural_attack_id(unit.race, unit.caste, attack_index)
end

-- Returns the raw-defined verb (e.g. punch) of a creature caste's attack given the attack index
function get_creature_caste_natural_attack_verb(creature_index, caste_index, attack_index)
	local creature_raw = df.creature_raw.find(creature_index)
	local caste_raw = creature_raw.caste[caste_index]
	
	return caste_raw.body_info.attacks[attack_index]["verb_2nd"]
end

-- Returns the raw-defined id (e.g. punch) of a unit's attack given the attack index
function get_unit_natural_attack_verb(unit, attack_index)
	return get_creature_caste_natural_attack_verb(unit.race, unit.caste, attack_index)
end

function get_unit_creature_caste_token(unit)
	local creature = df.creature_raw.find(unit.race)
	local creature_token = creature.creature_id
	local caste_token = creature.caste[unit.caste].caste_id
	
	return creature_token .. ":" .. caste_token
end

-- Returns the 2nd person attack verb (e.g. bash) of an item's given attack index
function get_item_attack_verb(item, attack_index)
	-- Items with attack definitions will still report an attack_index of 0 when used, so we've got to filter out those items
	if ( df.is_instance(df.item_weaponst, item) or df.is_instance(df.item_toolst, item) ) then
		return item.subtype.attacks[attack_index]["verb_2nd"]
	else
		return "strike" -- Default verb used
	end
end

function creature_caste_is_web_immune(creature_index, caste_index)
	local creature_raw = df.creature_raw.find(creature_index)
	local caste_raw = creature_raw.caste[caste_index]
	
	return caste_raw.flags.WEBIMMUNE
end

function unit_is_web_immune(unit)
	return creature_caste_is_web_immune(unit.race, unit.caste)
end

-- Use to entangle a unit
-- If using this from elsewhere for an entangler source, you'll likely want to use roll_chance and/or roll_power first
function entangle_unit(unit, power, ignore_immunity)
	if ( unit_is_web_immune(unit) and not ignore_immunity ) then
		return false
	end
	
	-- Only entangle if the value is greater than the current entangle value
	-- This is for a slight attempt at balancing. This functionality could easily be changed if desired.
	if ( power > unit.counters.webbed ) then
		unit.counters.webbed = power
	end
end

-- Run this to attempt to entangle using the given entangler
-- This will include rolling for the chance and power.
-- It DOESN'T check if the trigger type is correct
function try_entangle_unit_with_entangler(token, entangler_type, target_unit, is_strike)
	local chance_roll = roll_chance(token, entangler_type, is_strike)
	
	if ( chance_roll ) then -- Roll was a success
		local power_roll = roll_power(token, entangler_type, is_strike)
		local bypass_immunity = get_should_bypass_immunity(token, entangler_type)
		return entangle_unit(target_unit, power_roll, bypass_immunity)
	end
	
	return false
end

---------------------------------------------------------------------
-- HANDLERS AND RELATED
handled_projectiles = {}

-- Returns array of all units in given tile
-- There is a proper native dfhack way to do this, but I just can't find it
function get_units_in_tile(x, y, z)
	local units_in_tile = {}
	
	for _, unit in pairs( df.global.world.units.active ) do
		if ( unit.pos.x == x and unit.pos.y == y and unit.pos.z == z ) then
			table.insert(units_in_tile, unit)
		end
	end
	
	return units_in_tile
end

function get_item_token(item)
	local subtype_token
	
	if item:getSubtype() == -1 then -- item has no subtype
		subtype_token = "NONE"
	else
		local subtype_def = dfhack.items.getSubtypeDef(item:getType() ,item:getSubtype())
		subtype_token = subtype_def.id
	end
	
	local type_token = df.item_type[item:getType()]
	
	return type_token .. ":" .. subtype_token
end

function projectile_was_shot(projectile)
	return projectile.bow_id ~= -1
end

function projectile_was_thrown(projectile)
	return not projectile_was_shot(projectile)
end

function on_unit_attack(attacker_id, defender_id, wound_id)
	attacker = df.unit.find(attacker_id)
	defender = df.unit.find(defender_id)
	
	if ( not attacker ) then return end -- Don't know how necessary this check is, but I saw it done elsewhere
	
	-- Annoyingly the event doesn't actually provide the action of the attack
	-- We have to make our best guess to work out what they're attacking with (hopefully they'll only have 1 attack action in effect at a time!)
	-- `modtools/item-trigger`'s check is less reliable, as it naively searches for the first item in the unit's inventory in Weapon mode, when in reality every held (non-hauled) item is in Weapon mode, and so can't be reliably used to get the attack's weapon.
	-- TODO: Investigate + improve filtering if possible
	for index, action in pairs( attacker.actions ) do
		if ( action.type == df.unit_action_type.Attack and action.data.attack.target_unit_id == defender_id) then
			local attack = action.data.attack
			
			if ( attack.attack_item_id > -1 ) then -- Attack was made with a weapon
				local weapon = df.item.find(attack.attack_item_id)
				local weapon_token = get_item_token(weapon)
				local entangler = get_entangle_data(weapon_token, "item")
				
				if ( entangler ~= nil ) then
					local is_strike = get_is_strike(weapon_token, "item")
					local attack_verb = get_item_attack_verb(item, attack.attack_id)
					local valid_verb = is_valid_verb(weapon_token, "item", attack_verb)
					
					if ( is_strike and valid_verb ) then
						try_entangle_unit_with_entangler(weapon_token, "item", defender, true)
					end
				end
			else -- Creature attack
				local token = get_unit_creature_caste_token(attacker)
				local entangler = get_entangle_data(token, "creature")
				
				if ( entangler ~= nil ) then
					local attack_verb = get_unit_natural_attack_verb(attacker, attack.attack_id)
					local valid_verb = is_valid_verb(token, "creature", attack_verb)
					
					if ( valid_verb ) then
						try_entangle_unit_with_entangler(token, "creature", defender, false) -- (creature attacks don't use strike triggers)
					end
				end
			end
		end
	end
end

function on_projectile_move(projectile)
	if ( handled_projectiles[projectile.id] == nil ) then -- Only bother handling projectile things once
		handled_projectiles[projectile.id] = true
		
		if ( df.is_instance(df.proj_itemst, projectile) ) then -- We only handle item projectiles at the moment. Magic could be added later. I don't think projectile units really need handling, though it would be quite funny to have sticky slimes that entangle people if they happen to be launched into somebody...
			local token = get_item_token(projectile.item)
			local entangler = get_entangle_data(token, "item")
			
			if ( entangler ~= nil ) then
				local was_shot = projectile_was_shot(projectile)
				
				if ( was_shot ) then
					projectile.flags.no_impact_destroy = get_preserve_shot(token, "item")
				else -- Thrown
					projectile.flags.no_impact_destroy = get_preserve_thrown(token, "item")
				end
			end
		end
	end
end

function on_projectile_impact(projectile)
	if ( df.is_instance(df.proj_itemst, projectile) ) then
		local token = get_item_token(projectile.item)
		local entangler = get_entangle_data(token, "item")
		
		-- Eliminate projectiles that shouldn't entangle
		if ( not entangler ) then
			return
		end
		if ( projectile_was_shot(projectile) and not get_is_shoot(token, "item") ) then
			return
		end
		if ( projectile_was_thrown(projectile) and not get_is_throw(token, "item") ) then
			return
		end
		
		local units_to_entangle = get_units_in_tile(projectile.cur_pos.x, projectile.cur_pos.y, projectile.cur_pos.z)
		for _, unit in pairs( units_to_entangle ) do
			try_entangle_unit_with_entangler(token, "item", unit, false)
		end
	end
end

---------------------------------------------------------------------
initialized = initialized or false
function init()
	registered_items = {}
	registered_creatures = {}
	handled_projectiles = {}
	
	eventful.enableEvent(eventful.eventType.UNIT_ATTACK, 1)
	eventful.onProjItemCheckMovement.entangler = on_projectile_move
	eventful.onProjItemCheckImpact.entangler = on_projectile_impact
	eventful.onUnitAttack.entangler = on_unit_attack
	
	initialized = true
end

function reset()
	registered_items = nil
	registered_creatures = nil
	handled_projectiles = nil
	
	eventful.onProjItemCheckMovement.entangler = nil
	eventful.onProjItemCheckImpact.entangler = nil
	eventful.onUnitAttack.entangler = nil
	
	initialized = false
end

dfhack.onStateChange.entangler = dfhack.onStateChange.entangler or function(code)
	-- Wipe registered items from this ended session
	if code == SC_WORLD_UNLOADED then
		reset()
	elseif code == SC_WORLD_LOADED then
		if ( not initialized ) then
			init()
		end
	end
end

function main(...)
	local args = utils.processArgs({...}, validArgs)

	if args.help then
		print(help)
		return
	end
	
	-- Optional usage that just webs a unit
	if args.unit then
		if not args.power then
			qerror("Power required to entangle given unit.")
		end
		
		if not tonumber(args.unit) then -- Attempt to grab selected unit
			unit = dfhack.gui.getSelectedUnit(true)
		else
			unit = df.unit.find(tonumber(args.unit))
		end
		
		if not unit then
			qerror("Couldn't find unit")
		end
		
		local min_power
		local max_power
		local power_rolled
		
		if ( type(args.power) == "table" ) then
			min_power = args.power[1]
			max_power = args.power[2]
		else
			min_power = tonumber(args.power)
			max_power = tonumber(args.power)
		end
		
		if ( min_power == max_power ) then
			power_rolled = min_power
		else
			local difference = math.abs(max_power - min_power)
			local random_roll = rng:random(difference + 1)
	
			power_rolled = min_power + random_roll
		end
		
		-- Since the player directly asked to do this, we'll assume they want to ignore immunity
		entangle_unit(unit, power_rolled, true)
		return true
	end
	
	if not dfhack.isWorldLoaded() then
		qerror("Script must only be run when a world is loaded.")
		return false
	end
	
	-- Initialize if not already
	if ( not initialized ) then
		init()
	end
	
	-- Time to process...
	local token
	local entangler_type

	if ( not args.item and not args.creature ) then
		qerror("Please provide a valid item or creature.")
	end
	
	if ( args.item ) then
		token = args.item
		entangler_type = "item"
	elseif ( args.creature ) then
		token = args.creature
		entangler_type = "creature"
	end
	
	-- Create the entry first
	register_entangler(token, entangler_type)
	
	-- Now define extra stuff as provided
	local function string_to_bool(s)
	 if ( s == nil or s:lower() == "false" ) then
		return false 
	 else
		return true
	 end
	end
	
	-- Triggers
	if ( args.strike ~= nil ) then set_is_strike(token, entangler_type, string_to_bool(args.strike)) end
	if ( args.throw ~= nil ) then set_is_throw(token, entangler_type, string_to_bool(args.throw)) end
	if ( args.shoot ~= nil ) then set_is_shoot(token, entangler_type, string_to_bool(args.shoot)) end
	
	-- Effect options
	if ( args.chance ~= nil ) then
		set_chance(token, entangler_type, tonumber(args.chance))
	end
	if ( args.strikeChance ~= nil ) then
		set_strike_chance(token, entangler_type, tonumber(args.strikeChance))
	end
	
	if ( args.power ~= nil ) then
	 if ( type(args.power) == "table" ) then
		args.power[1] = tonumber(args.power[1])
		args.power[2] = tonumber(args.power[2])
	 else
		args.power = tonumber(args.power)
	 end
	 
	 set_power(token, entangler_type, args.power)
	end
	
	if ( args.strikePower ~= nil ) then
	 if ( type(args.strikePower) == "table" ) then
		args.strikePower[1] = tonumber(args.strikePower[1])
		args.strikePower[2] = tonumber(args.strikePower[2])
	 else
		args.strikePower = tonumber(args.strikePower)
	 end
	 
	 set_strike_power(token, entangler_type, args.strikePower)
	end
	
	-- Misc options
	if ( args.bypassImmune ~= nil ) then set_bypass_immune(token, entangler_type, string_to_bool(args.bypassImmune)) end
	if ( args.preserveThrown ~= nil ) then set_preserve_thrown(token, entangler_type, string_to_bool(args.preserveThrown)) end
	if ( args.preserveShot ~= nil ) then set_preserve_shot(token, entangler_type, string_to_bool(args.preserveShot)) end
	if ( args.verb ) then add_verb(token, entangler_type, args.verb) end
	
	return true
end

if not dfhack_flags.module then
    main(...)
end

-- Entangler? I hardly know her!
-- ... Sorry, I had to do this somewhere