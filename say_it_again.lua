--[[   \   /        Say It Again - a VLC extension
 _______\_/______
| .------------. |  "Learn a language while watching TV"
| |~           | |
| | tvlang.com | |        for more details visit:
| |            | |  =D.
| '------------' | _   )    http://tvlang.com
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
 4. Download WordNet databases [http://wordnetcode.princeton.edu/wn3.1.dict.tar.gz] and extract them somewhere
 5. Edit say_it_again.lua: specify *dict_dir*, *wordnet_dir* and *words_file_path*
 6. Restart VLC, go to "View" and select "Say It Again" extension there
 7. ????
 8. PROFIT!

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
 to lubozle (Subtitler, Previous frame) and hector (Dico) and others, whose extensions helped to create this one;
 to Princeton University for their WordNet;

Abbreviations used in code:
 def     definition of a word (= translation)
 dlg     dialog (window)
 idx     index
 pos     part of speech (noun, verb etc)
 osd     on-screen display (text on screen)
 res     result
 str     string
 tbl     table
 tr      transcription of a word

]]--

--[[  Settings  ]]--
local sia_settings =
{
    --charset = "iso-8859-1", -- works for english and french subtitles (try also "Windows-1252")
    charset = nil,          -- UT8 encoding
    dict_dir = "c:/!MY_DOCS/say_it_again/dict",            -- where Stardict dictionaries are located
    wordnet_dir = "c:/!MY_DOCS/say_it_again/WordNet", -- where WordNet files are located
    --chosen_dict = "c:/!MY_DOCS/say_it_again/dict/Oxford Advanced Learner's Dictionary", -- Stardict dictionary used by default (there should be 3 files with this name but different extensions)
    chosen_dict = "c:/!MY_DOCS/say_it_again/dict/OxfordAmericanDictionaryEnEn", -- Stardict dictionary used by default (there should be 3 files with this name but different extensions)
    words_file_path = "c:/!MY_DOCS/say_it_again/sia_words.txt", -- if 'nil' then "Desktop/sia_words.txt" will be used
    always_show_subtitles = false,
    osd_position = "top",
    help_duration = 6, -- sec; change to nil to disable osd help
    log_enable = true, -- Logs can be viewed in the console (Ctrl-M)

    key_prev_subt = 121, -- y
    key_next_subt = 117, -- u
    key_again = 8, -- backspace
    key_save = 105, -- i
    key_enable_second_lang = 67108872, -- ctrl + backspace
    key_always_show_subs = 114, -- R
    
    -- global subtitles time shift to compensate vlc audio start delay or lack of subtitles synchronization
    subs_time_shift = -2.5
}


--[[  Global variables (no midifications beyond this point) ]]--
local g_version = "0.0.6"
local g_ignored_words = {"and", "the", "that", "not", "with", "you"}

local g_osd_enabled = false
local g_osd_channel = nil
local g_dlg = {}
local g_paused_by_btn_again = false
local g_second_lang_enabled = false
local g_words_file = nil
local g_callbacks_set = false
local g_current_dialog = nil
local g_found_dicts = {}
local g_subtitles = nil
local g_subtitles_native = nil

local g_dict = {
    loaded = false,
    name = nil,
    idx_table = {},
    dict_file = nil,
    format = nil
}

local g_dict_fmt = {
    {pattern = "Lingvo", tr = "<tr>(.-)</tr>", def = "<dtrn>(.-)</dtrn>", not_def = nil},
    {pattern = "Universal", tr = "<tr>(.-)</tr>", def = "<dtrn>(.-)</dtrn>", not_def = nil},
    {pattern = "OxfordAmericanDictionary", tr = "<tr>(.-)</tr>", def = "<dtrn>(.-)</dtrn>", not_def = {"<ex>"}},
    {pattern = "Merriam%-Webster", tr = "<co>\\(.-)\\</co>", def = "<dtrn> <b>:</b> (.-)</dtrn>", not_def = nil},
    {pattern = "Macmillan", tr = "<c c=\"teal\">%[(.-)%]</c>", def = "<blockquote>(.-)</blockquote>", not_def = {"<ex>", "c=\"darkslategray\""}},
    {pattern = "Longman", tr = " /(.-)/ ", def = "<blockquote>(.-)</blockquote>", not_def = {"<ex>", "Word Family:", "Origin: ", "c=\"crimson\"", "c=\"chocolate\"", "c=\"darkgoldenrod\"", "c=\"gray\""}},
    {pattern = "Babylon", tr = nil, def = "[>;,]%s(.-)%f[^%a%s]", not_def = nil}, -- uses the undocumented frontier pattern %f to work even at the end of the string
    {pattern = ".*", tr = nil, def = "(.-)\n", not_def = nil}, -- for unknown dictionaries
}

