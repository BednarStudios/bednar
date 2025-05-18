local lfs = require("lfs")

local mods_dir = "mods"
local output_file = "mod_list.txt"

local function ends_with(str, ending)
    return str:sub(-#ending) == ending
end

local function generate_mod_list()
    local file = io.open(output_file, "w")
    if not file then
        return
    end

    for file_name in lfs.dir(mods_dir) do
        if file_name ~= "." and file_name ~= ".." and ends_with(file_name, ".mod.json") then
            local mod_name = file_name:gsub("%.mod%.json$", "")
            file:write(mod_name .. "\n")
        end
    end

    file:close()
end

generate_mod_list()
