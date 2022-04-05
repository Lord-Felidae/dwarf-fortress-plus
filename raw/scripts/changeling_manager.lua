-- Manager for the changeling's scripted features
--@ module = true
-- Release Version 1

local help = [====[

changeling_manager
====================
Manager for the changeling's scripted features.

Notes:
- To ensure this script is always running, include ``changeling_manager -load`` within an ``onLoad*`` init file.
- Because interaction trigger is currently broken, transformation is currently performed by running ``changeling_manager -transform``. Make a keybind for it for ease of use.
- This feature isn't hardcoded to only work on changelings. By giving other creatures access to the right interactions, any other creature can use these features.

Arguments::

-cheat <true/false>
	If true, every creature will be available to transform into, even if you haven't learned the form.
	This option is saved on a per-world basis.
	Defaults to false.
-load
	Used to load the script so its features start running.
-transform
	Either opens the transformation menu, or transforms your current character back into their normal form, based on your current transformation state.
	
]====]

-- TODO: REMOVE ABILITY GRANTING SYNDROMES WHEN APPROPRIATE
---------------------------------------------------------------------
local eventful = require("plugins.eventful")
local syndromeUtil = require("syndrome-util")
local utils = require("utils")

local gui = require "gui"
local widgets = require 'gui.widgets'

local validArgs = utils.invert({
	"help",
	"cheat",
	"load",
	"transform",
})

---------------------------------------------------------------------
script_data = script_data or nil
script_syndromes = script_syndromes or {} -- Stores the IDs of each of the syndromes used by this script, so we don't have to look them up every time we need them
---------------------------------------------------------------------
-- Returns the currently active adventurer
function get_adventurer_unit()
	local nemesis = df.nemesis_record.find(df.global.ui_advmode.player_id)
	local unit = df.unit.find(nemesis.unit_id)
	
	return unit
end

function first_time_setup()
	script_data.unit_info = {}
	script_data.allow_all = false -- Option that allows all creatures (that have bodies) to be selected, even if you haven't learned the forms
end

function create_unit_entry(unit)
	local entry = {
		learned_forms = {}, -- Indexed table of tables containing information on known forms. keys are race and caste, with values being the numerical IDs for each.
		original_race = unit.race, -- Stores numerical ID for the creature's original race
		original_caste = unit.caste, -- Stores numerical ID for the creature's original caste
	}
	
	script_data.unit_info[tostring(unit.id)] = entry
	
	return entry
end

function get_unit_script_info(unit_id)
	return script_data.unit_info[tostring(unit_id)] or nil
end

-- Returns an indexed table containing all of a unit's learned forms (even if that table is empty)
-- Returns nil if the unit has no data for learned forms
function get_learned_forms(unit)
	-- Check if the unit even has any stored data / if they haven't learned any forms
	local unit_script_info = get_unit_script_info(unit.id)
	
	if unit_script_info == nil then
		return nil
	end
	
	return unit_script_info.learned_forms
end

-- Returns true if a the unit already has the learned form, or false if they don't
-- Assumes the unit has learned from data
function has_learned_form(unit, race_id, caste_id)
	local learned_forms = get_learned_forms(unit)
	
	for _, form in pairs(learned_forms) do
		if form.race == race_id and form.caste == caste_id then
			return true
		end
	end
	
	-- If we get here, they don't have it
	return false
end