local g_wordnet = {
    loaded = false,
    poss = {},

    rules = {
        noun = {
            {"s", ""},
            {"'s", ""},
            {"'", ""},
            {"ses", "s"},
            {"xes", "x"},
            {"zes" , "z"},
            {"ches" , "ch"},
            {"shes" , "sh"},
            {"men" , "man"},
            {"ies" , "y"}
        },
        verb = {
            {"s", ""},
            {"ies", "y"},
            {"es", "e"},
            {"es", ""},
            {"ed", "e"},
            {"ed", ""},
            {"ing", "e"},
            {"ing", ""}
        },
        adj = {
            {"er", ""},
            {"er", "e"},
            {"est", ""},
            {"est", "e"}
        },
        adv = {}
    }
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
 -- Ability to use two subtitles languages simultaneously - key <b>[ctrl+backspace]</b><br />
 -- Ability to always show subtitles - key <b>[R]</b><br />
</html>]],
        capabilities = {"input-listener", "menu"}
    }
end

-- extension activated
function activate()
    log("Activate")

    if vlc.object.input() and (sia_settings.chosen_dict or sia_settings.wordnet_dir) then
        gui_show_osd_loading()
    end

    g_found_dicts = g_dict:get_dicts(g_dict:get_dict_paths(sia_settings.dict_dir))
    g_dict:load(sia_settings.chosen_dict)
    g_wordnet:load(sia_settings.wordnet_dir)

    if is_nil_or_empty(sia_settings.words_file_path) then
        if (is_unix_platform()) then
            sia_settings.words_file_path = vlc.config.homedir() .. "/Desktop/sia_words.txt"
        else
            sia_settings.words_file_path = vlc.config.homedir() .. "\\..\\Desktop\\sia_words.txt"
        end
    end

    local msg
    g_words_file, msg = io.open(sia_settings.words_file_path, "a+")
    if not g_words_file then
        log("Can't open words file: " .. (msg or "unknown error"))
    end

    --TODO consider this
    if vlc.object.input() then
        g_subtitles = Subtitles.create()
        g_subtitles_native = Subtitles.create()
        
        local loaded, msg = g_subtitles:load(get_subtitles_path())
        if not loaded then
            log(msg)
            return
        end
        
        local loaded, msg = g_subtitles_native:load(get_subtitles_native_path())
        if not loaded then
            log(msg)
        end
       
        g_osd_channel = vlc.osd.channel_register()
        gui_show_osd_help()
        g_osd_enabled = sia_settings.always_show_subtitles
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
    playback_play()
end

-- menu items 
function menu()
    return {"Settings"}
end

-- a menu element is selected
function trigger_menu(id)

    if id == 1 then
        playback_pause()
        gui_show_dialog_settings()
    elseif id == 2 then
        log("Menu2 clicked")
    end
end


--[[  SIA Functions  ]]--

function g_ignored_words:contains(word)
    for _, w in ipairs(self) do
        if w == word:lower() then
            return true
        end
    end
    return false
end

Subtitles = {}
Subtitles.__index = Subtitles

function Subtitles.create()
  local o = 
  {
      path = nil,
      loaded = false,
      currents = {}, -- indexes of current subtitles

      prev_time = nil, -- start time of previous subtitle
      begin_time = nil, -- start time of current subtitle
      end_time = nil, -- end time of current subtitle
      next_time = nil, -- next subtitle start time

      subtitles = {} -- contains all the subtitles
  }    
  
  setmetatable(o, Subtitles)
  return o
end

