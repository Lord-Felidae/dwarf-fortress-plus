-- Enables event that tracks consumption of food and drink
-- Currently only available to use as a module
--@ module = true
-- Release Version 1

-- If you only want to check if a creature eats a particular material, it may just be easier to give that material an ingestion syndrome and check for that instead
---------------------------------------------------------------------
registered = registered or {}
tracked_units = {}
rate = rate or 10

special_item_types = special_item_types or require("utils").invert({df.item_type.REMAINS, df.item_type.FISH, df.item_type.FISH_RAW, df.item_type.VERMIN, df.item_type.PET, df.item_type.EGG}) -- Lookup for the special-case item types. Used by is_special_item_type

loop_timer = loop_timer or nil
---------------------------------------------------------------------
--[[
Arguments from the event (in order)
> unit - The unit involved
> type (either "food" or "drink") - Whether the consumed object was eaten or drank
> item_type - The numerical item type of the item
> item_subtype - The numerical item subtype of the item (for items without a subtype, this value is -1)
> mat_type - The mat_type of the material consumed
> mat_index - The mat_index of the material consumed
> year - The year that the item was consumed
> year_time - The year tick that the item was consumed (in fort mode scale)

NOTE: When the item involved is REMAINS, FISH, FISH_RAW, VERMIN, PET, or EGG then:
> mat_index is the creature's race id
> mat_type is the caste's index
]]

-- Registering a function or setting rates will cause monitoring to begin if possible. Otherwise, start_monitoring can be called to start it.

-- Use to register a listener. The provided function will be run whenever new food / drink changes are detected.
-- Functions should be registered on world load, as they are automatically unregistered 
function register(key, func)
	registered[key] = func
	
	start_monitoring()
end

-- Works similar to eventful's enableEvent. Sets the rate at which checks should be made
-- The lowest rate is the one that's used
function set_rate(new_rate)
	if new_rate < rate then
		rate = new_rate
	end
	
	start_monitoring()
end

-- Start the script actually monitoring for newly consumed food + drink
function start_monitoring()
	if loop_timer == nil and dfhack.isWorldLoaded() == true then
		food_check_loop()
	end
end

-- Returns true if the given item type is one of the special-case items that stores creature race id and caste id in mat_type and mat_index respectively, instead of material data
function is_special_item_type(item_type)
	return (special_item_types[item_type] ~= nil)
end

---------------------------------------------------------------------
-- Remove all registered functions
function clear_registered()
	registered = {}
end

-- Wipe the data on all currently tracked units
function clear_tracking()
	tracked_units = {}
end
---------------------------------------------------------------------

-- Takes a given number of years and year ticks (the fortmode-scale ones)
-- Returns the full number of ticks
local function get_full_ticks(years, year_ticks)
	return (1200*28*3*4*years) + year_ticks
end

-- triggers an event for all registered listeners
local function raise_event(unit, type, item_type, item_subtype, mat_type, mat_index, year, year_time)
	for _, func in pairs(registered) do
		func(unit, type, item_type, item_subtype, mat_type, mat_index, year, year_time)
	end
end


