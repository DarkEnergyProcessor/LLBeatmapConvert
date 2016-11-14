-- Midi to SIF convert

local stringstream = require("stringstream")
local JSON = require("JSON")

local function str2dword_be(str)
	return str:sub(1,1):byte() * 16777216 + str:sub(2,2):byte() * 65536 + str:sub(3,3):byte() * 256 + str:sub(4,4):byte()
end

local function read_varint(fs)
	local last_bit_set = false
	local out = 0
	
	repeat
		local b = fs:read(1):byte()
		
		last_bit_set = b / 128 >= 1
		out = out * 128 + (b % 128)
	until last_bit_set == false
	
	return out
end

-- returns table, not JSON-encoded file.
function midi_to_sif(stream)
	if stream:read(4) ~= "MThd" then
		error("Not MIDI")
	end
	
	if str2dword_be(stream:read(4)) ~= 6 then
		error("Header size not 6")
	end
	
	stream:read(2)
	
	local mtrk_count = str2dword_be("\0\0"..stream:read(2))
	local ppqn = str2dword_be("\0\0"..stream:read(2))
	
	local tempo = 120			-- Default tempo, 120 BPM
	local event_list = {}		-- Will be analyzed later. For now, just collect all of it
	
	if ppqn > 32768 then
		error("PPQN is negative")
	end
	
	local function insert_event(tick, data)
		if event_list[tick] then
			table.insert(event_list[tick], data)
		else
			event_list[tick] = {data}
		end
	end
	
	for i = 1, mtrk_count do
		if stream:read(4) ~= "MTrk" then
			error("Not MIDI Track")
		end
		
		local mtrk_len = str2dword_be(stream:read(4))
		local ss = stringstream.create(stream:read(mtrk_len))
		local timing_total = 0
		
		if ss:seek("end") ~= mtrk_len then
			error("Unexpected EOF")
		end
		ss:seek("set")
		
		while ss:seek() < mtrk_len do
			local timing = read_varint(ss)
			local event_byte = ss:read(1):byte()
			local event_type = math.floor(event_byte / 16)
			local note
			
			timing_total = timing_total + timing
			
			if event_type == 8 then
				note = ss:read(1):byte()
				ss:seek("cur", 1)
				
				insert_event(timing_total, {
					note = false,	-- false = off, true = on.
					pos = note,
					channel = event_byte % 16
				})
			elseif event_type == 9 then
				note = ss:read(1):byte()
				ss:seek("cur", 1)
				
				insert_event(timing_total, {
					note = true,	-- false = off, true = on.
					pos = note,
					channel = event_byte % 16
				})
			elseif event_byte == 255 then
				-- meta
				
				insert_event(timing_total, {
					meta = ss:read(1):byte(),
					data = ss:read(read_varint(ss))
				})
			elseif event_byte == 240 or event_byte == 247 then
				-- sysex event
				while ss:read(1):byte() ~= 247 do end
			else
				ss:seek("cur", 2)
			end
		end
	end
	
	-- Now, create new event_list table
	local temp_event_list = event_list
	event_list = {}
	
	for n, v in pairs(temp_event_list) do
		for a, b in pairs(v) do
			table.insert(event_list, {
				tick = n,
				order = a,
				meta = b.meta,
				data = b.data,
				note = b.note,
				pos = b.pos,
				channel = b.channel
			})
		end
	end
	
	-- Sort by tick, then by order. All are ascending
	table.sort(event_list, function(a, b)
		return a.tick < b.tick or (a.tick == b.tick and a.order < b.order)
	end)
	
	local top_index = 0
	local bottom_index = 127
	
	-- Analyze start and end position. 
	for n, v in pairs(event_list) do
		if type(v.note) == "boolean" then
			-- Note
			top_index = math.max(top_index, v.pos)
			bottom_index = math.min(bottom_index, v.pos)
		end
	end
	
	local mid_idx = top_index - bottom_index  + 1
	
	if mid_idx > 9 or mid_idx % 2 == 0 then
		error("Failed to analyze note position. Make sure you only use 9 note keys or odd amount of note keys")
	end
	
	-- If it's not 9 and it's odd, automatically adjust
	if mid_idx ~= 9 and midi_idx % 2 == 1 then
		local mid_pos = (top_index + bottom_index) / 2
		
		top_index = mid_pos + 4
		bottom_index = mid_pos - 4
	end
	
	-- Now start conversion.
	local longnote_queue = {}
	local sif_beatmap = {}
	
	for n, v in pairs(event_list) do
		if v.meta == 81 then
			-- Tempo change
			local tempo_num = {string.byte(v.data, 1, 128)}
			tempo = 0
			
			for i = 1, #tempo_num do
				tempo = tempo * 256 + tempo_num[i]
			end
			
			tempo = math.floor(600000000 / tempo) / 10
		elseif type(v.note) == "boolean" then
			local position = v.pos - bottom_index + 1
			local attribute = math.floor(v.channel / 4)
			local effect = v.channel % 4 + 1
			
			if attribute > 0 then
				if v.note then
					if effect == 3 then
						-- Add to longnote queue
						assert(longnote_queue[position] == nil, "another note in pos "..position.." is in queue")
						longnote_queue[position] = {v.tick, attribute, effect, position}
					else
						sif_beatmap[#sif_beatmap + 1] = {
							timing_sec = v.tick * 60 / ppqn / tempo,
							notes_attribute = attribute,
							notes_level = 1,
							effect = effect,
							effect_value = 2,
							position = position
						}
					end
				elseif v.note == false and effect == 3 then
					-- Stop longnote queue
					local queue = assert(longnote_queue[position], "queue for pos "..position.." is empty")
					
					longnote_queue[position] = nil
					sif_beatmap[#sif_beatmap + 1] = {
						timing_sec = queue[1] * 60 / ppqn / tempo,
						notes_attribute = attribute,
						notes_level = 1,
						effect = 3,
						effect_value = (v.tick - queue[1]) * 60 / ppqn / tempo,
						position = position
					}
				end
			end
		end
	end
	
	table.sort(sif_beatmap, function(a, b) return a.timing_sec < b.timing_sec end)
	
	return sif_beatmap
end

local arg = arg or {...}

if #arg > 0 then
	local JSON = require("JSON")
	local input_file = assert(io.open(arg[1], "rb"))
	local output_file = io.open(arg[2] or "", "wb") or io.stdout
	
	local x = midi_to_sif(input_file)
	input_file:close()
	output_file:write(JSON:encode(x))
	
	if output_file ~= io.stdout then
		output_file:close()
	end
elseif arg[-1] then
	print("Usage: lua midi2sif.lua <input> <output=stdout>")
end

