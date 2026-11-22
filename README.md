# Audio Region Exporter
 
"Audio Region Exporter" _(Audio_Region_Exporter.lua)_ is a Lua script for Ardour 9.10+ (and Harrison Mixbus) that will batch-export selected audio regions.

![Audio Region Exporter - Main Window](https://github.com/GhostsonAcid/Audio_Region_Exporter/blob/main/Images/Audio%20Region%20Exporter%20-%20Main%20Window%20(1).png)

### Features

- Works with audio regions of all kinds.
- Exports each selected region to its own, single file, one after the next.
- Select from any of the available Preset options.
- Select the location to export the files to.
- Automatically solos the appropriate track for each region selected (-although this can be disabled if desired).
- Automatically prevents file erasure by checking for existing file-names in the destination.
- Reports export data in a final popup window.

--------------------------------------------------

(~Example usage coming soon...)

--------------------------------------------------

## Installation

Simply [download the script](https://github.com/GhostsonAcid/Audio_Region_Exporter/blob/main/Audio_Region_Exporter.lua), and then do the following based on your OS:

### GNU/Linux:

1. Navigate to the $HOME/.config/ardour9/scripts folder.
2. Place Audio_Region_Exporter.lua in that scripts folder.
3. _(continues below...)_

### macOS/Mac OS X:

1. Open a Finder window, press cmd-shift-G, and type-in: ~/Library/Preferences/Ardour9/scripts/
2. Place Audio_Region_Exporter.lua in that scripts folder.
3. _(continues below...)_

### Windows:

1. Navigate to the %localappdata%\ardour9\scripts folder.
2. Place Audio_Region_Exporter.lua in that scripts folder.
3. _(continues below...)_

### _Continued steps for all systems:_

3. Open Ardour and go to _Edit → Lua Scripts → Script Manager._
4. Select an "Action" (e.g. "Action 1", etc.) that is "Unset", then click "Add/Set" at the bottom-left.
5. Click "Refresh", and then find and select Audio Region Exporter in the "Shortcut" drop-down menu.
6. Click "Add" and then close the Script Manager window.
7. Audio Region Exporter now exists as an easy-access button in the top-right of the DAW.

> [!TIP]
> You can always just click any empty shortcut button in the top-right, hit "Refresh", and then find and set a Lua script.
> To remove a shortcut from a button, hold shift and then right-click it.

--------------------------------------------------

_~Enjoy!_

_J. K. Lookinland_