function Subtitles:load(spath)
    self.loaded = false

    if is_nil_or_empty(spath) then return false, "cant load subtitles: path is nil" end

    if spath == self.path then
        self.loaded = true
        return false, "cant load subtitles: already loaded"
    end

    self.path = spath

    local data = read_file(self.path)
    if not data then return false end
 
    data = data:gsub("\r\n", "\n") -- fixes issues with Linux
    local srt_pattern = "(%d%d):(%d%d):(%d%d),(%d%d%d) %-%-> (%d%d):(%d%d):(%d%d),(%d%d%d).-\n(.-)\n\n"
    
    -- Special record for calculation simplicity 
    table.insert(self.subtitles, {to_sec(0, 0, 0, 0), to_sec(0, 0, 0, 0), "[START]"})
    
    for h1, m1, s1, ms1, h2, m2, s2, ms2, text in string.gmatch(data, srt_pattern) do
        if not is_nil_or_empty(text) then
            if sia_settings.charset then
                text = vlc.strings.from_charset(sia_settings.charset, text)
            end
            table.insert(self.subtitles, {to_sec(h1, m1, s1, ms1), to_sec(h2, m2, s2, ms2), text})
        end
    end
    
    -- Special record for calculation simplicity
    table.insert(self.subtitles, {to_sec(100, 0, 0, 0), to_sec(100, 0, 0, 0), "[END]"})

    if #self.subtitles == 2 then return false, "cant load subtitles: could not parse" end

    self.loaded = true

    log("loaded subtitles: " .. self.path)

    return true
end

function Subtitles:get_prev_time(time)
    local point_of_replay = self.begin_time + math.max( (self.end_time - self.begin_time) / 3, 0.8 )
    
    -- log( tos(time).." < "..tos(point_of_replay).."\t"..tos(point_of_replay - self.begin_time).."\t"..tos(point_of_replay - time) )
    
    if #self.currents == 0 or time < point_of_replay then
        return self.prev_time
    else
        return self.begin_time
    end
end

function Subtitles:get_next_time(time)
    return self.next_time
end

function Subtitles:get_by_delta(delta)
   return filter_html(self.currents[1] and
        self.subtitles[self.currents[1]+delta] and
        self.subtitles[self.currents[1]+delta][3])
end

-- works only if there is current subtitle!
function Subtitles:get_previous()
    return self:get_by_delta(-1)
end

-- works only if there is current subtitle!
function Subtitles:get_next()
    return self:get_by_delta(1)
end

function Subtitles:get_current()
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
function Subtitles:move(time_beg, time_end)
    if not self.loaded then
        return false, "", 0
    end 

    time_end = time_end or time_beg   

    if self.begin_time and self.end_time and time_beg >= self.begin_time and time_end <= self.end_time then
        return false, self:get_current(), self.end_time-time_beg
    end
    
    self:_fill_currents(time_beg, time_end)

    return true, self:get_current(), self.end_time and self.end_time-time_beg
end

function tos( val )
    return tostring(val or "nil")
end

-- private
function Subtitles:_fill_currents(time_beg, time_end)
    -- there might be several current overlapping subtitles
    self.currents = {}
    
    -- temporary currents to prevent data duplication when 
    -- this function is called in different threads
    local currents = {} 
    
    local first = 1
    
    while first < #self.subtitles and time_beg > self.subtitles[first][2] do
        first = first + 1
    end
    
    local last = first
       
    while last < #self.subtitles and time_end > self.subtitles[last][1] do
        table.insert(currents, last)
        last = last + 1   
    end 
    
    self.currents = currents
    
    self.prev_time = self.subtitles[first - 1][1]
    self.next_time = self.subtitles[last][1]
    
    if first ~= last then        
        self.begin_time = math.min( self.subtitles[first][1], time_beg )
        self.end_time = math.max( self.subtitles[last - 1][2], time_end )
    else
        self.begin_time = self.subtitles[first - 1][2]
        self.end_time = self.subtitles[last][1]
    end
      
    local function dbgprint()  
        log("________________________________________________")
        log("request\t["..tos(time_beg)..","..tos(time_end)..")")
        log(tos(self.prev_time).."\t["..tos(self.begin_time)..","..tos(self.end_time).."]\t"..tos(self.next_time))
        for _, cur in ipairs(self.currents) do
            log("   ["..tos(self.subtitles[cur][1])..","..tos(self.subtitles[cur][2]).."]: "..tos(self.subtitles[cur][3]))
        end
        log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    end

    --dbgprint()
 end

function add_intf_callback()
    if vlc.object.input() then
        vlc.var.add_callback(vlc.object.input(), "intf-event", input_events_handler, 0)
    end
end

function del_intf_callback()
    if vlc.object.input() then
        vlc.var.del_callback(vlc.object.input(), "intf-event", input_events_handler, 0)
    end
end

function add_callbacks()
    if g_callbacks_set then return end
    add_intf_callback()
    vlc.var.add_callback(vlc.object.libvlc(), "key-pressed", key_pressed_handler, 0)
    g_callbacks_set = true
