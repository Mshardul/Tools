--[[
  file_memory.lua — VLC extension
  Remembers audio track, subtitle (SPU) track, and A/V delays per file.

  Activate via: View → Extensions → Per-File Audio/Subtitle Memory
  Install helper: python3 vlc_file_memory.py install

  Store (JSON): <userdatadir>/lua/extensions/file_memory_store.json
  Keys: normalized filesystem paths (file:// URIs decoded).
]]

local STORE_NAME = "file_memory_store.json"

-- Last media key we restored for (avoid thrashing on meta churn).
local current_key = nil
-- True after we applied a saved entry for current_key (or decided none exists).
local restored_for_key = nil
-- Debounce saves while we are still applying restore.
local applying = false

function descriptor()
    return {
        title = "Per-File Audio/Subtitle Memory",
        version = "1.0.0",
        author = "Tools collection",
        url = "https://github.com",
        shortdesc = "Remember audio, subtitle, and delay per file",
        description = "Saves and restores audio track, subtitle track, "
            .. "audio delay, and subtitle delay for each local file.",
        capabilities = { "input-listener", "meta-listener" },
    }
end

function activate()
    current_key = nil
    restored_for_key = nil
    applying = false
    try_restore()
end

function deactivate()
    try_save()
    current_key = nil
    restored_for_key = nil
    applying = false
end

function close()
    deactivate()
end

function input_changed()
    -- New item: save previous (if any), then restore for the new file.
    if current_key ~= nil and restored_for_key == current_key then
        try_save()
    end
    current_key = nil
    restored_for_key = nil
    try_restore()
end

function meta_changed()
    -- Tracks often become available after meta settles; restore once, then save.
    if restored_for_key ~= current_key then
        try_restore()
    else
        try_save()
    end
end

--- Store path beside user Lua extensions (same dir the install helper uses).
local function store_file_path()
    local base = nil
    if vlc.config and vlc.config.userdatadir then
        base = vlc.config.userdatadir()
    end
    if not base or base == "" then
        local home = (vlc.config and vlc.config.homedir and vlc.config.homedir()) or ""
        base = home .. "/Library/Application Support/org.videolan.vlc"
    end
    return base .. "/lua/extensions/" .. STORE_NAME
end

--- Percent-decode a path segment (minimal; enough for file URIs).
local function url_decode(s)
    if s == nil then
        return nil
    end
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return s
end

--- Normalize file URI / path to match Python normalize_media_path().
local function normalize_media_path(uri_or_path)
    if uri_or_path == nil then
        return nil
    end
    local text = tostring(uri_or_path)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        return nil
    end

    local lower = string.lower(text)
    if string.sub(lower, 1, 5) == "file:" then
        -- file:///path or file://localhost/path
        local path = string.match(text, "^[Ff][Ii][Ll][Ee]://localhost(/.*)$")
            or string.match(text, "^[Ff][Ii][Ll][Ee]://(/.*)$")
            or string.match(text, "^[Ff][Ii][Ll][Ee]:(/.*)$")
        if path then
            text = url_decode(path)
        end
    end

    text = string.gsub(text, "\\", "/")
    while #text > 1 and string.sub(text, -1) == "/" do
        text = string.sub(text, 1, -2)
    end
    if text == "" then
        return nil
    end
    return text
end

local function current_item_uri()
    if not vlc.input or not vlc.input.item then
        return nil
    end
    local item = vlc.input.item()
    if not item then
        return nil
    end
    local ok, uri = pcall(function()
        return item:uri()
    end)
    if ok then
        return uri
    end
    return nil
end

------------------------------------------------------------------------
-- Minimal JSON codec for { "<path>": { "k": number|string, ... }, ... }
------------------------------------------------------------------------

local function json_escape(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\t", "\\t")
    return s
end

local function json_encode_value(v)
    local t = type(v)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return '"' .. json_escape(v) .. '"'
    elseif t == "table" then
        -- Detect array vs object: our store is always an object map.
        local parts = {}
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = '"'
                .. json_escape(tostring(k))
                .. '": '
                .. json_encode_value(v[k])
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    return "null"
end

local function json_encode_store(store)
    local keys = {}
    for k in pairs(store) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    if #keys == 0 then
        return "{}\n"
    end
    local lines = { "{" }
    for i, k in ipairs(keys) do
        local entry = store[k]
        local fields = {}
        local fkeys = {}
        for fk in pairs(entry) do
            fkeys[#fkeys + 1] = fk
        end
        table.sort(fkeys)
        for _, fk in ipairs(fkeys) do
            fields[#fields + 1] = '    "'
                .. json_escape(fk)
                .. '": '
                .. json_encode_value(entry[fk])
        end
        local comma = (i < #keys) and "," or ""
        lines[#lines + 1] = '  "'
            .. json_escape(k)
            .. '": {\n'
            .. table.concat(fields, ",\n")
            .. "\n  }"
            .. comma
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

-- Tiny decoder: enough for our store shape (no arrays nesting beyond objects).
local function json_parse(str)
    local i = 1
    local n = #str

    local function peek()
        return string.sub(str, i, i)
    end

    local function skip_ws()
        while i <= n and string.match(peek(), "%s") do
            i = i + 1
        end
    end

    local parse_value

    local function parse_string()
        if peek() ~= '"' then
            return nil
        end
        i = i + 1
        local out = {}
        while i <= n do
            local c = peek()
            if c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                i = i + 1
                local e = peek()
                if e == "n" then
                    out[#out + 1] = "\n"
                elseif e == "r" then
                    out[#out + 1] = "\r"
                elseif e == "t" then
                    out[#out + 1] = "\t"
                else
                    out[#out + 1] = e
                end
                i = i + 1
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return nil
    end

    local function parse_number()
        local s, e = string.find(str, "^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if not s then
            return nil
        end
        local num = tonumber(string.sub(str, s, e))
        i = e + 1
        return num
    end

    local function parse_object()
        if peek() ~= "{" then
            return nil
        end
        i = i + 1
        local obj = {}
        skip_ws()
        if peek() == "}" then
            i = i + 1
            return obj
        end
        while true do
            skip_ws()
            local key = parse_string()
            if key == nil then
                return nil
            end
            skip_ws()
            if peek() ~= ":" then
                return nil
            end
            i = i + 1
            skip_ws()
            local val = parse_value()
            if val == nil and peek() ~= "n" then
                -- allow explicit null
            end
            obj[key] = val
            skip_ws()
            local c = peek()
            if c == "}" then
                i = i + 1
                return obj
            elseif c == "," then
                i = i + 1
            else
                return nil
            end
        end
    end

    parse_value = function()
        skip_ws()
        local c = peek()
        if c == '"' then
            return parse_string()
        elseif c == "{" then
            return parse_object()
        elseif c == "t" and string.sub(str, i, i + 3) == "true" then
            i = i + 4
            return true
        elseif c == "f" and string.sub(str, i, i + 4) == "false" then
            i = i + 5
            return false
        elseif c == "n" and string.sub(str, i, i + 3) == "null" then
            i = i + 4
            return nil
        else
            return parse_number()
        end
    end

    skip_ws()
    local root = parse_value()
    if type(root) ~= "table" then
        return {}
    end
    return root
end

local function load_store()
    local path = store_file_path()
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then
        return {}
    end
    local ok, store = pcall(json_parse, data)
    if not ok or type(store) ~= "table" then
        vlc.msg.warn("[file_memory] could not parse store; starting empty")
        return {}
    end
    return store
end

local function save_store(store)
    local path = store_file_path()
    -- Ensure parent dir exists (best-effort; install helper usually created it).
    local dir = string.match(path, "^(.+)/[^/]+$")
    if dir then
        os.execute('mkdir -p "' .. dir:gsub('"', '\\"') .. '" 2>/dev/null')
    end
    local f = io.open(path, "w")
    if not f then
        vlc.msg.warn("[file_memory] cannot write store: " .. tostring(path))
        return false
    end
    f:write(json_encode_store(store))
    f:close()
    return true
end

------------------------------------------------------------------------
-- Track / delay get-set (best-effort across VLC API variants)
------------------------------------------------------------------------

local function selected_track_id(tracks)
    if type(tracks) ~= "table" then
        return nil
    end
    for _, t in ipairs(tracks) do
        if type(t) == "table" and t.selected then
            return t.id
        end
    end
    -- Some builds return map-like tables
    for _, t in pairs(tracks) do
        if type(t) == "table" and t.selected then
            return t.id
        end
    end
    return nil
end

local function get_audio_track()
    if vlc.player and vlc.player.get_audio_tracks then
        local ok, tracks = pcall(vlc.player.get_audio_tracks)
        if ok then
            local id = selected_track_id(tracks)
            if id ~= nil then
                return id
            end
        end
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        local ok, v = pcall(vlc.var.get, input, "audio-es")
        if ok then
            return v
        end
    end
    return nil
end

local function get_spu_track()
    if vlc.player and vlc.player.get_spu_tracks then
        local ok, tracks = pcall(vlc.player.get_spu_tracks)
        if ok then
            local id = selected_track_id(tracks)
            if id ~= nil then
                return id
            end
        end
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        local ok, v = pcall(vlc.var.get, input, "spu-es")
        if ok then
            return v
        end
    end
    return nil
end

local function set_audio_track(id)
    if id == nil then
        return
    end
    if vlc.player and vlc.player.toggle_audio_track then
        pcall(vlc.player.toggle_audio_track, id)
        return
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        pcall(vlc.var.set, input, "audio-es", id)
    end
end

local function set_spu_track(id)
    if id == nil then
        return
    end
    if vlc.player and vlc.player.toggle_spu_track then
        pcall(vlc.player.toggle_spu_track, id)
        return
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        pcall(vlc.var.set, input, "spu-es", id)
    end
end

local function get_audio_delay()
    if vlc.player and vlc.player.get_audio_delay then
        local ok, v = pcall(vlc.player.get_audio_delay)
        if ok and type(v) == "number" then
            return v
        end
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        local ok, v = pcall(vlc.var.get, input, "audio-delay")
        -- Older VLC exposes microseconds on the input var.
        if ok and type(v) == "number" then
            if math.abs(v) > 10 then
                return v / 1000000
            end
            return v
        end
    end
    return nil
end

local function get_subtitle_delay()
    if vlc.player and vlc.player.get_subtitle_delay then
        local ok, v = pcall(vlc.player.get_subtitle_delay)
        if ok and type(v) == "number" then
            return v
        end
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        local ok, v = pcall(vlc.var.get, input, "spu-delay")
        if ok and type(v) == "number" then
            if math.abs(v) > 10 then
                return v / 1000000
            end
            return v
        end
    end
    return nil
end

local function set_audio_delay(seconds)
    if seconds == nil then
        return
    end
    if vlc.player and vlc.player.set_audio_delay then
        pcall(vlc.player.set_audio_delay, seconds)
        return
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        pcall(vlc.var.set, input, "audio-delay", math.floor(seconds * 1000000))
    end
end

local function set_subtitle_delay(seconds)
    if seconds == nil then
        return
    end
    if vlc.player and vlc.player.set_subtitle_delay then
        pcall(vlc.player.set_subtitle_delay, seconds)
        return
    end
    local input = vlc.object and vlc.object.input and vlc.object.input()
    if input then
        pcall(vlc.var.set, input, "spu-delay", math.floor(seconds * 1000000))
    end
end

------------------------------------------------------------------------
-- Restore / save
------------------------------------------------------------------------

function try_restore()
    local uri = current_item_uri()
    local key = normalize_media_path(uri)
    if key == nil then
        return
    end
    -- Network streams: still key by URI path-ish; skip empty.
    current_key = key

    local store = load_store()
    local entry = store[key]
    if type(entry) ~= "table" then
        restored_for_key = key
        return
    end

    applying = true
    if entry.audio_track ~= nil then
        set_audio_track(entry.audio_track)
    end
    if entry.spu_track ~= nil then
        set_spu_track(entry.spu_track)
    end
    if entry.audio_delay ~= nil then
        set_audio_delay(entry.audio_delay)
    end
    if entry.subtitle_delay ~= nil then
        set_subtitle_delay(entry.subtitle_delay)
    end
    applying = false
    restored_for_key = key
    vlc.msg.info("[file_memory] restored settings for " .. key)
end

function try_save()
    if applying then
        return
    end
    local uri = current_item_uri()
    local key = normalize_media_path(uri)
    if key == nil then
        return
    end

    local audio = get_audio_track()
    local spu = get_spu_track()
    local adelay = get_audio_delay()
    local sdelay = get_subtitle_delay()

    -- Nothing useful yet (tracks not enumerated) — skip write.
    if audio == nil and spu == nil and adelay == nil and sdelay == nil then
        return
    end

    local store = load_store()
    local entry = store[key] or {}
    entry.path = key
    if audio ~= nil then
        entry.audio_track = audio
    end
    if spu ~= nil then
        entry.spu_track = spu
    end
    if adelay ~= nil then
        entry.audio_delay = adelay
    end
    if sdelay ~= nil then
        entry.subtitle_delay = sdelay
    end
    store[key] = entry
    if save_store(store) then
        current_key = key
        restored_for_key = key
    end
end
