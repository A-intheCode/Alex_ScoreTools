-- @description Alex Score Tools_set_dynamics
-- @version 11.11
-- @author A-intheCode
-- @about
--   Description: Adds a Anchor based Dynamics programming feature to Reaper as external script.
--   Lizenz: GPLv3
-- @changelog
--   # 11.11 (2026-03-31)
     changelog integration into the lua script.
--   # 11.10 (2026-03-31)
--   Copy Paste Function was included. 
--   (you can now copy and paste from one Midi Item to another - all markers will get copied and the curves will regenerated.) 
--   The Help Description was changed and extended. 
--   The Score Dynamics Tool can now be docked to the Reaper Windows and the State of the docking position will be stored ...
--   # 11.00.04 Inital Release

-- [[
--  Name: Alex Score Tools_set_dynamics
--  Description: Adds a Anchor based Dynamics programming feature to Reaper as external script.
--  Author: A-intheCode

--  License: GNU General Public License v3.0
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program. If not, see <https://www.gnu.org/licenses/>.
-- ]]

-- Score Dynamics v11.11
 -- BASED ON v11.10 STABLE
 

 local last_mouse_cap = 0 
 local selected_grid_idx = 4  
 local cc_a, cc_b = 1, 11  
 local phrasing_active = true 
 local phrasing_intensity = 0.5  
 local humanize_intensity = 0.3  
 local stress_factor = 0.5  
 local vel_sensitivity = 0.8  
 local show_help = false 
 
 -- --- DATA BUFFER ---
 local dynamic_buffer = {} 

 -- --- DOCKING & POSITION MEMORY ---
 local section = "SCORE_DYNAMICS_MASTER"
 local last_dock = tonumber(reaper.GetExtState(section, "dock")) or 0
 local last_x = tonumber(reaper.GetExtState(section, "x")) or 100
 local last_y = tonumber(reaper.GetExtState(section, "y")) or 100

 local grid_options = { 
     {label = "1/2",   val = 2.0}, {label = "1/4",   val = 1.0}, 
     {label = "1/8",   val = 0.5}, {label = "1/16",  val = 0.25}, 
     {label = "1/32",  val = 0.125}, {label = "1/64",  val = 0.0625}, 
     {label = "1/128", val = 0.03125} 
 } 

 local buttons = { 
     {label = "pppp", c1 = 8,  c11 = 12,  color = {0.1, 0.1, 0.4}}, 
     {label = "ppp",  c1 = 20, c11 = 25,  color = {0.1, 0.2, 0.6}}, 
     {label = "pp",   c1 = 35, c11 = 40,  color = {0.2, 0.3, 0.8}}, 
     {label = "p",    c1 = 50, c11 = 55,  color = {0.3, 0.5, 0.9}}, 
     {label = "mp",   c1 = 65, c11 = 70,  color = {0.2, 0.7, 0.4}}, 
     {label = "mf",   c1 = 80, c11 = 85,  color = {0.7, 0.7, 0.2}}, 
     {label = "f",    c1 = 95, c11 = 100, color = {0.9, 0.5, 0.1}}, 
     {label = "ff",   c1 = 110, c11 = 115,color = {0.9, 0.2, 0.1}}, 
     {label = "fff",  c1 = 120, c11 = 120,color = {0.8, 0.1, 0.0}}, 
     {label = "ffff", c1 = 127, c11 = 127,color = {0.6, 0.0, 0.0}} 
 } 

 -- --- HELPERS & MATH --- 
 local function get_pitch_at_pos(take, ppq) 
     local _, note_cnt = reaper.MIDI_CountEvts(take) 
     for i = 0, note_cnt - 1 do 
         local _, _, _, start_ppq, end_ppq, _, pitch, _ = reaper.MIDI_GetNote(take, i) 
         if ppq >= start_ppq and ppq <= end_ppq then return pitch end 
     end 
     return nil 
 end 

 local function get_smart_val(v1, v2, ratio, pitch_delta, seed_base) 
     local v = v1 + (v2 - v1) * ratio 
     if phrasing_active then 
         local s = (1 - math.cos(ratio * math.pi)) / 2 
         v = v1 + (v2 - v1) * (ratio + (s - ratio) * phrasing_intensity) 
     end 
     if stress_factor > 0 and pitch_delta ~= 0 then 
         local amp = (pitch_delta / 12) * 24 * stress_factor  
         local sine_mod = math.sin(ratio * math.pi * 1.5) * math.exp(-ratio * 2) 
         v = v + (sine_mod * amp) 
     end 
     if humanize_intensity > 0 then 
         math.randomseed(math.floor(seed_base + ratio * 5000)) 
         v = v + (math.random() - 0.5) * 12 * humanize_intensity 
     end 
     return math.max(0, math.min(127, math.floor(v + 0.5))) 
 end 

 -- --- CORE ACTIONS --- 

 local function smart_reblend_all() 
     local ed = reaper.MIDIEditor_GetActive() 
     local take = reaper.MIDIEditor_GetTake(ed) 
     if not take then return end 
     reaper.Undo_BeginBlock() 
     
     local _, midi_string = reaper.MIDI_GetAllEvts(take, "") 
     local new_midi_table, string_pos, acc_offset = {}, 1, 0 
     while string_pos <= #midi_string do 
         local offset, flag, msg, next_pos = string.unpack("<i4Bs4", midi_string, string_pos) 
         if #msg > 0 and msg:byte(1) == 0xFF and msg:byte(2) == 0x07 then acc_offset = acc_offset + offset 
         else table.insert(new_midi_table, string.pack("<i4Bs4", offset + acc_offset, flag, msg)) acc_offset = 0 end 
         string_pos = next_pos 
     end 
     reaper.MIDI_SetAllEvts(take, table.concat(new_midi_table)) 

     local anchors = {} 
     local _, count = reaper.MIDI_CountEvts(take) 
     for i = 0, count - 1 do 
         local _, _, _, ppq, type, msg = reaper.MIDI_GetTextSysexEvt(take, i) 
         if type == 15 then 
             local v1, v2 = msg:match(":(%d+):(%d+)") 
             if v1 and v2 then table.insert(anchors, {ppq = ppq, c1 = tonumber(v1), c2 = tonumber(v2)}) end 
         end 
     end 
     if #anchors < 2 then reaper.Undo_EndBlock("Abort", -1) return end 
     table.sort(anchors, function(a,b) return a.ppq < b.ppq end) 

     local cc_count = reaper.MIDI_CountEvts(take) 
     for j = cc_count - 1, 0, -1 do 
         local _, _, _, _, _, _, m, _ = reaper.MIDI_GetCC(take, j) 
         if m == cc_a or m == cc_b then reaper.MIDI_DeleteCC(take, j) end 
     end 

     local grid_ppq = grid_options[selected_grid_idx].val * 960 * 4 
     for i = 1, #anchors - 1 do 
         local a1, a2 = anchors[i], anchors[i+1] 
         local dur = a2.ppq - a1.ppq 
         local steps = math.floor(dur / grid_ppq) 
         local p_start = get_pitch_at_pos(take, a1.ppq) 
         local p_end = get_pitch_at_pos(take, a2.ppq) 
         local delta = (p_start and p_end) and (p_end - p_start) or 0 
         for s = 0, steps do 
             local cur = a1.ppq + (s * grid_ppq) 
             if cur <= a2.ppq then 
                 local ratio = (cur - a1.ppq) / dur 
                 reaper.MIDI_InsertCC(take, false, false, cur, 176, 0, cc_a, get_smart_val(a1.c1, a2.c1, ratio, delta, a1.c1 + cur)) 
                 reaper.MIDI_InsertCC(take, false, false, cur, 176, 0, cc_b, get_smart_val(a1.c2, a2.c2, ratio, delta, a1.c2 + cur)) 
             end 
         end 
     end 
     reaper.MIDI_Sort(take) 

     local _, midi_string = reaper.MIDI_GetAllEvts(take, "") 
     local final_midi_table, f_pos = {}, 1 
     while f_pos <= #midi_string do 
         local offset, flag, msg, next_pos = string.unpack("<i4Bs4", midi_string, f_pos) 
         if #msg == 3 and (msg:byte(1) & 0xF0) == 0xB0 then 
             local cn = msg:byte(2) 
             if cn == cc_a or cn == cc_b then flag = (flag & 0x0F) | (5 << 4) end 
         end 
         table.insert(final_midi_table, string.pack("<i4Bs4", offset, flag, msg)) 
         f_pos = next_pos 
     end 
     reaper.MIDI_SetAllEvts(take, table.concat(final_midi_table)) 

     local _, _, _, extevntcnt = reaper.MIDI_CountEvts(take) 
     for j = extevntcnt - 1, 0, -1 do 
         local _, _, _, ppq, type, msg = reaper.MIDI_GetTextSysexEvt(take, j) 
         if type == 15 then 
             local mark = msg:match("dynamic%s+([%a%d]+)") 
             if mark then reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 7, mark) end 
         end 
     end 
     reaper.MIDI_Sort(take) 
     reaper.Undo_EndBlock("Re-Blend", -1) 
     reaper.UpdateArrange() 
 end 

 local function copy_paste_logic()
     local ed = reaper.MIDIEditor_GetActive()
     local take = reaper.MIDIEditor_GetTake(ed)
     if not take then return end
     if #dynamic_buffer == 0 then
         local current_anchors = {}
         local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
         for i = 0, text_cnt - 1 do
             local _, _, _, ppq, type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
             if type == 15 or type == 7 then table.insert(current_anchors, {ppq=ppq, type=type, msg=msg}) end
         end
         if #current_anchors > 0 then dynamic_buffer = current_anchors end
     else
         reaper.Undo_BeginBlock()
         local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
         for i = text_cnt - 1, 0, -1 do
             local _, _, _, _, type, _ = reaper.MIDI_GetTextSysexEvt(take, i)
             if type == 15 or type == 7 then reaper.MIDI_DeleteEvt(take, i) end
         end
         for _, data in ipairs(dynamic_buffer) do reaper.MIDI_InsertTextSysexEvt(take, false, false, data.ppq, data.type, data.msg) end
         reaper.MIDI_Sort(take); dynamic_buffer = {} 
         reaper.Undo_EndBlock("Paste Dynamics", -1)
         smart_reblend_all() 
     end
 end

 local function emphasize_velocity() 
     local ed = reaper.MIDIEditor_GetActive() 
     local take = reaper.MIDIEditor_GetTake(ed) 
     if not take then return end 
     local anchors = {} 
     local _, count = reaper.MIDI_CountEvts(take) 
     for i = 0, count - 1 do 
         local _, _, _, ppq, type, msg = reaper.MIDI_GetTextSysexEvt(take, i) 
         if type == 15 then 
             local v1, v2 = msg:match(":(%d+):(%d+)") 
             if v1 and v2 then table.insert(anchors, {ppq = ppq, c1 = tonumber(v1), c2 = tonumber(v2)}) end 
         end 
     end 
     if #anchors < 2 then return end 
     table.sort(anchors, function(a,b) return a.ppq < b.ppq end) 
     reaper.Undo_BeginBlock() 
     local _, note_count = reaper.MIDI_CountEvts(take) 
     for i = 0, note_count - 1 do 
         local _, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i) 
         for j = 1, #anchors - 1 do 
             local a1, a2 = anchors[j], anchors[j+1] 
             if start_ppq >= a1.ppq and start_ppq <= a2.ppq then 
                 local final_vel 
                 if vel_sensitivity <= 0 then final_vel = 60 
                 else 
                     local ratio = (start_ppq - a1.ppq) / (a2.ppq - a1.ppq) 
                     local p_start = get_pitch_at_pos(take, a1.ppq) 
                     local p_end = get_pitch_at_pos(take, a2.ppq) 
                     local delta = (p_start and p_end) and (p_end - p_start) or 0 
                     local target_vel = get_smart_val(a1.c1, a2.c1, ratio, delta, a1.c1 + start_ppq) 
                     final_vel = math.floor(vel * (1 - vel_sensitivity) + target_vel * vel_sensitivity + 0.5) 
                 end 
                 reaper.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, nil, math.max(1, math.min(127, final_vel)), true) 
                 break 
             end 
         end 
     end 
     reaper.MIDI_Sort(take); reaper.Undo_EndBlock("Emphasize Velocity", -1); reaper.UpdateArrange() 
 end 

 -- --- GUI --- 
 function Main() 
     local mouse_click = (gfx.mouse_cap == 1 and last_mouse_cap == 0) 
     
     if show_help then 
         gfx.set(0.05, 0.05, 0.05, 0.98); gfx.rect(0, 0, gfx.w, gfx.h, 1) 
         gfx.set(1, 1, 1, 1); gfx.setfont(1, "Arial", 14) 
         local help_text = { 
             "SCORE DYNAMICS v11.10 - MANUAL", 
             "---------------------------------------------------", 
             "1. INSERT DYNAMICS", 
             "Set Edit-Cursor in MIDI Editor and click a button.", 
             "Creates a hidden data marker and a visible label.", 
             "", 
             "2. RE-BLEND ALL", 
             "Calculates smooth transitions between all markers.", 
             "Targets CC A and CC B simultaneously.", 
             "", 
             "3. COPY / PASTE", 
             "- Click COPY DATA in source item.", 
             "- Switch to target item, click PASTE DATA.", 
             "You have to delete all old markers (Notation Events",
             "and Text Events) before pasting the Data.", 
             "", 
             "4. MODULATORS", 
             "- Phrasing: Simulates musical 'breathing'.", 
             "- Stress: Higher pitches get more intensity.", 
             "- Vel-Sens: Blends MIDI velocity into logic.", 
             "", 
             "5. GRID", 
             "Defines the resolution of the generated CC curve.", 
             "---------------------------------------------------", 
             "CLICK ANYWHERE TO CLOSE" 
         } 
         for i, line in ipairs(help_text) do 
             gfx.x, gfx.y = 15, 25 + (i*19); gfx.drawstr(line) 
         end 
         if mouse_click then show_help = false end 
     else 
         for i, btn in ipairs(buttons) do 
             local x, y, w, h = 10, (i-1)*26 + 10, 120, 22 
             gfx.set(btn.color[1], btn.color[2], btn.color[3], 1); gfx.rect(x, y, w, h, 1) 
             gfx.set(1, 1, 1, 1); gfx.x, gfx.y = x + 40, y + 4; gfx.drawstr(btn.label) 
             if mouse_click and gfx.mouse_x >= x and gfx.mouse_x <= x+w and gfx.mouse_y >= y and gfx.mouse_y <= y+h then 
                 local ed = reaper.MIDIEditor_GetActive() 
                 local take = reaper.MIDIEditor_GetTake(ed) 
                 if take then 
                     local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition()) + 0.5) 
                     reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 15, string.format("dynamic %s :%d:%d", btn.label, btn.c1, btn.c11)) 
                     reaper.MIDI_InsertCC(take, false, false, ppq, 176, 0, cc_a, btn.c1) 
                     reaper.MIDI_InsertCC(take, false, false, ppq, 176, 0, cc_b, btn.c11) 
                     reaper.MIDI_Sort(take) 
                 end 
             end 
         end 
         
         local cx = 140 
         gfx.set(0.4, 0.4, 0.4, 1); gfx.rect(cx, 10, 80, 22, 1); gfx.set(1,1,1,1) 
         gfx.x, gfx.y = cx+18, 14; gfx.drawstr("HELP") 
         if mouse_click and gfx.mouse_x >= cx and gfx.mouse_x <= cx+80 and gfx.mouse_y >= 10 and gfx.mouse_y <= 32 then show_help = true end 

         gfx.set(0.2, 0.2, 0.2, 1); gfx.rect(cx, 36, 80, 22, 1); gfx.set(1,1,1,1) 
         gfx.x, gfx.y = cx+5, 40; gfx.drawstr("CC A: " .. cc_a) 
         if mouse_click and gfx.mouse_x >= cx and gfx.mouse_x <= cx+80 and gfx.mouse_y >= 36 and gfx.mouse_y <= 58 then 
             local ok, val = reaper.GetUserInputs("CC A", 1, "Num:", tostring(cc_a)) 
             if ok then cc_a = tonumber(val) or 1 end 
         end 
         gfx.set(0.2, 0.2, 0.2, 1); gfx.rect(cx, 62, 80, 22, 1); gfx.set(1,1,1,1) 
         gfx.x, gfx.y = cx+5, 66; gfx.drawstr("CC B: " .. cc_b) 
         if mouse_click and gfx.mouse_x >= cx and gfx.mouse_x <= cx+80 and gfx.mouse_y >= 62 and gfx.mouse_y <= 84 then 
             local ok, val = reaper.GetUserInputs("CC B", 1, "Num:", tostring(cc_b)) 
             if ok then cc_b = tonumber(val) or 11 end 
         end 

         gfx.set(0.8, 0.8, 0.8, 1); gfx.setfont(1, "Arial", 16)
         gfx.x, gfx.y = cx+12, 103; gfx.drawstr("Phrasing:") 

         local function draw_slider(y, val, label, color) 
             gfx.set(0.2, 0.2, 0.2, 1); gfx.rect(cx, y, 80, 15, 1) 
             gfx.set(color[1], color[2], color[3], 1); gfx.rect(cx, y, 80 * val, 15, 1) 
             if gfx.mouse_cap == 1 and gfx.mouse_x >= cx and gfx.mouse_x <= cx+80 and gfx.mouse_y >= y and gfx.mouse_y <= y+15 then val = (gfx.mouse_x - cx) / 80 end 
             gfx.set(1,1,1,1); gfx.setfont(1, "Arial", 11); gfx.x, gfx.y = cx+5, y + 18; gfx.drawstr(label .. ": " .. math.floor(val * 100) .. "%") 
             return val 
         end 
         phrasing_intensity = draw_slider(140, phrasing_intensity, "Phr-Int", {0.2, 0.6, 1}) 
         humanize_intensity = draw_slider(180, humanize_intensity, "Hum-Int", {1, 0.6, 0.2}) 
         stress_factor = draw_slider(220, stress_factor, "Stress", {0.8, 0.2, 0.8}) 
         vel_sensitivity = draw_slider(260, vel_sensitivity, "Vel-Sens", {0.2, 0.9, 0.6}) 

         gfx.setfont(1, "Arial", 16) 
         local bx, by = 10, #buttons * 26 + 30  
         gfx.set(0.2, 0.8, 0.3, 1); gfx.rect(bx, by, 210, 30, 1) 
         gfx.set(0, 0, 0, 1); gfx.x, gfx.y = bx + 55, by + 8; gfx.drawstr("RE-BLEND ALL") 
         if mouse_click and gfx.mouse_x >= bx and gfx.mouse_x <= bx+210 and gfx.mouse_y >= by and gfx.mouse_y <= by+30 then smart_reblend_all() end 
         
         local cby = by + 35
         local has_data = (#dynamic_buffer > 0)
         if has_data then gfx.set(0.1, 0.6, 1, 1) else gfx.set(0.4, 0.4, 0.4, 1) end
         gfx.rect(bx, cby, 210, 30, 1)
         gfx.set(1, 1, 1, 1); gfx.x, gfx.y = bx + (has_data and 55 or 60), cby + 8
         gfx.drawstr(has_data and "PASTE DATA" or "COPY DATA")
         if mouse_click and gfx.mouse_x >= bx and gfx.mouse_x <= bx+210 and gfx.mouse_y >= cby and gfx.mouse_y <= cby+30 then copy_paste_logic() end

         local vby = cby + 35 
         gfx.set(0.8, 0.5, 0.2, 1); gfx.rect(bx, vby, 210, 30, 1) 
         gfx.set(0, 0, 0, 1); gfx.x, gfx.y = bx + 35, vby + 8; gfx.drawstr("EMPHASIZE VELOCITY") 
         if mouse_click and gfx.mouse_x >= bx and gfx.mouse_x <= bx+210 and gfx.mouse_y >= vby and gfx.mouse_y <= vby+30 then emphasize_velocity() end 

         local gx, gy = 10, vby + 40 
         gfx.set(0.2, 0.2, 0.2, 1); gfx.rect(gx, gy, 210, 22, 1) 
         gfx.set(1, 1, 1, 1); gfx.x, gfx.y = gx + 60, gy + 4; gfx.drawstr("Grid: " .. grid_options[selected_grid_idx].label) 
         if mouse_click and gfx.mouse_x >= gx and gfx.mouse_x <= gx+210 and gfx.mouse_y >= gy and gfx.mouse_y <= gy+22 then 
             local m = "" 
             for i, opt in ipairs(grid_options) do m = m .. (i == selected_grid_idx and "!" or "") .. opt.label .. "|" end 
             local sel = gfx.showmenu(m) 
             if sel > 0 then selected_grid_idx = sel end 
         end 
     end
     
     last_mouse_cap = gfx.mouse_cap 
     local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
     reaper.SetExtState(section, "dock", tostring(dock), true)
     if dock == 0 then 
         reaper.SetExtState(section, "x", tostring(x), true)
         reaper.SetExtState(section, "y", tostring(y), true)
     end
     if gfx.getchar() >= 0 then reaper.defer(Main) end 
 end 

 gfx.init("Score Dynamics v11.10", 230, 650, last_dock, last_x, last_y) 
 gfx.setfont(1, "Arial", 16) 
 Main()
