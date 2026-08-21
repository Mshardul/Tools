--[[
  skip_chapter.lua — VLC extension
  Auto-skips chapters whose titles match intro/credits-style names.

  Activate via: View → Extensions → Skip Intro/Credits Chapters
  Install helper: python3 vlc_skip_chapter.py install

  Matching rules mirror Python should_skip_chapter() / DEFAULT_PATTERNS.
]]

-- Default skip list (keep aligned with vlc_skip_chapter.DEFAULT_PATTERNS).
local SKIP_PATTERNS = { "intro", "credits", "opening", "ending", "outro" }

local last_chapter = nil

function descriptor()
    return {
        title = "Skip Intro/Credits Chapters",
        version = "1.0.0",
        author = "Tools collection",
        url = "https://github.com",
        shortdesc = "Auto-skip Intro/Credits chapters",
        description = "Jumps to the next chapter when the current chapter "
            .. "title matches intro, credits, opening, ending, or outro.",
        -- Fires when the input item or its metadata (incl. chapter) changes.
        capabilities = { "input-listener", "meta-listener" },
    }
end

function activate()
    last_chapter = nil
    check_and_skip()
end

function deactivate()
    last_chapter = nil
end

function close()
    deactivate()
end

-- New file / playlist item.
function input_changed()
    last_chapter = nil
    check_and_skip()
end

-- Chapter title / position updates often arrive as metadata changes.
function meta_changed()
    check_and_skip()
end

--- Case-insensitive whole-word / equality / startswith-with-separator match.
local function should_skip(name)
    if name == nil or name == "" then
        return false
    end
    local lowered = string.lower(name)
    lowered = string.gsub(lowered, "^%s+", "")
    lowered = string.gsub(lowered, "%s+$", "")
    if lowered == "" then
        return false
    end

    for _, pat in ipairs(SKIP_PATTERNS) do
        if lowered == pat then
            return true
        end
        -- startswith: pattern alone, or pattern + common separator
        if string.sub(lowered, 1, #pat) == pat then
            local rest = string.sub(lowered, #pat + 1, #pat + 1)
            if rest == "" or string.find(" -_.:/()[]", rest, 1, true) then
                return true
            end
        end
        -- whole word: non-alnum (or string edges) around the pattern
        local i = 1
        while true do
            local s, e = string.find(lowered, pat, i, true)
            if not s then
                break
            end
            local before = (s == 1) and "" or string.sub(lowered, s - 1, s - 1)
            local after = (e == #lowered) and "" or string.sub(lowered, e + 1, e + 1)
            local before_ok = (before == "" or not string.match(before, "%w"))
            local after_ok = (after == "" or not string.match(after, "%w"))
            if before_ok and after_ok then
                return true
            end
            i = s + 1
        end
    end
    return false
end

--- Current chapter index (0-based) and display title, if available.
local function current_chapter_info()
    local input = vlc.object.input()
    if not input then
        return nil, nil
    end
    local idx = vlc.var.get(input, "chapter")
    if idx == nil or idx < 0 then
        return nil, nil
    end
    -- get_list returns parallel value / text tables for the chapter list
    local ok, _values, texts = pcall(vlc.var.get_list, input, "chapter")
    local title = nil
    if ok and texts ~= nil then
        -- Lua tables from VLC are 1-indexed; chapter index is 0-based
        title = texts[idx + 1]
    end
    return idx, title
end

function check_and_skip()
    local idx, title = current_chapter_info()
    if idx == nil then
        return
    end
    -- Do not re-fire on the same chapter after we already advanced past it
    if last_chapter == idx then
        return
    end
    last_chapter = idx

    if title == nil or title == "" then
        return
    end
    if not should_skip(title) then
        return
    end

    local input = vlc.object.input()
    if not input then
        return
    end
    vlc.msg.info("[skip_chapter] skipping chapter: " .. tostring(title))
    -- Next chapter (VLC clamps if already at the last one)
    vlc.var.set(input, "chapter", idx + 1)
    last_chapter = idx + 1
end
