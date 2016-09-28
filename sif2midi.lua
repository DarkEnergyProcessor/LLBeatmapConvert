-- Converts SIF beatmap to MIDI

local stringstream = require("stringstream")
local JSON = require("JSON")

local function write_varint(int)
	local out = {}
	local first = true
	
	int = int % 4294967296 -- support negative values.
	
	table.insert(out, 1, string.char(int % 128))
	int = math.floor(int / 128)
	
	while int > 0 do
		table.insert(out, 1, string.char((int % 128) + 128))
		int = math.floor(int / 128)
	end
	
	return table.concat(out)
end


local function sort_queue(a, b)
	return a.loc < b.loc
end

-- Returns string
function sif_to_midi(sif_json, tempo)
	local ss = stringstream.create()
	local bm = type(sif_json) ~= "table" and JSON:decode(sif_json) or sif_json
	
	tempo = tempo or 120	-- BPM
	ss:write("MThd\0\0\0\6\0\0\0\1\0\96MTrk")
	
	local len_pos = ss:seek()
	
	ss:write("\0\255\81")
	
	-- Encode tempo info
	do
		local tempo_micro = math.floor(60000000 / tempo + 0.5)
		local byte_len = math.ceil(#string.format("%x", tempo_micro) / 2)
		
		ss:write(string.char(byte_len))
		
		local out = {}
		
		while tempo_micro > 0 do
			table.insert(out, 1, string.char(tempo_micro % 256))
			tempo_micro = math.floor(tempo_micro / 256)
		end
		
		ss:write(table.concat(out))
	end
	
	local note_queue = {}
	local note_def_len = 24 * 60000 / 96 / tempo
	
	for _, note in ipairs(bm) do
		local note_pos = note.position + 55	-- Pos 5 = C5
		local note_len = note_def_len
		local note_start = note.timing_sec * 1000
		local eff = note.effect - 1
		
		if note.effect == 3 then
			note_len = math.floor(note.effect_value * 1000)
			
			-- Attribute 0
			-- Note On
			table.insert(note_queue, {
				on = true,
				loc = math.floor(math.floor(note_start + note_len) / 60000 * 96 * tempo + 0.5),
				pos = note_pos,
				effect = eff,
				attr = 0
			})
			-- Note Off
			table.insert(note_queue, {
				on = false,
				loc = math.floor(math.floor(note_start + note_len + note_def_len) / 60000 * 96 * tempo + 0.5),
				pos = note_pos,
				effect = eff,
				attr = 0
			})
		end
		
		-- Note On
		table.insert(note_queue, {
			on = true,
			loc = math.floor(math.floor(note_start) / 60000 * 96 * tempo + 0.5),
			pos = note_pos,
			effect = eff,
			attr = note.notes_attribute
		})
		-- Note Off
		table.insert(note_queue, {
			on = false,
			loc = math.floor(math.floor(note_start + note_len) / 60000 * 96 * tempo + 0.5),
			pos = note_pos,
			effect = eff,
			attr = note.notes_attribute
		})
	end
	
	table.sort(note_queue, sort_queue)
	
	local last_tick = 0
	
	-- Now write to MIDI
	for _, note in ipairs(note_queue) do
		ss:write(write_varint(note.loc - last_tick), string.char(
			(note.on and 144 or 128) +	-- Note on/Note off
			note.attr * 4 +				-- MIDI ID: SIF Note attribute
			note.effect - 1				-- MIDI ID: Note effect
		), string.char(note.pos), "d")
		
		last_tick = note.loc
	end
	
	-- Write end
	ss:write("\255\47\0")
	
	local mtrk_len = ss:seek() - len_pos
	
	ss:seek("set", len_pos)
	ss:write(
		string.char(math.floor(mtrk_len / 16777216)),
		string.char(math.floor(mtrk_len / 65536) % 256),
		string.char(math.floor(mtrk_len / 256) % 256),
		string.char(mtrk_len % 256)
	)
	
	return ss:string()
end

do
	local arg = {...}
	if #arg >= 2 then
		local a = assert(io.open(arg[1], "rb"))
		local b = assert(io.open(arg[2], "wb"))
		
		b:write(sif_to_midi(a:read("*a"), tonumber(arg[3] or 120) or 120))
		b:close()
		a:close()
	end
end