end

function del_callbacks()
    if not g_callbacks_set then return end
    del_intf_callback()
    vlc.var.del_callback(vlc.object.libvlc(), "key-pressed", key_pressed_handler, 0)
    g_callbacks_set = false
end

function change_callbacks()
    if vlc.object.input() then
        vlc.var.add_callback(vlc.object.input(), "intf-event", input_events_handler, 0) -- TODO is it obligatory?
    end
end

function get_vlc_time(input)
  return vlc.var.get(input, "time") - sia_settings.subs_time_shift
end

function input_events_handler(var, old, new, data)

    -- listen to input events only to show subtitles
    if not g_osd_enabled or not g_subtitles.loaded then return end

    -- get current time
    local input = vlc.object.input()
    local current_time = get_vlc_time(input)

    -- if the video was paused by 'again!' button (backspace by default)
    --  then restore initial g_osd_enabled state
    if g_paused_by_btn_again and vlc.playlist.status() ~= "paused" then
        g_paused_by_btn_again = false 
        g_osd_enabled = sia_settings.always_show_subtitles
        
        if not sia_settings.always_show_subtitles then
            g_second_lang_enabled = false
        end    
    end

    local _, subtitle, duration = g_subtitles:move(current_time)
    
    if g_second_lang_enabled and subtitle and subtitle then     
        local _, subtitle_n, duration_n = g_subtitles_native:move(g_subtitles.begin_time, g_subtitles.end_time)
        
        if subtitle_n and duration_n then
            subtitle = subtitle .. "\n\n" .. subtitle_n
        end
    end
    
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
    elseif new == sia_settings.key_enable_second_lang then
        enable_second_lang()
    elseif new == sia_settings.key_always_show_subs then
        always_show_subs()
    end
end

function goto_prev_subtitle()
    local input = vlc.object.input()
    if not input then return end

    local curr_time = get_vlc_time(input)

    g_subtitles:move(curr_time)

    playback_goto(input, g_subtitles:get_prev_time(curr_time))
end

function goto_next_subtitle()
    local input = vlc.object.input()
    if not input then return end

    local curr_time = get_vlc_time(input)

    g_subtitles:move(curr_time)

    playback_goto(input, g_subtitles:get_next_time(curr_time))
end

function subtitle_again()
    local input = vlc.object.input()
    if not input then return end

    local current_time = get_vlc_time(input)

    playback_pause()
    g_paused_by_btn_again = true
    g_osd_enabled = true

    g_subtitles:move(current_time)

    playback_goto(input, g_subtitles:get_prev_time(current_time))
end

function enable_second_lang()
    if g_subtitles_native.loaded then
        g_second_lang_enabled = not g_second_lang_enabled;
    end
end

function always_show_subs()
    sia_settings.always_show_subtitles = not sia_settings.always_show_subtitles;
    g_osd_enabled = sia_settings.always_show_subtitles;
end

function subtitle_save()
    local input = vlc.object.input()
    if not input then return end

    g_subtitles:move(get_vlc_time(input))

    local curr_subtitle = g_subtitles:get_current()
    if curr_subtitle then
        playback_pause()
        gui_show_dialog_save_word(curr_subtitle)
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
    vlc.osd.message("[i] - save\n\n[backspace] - again!\n\n[ctrl+backspace] - second language\n\n[r] - always show subtitles", vlc.osd.channel_register(), "center", duration)
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

function gui_dict_from_list(found_dicts, list)
    for k,_ in pairs(list) do
        return found_dicts[k].filename -- return first in list
    end
    return nil
end

function gui_clear_dialog()
    --g_dlg.dlg:hide()

    for _,w in pairs(g_dlg.w) do
        g_dlg.dlg:del_widget(w)
    end

    g_dlg.w = {}

    gui_del_words_buttons()

    --g_dlg.dlg:show()
end

function gui_choose_dict()
    del_callbacks()
    g_dict:load(gui_dict_from_list(g_found_dicts, g_dlg.w.list_dict:get_selection()))
    gui_update_list_dicts()
    add_callbacks()
end

function gui_create_dialog_settings()
    g_dlg.w.lbl_found_dicts = g_dlg.dlg:add_label("",1,1,10,1)
    g_dlg.w.list_dict = g_dlg.dlg:add_list(1, 2, 10, 5)
    g_dlg.w.lbl_note = g_dlg.dlg:add_label("Dictionaries marked with '*' have known format",1,7,10,1)
    g_dlg.w.btn_choose = g_dlg.dlg:add_button("Choose", gui_choose_dict, 5,8,2,1)
