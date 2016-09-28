local arg = {...}

dofile("ll_beatmap.lua")

local x = load_rs_beatmap(arg[1])
local y = rs2sif(x, arg[3])
save_sif_beatmap(arg[2], y)
