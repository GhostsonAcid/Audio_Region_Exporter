
ardour {
  ["type"] = "EditorAction",
  name = "Audio Region Exporter",
  author = "Joseph K. Lookinland",
  description = [[This script lets you quickly export each selected
  audio region as an individual file, and in a location of your choice.
  (v1.0 Pre-release) (2026-11-22)]]
}

function factory() return function()

  ----------------------------------------------------------------
  -------------- Step 0: Establish Global Functions --------------
  ----------------------------------------------------------------

  -- Quote a path safely for use in a shell command:
  local function shell_quote(str)
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
  end

  -- Generate the expected output filenames for a given base name:
  local function get_export_filenames(base_name, formats)

    local extension_counts = {}

    for _, format in ipairs(formats) do
      local extension = format.extension:lower()
      extension_counts[extension] = (extension_counts[extension] or 0) + 1
    end

    local filenames = {}

    for _, format in ipairs(formats) do

      local filename = base_name

      -- Append an underscore and the format name (e.g. _Apple Music) when extensions
      -- will be shared (e.g. four .wav exports will be exported).  Ardour will ultimately
      -- do this in these cases, so we need to account for it when checking for existing files, etc.:
      if extension_counts[format.extension:lower()] > 1 then -- With single file exports, Ardour will append nothing.
        filename = filename .. "_" .. format.name
      end

      filename = filename .. "." .. format.extension -- Add the exact extension.

      table.insert(filenames, filename)

    end

    return filenames
  end

  -- Generate a filename stem that does not already exist.
  local function make_nonconflicting_name(folder, requested_name, formats)

    local existing = {}

    local command = "find " .. shell_quote(folder) .. " -maxdepth 1 -type f -print 2>/dev/null"
    local pipe = io.popen(command, "r")

    if not pipe then
      return nil, "Could not scan the export folder."
    end

    for filepath in pipe:lines() do
      local filename = filepath:match("([^/]+)$") or filepath
      local stem = filename:match("^(.*)%.[^%.]+$") or filename
      existing[stem:lower()] = true
    end

    local ok = pipe:close()

    if not ok then
      return nil, "Could not complete the export-folder scan."
    end

    -- Check every filename the selected preset is expected to *actually* produce:
    local function name_is_available(base_name)

      for _, filename in ipairs(get_export_filenames(base_name, formats)) do

        local stem = filename:match("^(.*)%.[^%.]+$") or filename

        if existing[stem:lower()] then
          return false
        end

      end

      return true
    end

    if name_is_available(requested_name) then
      return requested_name
    end

    local n = 2

    while not name_is_available(requested_name .. "-" .. n) do
      n = n + 1
    end

    return requested_name .. "-" .. n
  end

  local function parse_xml_attributes(tag)
    local attributes = {}

    for key, value in tag:gmatch('([%w_%-]+)%s*=%s*"([^"]*)"') do
      attributes[key] = value
    end

    return attributes
  end

  local function find_track_for_region(region)
    local region_id = region:to_stateful():id()
    for route in Session:get_tracks():iter() do
      local track = route:to_track()
      if not track:isnil() then
        local playlist = track:playlist()
        if not playlist:isnil() then
          local found = playlist:region_by_id(region_id)
          if not found:isnil() then
            return track -- Return the appropriate track on which the region 'lives'.
          end
        end
      end
    end
    return nil -- Otherwise return nil, if something goes wrong.
  end

  ----------------------------------------------------------------------------
  -------------- Step 1: Acquire and Check All Selected Regions --------------
  ----------------------------------------------------------------------------

  local sel = Editor:get_selection()
  local selected_regions = {}

  for region in sel.regions:regionlist():iter() do
    local audio_region = region:to_audioregion()
    if audio_region:isnil() then -- This means it's *MIDI*, which I currently don't want to deal with for this script. :P
      LuaDialog.Message(
        "Invalid Selection!",
        "Unfortunately MIDI regions cannot be\nexported by this script at this time.\n" ..
        "(If you desire this feature, please\nleave on comment over on GitHub.)\n\n" ..
        "Please select at least one audio region\n(and nothing MIDI) " ..
        "to initiate this\nscript's main export window.",
        LuaDialog.MessageType.Warning,
        LuaDialog.ButtonType.Close
      ):run()
      return
    else
        table.insert(selected_regions, region) -- Add the valid, *audio* region.
    end
  end

  if #selected_regions == 0 then -- Warn if nothing is selected.
    LuaDialog.Message(
      "Nothing is selected!",
      "Please select at least one audio region\n" ..
      "to initiate this script's main export window.",
      LuaDialog.MessageType.Warning,
      LuaDialog.ButtonType.Close
    ):run()
    return
  end

  -------------------------------------------------------------------------------------
  -------------- Step 2: Discover Existing Export Preset and Format Data --------------
  -------------------------------------------------------------------------------------

  local presets = {} -- Create a table to save preset IDs, user-shown names, and used file extensions...

  -- Create a function to scan the directories we need:
  local function scan_preset_directory(directory, source)

    if not directory or directory == "" then
      return
    end

    if not io or not io.popen then
      error("io.popen is unavailable.")
    end

    -- Firstly, only inspect ".preset" files (as opposed to ".format" ones), which are the ONLY ones available
    -- to the "simple_export" binding (-which I'm 99% is essentially the "Quick Export" option in the DAW):
    local preset_command = "find " .. shell_quote(directory) .. " -type f -name '*.preset' -print 2>/dev/null"
    local preset_pipe, err = io.popen(preset_command, "r")

    if not preset_pipe then
      error("Could not scan " .. directory .. ": " .. tostring(err))
    end

    for filepath in preset_pipe:lines() do
      local file = io.open(filepath, "r")
      if file then
        local contents = file:read("*a")
        file:close()

        local line1 = contents:match("<ExportPreset%s+([^>]*)>") -- Capture for the line starting with "<ExportPreset".
        local line2 = contents:match("<ExportFormat%s+([^>]*)>") -- The "<ExportFormat" line contains an id to link later to
                                                                 -- the appropriate/associated .format file (for extension info).
        if line1 and line2 then

          local export_preset_attributes = parse_xml_attributes(line1) -- Parse the current .preset chunks...
          local export_format_attributes = parse_xml_attributes(line2)

          local format_ids = {} -- Keep track and save *multiple* .format ids, if present...

          for attributes in contents:gmatch("<ExportFormat%s+([^>]*)>") do
            local format_attributes = parse_xml_attributes(attributes)
          
            if format_attributes.id then
              table.insert(format_ids, format_attributes.id)
            end
          end

          if export_preset_attributes.id and export_preset_attributes.name and export_format_attributes.id then

            table.insert(presets, { -- Insert/save the appropriate .preset data...
              preset_id = export_preset_attributes.id,
              format_ids = format_ids,
              name = export_preset_attributes.name,
              source = source,
              path = filepath,
              formats = {}
            })

          end
        end
      end
    end

    preset_pipe:close()

    local formats_by_id = {} -- Create another table for storing the exact extensions/name info. used during export.

    -- Initiate a second loop to gather and append *extension* data from the each .preset file's associated .format file:
    local format_command = "find " .. shell_quote(directory) .. " -type f -name '*.format' -print 2>/dev/null"
    local format_pipe = io.popen(format_command, "r")

    for filepath in format_pipe:lines() do
      local file = io.open(filepath, "r")
      if file then
        local contents = file:read("*a")
        file:close()
        local line1 = contents:match("<ExportFormatSpecification%s+([^>]*)>") -- This line contains the id (that .preset files have).
        local line2 = contents:match("<Encoding%s+([^>]*)>") -- The "<Encoding" line contains the exact extension used.
        if line1 and line2 then
          local export_format_spec_attributes = parse_xml_attributes(line1) -- Parse the current .format chunks...
          local encoding_attributes = parse_xml_attributes(line2)

          if export_format_spec_attributes.id and encoding_attributes.extension then -- If the extension found/returned, then...

            formats_by_id[export_format_spec_attributes.id] = { -- Save the extension *and* name (-both used in the final popup).
              name = export_format_spec_attributes.name,
              extension = encoding_attributes.extension
            }

          end
        end
      end
    end

    format_pipe:close()

    -- Initiate a final loop to append each appropriate extension/name (that will ultimately be used for export):
    for _, preset in ipairs(presets) do
      if preset.source == source then
        for _, format_id in ipairs(preset.format_ids) do
          local format = formats_by_id[format_id]
    
          if format then
            table.insert(preset.formats, format)
          end
        end
      end
    end

  end

  local main_data_dir = os.getenv("ARDOUR_DATA_PATH")

  if not main_data_dir or main_data_dir == "" then
    LuaDialog.Message(
      "Export Preset Discovery Problem!",
      "ARDOUR_DATA_PATH is unavailable for some reason...",
      LuaDialog.MessageType.Error,
      LuaDialog.ButtonType.Close
    ):run()
    return
  end

  local internal_export_dir = ARDOUR.LuaAPI.build_filename(main_data_dir, "export") -- Application-internal presets/formats location.
  local external_export_dir = ARDOUR.LuaAPI.build_filename(ARDOUR.user_config_directory(-1), "export") -- User-created presets/formats location.

  local scan_ok, scan_error = pcall(function() -- Wrap in pcall for potential messages momentarily...

    scan_preset_directory(internal_export_dir, "built-in") -- Scan for available presets...
    scan_preset_directory(external_export_dir, "user-created")

  end)

  if not scan_ok then
    LuaDialog.Message(
      "Export Preset Discovery - Error",
      tostring(scan_error),
      LuaDialog.MessageType.Error,
      LuaDialog.ButtonType.Close
    ):run()
    return
  end

  if #presets == 0 then
    LuaDialog.Message(
      "Export Preset Discovery",
      "No ExportPreset files were found.",
      LuaDialog.MessageType.Warning,
      LuaDialog.ButtonType.Close
    ):run()
    return
  end

  --------------------------------------------------------------------------------------
  -------------- Step 3: Sort Found Presets and Build Drop-down Menu Info --------------
  --------------------------------------------------------------------------------------

  table.sort(presets, function(a, b)

    local a_label = a.name .. " [" .. a.source .. "]"
    local b_label = b.name .. " [" .. b.source .. "]"

    return a_label:lower() < b_label:lower()

  end)

  local dropdown_preset_values = {}
  local dropdown_preset_labels = {}

  for _, preset in ipairs(presets) do

    local label = string.format("%s [%s]", preset.name, preset.source)

    dropdown_preset_values[label] = preset.preset_id
    table.insert(dropdown_preset_labels, label)

  end

  ----------------------------------------------------------------
  -------------- Step 4: Initiate Main Popup Window --------------
  ----------------------------------------------------------------

  local dialog = LuaDialog.Dialog(
      "Audio Region Exporter (v1.0 Pre-release)",
      {
          {type = "heading", title = "Select an export preset and destination:"},
          {type = "dropdown", key = "preset_option", title = "Export Preset", values = dropdown_preset_values, default = dropdown_preset_labels[1]},
          {type = "folder", key = "folder", title = "Export Destination", path = Session:path()},
          {type = "label", title = "  Please note that this script exports audio from the Master bus.\n" .. -- Extra spaces to help center text.
          "Therefore, any automation or plugins in your chain that currently\n" ..
          " affect the selected audio will be reflected in the exported file(s).\n"}, -- Extra space to help center text.
          {type = "dropdown",
          key = "solo_option",
          title = "Soloing Option",
          values = {
            ["Option 1: Automatically solo a region's track"] = "yes_solo",
            ["Option 2: Do not solo a region's track"] = "no_solo"
          },
          default = "Option 1: Automatically solo a region's track"},
          {type = "label", title = "Original soloing state will be restored after exporting.\n"}
      }
  )

  local dialog_result = dialog:run()

  if not dialog_result then
    return
  end

  -- Establish the user's choices:
  local selected_preset_id = dialog_result["preset_option"] -- Note that a proper .preset ID is required by simple_export, NOT a .preset name.
  local selected_output_folder = dialog_result["folder"]
  local selected_solo_option = dialog_result["solo_option"]

  -- Establish the corresponding display name for use in the final popup:
  local selected_preset_name = nil

  for _, preset in ipairs(presets) do
    if preset.preset_id == selected_preset_id then
      selected_preset_name = preset.name .. " [" .. preset.source .. "]"
      break
    end
  end

  ---------------------------------------------------------------------
  -------------- Step 5: Build and Sort the Export Queue -------------- 
  ---------------------------------------------------------------------

  local export_queue = {}

  for selection_index, region in ipairs(selected_regions) do

    local track = find_track_for_region(region)

    table.insert(export_queue, {
      region = region,
      track = track,
      track_order = track:presentation_info_ptr():order(),
      start_sample = region:position():samples(),
      selection_index = selection_index
    })

  end

  table.sort(export_queue, function(a, b)

    if a.track_order ~= b.track_order then -- Sort tracks from highest to lowest.
        return a.track_order < b.track_order
    end

    if a.start_sample ~= b.start_sample then -- Sort regions from earliest to latest.
        return a.start_sample < b.start_sample
    end

    return a.selection_index < b.selection_index -- Sort via original selection order (-a precautionary tie-breaker).

  end)

  ---------------------------------------------------------------------------------
  -------------- Step 6: Save the Original Solo State of the Session --------------
  ---------------------------------------------------------------------------------

  local original_solos = {}

  if selected_solo_option == "yes_solo" then
    for route in Session:get_routes():iter() do
      local control = route:solo_control()
      if not control:isnil() and control:can_solo() then
        table.insert(original_solos, {
          control = control,
          state = control:self_soloed()
        })
      end
    end
  end

  ---------------------------------------------------------------
  -------------- Step 7: Initiate Main Export Loop --------------
  ---------------------------------------------------------------

  -- Establish a table for completed export data:
  local completed_exports = {}

  -- Establish the selected preset for extension appending (etc.) later on:
  local selected_preset

  for _, preset in ipairs(presets) do
    if preset.preset_id == selected_preset_id then
      selected_preset = preset
      break
    end
  end

  local export_success, export_result = pcall(function()

    -- Initiate an export loop over our export_queue (i.e. selected regions):
    for index, item in ipairs(export_queue) do

      local region = item.region
      local target_track = item.track

      assert(target_track, "Could not find the track containing region: " .. region:name())

      -- Clear all existing route soloing, if any, and if desired by the user:
      if selected_solo_option == "yes_solo" then
        for _, item in ipairs(original_solos) do
          Session:set_control(item.control, 0, PBD.GroupControlDisposition.NoGroup)
        end

        -- Wait:
        assert(ARDOUR.LuaAPI.wait_for_process_callback(0, 2000), "Timed out waiting after clearing solos.")

        -- Solo the current region's source track:
        local target_solo = target_track:solo_control()
        Session:set_control(target_solo, 1, PBD.GroupControlDisposition.NoGroup)

        -- Wait:
        assert(ARDOUR.LuaAPI.wait_for_process_callback(0, 2000), "Timed out waiting after soloing: " .. target_track:name())
      end

      local region_name = region:name()
      region_name = region_name:gsub("[/\\:]", "_") -- Precautionary; -not even sure if \, /, or : can be added to a region's name. o___o

      -- Generate a collision-safe filename:
      local safe_name = make_nonconflicting_name(selected_output_folder, region_name, selected_preset.formats)

      -- Calculate this region's timeline range:
      local start_sample = region:position():samples()
      local end_sample = start_sample + region:length():samples()

      -- Create a fresh export for this region:
      local exporter = Session:simple_export()

      exporter:set_folder(selected_output_folder)
      exporter:set_name(safe_name)
      exporter:set_preset(selected_preset_id)
      exporter:set_range(start_sample, end_sample)

      -- Check output connection(s) (-not sure exactly what Ardour is looking for, but alright):
      assert(exporter:check_outputs(), "Output validation failed for: " .. region:name()) -- Catch if there was an issue.

      -- Actually execute the "quick"/"simple" export for this region:
      assert(exporter:run_export(), "Export failed for: " .. region:name()) -- Catch if it fails.

      -- Count how many formats use each extension...
      -- Needed to determine accurate file-names used in the final popup:
      local extension_counts = {}

      for _, format in ipairs(selected_preset.formats) do
        extension_counts[format.extension] =
          (extension_counts[format.extension] or 0) + 1
      end

      local filenames = get_export_filenames(safe_name, selected_preset.formats)

      -- Record any successful export:
      table.insert(completed_exports, {
        region = region:name(),
        track = target_track:name(),
        filenames = filenames
      })

      print(string.format("Exported region %d/%d: %s", index, #selected_regions, region:name()))

    end

    return string.format("Successfully exported all %d selected region(s).", #completed_exports)

  end)

  -- Once the loop is complete, restore all original solo states
  -- and monitor whether or not it's successful at doing so:
  local restore_success, restore_error = pcall(function()

    if selected_solo_option == "yes_solo" then
      for _, item in ipairs(original_solos) do
        Session:set_control(item.control, item.state and 1 or 0, PBD.GroupControlDisposition.NoGroup)
      end
      assert(ARDOUR.LuaAPI.wait_for_process_callback(0, 2000), "Timed out waiting after restoring original solo states.")
    end

  end)
  
  ----------------------------------------------------------
  -------------- Step 8: Manifest Final Popup --------------
  ----------------------------------------------------------

  local total_files_exported = 0 -- A count of the total files exported (-because some presets export *multiple* files).

  for _, item in ipairs(completed_exports) do
    total_files_exported = total_files_exported + #item.filenames
  end

  local report =
    "Selected audio regions: " .. #selected_regions ..
    "\nSuccessfully exported: " .. #completed_exports ..
    "\nFiles produced: " .. total_files_exported ..
    "\n\nExport Preset Used: " .. selected_preset_name ..
    "\nExport Destination Used: " .. selected_output_folder

  if #completed_exports > 0 then
    report = report .. "\n\nExported files:\n"
  
    for _, item in ipairs(completed_exports) do
      for _, filename in ipairs(item.filenames) do
        report = report .. filename .. "\n"
      end
    end
  end

  if export_success and restore_success then

    LuaDialog.Message("Export Completed!", export_result .. "\n\n" .. report, LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()

  elseif export_success and not restore_success then

    LuaDialog.Message(
      "Export Completed / Solo Restoration Warning!",
      "All exports completed, but restoring the original solo states encountered an error:\n\n" ..
      tostring(restore_error) .. "\n\n" .. report,
      LuaDialog.MessageType.Warning,
      LuaDialog.ButtonType.Close
    ):run()

  else

    local error_report =
      "Export stopped because of an error:\n\n" ..
      tostring(export_result) ..
      "\n\nOriginal solo states " ..
      (restore_success and "have been restored." or
        "could NOT be fully restored: " .. tostring(restore_error)) ..
      "\n\n" .. report

      LuaDialog.Message("Export Error", error_report, LuaDialog.MessageType.Error, LuaDialog.ButtonType.Close):run()

  end

end end
