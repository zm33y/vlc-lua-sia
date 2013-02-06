--[[   \   /        Say It Again - a VLC extension
 _______\_/______
| .------------. |  "Learn a language while watching TV"
| |~           | |
| | tvlang.com | |        for more details visit:
| |            | |  =D.
| '------------' | _   )    http://tvlang.com/sia
|  ###### o o [] |/ `-'
'================'

Features:
 -- Phrases navigation (go to previous, next subtitle) - keys [y], [u]
 -- Word translation and export to Anki (together with context and transcription) - key [i]
 -- "Again": go to previous phrase, show subtitle and pause video - key [backspace]

How To Install And Use:
 1. Copy say_it_again.lua (this file) to %ProgramFiles%\VideoLAN\VLC\lua\extensions\ (or /usr/share/vlc/lua/extensions/ for Linux users)
 2. Download a dictionary in Stardict format (eg google "lingvo x3 stardict torrent"; keep in mind that it is kind of illegal, though)
 3. Extract dictionaries: there should be three files (.ifo, .idx and .dict (not .dz)) in one directory
 4. Edit say_it_again.lua: specify *dict_path* and *words_file_path*
 5. Restart VLC, go to "View" and select "Say It Again" extension there
 6. ????
 7. PROFIT!

License -- MIT:
 Copyright (c) 2013 Vasily Goldobin
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 IN THE SOFTWARE.

Thanks
 to lubozle (Subtitler, Previous frame) and hector (Dico) and others, whose extensions helped to create this one.

Abbreviations used in code:
 def     definition of a word (= translation)
 dlg     dialog (window)
 idx     index
 osd     on-screen display (text on screen)
 res     result
 str     string
 tbl     table
 tr      transcription of a word

]]--

--[[  Settings  ]]--
local sia_settings =
{
    dict_path = "C:\\dict\\LingvoEnRu", -- path to stardict files (without extension!) or nil to not to use dictionary
    words_file_path = "C:\\users\\vasily\\Desktop\\sia_words.txt",
    always_show_subtitles = false,
    osd_position = "top",
    help_duration = 6, -- sec; change to nil to disable osd help
    log_enable = true, -- Logs can be viewed in the console (Ctrl-M)

    key_prev_subt = 121, -- y
    key_next_subt = 117, -- u
    key_again = 8, -- backspace
    key_save = 105, -- i
}


--[[  Global variables (no midifications beyond this point) ]]--
local g_version = "0.0.1"
local g_ignored_words = {"and", "the", "that", "not", "with", "you"}

local g_osd_enabled = false
local g_osd_channel = nil
local g_dlg = {}
local g_paused_by_btn_again = false
local g_words_file = nil

local g_subtitles = {
    path = nil,
    loaded = false,
    currents = {}, -- indexes of current subtitles

    prev_time = nil, -- start time of previous subtitle
    begin_time = nil, -- start time of current subtitle
    end_time = nil, -- end time of current subtitle
    next_time = nil, -- next subtitle start time

    subtitles = {} -- contains all the subtitles
}

local g_dict = {
    loaded = false,
    idx_table = {},
    dict_file = nil,
    format = nil
}


--[[  Functions required by VLC  ]]--

function descriptor()
    return {
        title = "Say It Again",
        version = g_version;
        author = "tv language",
        url = 'http://tvlang.com',
        shortdesc = "Learn a language while watching TV!",
        description = [[<html>
 -- Phrases navigation (go to previous, next subtitle) - keys <b>[y]</b>, <b>[u]</b><br />
 -- Word translation and export to Anki (together with context and transcription) - key <b>[i]</b><br />
 -- "Again": go to previous phrase, show subtitle and pause video - key <b>[backspace]</b><br />
</html>]],
        capabilities = {"input-listener"} --, "menu"}
    }
end

-- extension activated
function activate()
    log("Activate")

    if vlc.object.input() then
        gui_show_osd_loading()
    end

    g_dict:load(sia_settings.dict_path)

    if false then
        log(g_dict:find_raw("arson"))
        return
    end

    --TODO consider this
    if vlc.object.input() then
        local loaded, msg = g_subtitles:load(get_subtitles_path())
        if not loaded then
            log(msg)
            return
        end
        g_osd_channel = vlc.osd.channel_register()
        gui_show_osd_help()
        local g_osd_enabled = sia_settings.always_show_subtitles
    end

    local msg
    if sia_settings.words_file_path and sia_settings.words_file_path ~= "" then
        g_words_file, msg = io.open(sia_settings.words_file_path, "a+")
        if not g_words_file then
            log("cant open words file: " .. (msg or "unknown error"))
        end
    end

    add_callbacks()