end

function gui_show_dialog_settings()
    del_intf_callback() -- HACK avoid vlc hanging
    if g_current_dialog ~= "settings" then
        log("creating dialog: settings")
        if g_dlg.dlg then
            gui_clear_dialog()
        else
            log("creating dialog for the first time")
            g_dlg.dlg = vlc.dialog("Say It Again " .. g_version)
            g_dlg.w = {} -- widgets
        end

        gui_create_dialog_settings()
    end
    
    local lbl = "Dictionaries found in '"..(sia_settings.dict_dir or "n/a").."':"
    lbl = lbl .. ("&nbsp;"):rep(70)

    g_dlg.w.lbl_found_dicts:set_text(lbl)

    gui_update_list_dicts()

    g_current_dialog = "settings"
    g_dlg.dlg:update()

    add_intf_callback()

    return true
end

function gui_update_list_dicts()
    if not g_dlg.w or not g_dlg.w.list_dict then return end

    g_dlg.w.list_dict:clear()

    for i,dict in ipairs(g_found_dicts) do
        local is_current = g_dict.loaded and (dict.full_name == g_dict.name)
        g_dlg.w.list_dict:add_value((is_current and ">" or "  ") .. (dict.is_known_format and "*" or " ") .. dict.full_name, i)
    end
end

function gui_create_dialog_save_word()
    g_dlg.w.lbl_context = g_dlg.dlg:add_label("<b>1. Edit<br />context:</b>",1,1,1,4)
    g_dlg.w.lbl_prev_s = g_dlg.dlg:add_label("",3,1,12,1)
    g_dlg.w.btn_add_prev =g_dlg.dlg:add_button("|<--", gui_add_prev_sub, 2,1,1,1)
    g_dlg.w.tb_curr_s = g_dlg.dlg:add_text_input("",2,2,13,1)
    g_dlg.w.tb_curr_s2 = g_dlg.dlg:add_text_input("",2,3,13,1)
    g_dlg.w.lbl_next_s = g_dlg.dlg:add_label("",3,4,12,1)
    g_dlg.w.btn_add_next =g_dlg.dlg:add_button("-->|", gui_add_next_sub, 2,4,1,1)

    g_dlg.w.lbl_add_word = g_dlg.dlg:add_label("<b>2. Choose a word to look it up:</b>",1,5,10,1)
    -- (words buttons here)
    g_dlg.w.lbl_or_enter = g_dlg.dlg:add_label("or enter:",1,10,1,1)
    g_dlg.w.tb_word = g_dlg.dlg:add_text_input("",2,10,8,1)
    g_dlg.w.btn_lookup =g_dlg.dlg:add_button("look up", gui_lookup_word, 10, 10, 1, 1)
    g_dlg.w.lbl_choose_def = g_dlg.dlg:add_label("<b>3. Choose appropriate definition(s):</b>",1,11,10,1)
    g_dlg.w.list_def = g_dlg.dlg:add_list(1, 12, 10, 10)

    g_dlg.w.btn_get_tr = g_dlg.dlg:add_button("edit def", function() g_dlg.w.tb_def:set_text(gui_def2str(g_dlg.w.list_def:get_selection())) end, 1, 22, 1, 1)
    g_dlg.w.tb_def = g_dlg.dlg:add_text_input("",2,22,8,1)
    g_dlg.w.btn_save = g_dlg.dlg:add_button("SAVE >>>", gui_save_word, 10, 22, 1, 1)

    g_dlg.w.lbl_file = g_dlg.dlg:add_label("File '" .. (sia_settings.words_file_path or "n/a") .. "':",11,5,4,1)
    g_dlg.w.list_file = g_dlg.dlg:add_list(11, 6, 4, 18)
end

function gui_add_prev_sub()
  g_dlg.w.tb_curr_s:set_text(g_subtitles:get_by_delta(g_dlg.prev_sub_diff) .. " " .. g_dlg.w.tb_curr_s:get_text())
  
  if g_second_lang_enabled then
     g_dlg.w.tb_curr_s2:set_text(g_subtitles_native:get_by_delta(g_dlg.prev_sub_diff) .. " " .. g_dlg.w.tb_curr_s2:get_text())
  end
  
  g_dlg.prev_sub_diff = g_dlg.prev_sub_diff - 1
  
  local nextsub = g_subtitles:get_by_delta(g_dlg.prev_sub_diff)
  
  if g_second_lang_enabled then
     nextsub = nextsub .. " / " .. g_subtitles_native:get_by_delta(g_dlg.prev_sub_diff)
  end
  
  g_dlg.w.lbl_prev_s:set_text("<font color='grey'>" .. nextsub .. "</font>")
