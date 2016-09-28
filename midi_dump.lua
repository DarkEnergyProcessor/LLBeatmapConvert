-- MIDI printer

local stringstream = require("stringstream")

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

local note_tables = {
	[0] = "C",
	"C#",
	"D",
	"D#",
	"E",
	"F",
	"F#",
	"G",
	"G#",
	"A",
	"A#",
	"B"
}

function print_notes(filename)
	local f = io.open(filename, "rb")
	
	if f:read(4) ~= "MThd" then
		f:close()
		print("Not MIDI")
		return
	end
	
	if str2dword_be(f:read(4)) ~= 6 then
		f:close()
		print("Header size not 6")
		return
	end
	
	f:read(2)
	
	local mtrk_count = str2dword_be("\0\0"..f:read(2))
	local ppqn = str2dword_be("\0\0"..f:read(2))
	
	if ppqn > 32768 then
		f:close()
		print("PPQN is negative", ppqn)
		return
	end
	
	print("mtrk_count", mtrk_count)
	print("ppqn", ppqn)
	
	for i = 1, mtrk_count do
		print("==== Track #"..i.." ====")
		
		if f:read(4) ~= "MTrk" then
			f:close()
			print("Not MIDI Track")
			return
		end
		
		local mtrk_len = str2dword_be(f:read(4))
		local ss = stringstream.create(f:read(mtrk_len))
		local timing_total = 0
		
		if ss:seek("end") ~= mtrk_len then
			f:close()
			print("Unexpected EOF")
			return
		end
		
		print("mtrk_len", mtrk_len)
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
				print("Note Off at "..timing_total.." tick. MIDI #"..(event_byte % 16).." Note "..note_tables[note % 12].." "..math.floor(note / 12))
			elseif event_type == 9 then
				note = ss:read(1):byte()
				ss:seek("cur", 1)
				print("Note On at "..timing_total.." tick. MIDI #"..(event_byte % 16).." Note "..note_tables[note % 12].." "..math.floor(note / 12))
			elseif event_byte == 255 then
				-- meta event
				local meta_byte = ss:read(1):byte()
				
				if meta_byte == 81 then
					-- tempo
					local tempo_data = ss:read(read_varint(ss))
					print("Tempo set: "..(60000000 / str2dword_be(string.rep("\0", 4 - #tempo_data)..tempo_data)))
				else
					ss:seek("cur", read_varint(ss))
				end
			elseif event_byte == 240 or event_byte == 247 then
				-- sysex event
				while f:read(1):byte() ~= 247 do end
			else
				ss:seek("cur", 2)
				--print("Other event at "..timing_total.." tick.")
			end
		end
	end
	
	f:close()
	print("==== END ====")
end

do
	local arg = {...}
	if #arg > 0 then
		print_notes(arg[1])
	end
end