end

-- extension deactivated
function deactivate()
    log("Deactivate")

    g_dict:destroy()
    
    del_callbacks()

    -- TODO
    if vlc.object.input() and g_osd_channel then
        vlc.osd.channel_clear(g_osd_channel)
    end

    if g_words_file then
        g_words_file:close()
    end
end

-- input changed (playback stopped, file changed)
function input_changed()
    log("Input changed: " .. get_title())
    local loaded, msg = g_subtitles:load(get_subtitles_path())
    if not loaded then
        log(msg)
    end
    if not g_osd_channel then g_osd_channel = vlc.osd.channel_register() end
    change_callbacks()
end

-- main dialog window closed
function close()
    log("Close")
    g_dlg.dlg:delete()
    playback_play()
end

-- -- menu items 
-- function menu()
--     return {"Help"}
-- end

-- -- a menu element is selected
-- function trigger_menu(id)

--     if id == 1 then
--         log("need help? read sources :)")
--     elseif id == 2 then
--         log("Menu2 clicked")
--     end
-- end


--[[  SIA Functions  ]]--

function g_ignored_words:contains(word)
    for _, w in ipairs(self) do
        if w == word:lower() then
            return true
        end
    end
    return false
end

function g_subtitles:load(spath)
    self.loaded = false

    if not spath or spath == "" then return false, "cant load subtitles: path is nil" end

    if spath == self.path then
        self.loaded = true
        return false, "cant load subtitles: already loaded"
    end

    self.path = spath

    local file, msg = io.open(spath, "r")
    if not file then return false, "cant load subtitles: " .. (msg or "unknown error") end

    local data = file:read("*a")
    file:close()

    local srt_pattern = "(%d%d):(%d%d):(%d%d),(%d%d%d) %-%-> (%d%d):(%d%d):(%d%d),(%d%d%d).-\n(.-)\n\n"
    for h1, m1, s1, ms1, h2, m2, s2, ms2, text in string.gmatch(data, srt_pattern) do
        --if charset~=nil then text=vlc.strings.from_charset(charset, text) end   -- TODO charsets
        table.insert(self.subtitles, {to_sec(h1, m1, s1, ms1), to_sec(h2, m2, s2, ms2), text})
    end

    if #self.subtitles==0 then return false, "cant load subtitles: could not parse" end

    self.loaded = true

    log("loaded subtitles: " .. spath)

    return true
end

function g_subtitles:get_prev_time(time)
    local epsilon = 0.8 -- sec -- TODO to settings!
    if time < self.begin_time + epsilon or #self.currents == 0 then
        return self.prev_time
    else
        return self.begin_time
    end
end

function g_subtitles:get_next_time(time)
    return self.next_time
end

-- works only if there is current subtitle!
function g_subtitles:get_previous()
    return filter_html(self.currents[1] and
        self.subtitles[self.currents[1]-1] and
        self.subtitles[self.currents[1]-1][3])
end