end

function gui_add_next_sub()
  g_dlg.w.tb_curr_s:set_text(g_dlg.w.tb_curr_s:get_text() .. " " .. g_subtitles:get_by_delta(g_dlg.next_sub_diff))
  
  if g_second_lang_enabled then
     g_dlg.w.tb_curr_s2:set_text(g_dlg.w.tb_curr_s2:get_text() .. " " .. g_subtitles_native:get_by_delta(g_dlg.next_sub_diff))
  end
  
  g_dlg.next_sub_diff = g_dlg.next_sub_diff + 1
  
  local nextsub = g_subtitles:get_by_delta(g_dlg.next_sub_diff)
  
  if g_second_lang_enabled then
     nextsub = nextsub .. " / " .. g_subtitles_native:get_by_delta(g_dlg.next_sub_diff)
  end
  
  g_dlg.w.lbl_next_s:set_text("<font color='grey'>" .. nextsub .. "</font>")
end

function gui_show_dialog_save_word(curr_subtitle)
    del_intf_callback() -- HACK avoid vlc hanging
    if g_current_dialog ~= "save_word" then
        log("creating dialog: save_word")
        if g_dlg.dlg then
            gui_clear_dialog()
        else
            log("creating dialog for the first time")
            g_dlg.dlg = vlc.dialog("Say It Again " .. g_version)
            g_dlg.w = {} -- widgets
        end

        gui_create_dialog_save_word()
    else
        gui_del_words_buttons()
    end

    g_dlg.prev_sub_diff = 0
    g_dlg.next_sub_diff = 0
    
    gui_add_prev_sub()
    gui_add_next_sub()
    g_dlg.w.tb_curr_s:set_text(curr_subtitle)
    g_dlg.w.tb_curr_s2:set_text( "" )
    
    local _, subtitle_n, _ = g_subtitles_native:move(g_subtitles.begin_time, g_subtitles.end_time)
  
    if g_second_lang_enabled and subtitle_n then
        g_dlg.w.tb_curr_s2:set_text( subtitle_n )
    end

    g_dlg.btns = gui_get_words_buttons(curr_subtitle, 6)
    
    g_dlg.w.list_def:clear()
    g_dlg.w.list_file:clear()

    if not g_words_file then
        g_dlg.w.btn_save:set_text("[CANT SAVE]")
        g_dlg.w.list_file:add_value("could not open the file :(", 0)
    else
        g_words_file:seek("set")
        for line in g_words_file:lines() do
            g_dlg.w.list_file:add_value(line, 0)
        end 
    end

    g_current_dialog = "save_word"
    g_dlg.dlg:update()
    add_intf_callback()
    return true
end

-- takes the word from tb_word and fills list_def with definitions
function gui_lookup_word()
    g_dlg.w.list_def:clear()

    if not g_dict.loaded then
        g_dlg.w.list_def:add_value("No dictionary loaded :(", 0)
        g_dlg.w.list_def:add_value("But you can still enter definition manually", 0)
        return false
    end

    local word = g_dlg.w.tb_word:get_text()
    local def, lemma = g_dict:find_tbl(word)
    if def and #def > 0 then
        g_dlg.tr = def.tr
        for i,v in ipairs(def) do
            g_dlg.w.list_def:add_value(v, i)
        end

        g_dlg.w.tb_word:set_text(lemma)
    else
        g_dlg.w.list_def:add_value("no result :(", 0)
        return false
    end

    return true
end