-- Perform checks for any newly consumed items by the given unit, and raise an event for any of them
function check_unit(unit)
	-- If the unit doesn't have any previous tracking information, make a tracked_units entry for them
	-- As they're newly added, we don't want to start triggering off of what's in their eat history currently, just record it
	if tracked_units[unit.id] == nil then
		tracked_units[unit.id] = {
			last_check = get_full_ticks(df.global.cur_year, df.global.cur_year_tick)
		}
		
		-- If they have some information in their eat history, record it
		if unit.status.eat_history ~= nil then
			tracked_units[unit.id].last_food_length = #unit.status.eat_history.food.item_type
			tracked_units[unit.id].last_drink_length = #unit.status.eat_history.drink.item_type
		else
			tracked_units[unit.id].last_food_length = 0
			tracked_units[unit.id].last_drink_length = 0
		end
		
		-- Exit out now instead of going on to check if we should trigger events
		return
	end
	
	-- If the unit has no eat history, record that and abort
	if unit.status.eat_history == nil then
		tracked_units[unit.id].last_food_length = 0
		tracked_units[unit.id].last_drink_length = 0
		
		tracked_units[unit.id].last_check = get_full_ticks(df.global.cur_year, df.global.cur_year_tick)
		return
	end
	
	-- Check the unit's eat history for new entries

	-- This is all done in a function because food and drink can be handled basically exactly the same way
	local function do_checks(food_or_drink)
		local last_check = tracked_units[unit.id].last_check
	
		-- Set things up based on if we're currently doing food or drink
		local history
		local last_length
	
		if food_or_drink == "food" then
			history = unit.status.eat_history.food
			last_length = tracked_units[unit.id].last_food_length
		else --assume drink
			history = unit.status.eat_history.drink
			last_length = tracked_units[unit.id].last_drink_length
		end

		-- Attempt to identify the last position that was checked (assuming that the eat history hasn't reset in the meantime)
		-- This is so we can catch some meals that occurred on the same world tick as the last check, but after it was made (which is possible to happen in adventure mode)
		local last_index
		if last_length < #history.item_type then -- The number of entries is more, so assume we are continuing, rather than having reset
			last_index = last_length - 1 -- Because tables are 0 indexed
		end
		
		-- Work backwards through the list of entries, checking for any new entries that have happened since our last check
		-- We'll go until we've gone past the time we last checked (or if last_index isn't nil, until we reach that point)
		
		-- For now we just record them, so that later we can trigger them all in chronological order
		-- (ensuring order adds more overhead. If it proves too much this can just be dropped, at the cost of newly detected foodstuff events triggering in no particular order)
		local new_entries = {}
		
		for index = #history.item_type - 1, 0, -1 do
			local entry_tick = get_full_ticks(history.year[index], history.year_time[index])
			
			-- If we've reached (or gone futher than) the last index, and the entry occurred during or earlier than the last check, stop checking any further!
			if last_index ~= nil and entry_tick <= last_check and index <= last_index then
				break
			elseif entry_tick >= last_check then -- Add anything that's happened since the last check (or during it) TODO: IS THIS RIGHT? Or should be checking only for greater than?
				table.insert(new_entries, index) -- Store the index that the entry appears in the history at
			end
		end
		
		-- Now go through that list of entries in reverse order (making it chronological), and raise events for each
		for index = #new_entries, 1, -1 do
			local entry_index = new_entries[index]
			raise_event(unit, food_or_drink, history.item_type[entry_index], history.item_subtype[entry_index], history.material.mat_type[entry_index], history.material.mat_index[entry_index], history.year[entry_index], history.year_time[entry_index])
		end
	end
	
	-- Trigger checks and raising events for food, followed by drinks
	do_checks("food")
	do_checks("drink")
	
	-- Update records for each
	tracked_units[unit.id].last_food_length = #unit.status.eat_history.food.item_type
	tracked_units[unit.id].last_drink_length = #unit.status.eat_history.drink.item_type
	
	tracked_units[unit.id].last_check = get_full_ticks(df.global.cur_year, df.global.cur_year_tick)
end

-- Run through all current units and check them for any newly consumed items
function update()
	for _, unit in pairs(df.global.world.units.active) do
		check_unit(unit)
	end
end

function start_loop()
	loop_timer = dfhack.timeout(rate, "ticks", food_check_loop)
end

-- Runs every time the timer runs out
function food_check_loop()
	update()
	
	-- Restart the loop
	start_loop()
end

dfhack.onStateChange["food_trigger"] = function(event)
	if event == SC_WORLD_UNLOADED then
		-- Wipe all currently registered functions
		clear_registered()
		-- Cleanup
		rate = 10
		loop_timer = nil
	elseif event == SC_MAP_LOADED then
		-- Immediately trigger an update (if there's any registered listeners)
		if next(registered) ~= nil then
			update()
		end
	end
end