-- Adds a learned form to the unit using numerical race and caste ids
function add_learned_form(unit, race_id, caste_id)
	-- Get list of learned forms (or create an entry if the unit doesn't have one)
	local learned_forms = get_learned_forms(unit)
	if learned_forms == nil then
		-- Unit doesn't have any script data, so we'll make a new entry
		create_unit_entry(unit)
		learned_forms = get_learned_forms(unit)
	end
	
	-- Make sure they don't already have the form to begin with when adding it
	local already_has = false
	for _, form in pairs(learned_forms) do
		if form.race == race_id and form.caste == caste_id then
			already_has = true
			break
		end
	end
	
	if already_has == false then
		table.insert(learned_forms, {race = race_id, caste = caste_id})
		
		-- If it's adventure mode, and the unit getting the form is the currently controlled adventurer, give them a notification
		if dfhack.world.isAdventureMode() and unit == get_adventurer_unit() then
			dfhack.gui.makeAnnouncement(df.announcement_type.POWER_LEARNED, {A_DISPLAY = true}, xyz2pos(1,2,3), "You have learned a new form.", COLOR_CYAN, true)
		end
	end
end

-- Adds a creature+caste combination to a unit based on a given token (e.g. "DWARF:FEMALE")
function add_learned_form_by_token(unit, token)
	local race_token, caste_token = string.match(token, "([^:]+):([^:]+)")
	
	local race_id
	local creature_raw
	for index, creature in pairs(df.global.world.raws.creatures.all) do
		if creature.creature_id == race_token then
			race_id = index
			creature_raw = creature
			break
		end
	end
	
	local caste_id
	for index, caste in pairs(creature_raw.caste) do
		if caste.caste_id == caste_token then
			caste_id = index
			break
		end
	end
	
	add_learned_form(unit, race_id, caste_id)
end

-- Adds all of a creature's castes as learned forms to the unit
function add_learned_form_creature(unit, race_id)
	local creature_raw = df.creature_raw.find(race_id)
	
	for caste_id, caste in pairs(creature_raw.caste) do
		add_learned_form(unit, race_id, caste_id)
	end
end

-- As above, but takes a creature token as an argument
function add_learned_form_creature_by_token(unit, token)
	-- Find the ID of the creature
	local race_id
	
	for index, creature in pairs(df.global.world.raws.creatures.all) do
		if creature.creature_id == race_token then
			race_id = index
			break
		end
	end
	
	-- Send it along
	add_learned_form_creature(unit, race_id)
end

-- Take a race id and caste id and returns 2 values: creature token followed by caste token
local function get_creature_caste_tokens(race, caste)
	local creature_raw = df.creature_raw.find(race)
	local caste_raw = creature_raw.caste[caste]
	
	return creature_raw.creature_id, caste_raw.caste_id
end

function transform_into_form(unit, race_id, caste_id)
	-- Ensure the unit has stored information (or make it if it's missing)
	-- (This is so their original race + caste get recorded so they can switch back)
	local unit_script_info = get_unit_script_info(unit.id)
	if unit_script_info == nil then
		unit_script_info = create_unit_entry(unit)
	end
	
	local race_token, caste_token = get_creature_caste_tokens(race_id, caste_id)

	dfhack.run_script("modtools/transform-unit", table.unpack({
		"-unit", unit.id,
		"-race", race_token,
		"-caste", caste_token,
		"-duration", "forever",
		"-keepInventory"
	}))

	-- Give the unit a dummy syndrome used to mark that they are transformed, as well as granting them CAN_LEARN + NO_AGING even in their changed form
	syndromeUtil.infectWithSyndrome(unit, script_syndromes["KANA_CHANGELING_IS_TRANSFORMED"], syndromeUtil.ResetPolicy.DoNothing)
	
	-- Give the unit a syndrome that gives them the interaction required to change back to their normal form
	syndromeUtil.infectWithSyndrome(unit, script_syndromes["KANA_CHANGELING_GIVE_SHED"], syndromeUtil.ResetPolicy.DoNothing)
end

-- Checks to ensure the given creature is safe to turn into
-- (as some creatures may have no materials / tissues / bodies, since they're not intended to actually exist)
function creature_safety_check(creature)
	-- We notably won't be excluding creatures with DOES_NOT_EXIST, as there can be valid creatures with that tag
	
	-- Forbid vermin
	if creature.flags.SMALL_RACE == true then
		return false
	end
	
	-- Check for tissues (material checks don't really work because it's valid for a creature to not have any self-defined materials, while all creatures should have tissues)
	if #creature.tissue == 0 then
		return false
	end
	
	-- Ensure they have any castes
	if #creature.caste == 0 then
		return false
	end
	
	-- Do a lazy check to ensure they have a body (only check the first caste to see if it's the case)
	local there_is_a_body_part = false
	for _, _ in pairs(creature.caste[0].body_info.body_parts ) do
		there_is_a_body_part = true
		break
	end
	
	if not there_is_a_body_part then
		return false
	end
	
	-- If we get here, we passed all the checks
	return true
end

-- Returns true if the unit has the given creature class
-- Optionally, creature_class can be an indexed table of creature classes to check. Returns true if any match.
local function unit_is_creature_class(unit, creature_class)
	local class_table
	
	if type(creature_class) == "table" then
		class_table = creature_class
	else
		class_table = {}
		table.insert(class_table, creature_class)
	end
	
	local caste_raw = df.creature_raw.find(unit.race).caste[unit.caste]

	for index, entry in pairs(caste_raw.creature_class) do
		for index, class in pairs(class_table) do
			if entry.value == class then
				return true
			end
		end
	end
	
	return false
end

-- Returns true if the unit has a syndrome with the given class
-- Optionally, class may be an indexed table of syndrome classes to check. Returns true if any match.
local function unit_has_syndrome_class(unit, syndrome_class)
	local classes_to_check
	
	if type(syndrome_class) == "table" then
		classes_to_check = syndrome_class
	else
		classes_to_check = {}
		table.insert(classes_to_check, syndrome_class)
	end
	
	for _, active_syndrome in pairs(unit.syndromes.active) do
		-- Get the actual syndrome info
		local syndrome = df.syndrome.find(active_syndrome.type)
		
		-- Loop through each syn_class entry for the syndrome
		for _, entry in pairs(syndrome.syn_class) do -- < Crashes before returning to this loop after going through once
			local current_class = entry.value
			
			-- Check if the current class is one of the ones we were given to look for
			for _, check_class in pairs(classes_to_check) do
				if check_class == current_class then
					return true
				end
			end
		end
	end
	
	return false
end

-- Returns true if the unit has a syndrome with the given identifier
-- Optionally, identifier may be an indexed table of syndrome identifiers to check. Returns true if any match.
function unit_has_syndrome_identifier(unit, identifier)
	local indentifier_table
	
	if type(identifier) == "table" then
		indentifier_table = identifier
	else
		indentifier_table = {}
		table.insert(indentifier_table, identifier)
	end
	
	for _, active_syndrome in pairs(unit.syndromes.active) do
		local syndrome = df.syndrome.find(active_syndrome.type)
		
		for _, identifier in pairs(indentifier_table) do
			if syndrome.syn_identifier == identifier then
				return true
			end
		end
	end
	
	return false
end

-- Use to check if a unit is capable of using the learned forms + devouring abilities
function unit_can_eat_to_learn(unit)
	-- Will count as a changeling if either:
	-- > The unit's caste has particular classes
	-- > The unit has a syndrome of a particular syndrome class

	if unit_is_creature_class(unit, "KANA_CHANGELING_CAN_LEARN_FORMS") == true then
		return true
	elseif unit_has_syndrome_class(unit, "KANA_CHANGELING_CAN_LEARN_FORMS") == true then
		return true
	end
	
	-- Also apply the class checks to the original creature (meaning that creatures which can naturally learn forms can still eat to learn while transformed)
	local unit_script_info = get_unit_script_info(unit.id)
	if unit_script_info ~= nil then
		local caste_raw = df.creature_raw.find(unit_script_info.original_race).caste[unit_script_info.original_caste]
		
		for index, entry in pairs(caste_raw.creature_class) do
			if entry.value == "KANA_CHANGELING_CAN_LEARN_FORMS" then
				return true
			end
		end
	end
	
	-- If we get here, they haven't passed any of the tests
	return false
end

-- Returns true if the given unit is currently transformed due to changeling transformation
function unit_is_changeling_transformed(unit)
	return unit_has_syndrome_identifier(unit, "KANA_CHANGELING_IS_TRANSFORMED")
end
---------------------------------------------------------------------
-- GUI
local function capitalise_first(text)
	return text:gsub("^%l", string.upper)
end

-- Swiped from gui/create-item :p
function getGenderString(gender)
  local sym = df.pronoun_type.attrs[gender].symbol
  if not sym then
    return ""
  end
  return "("..sym..")"
end

-- Returns the display string for the creature form, displayed as [Creature name] - [Caste name] ([gender symbol])
function get_form_string(form)
	local creature = df.creature_raw.find(form.race)
	local caste = creature.caste[form.caste]
	
	local creature_name = creature.name[0]
	local caste_name = creature.caste[form.caste].caste_name[0]
	local gender_string = getGenderString(caste.sex)
	
	local text = capitalise_first(creature_name) .. " - " .. capitalise_first(caste_name) .. " " .. gender_string
	
	return text
end

------
FormList = defclass(FormList, gui.FramedScreen)
FormList.ATTRS = {
	frame_style = gui.GREY_LINE_FRAME,
	frame_title = "Form Selector",
	frame_width = 40,
	frame_height = 25,
	frame_inset = 1,
	unit = DEFAULT_NIL,
}

function FormList:update_choices()
	local choices = {}
	local learned_forms = get_learned_forms(self.unit)
	
	if script_data.allow_all == false then
		for _, form in pairs(learned_forms) do
			local addition = {}
			addition.race = form.race
			addition.caste = form.caste
			addition.text = get_form_string(form)
			
			table.insert(choices, addition)
		end
	elseif script_data.allow_all == true then
		-- All the forms are available, regardless on whether or not they're known forms 
		for race_id, creature in pairs(df.global.world.raws.creatures.all) do
			
			-- Ensure we only add options for creatures that are actually valid and won't crash the game
			if creature_safety_check(creature) == true then
				for caste_id, caste_raw in pairs(creature.caste) do
					local addition = {}
					addition.race = race_id
					addition.caste = caste_id
					addition.text = get_form_string(addition)
					
					table.insert(choices, addition)
				end
			end
		end
	end
	
	-- Sort into alphabetical order
	table.sort(choices, function(a, b) return (a.text < b.text) end)

	self.subviews.form_list:setChoices(choices)
end

function FormList:init(info)
	self:addviews{
		widgets.Label{
			frame = { l = 0, r = 0, t = 0},
			text = {
				{text = "Select a form to change into."}
			},
		},
		widgets.FilteredList{
			view_id = "form_list",
			with_filter = true,
			frame = { l = 0, r = 0, t = 1, b = 1 },
			on_submit = function(index, choice)
				if self.subviews.form_list:canSubmit() then
					transform_into_form(self.unit, choice.race, choice.caste)
					self:dismiss()
				end
			end,
		},
		widgets.Label{
			frame = { b = 0 },
			text = {
				{text = ": Select form", key = "SELECT"} -- Note: list already handles the stuff, so no need for an on_activate callback here
			},
		}
	}
	
	self:update_choices()
end

function FormList:onInput(keys)
	if keys.LEAVESCREEN then
		self:dismiss()
	else
		self:inputToSubviews(keys)
	end
end

function showFormSelector(unit)
	FormList{
		unit = unit
	}:show()
end

---------------------------------------------------------------------
-- EVENT

function on_unit_want_to_shed(unit, give_fatigue)
	-- Get + Ensure the unit has stored information
	local unit_script_info = get_unit_script_info(unit.id)
	
	if unit_script_info == nil then
		-- There's no stored information on this creature, so we don't know their normal form!
		return false
	end
	
	-- Revert the creature to their previous form
	-- (Note that a lot of transform-unit's features are unusable for us, because transform unit doesn't save any data between loads, so we have to do things ourselves)
	
	local race_token, caste_token = get_creature_caste_tokens(unit_script_info.original_race, unit_script_info.original_caste)

	dfhack.run_script("modtools/transform-unit", table.unpack({
		"-unit", unit.id,
		"-race", race_token,
		"-caste", caste_token,
		"-duration", "forever",
		"-keepInventory"
	}))
	
	syndromeUtil.eraseSyndromes(unit, script_syndromes["KANA_CHANGELING_GIVE_SHED"].id)
	syndromeUtil.eraseSyndromes(unit, script_syndromes["KANA_CHANGELING_IS_TRANSFORMED"].id)

	-- The KANA_CHANGELING_SHED_FORM interaction now inflicts the transformation fatigue syndrome instead of giving it via code. This makes it so it can use the concentration added mechanics, at the cost of making the fatigue gaining non-optional.
	-- ^ KEYBIND HACK: That doesn't really happen at the moment because we're not using the interactions for transformation, so we'll add it here:
	if ( give_fatigue ) then
		syndromeUtil.infectWithSyndrome(unit, script_syndromes["KANA_CHANGELING_PLAYER_RECOVERY"], syndromeUtil.ResetPolicy.AddDuration) -- Not sure if syndromeUtil will actually make the concentration stronger as intended...
	end
	
	return true
end

function on_unit_want_to_select(unit)
	-- Abort if the unit isn't the currently selected adventurer!
	-- (Not that this should happen outside of syndrome detection delay)
	-- TODO: Could make it so creatures not under player control pick a random learned form
	
	if unit.id ~= get_adventurer_unit().id then
		return
	end
	
	syndromeUtil.eraseSyndromes(unit, script_syndromes["KANA_CHANGELING_WANT_TO_SELECT"].id)
	
	-- Get the script-related data for this unit (or make it if it's missing)
	local unit_script_info = get_unit_script_info(unit.id)
	if unit_script_info == nil then
		unit_script_info = create_unit_entry(unit)
	end
	
	local learned_forms = get_learned_forms(unit)
	
	-- Give an error message if the player can't turn into anything
	if (learned_forms == nil or next(learned_forms) == nil) and script_data.allow_all == false then
		dfhack.gui.makeAnnouncement(df.announcement_type.NOTHING_TO_INTERACT, {A_DISPLAY = true}, xyz2pos(1,2,3), "You don't know any forms to shift into.", COLOR_RED, true)
		return
	end
	
	showFormSelector(unit)
end

-- KEYBIND HACK: Player has selected
function on_request_transform(unit)
	-- Since the respective functions already do sanity checking, we don't have to do any here
	if ( unit_is_changeling_transformed(unit) ) then -- We can assume the creature is currently transformed
		on_unit_want_to_shed(unit, true)
	else -- Not transformed, and wants to
		on_unit_want_to_select(unit)
	end
end

-- Returns the race ID of the given creature
local function find_creature_id(creature)
	for index, current_creature in pairs(df.global.world.raws.creatures.all) do
		if creature.creature_id == current_creature.creature_id then
			return index
		end
	end
end

function on_eat(unit, type, item_type, item_subtype, mat_type, mat_index, year, year_time)
	-- Only continue if the unit has the ability to learn changeling forms via eating
	if unit_can_eat_to_learn(unit) == false then
		return
	end
	
	-- Want to restrict to only counting certain item types (so it's more interesting to go out, hunt, and eat the creatures)
	-- Notably not counting blood as a valid thing - you've got to hunt and fully kill a creature if you want its form!
	local valid_item_types = {df.item_type.MEAT, df.item_type.REMAINS, df.item_type.FISH, df.item_type.FISH_RAW, df.item_type.VERMIN, df.item_type.PET}
	-- Possible TODO: Add in meals as an option, with some special logic for checking each of the ingredients
	
	local is_valid_item_type = false
	
	for _, valid_type in pairs(valid_item_types) do
		if item_type == valid_type then
			is_valid_item_type = true
			break
		end
	end
	
	if is_valid_item_type == false then
		return
	end
	
	-- Figure out if it is part of a creature, and if so which
	local creature
	
	-- Some item types handle their recorded material in a special way
	-- Check from the item types that are allowed if the eaten item is one of these
	local special_valid_types = {df.item_type.REMAINS, df.item_type.FISH, df.item_type.FISH_RAW, df.item_type.VERMIN, df.item_type.PET}
	local is_special = false
	
	for _, special_type in pairs(special_valid_types) do
		if item_type == special_type then
			is_special = true
			break
		end
	end
	
	if is_special == true then
		-- mat_index is actually the creature's race id instead of material data!
		creature = df.creature_raw.find(mat_index)
	else
		local mat_info = dfhack.matinfo.decode(mat_type, mat_index)
		-- If this isn't a creature material, abort
		if mat_info.mode ~= "creature" then
			return
		end
		
		creature = mat_info.creature
	end
	
	-- Add the creature and all of its castes as learned forms for the unit
	add_learned_form_creature(unit, find_creature_id(creature))
end


-- SYNDROME HACK: REMOVED
--[[
eventful.onSyndrome.changeling_manager = function(unitId, syndromeIndex)
	-- (A decent portion of this is copied from modtools/syndrome-trigger
	local unit = df.unit.find(unitId)
	local unit_syndrome = unit.syndromes.active[syndromeIndex]
	local syn_id = unit_syndrome['type']

	local syndrome = df.syndrome.find(syn_id)
	-- syndrome.syn_identifier
	-- syndrome.syn_name
	
	if syndrome.syn_identifier == "KANA_CHANGELING_WANT_TO_SHED" then
		-- Remove the dummy syndrome
		syndromeUtil.eraseSyndromes(unit, syn_id)

		-- If the shedding was successful, remove the syndrome that grants the interaction
		-- (Not that there should be a situation where they can try and shed without everything already being set up)
		local success = on_unit_want_to_shed(unit)
		if success == true then
			syndromeUtil.eraseSyndromes(unit, script_syndromes["KANA_CHANGELING_GIVE_SHED"].id)
			syndromeUtil.eraseSyndromes(unit, script_syndromes["KANA_CHANGELING_IS_TRANSFORMED"].id)
		end
		
	elseif syndrome.syn_identifier == "KANA_CHANGELING_WANT_TO_SELECT" then
		-- Remove the dummy syndrome
		syndromeUtil.eraseSyndromes(unit, syn_id)

		on_unit_want_to_select(unit)
	end
end
]]

-- Cut reaction trying to make corpses edible
-- Cannibalism checks prevent dead_dwarf items from showing up as options in the reaction menu, so there's no way to use a reaction to change them.
--[[
eventful.onReactionCompleting.changeling_manager = function(reaction,reaction_product,unit,input_items,input_reagents,output_items,call_native)
	if reaction.code == "KANA_CHANGELING_CORPSE_PREP" then
		input_items[0].flags.dead_dwarf = false
		call_native = false
	end
end
]]

-- Enables players to use the "make all held sapient bodies/parts usable/edible" reaction to make all items they're holding in their hands usable in reactions/edible by removing the dead_dwarf flag from them.
eventful.onReactionCompleting.changeling_manager = function(reaction,reaction_product,unit,input_items,input_reagents,output_items,call_native)
	if reaction.code == "KANA_CHANGELING_CORPSE_PREP" then
		call_native.value = false -- Don't think this is actually working, but the reaction shouldn't produce its product anyway because of its 0% chance.
		
		-- Loop through all the items the unit is currently holding, removing the dead_dwarf tag from any items
		for _, inventory_entry in pairs(unit.inventory) do
			if inventory_entry.mode == df.unit_inventory_item.T_mode.Weapon then
				inventory_entry.item.flags.dead_dwarf = false
			end
		end
	end
end


-- Performs necessary setup for when a world is loaded
local function initialize()
	local loader = require("script-data")
	
	script_data = loader.load_world("kana_changeling", true)
	
	-- If this is the first time launching this script in this world, run first time setup
	if script_data.unit_info == nil then
		first_time_setup()
	end
	
	-- SYNDROME HACK REMOVED
	--eventful.enableEvent(eventful.eventType.SYNDROME, 5)
	
	local desired_syndromes = utils.invert({"KANA_CHANGELING_GIVE_SHED", "KANA_CHANGELING_WANT_TO_SELECT", "KANA_CHANGELING_WANT_TO_SHED", "KANA_CHANGELING_IS_TRANSFORMED","KANA_CHANGELING_PLAYER_RECOVERY"})
	-- Store the IDs of each syndrome associated with the script
	for _, syndrome in pairs(df.global.world.raws.syndromes.all) do
		if desired_syndromes[syndrome.syn_identifier] ~= nil then
			script_syndromes[syndrome.syn_identifier] = syndrome
		end
	end
	
	-- Check that all the syndromes are present
	local missing = false
	for identifier, _ in pairs(desired_syndromes) do
		if script_syndromes[identifier] == nil then
			missing = true
			break
		end
	end
	
	if missing == true then
		qerror("Syndromes required by this script are missing!")
	end
	
	-- Register listener for food + drink consumption
	local food_trigger = dfhack.reqscript("modtools/food_trigger")
	food_trigger.set_rate(10)
	food_trigger.register("changeling_manager", on_eat)
end

dfhack.onStateChange["changeling_manager"] = function(event)
	if event == SC_WORLD_LOADED then
		--
		initialize()

	elseif event == SC_WORLD_UNLOADED then
		-- Cleanup
		script_syndromes = {}
		script_data = nil
	end
end

function main(...)
	-- Ensure world is actually loaded
	if not dfhack.isWorldLoaded() then
		qerror("The world needs to be loaded to use this")
	end
	
	-- Ensure setup has been done
	-- (technically the -load command does nothing because we always do this :p)
	if script_data == nil then
		initialize()
	end
	
	local args = utils.processArgs({...}, validArgs)
	
	if args.cheat ~= nil then
		if args.cheat == "true" then
			script_data.allow_all = true
		else
			script_data.allow_all = false
		end
	end
	
	-- KEYBIND HACK
	if args.transform ~= nil then
		local adventurer = get_adventurer_unit()
		if ( not adventurer ) then
			qerror("Transformation requires an active adventurer")
			return false
		end
		
		on_request_transform(adventurer)
	end
end

if not dfhack_flags.module then
    main(...)
end