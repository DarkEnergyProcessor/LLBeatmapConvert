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
	local tick_before_tempo = 0	-- Tick before FF 51 event comes
	local sec_before_tempo = 0	-- Seconds before FF 51 event comes
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
					pos = note
				})
			elseif event_type == 9 then
				note = ss:read(1):byte()
				ss:seek("cur", 1)
				
				insert_event(timing_total, {
					note = false,	-- false = off, true = on.
					pos = note
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
			})
		end
	end
	
	-- Sort by tick, then by order. All are ascending
	table.sort(event_list, function(a, b)
		return a.tick < b.tick or (a.tick == b.tick and a.order < b.order)
	end)
	
	local left_index, right_index
	
	-- Analyze start and end position. 
	for n, v in pairs(event_list) do
	end
end