function gui_save_word()
    if not g_words_file then
        log("file not open")
        return
    end

    local word = g_dlg.w.tb_word:get_text()
    local def = g_dlg.w.tb_def:get_text()

    if is_nil_or_empty(def) then
        def = gui_def2str(g_dlg.w.list_def:get_selection())
    end

    if is_nil_or_empty(word) or is_nil_or_empty(def) then
        log("either no word or no definition selected")
        return
    end

    local transcription = g_dlg.tr and ("["..g_dlg.tr.."]") or ""

    local context = string.gsub(g_dlg.w.tb_curr_s:get_text(), "\n", " ") or ""
    local context_n = string.gsub(g_dlg.w.tb_curr_s2:get_text(), "\n", " ") or ""
    local tags = get_title() or ""

    local res = context .. "\t" .. context_n .. "\t" .. word .. "\t" .. transcription .. "\t" .. def
    
    g_dlg.w.tb_def:set_text("") -- clear custom definition

    g_dlg.w.list_file:add_value(res, 0)
    g_words_file:write(res .. "\r\n")
    g_words_file:flush()
end

function gui_get_words_buttons(subtitle, cur_line)
    local btns = {}
    local i = 1
    -- match words that are at least 3 chars long and may contain hyphens
    -- we don't use '%a' here because it requires changing system locale to match non-ascii chars like 'á'
    for word in string.gmatch(subtitle, "[^%c%p%s%d][^%c%s%d]+[^%c%p%s%d]") do
        if not g_ignored_words:contains(word) then
            local lemma = word:lower()
            if g_wordnet and g_wordnet.loaded then -- try to search for lemma
                lemma = g_wordnet:get_lemma(word:lower())
            end
            table.insert(btns, g_dlg.dlg:add_button(word, function() g_dlg.w.tb_word:set_text(lemma) gui_lookup_word() end, i, cur_line, 1, 1))
            i = i + 1
            if i > 10 then
                cur_line = cur_line + 1
                i = 1
            end
        end
    end
    return btns
end

function gui_del_words_buttons()
    if g_dlg.dlg and g_dlg.btns then
        for _,btn in ipairs(g_dlg.btns) do
            g_dlg.dlg:del_widget(btn)
        end
    end
    g_dlg.btns = nil
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
    if not metas then return string.match(item:name() or "", "^(.*)%.") or item:name() end

    if metas["title"] then
        return metas["title"]
    else
        return string.match(item:name() or "", "^(.*)%.") or item:name()
    end
end

function uri_to_path(uri, is_unix_platform)
    if is_nil_or_empty(uri) then return "" end
    local path
    if not is_unix_platform then
        if uri:match("file://[^/]") then -- path to windows share
            path = uri:gsub("file://", "\\\\")
        else
            path = uri:gsub("file:///", "")
        end
        return path:gsub("/", "\\")
    else
        return uri:gsub("file://", "")
    end
end

function is_unix_platform()
    if string.match(vlc.config.homedir(), "^/") then
        return true
    else
        return false
    end
end

function get_subtitles_path_impl(ext)
    local item = get_input_item()
    if not item then return "" end

    local path_to_video = uri_to_path(vlc.strings.decode_uri(item:uri()), is_unix_platform())
    log(path_to_video)

    return path_to_video:gsub("\.[^.]*$", ext)
end

function get_subtitles_path()
    return get_subtitles_path_impl( ".srt" )
end

function get_subtitles_native_path()
    return get_subtitles_path_impl( "_2.srt" )
end

function filter_html(str)
    local res = str or ""
    res = string.gsub(res, "&apos;", "'")
    res = string.gsub(res, "<.->", "")
    return res
end

function trim(str)
    if not str then return "" end
    return str:match("^%s*(.*%S)") or ""
end

function to_sec(h,m,s,ms)
    return tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) + tonumber(ms)/1000
end

function playback_goto(input, time)
    if input and time then
        vlc.var.set(input, "time", time + sia_settings.subs_time_shift)
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

function read_file(path, binary)
    if is_nil_or_empty(path) then
        log("Can't open file: Path is empty")
        return nil
    end

    local f, msg = io.open(path, "r" .. (binary and "b" or ""))

    if not f then
        log("Can't open file '"..path.."': ".. (msg or "unknown error"))
        return nil
    end

    local res = f:read("*all")

    f:close()

    return res
end

function is_nil_or_empty(str)
    return not str or str == ""
end


--[[ Work with dictionary ]]--

-- parses .idx file
-- file format (binary data): entry_name\0 offset(4bytes) size(4bytes)
function g_dict:_load_index(path)
    if not path then return nil end

    log("Loading index: "..(path..".idx"))
    local idx_str = read_file(path..".idx", true)
    if not idx_str then return nil end

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

