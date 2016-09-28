-- SIF Beatmap to Sukufesu Simyuuretaa beatmap (yuyu's Live Simulator)

-- usage: lua sif2sifsimu.lua [input = stdin] [output = stdout] [bpm = 120] [offsetms = 0] [attribute = smile] [difficulty = 1] [songfile = ""]
local arg = {...}

local yajl = require("yajl")
local target_in = io.stdin
local target_out = io.stdout
local target_bpm = 120
local target_offset = 0
local target_attr = 1	-- smile
local target_diff = 1
local target_songfile = ""

if arg[1] then
	target_in = assert(io.open(arg[1], "rb"))
end

if arg[2] then
	target_out = assert(io.open(arg[2], "w"))
end

target_bpm = tonumber(arg[3]) or 120
target_offset = tonumber(arg[4]) or 0

if arg[5] == "smile" then
	target_attr = 1
elseif arg[5] == "pure" then
	target_attr = 2
elseif arg[5] == "cool" then
	target_attr = 3
end

target_diff = tonumber(arg[6]) or 1
target_songfile = arg[7] or ""

target_out:write(string.format("BPM = %d;\n", target_bpm))
target_out:write(string.format("OFFSET = %d;\n", target_offset))
target_out:write"TIME = 4;\n"
target_out:write(string.format("ATTRIBUTE = %d;\n", target_attr - 1))
target_out:write(string.format("DIFFICULTY = %d;\n", target_diff))
target_out:write(string.format("MUSIC = GetCurrentScriptDirectory~%q;\n", target_songfile))
target_out:write"RANDOMIZE = 0;\n"
target_out:write"imgJacket = \"\";\n"
target_out:write"TITLE = \"dummy\";\n"
target_out:write"COMMENT = \"dummy\";\n"
target_out:write"BEATMAP = [\n"

local function explode(divider, str)
	local out = {}
	
	for w in str:gmatch("[^"..divider.."]+") do
		table.insert(out, w)
	end
	
	return out
end

--tick = currentMillis / 60000 * ppqn * tempo
local current_attr = target_attr
local current_simu = false
local input_data = yajl.to_value(target_in:read("*a"))
local foreach = table.foreach or function(a,b)for n,v in pairs(a)do b(n,v)end end
local data_out = {}

-- Write BPM
table.insert(data_out, string.format("0,10,%d", target_bpm))

foreach(input_data, function(n, v)
	local tick = math.floor((v.timing_sec + target_offset) * 1000 / 60000 * 48 * target_bpm + 0.5)
	local sifspos = 10 - v.position
	
	if current_attr ~= v.notes_attribute then
		current_attr = v.notes_attribute
		table.insert(data_out, string.format("%d,18,%d", tick, current_attr - 1))
	end
	
	if v.effect == 4 then
		-- star note
		table.insert(data_out, string.format("%d,%d,2", tick, sifspos))
	elseif v.effect == 3 then
		-- long note
		table.insert(data_out, string.format("%d,%d,-%d", tick, sifspos, math.floor(v.effect_value * 1000 / 60000 * 48 * target_bpm + 0.5)))
	else
		-- normal/token note
		local simunote = 0
		
		if v.timing_sec == (input_data[n + 1] or {}).timing_sec then
			simunote = 1
			current_simu = true
		elseif current_simu == true then
			simunote = 1
			current_simu = false
		end
		
		table.insert(data_out, string.format("%d,%d,%d", tick, sifspos, simunote))
	end
end)

target_out:write(table.concat(data_out, ","))
