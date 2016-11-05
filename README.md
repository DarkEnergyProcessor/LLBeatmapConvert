# LLBeatmapConvert
Various Lua scripts to convert SIF beatmap from one format to another.

# Requirements

* Lua 5.1 with [lua-yajl](https://github.com/brimworks/lua-yajl) library. Might move to pure Lua 5.1 JSON later.

# Implementation Table (Column part is From, Row part is Target)

Beatmap | SIF | RS  | LLP | SifSimu | CBF | MIDI
------- | --- | --- | --- | ------- | --- | ----
SIF     | \-  | \✓  | \✓  | \*      | \*  |
RS      |     | \-  |     |         |     |
LLP     |     |     | \-  |         |     |
SifSimu | \*  |     |     | \-      |     |
CBF     |     |     |     |         | \-  |
MIDI    | \✓  |     |     |         |     | \-

\✓ = Fully implemented  
\* = Experimental  
\- = Unnecessary

# Disclaimer

* [`JSON.lua` source](http://regex.info/blog/lua/json)