-- returns name and format table
function g_dict:load_info(path)
    if not path then return nil end

    local ifo_str = read_file(path..".ifo")
    if not ifo_str then return nil end

    local bookname = ifo_str:match("bookname=(.-)\n")
    if is_nil_or_empty(bookname) then
        log("Cant read bookname")
        return nil
    end

    for i,fmt in ipairs(g_dict_fmt) do
        if bookname:match(fmt.pattern) then
            --log("matched pattern: "..fmt.pattern)
            return bookname, fmt
        end
    end

    return bookname, nil
end

function g_dict:load(path)
    if is_nil_or_empty(path) then return false end

    self:destroy()

    local name, fmt = self:load_info(path)
    if not name or not fmt then
        log("cant load dictionary")
        return false
    end

    log("Using dictionary: ".. name)
    self.format = fmt
    self.name = name

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
    self.name = nil
    self.idx_table = {}
    if self.dict_file then self.dict_file:close() end
    self.dict_file = nil
    self.format = nil
end

function g_dict:find_raw(word)
    if not self.loaded then return nil end

    local lemma = word
    local idx_value = self.idx_table[lemma]

    if not idx_value and g_wordnet and g_wordnet.loaded then -- try to search for lemma
        lemma = g_wordnet:get_lemma(word)
        if lemma then idx_value = self.idx_table[lemma] end
    end

    if idx_value then
        self.dict_file:seek("set", idx_value[1])
        local entry, msg = self.dict_file:read(idx_value[2])

        if not entry then
            log("Error reading dictionary entry: "..(msg or "unknown error"))
            return nil
        end
        return entry, lemma
    end

    return nil
end

function g_dict:find_tbl(word)
    local str, lemma = self:find_raw(word)
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
    return res, lemma
end

-- returns paths of dictionaries files found in given directory
function g_dict:get_dict_paths(directory)
    if is_nil_or_empty(directory) or not vlc.net.stat(directory) then return nil end
    local res = {}
    for _,v in ipairs(vlc.net.opendir(directory)) do
        local fname = v:match("(.*)%.ifo$")
        if fname then
            table.insert(res, directory.."/"..fname)
        end
    end
    return res
end

-- returns a table with the following fields: {filename, full_name, is_known_format, fmt_table}
function g_dict:get_dicts(paths)
    if not paths then return {} end
    local res = {}
    for _,v in ipairs(paths) do
        -- check if all three dict files are present
        if vlc.net.stat(v..".dict") and vlc.net.stat(v..".idx") then
            local full_name, fmt = self:load_info(v)
            if full_name and fmt then
                --log(full_name)
                table.insert(res, {filename=v, full_name=full_name, is_known_format=(fmt.pattern ~= ".*"), fmt_table=fmt})
            end
        end
    end
    return res
end


--[[  WordNet  ]]--

function g_wordnet:load(wordnet_path)
    self.loaded = false

    if is_nil_or_empty(wordnet_path) then return false end

    log("Initializing WordNet...")

    local posn = {"verb", "adj", "adv", "noun"}
    for i,pos in ipairs(posn) do
        self.poss[i] = {name = pos}
        self.poss[i].exc = self:_load_exc_file(wordnet_path .. "/" .. pos .. ".exc")
        self.poss[i].idx = self:_load_index_file(wordnet_path .. "/" .. "index." .. pos)

        if not self.poss[i].exc or not self.poss[i].idx then
            self:destroy()
            log("Can't initialize WordNet")
            return false
        end
    end

    log("WordNet initialized successfully!")

    self.loaded = true
    return true
end

function g_wordnet:destroy()
    self.loaded = false
    self.poss = {}
end

function g_wordnet:get_lemma(word)
    if not word or word:len() <= 1 then return word end

    for _,pos in ipairs(self.poss) do
        if pos.name == "noun" and word:match("ss$") then
            return word
        end

        if pos.idx[word] then return word end
        if pos.exc[word] then return pos.exc[word] end

        for _,rule in ipairs(self.rules[pos.name]) do
            local new_word, subsn = word:gsub(rule[1].."$", rule[2])
            if subsn > 0 and pos.idx[new_word] then return new_word end
        end
    end

    return word
end

function g_wordnet:_load_exc_file(path)
    local data = read_file(path)
    if not data then return nil end
    local res = {}
    for w,l in data:gmatch("(%S+)%s(%S+)\n") do
        res[w] = l
    end
    return res
end

function g_wordnet:_load_index_file(path)
    local data = read_file(path)
    if not data then return nil end
    local res = {}
    for w in data:gmatch("\n(%S+)") do
        res[w] = true
    end
    return res
end