-- works only if there is current subtitle!
function g_subtitles:get_next()
    return filter_html(self.currents[#self.currents] and
        self.subtitles[self.currents[#self.currents]+1] and
        self.subtitles[self.currents[#self.currents]+1][3])
end

function g_subtitles:get_current()
    if #self.currents == 0 then return nil end

    local subtitle = ""
    for i = 1, #self.currents do
        subtitle = subtitle .. self.subtitles[self.currents[i]][3] .. "\n"
    end

    subtitle = subtitle:sub(1,-2) -- remove trailing \n
    subtitle = filter_html(subtitle)

    return subtitle 
end

-- returns false if time is withing current subtitle
function g_subtitles:move(time)
    if self.begin_time and self.end_time and self.begin_time <= time and time <= self.end_time then
        --log("same title")
        return false, self:get_current(), self.end_time-time
    end
    
    self:_fill_currents(time)

    --g_subtitles:log(time)

    return true, self:get_current(), self.end_time and self.end_time-time or 0
end

function g_subtitles:log(cur_time)
        log("________________________________________________")
        log("prev\tbegin\tcurr\tend\tnext")
        log(tostring(self.prev_time or "----").."\t"..tostring(self.begin_time or "----").."\t"..
                tostring(cur_time or "----").."\t"..tostring(self.end_time or "----")..
                "\t"..tostring(self.next_time or "----"))
        log("nesting: " .. #self.currents)
        log("titre:" .. (g_subtitles:get_current() or "nil"))
        log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
end

-- private
function g_subtitles:_fill_currents(time)
    self.currents = {} -- there might be several current overlapping subtitles
    self.prev_time = nil
    self.begin_time = nil
    self.end_time = nil
    self.next_time = nil

    local last_checked = 0
    for i = 1, #self.subtitles do
        last_checked = i
        if self.subtitles[i][1] <= time and time <= self.subtitles[i][2] then
            self.prev_time = self.subtitles[i-1] and self.subtitles[i-1][1]
            self.begin_time = self.subtitles[i][1]
            self.end_time = math.min(self.subtitles[i+1] and self.subtitles[i+1][1] or 9999999, self.subtitles[i][2])
            table.insert(self.currents, i)
        end
        if self.subtitles[i][1] > time then
            self.next_time = self.subtitles[i][1]
            break
        end
    end

    -- if there are no current subtitles
    if #self.currents == 0 then
        self.prev_time = self.subtitles[last_checked-1] and self.subtitles[last_checked-1][1]
        self.begin_time = self.subtitles[last_checked-1] and self.subtitles[last_checked-1][2] or 0
        if last_checked < #self.subtitles then
            self.end_time = self.subtitles[last_checked] and self.subtitles[last_checked][1]
        else
            self.end_time = nil -- no end time after the last subtitle
        end
        self.next_time = self.end_time
    end
end

function add_callbacks()
    if vlc.object.input() then
        vlc.var.add_callback(vlc.object.input(), "intf-event", input_events_handler, 0)
    end
    vlc.var.add_callback(vlc.object.libvlc(), "key-pressed", key_pressed_handler, 0)
end

function del_callbacks()
    if vlc.object.input() then
        vlc.var.del_callback(vlc.object.input(), "intf-event", input_events_handler, 0)
    end
    vlc.var.del_callback(vlc.object.libvlc(), "key-pressed", key_pressed_handler, 0)
end

function change_callbacks()
    if vlc.object.input() then
        vlc.var.add_callback(vlc.object.input(), "intf-event", input_events_handler, 0) -- TODO is it obligatory?
    end
end

function input_events_handler(var, old, new, data)

    -- listen to input events only to show subtitles
    if not g_osd_enabled or not g_subtitles.loaded then return end

    -- get current time
    local input = vlc.object.input()
    local current_time = vlc.var.get(input, "time")

    -- if the video was paused by 'again!' button (backspace by default)
    --  then restore initial g_osd_enabled state
    if g_paused_by_btn_again and vlc.playlist.status() ~= "paused" then
        g_paused_by_btn_again = false
        g_osd_enabled = sia_settings.always_show_subtitles
    end

    local _, subtitle, duration = g_subtitles:move(current_time)

    osd_show(subtitle, duration)
end

function key_pressed_handler(var, old, new, data)
    --log("var: "..tostring(var).."; old: "..tostring(old).."; new: "..tostring(new).."; data: "..tostring(data))
    if new == sia_settings.key_prev_subt then
        goto_prev_subtitle()
    elseif new == sia_settings.key_next_subt then
        goto_next_subtitle()
    elseif new == sia_settings.key_again then
        subtitle_again()
    elseif new == sia_settings.key_save then
        subtitle_save()
    end
end

function goto_prev_subtitle()
    local input = vlc.object.input()
    if not input then return end

    local curr_time = vlc.var.get(input, "time")

    g_subtitles:move(curr_time)

    playback_goto(input, g_subtitles:get_prev_time(curr_time))
end

function goto_next_subtitle()
    local input = vlc.object.input()
    if not input then return end

    local curr_time = vlc.var.get(input, "time")

    g_subtitles:move(curr_time)

    playback_goto(input, g_subtitles:get_next_time(curr_time))
end

function subtitle_again()
    local input = vlc.object.input()
    if not input then return end

    local current_time = vlc.var.get(input, "time")

    playback_pause()
    g_paused_by_btn_again = true
    g_osd_enabled = true

    g_subtitles:move(current_time)

    playback_goto(input, g_subtitles:get_prev_time(current_time))
end

function subtitle_save()
    local input = vlc.object.input()
    if not input then return end

    playback_pause()

    if g_dlg.dlg and g_dlg.dlg.delete then
        pcall(g_dlg.dlg.delete, g_dlg.dlg) -- 'gently' close the dialog regardless of its state
    end

    g_subtitles:move(vlc.var.get(input, "time"))

    if gui_create_dialog(g_words_file) then
        g_dlg.dlg:update() -- HACK otherwise it won't show the window
    end
end

--[[  User Interface  ]]--

function gui_show_osd_loading()
    vlc.osd.message("SIA LOADING...", vlc.osd.channel_register(), "center")
end

function gui_show_osd_help()
    if not sia_settings.help_duration or sia_settings.help_duration <= 0 then return end

    local duration = sia_settings.help_duration * 1000000

    vlc.osd.message("!!! Press [v] to disable subtitles !!!", vlc.osd.channel_register(), "top", duration/2)
    vlc.osd.message("[y] - previous\n       phrase", vlc.osd.channel_register(), "left", duration)
    vlc.osd.message("[u] - next    \nphrase", vlc.osd.channel_register(), "right", duration)
    vlc.osd.message("[i] - save\n\n[backspace] - again!", vlc.osd.channel_register(), "center", duration)
end

function gui_def2str(list)
    local res = ""
    for k,v in pairs(list) do
        if k ~= 0 then -- do not add text 'no dict loaded'
            res = res .. v .. "<br />"
        end
    end
    return res:sub(1,-7)
end

function gui_create_dialog(file)
    local curr_subtitle = g_subtitles:get_current()
    if not curr_subtitle then
        return false
    end

    g_dlg.dlg = vlc.dialog("Say It Again " .. g_version .. " - save the word")

    g_dlg.lbl_context = g_dlg.dlg:add_label("<b>1. Edit<br />context:</b>",1,1,1,3)
    g_dlg.lbl_prev_s = g_dlg.dlg:add_label("<font color='grey'>" .. g_subtitles:get_previous() .. "</font>",2,1,8,1)
    g_dlg.btn_add_prev =g_dlg.dlg:add_button("+", function() g_dlg.tb_curr_s:set_text(g_subtitles:get_previous() .. " " .. g_dlg.tb_curr_s:get_text()) end, 10,1,1,1)
    g_dlg.tb_curr_s = g_dlg.dlg:add_text_input(curr_subtitle,2,2,9,1)
    g_dlg.lbl_next_s = g_dlg.dlg:add_label("<font color='grey'>" .. g_subtitles:get_next() .. "</font>",2,3,8,1)
    g_dlg.btn_add_next =g_dlg.dlg:add_button("+", function() g_dlg.tb_curr_s:set_text(g_dlg.tb_curr_s:get_text() .. " " .. g_subtitles:get_next()) end, 10,3,1,1)

    g_dlg.lbl_add_word = g_dlg.dlg:add_label("<br /><b>2. Choose a word to look it up:</b>",1,4,10,1)
    local cur_line = gui_get_buttons(curr_subtitle, 5)
    g_dlg.lbl_or_enter = g_dlg.dlg:add_label("or enter:",1,cur_line+1,1,1)
    g_dlg.tb_word = g_dlg.dlg:add_text_input("",2,cur_line+1,8,1)
    g_dlg.btn_lookup =g_dlg.dlg:add_button("look up", gui_lookup_word, 10, cur_line+1, 1, 1) -- TODO

    g_dlg.lbl_choose_def = g_dlg.dlg:add_label("<b>3. Choose appropriate definition(s):</b>",1,cur_line+2,10,1)

    g_dlg.list_def = g_dlg.dlg:add_list(1, cur_line+3, 10, 10)

    g_dlg.btn_get_tr = g_dlg.dlg:add_button("edit def", function() g_dlg.tb_def:set_text(gui_def2str(g_dlg.list_def:get_selection())) end, 1, cur_line+13, 1, 1)
    g_dlg.tb_def = g_dlg.dlg:add_text_input("",2,cur_line+13,8,1)
    if g_words_file then
        g_dlg.btn_save = g_dlg.dlg:add_button("SAVE >>>", gui_save_word, 10, cur_line+13, 1, 1)
    else
        g_dlg.lbl_cant_save = g_dlg.dlg:add_label("<font color='grey'> [CANT SAVE]</font>",10,cur_line+13,1,1)
    end
    g_dlg.lbl_file = g_dlg.dlg:add_label("File '" .. (sia_settings.words_file_path or "n/a") .. "':",11,1,4,1)
    g_dlg.list_file = g_dlg.dlg:add_list(11, 2, 4, cur_line+12)

    if g_words_file then
        g_words_file:seek("set")
        for line in file:lines() do
            g_dlg.list_file:add_value(line, 0)
        end
    else
        g_dlg.list_file:add_value("could not open the file :(", 0)
    end

    return true
end

-- takes the word from tb_word and fills list_def with definitions
function gui_lookup_word()
    g_dlg.list_def:clear()

    if not g_dict.loaded then
        g_dlg.list_def:add_value("No dictionary loaded :(", 0)
        g_dlg.list_def:add_value("But you can still enter definition manually", 0)
        return false
    end

    local word = g_dlg.tb_word:get_text()
    local def = g_dict:find_tbl(word)
    if def and #def > 0 then
        g_dlg.tr = def.tr
        for i,v in ipairs(def) do
            g_dlg.list_def:add_value(v, i)
        end
    else
        g_dlg.list_def:add_value("no result :(", 0)
        return false
    end

    return true
end

function gui_save_word()
    if not g_words_file then
        log("file not open")
        return
    end

    local word = g_dlg.tb_word:get_text()
    local def = g_dlg.tb_def:get_text()

    if not def or def == "" then
        def = gui_def2str(g_dlg.list_def:get_selection())
    end

    if not word or word == "" or not def or def == "" then
        log("either no word or no definition selected")
        return
    end

    local transcription = g_dlg.tr and ("["..g_dlg.tr.."]") or ""

    
    local context = string.gsub(g_dlg.tb_curr_s:get_text(), "\n", " ") or ""
    local tags = get_title() or ""

    local res = word .. "\t" .. transcription .. "\t" .. def .. "\t" .. context .. "\t" .. tags

    g_dlg.list_file:add_value(res, 0)
    g_words_file:write(res .. "\r\n")
    g_words_file:flush()
end

function gui_get_buttons(subtitle, cur_line)
    local btns = {}
    local i = 1
    for word in string.gmatch(subtitle, "%a[%a-]+%a") do
        if not g_ignored_words:contains(word) then
            table.insert(btns, g_dlg.dlg:add_button(word, function() g_dlg.tb_word:set_text(word:lower()) gui_lookup_word() end, i, cur_line, 1, 1))
            i = i + 1
            if i > 10 then
                cur_line = cur_line + 1
                i = 1
            end
        end
    end
    return cur_line
end

--[[  Utils  ]]--

-- shows osd message in specified [position]
-- if 'subtitle' is nil, then clears osd
function osd_show(subtitle, duration, position)
    duration = math.max(duration, 1) -- to prevent blinking if duration is too small
    if subtitle and duration and duration > 0 then
        vlc.osd.message(subtitle, g_osd_channel, position or sia_settings.osd_position, duration*1000000)
    else
        vlc.osd.message("", g_osd_channel)
    end
end

function log(msg, ...)
    if sia_settings.log_enable then
        vlc.msg.info("[sia] " .. tostring(msg), unpack(arg))
    end
end

function get_input_item()
    return vlc.input.item()
end

-- Returns title or empty string if not available
function get_title()
    local item = get_input_item()
    if not item then return "" end

    local metas = item.metas and item:metas()
    if not metas then return "" end

    if metas["title"] then
        return metas["title"]
    else
        local filename = string.gsub(item:name(), "^(.+)%.%w+$", "%1")
        return trim(filename or item:name())
    end
    
end

function get_subtitles_path()
    local item = get_input_item()
    if not item then return "" end

    return string.match(vlc.strings.decode_uri(item:uri()), "^.-///(.*)%.") .. ".srt"
end

function filter_html(str)
    local res = str or ""
    res = string.gsub(res, "&apos;", "'")
    res = string.gsub(res, "<.->", "")
    return res
end

function trim(str)
    if not str then return "" end
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

function to_sec(h,m,s,ms)
    return tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) + tonumber("0."..ms)
end

function playback_goto(input, time)
    if input and time then
        vlc.var.set(input, "time", time)
    end
end

function playback_pause()
    if vlc.playlist.status() == "playing" then
        vlc.playlist.pause()
    end
end

function playback_play()
    if vlc.playlist.status() ~= "playing" then
        vlc.playlist.pause()
    end
end

function bytes_to_int32(str)
    return string.byte(str,1)*0x1000000 + string.byte(str,2)*0x10000 +
        string.byte(str,3)*0x100 + string.byte(str,4)
end


--[[ Work with dictionary ]]--

-- parses .idx file
-- file format (binary data): entry_name\0 offset(4bytes) size(4bytes)
function g_dict:_load_index(path)

    if not path then return nil end

    local f, msg = io.open(path..".idx", "rb")

    if not f then
        log("Cant open index file '"..(path..".idx").."': "..msg)
        return false
    end

    log("Loading index: "..(path..".idx"))

    local idx_str = f:read("*all")
    f:close()

    local enb = 1 -- entry name begin
    local ene = string.find(idx_str,'\0',enb) -- entry name end

    while ene do
        local entry = string.sub(idx_str,enb,ene-1) 
        local offset= bytes_to_int32(string.sub(idx_str,ene+1,ene+4))
        local size = bytes_to_int32(string.sub(idx_str,ene+5,ene+8))
        self.idx_table[entry] = {offset, size}
        enb = ene + 9

        ene = string.find(idx_str,'\0',enb)
    end

    log("Index loaded successfully")

    return true
end

local g_dict_fmt = {
    {pattern = "LingvoUniversal", tr = "<tr>(.-)</tr>", def = "<dtrn>(.-)</dtrn>", not_def = nil},
    {pattern = "Merriam%-Webster", tr = "<co>\\(.-)\\</co>", def = "<dtrn> <b>:</b> (.-)</dtrn>", not_def = nil},
    {pattern = "Macmillan", tr = "<c c=\"teal\">%[(.-)%]</c>", def = "<blockquote>(.-)</blockquote>", not_def = {"<ex>", "c=\"darkslategray\""}},
    {pattern = "Longman", tr = " /(.-)/ ", def = "<blockquote>(.-)</blockquote>", not_def = {"<ex>", "Word Family:", "Origin: ", "c=\"crimson\"", "c=\"chocolate\"", "c=\"darkgoldenrod\"", "c=\"gray\""}},
    {pattern = ".*", tr = nil, def = "(.-)\n", not_def = nil}, -- for unknown dictionaries
}

-- returns name and format table
function g_dict:load_info(path)
    local f, msg = io.open(path..".ifo", "r")

    if not f then
        log("Cant load ifo file '"..(path..".ifo").."': "..(msg or "unknown error"))
        return nil
    end

    local ifo_str = f:read("*all")
    f:close()

    local bookname = ifo_str:match("bookname=(.-)\n")
    if not bookname or bookname == "" then
        log("Cant read bookname")
        return nil
    end

    for i,fmt in ipairs(g_dict_fmt) do
        if bookname:match(fmt.pattern) then
            log("matched pattern: "..fmt.pattern)
            return bookname, fmt
        end
    end

    return bookname, nil
end

function g_dict:load(path)
    self.loaded = false

    if not path or path == "" then return false end

    local name, fmt = self:load_info(path)
    if not name or not fmt then
        log("cant load dictionary")
        return false
    end

    log("Using dictionary: "..name)
    self.format = fmt

    local idx_loaded = self:_load_index(path)

    if not idx_loaded then
        log("cant load dictionary")
        return false
    end

    local f, msg = io.open(path..".dict", "r")

    if not f then
        log("Cant load dictionary file '"..(path..".dict").."': "..(msg or "unknown error"))
        return false
    end

    self.dict_file = f

    self.loaded = true
    return true
end

function g_dict:destroy()
    self.loaded = false
    self.idx_table = {}
    if self.dict_file then self.dict_file:close() end
    self.dict_file = nil
    self.format = nil
end

function g_dict:find_raw(word)
    if not self.loaded then return nil end

    local idx_value = self.idx_table[word]

    if idx_value then
        self.dict_file:seek("set", idx_value[1])
        local entry, msg = self.dict_file:read(idx_value[2])

        if not entry then
            log("Error reading dictionary entry: "..(msg or "unknown error"))
            return nil
        end
        return entry
    end

    return nil
end

function g_dict:find_tbl(word)
    local str = self:find_raw(word)
    local res = {}
    if str then
        if self.format.tr then res.tr = filter_html(str:match(self.format.tr)) end
        for def in str:gmatch(self.format.def) do
            local reject_def = false
            -- reject strings that are not definitions
            if self.format.not_def then
                for _,v in ipairs(self.format.not_def) do
                    if def:match(v) then
                        reject_def = true
                        break
                    end
                end
            end

            if not reject_def then
                def = filter_html(def)
                def = trim(def)
                table.insert(res, def)
            end
        end
    end
    return res
end