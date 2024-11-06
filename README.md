# Medal Collection
Keep track of every Trackmania 2020 medal you've ever earned with this Openplanet plugin.

# Description

Are you a binger of bronze medals, securer of silver medals, gatherer of gold medals or hoarder of author medals? Now you can find out and show off.

After installing this plugin, it will check for every medal you've earned on every track you've ever played and display it proudly in a highly customisable medal window. Watch your collection grow in real-time or just let it run in the background.

Wondering which tracks you only managed to get bronze on? Click the button next to it and find out, with a quick link to play it straight away. This makes it really easy to find out which times you can improve on.

New in 2.0: Now you can track your __World Records__! The plugin will compare all of your times against the leaderboards to see if you have the fastest time in your area. This also works for continental records, country records, and any state or district records if applicable.

You can get the plugin to recheck all of your medals, but I only recommend doing this if you've played on other devices or had the plugin disabled for a while. This is because medals aren't always updated immediately, so your counts can seemingly go down if you recheck too soon after playing a map.

# Known Issues
Royal Mode is not supported. You can't earn medals on a Royal map, so this isn't a big deal. Royal "training" maps work as normal. Stunt and Platform Modes should work fine though.

Champion Medals support: Coming soon (hopefully)

# Settings

## Display Options

### Display in horizontal mode
This is my preferred way of using the plugin. It fits neatly into the top centre of the screen and provides plenty of space for track names when using the randomiser buttons.

### Show collection title
Toggles the "[name] medal collection" title. You can turn this off if you want the plugin to take up less space.

### Accomplishment mode
New in 2.0 you can decide whether to show the counts for your medals (Author, Gold, etc), or for your leaderboard records (World, Continental, etc), or both.

### Show medal colours
Toggles a small circle for each medal, in an appropriate colour.

### Show medal names
Toggles the full name of the medals. You can hide these to save space or keep them visible to make things clearer.

### Show \"Play Random Map\" buttons"
Clicking on one of these buttons will randomly select a map from that medal category and present you with a button that you can use to jump directly into that map. Very useful if you want to figure out which maps you only have a bronze medal on and want to improve. If you don't have any medals or records at that tier, the button will be replaced with a coloured circle.

Note: This will require club access to let you download and play these maps.

### Show cumulative totals
Since earning the gold medal, for instance, means you've obviously beaten the required time for silver and bronze medals, this option lets you count every medal in each of the lower tiers. This has the added benefit of showing you the total number of maps you've finished. The cumulative totals will appear alongside the per-medal counters, not instead of them.

### Show percentages
Display the relative percentage of each medal alongside the number of medals in that tier.

### Show cumulative percentages
Similar to cumulative totals, this will show the total percentage of each medal and all higher tiers. Since this would always display 100% for the "played" category, that gets hidden.

### Show "Played" map counter
Keep track of every map you've attempted but couldn't finish. Maybe you can finish them later. This is hidden by default, since there's nothing to be ashamed of if you can't finish difficult maps.

Please note that Unfinished maps from before the plugin was installed won't be counted because there's no online history of unfinished maps that the plugin can check.


## Window Options

### Only show collection when Openplanet menu is visible
Toggles the collection window when you press F3 (when enabled) or stays visible at all times (when disabled).

### Show collection while racing
Toggles whether the plugin window will be visible while you are driving. Make sure it's not positioned anywhere too distracting if this is turned on.

### Show collection while in the main menu
Toggles whether the plugin window is visible in the main menu.


## Advanced Options

### Developer mode
Prints more lines to the Openplanet log to aid development and debugging.

### Re-check Nadeo medals
Only visible if your Accomplishment Mode includes medals.

This will ask the Nadeo servers for a list of every medal you have ever earned, allowing the plugin to reconstruct your collection. It will take a few seconds but is usually under a minute.

This happens automatically when the plugin is first installed, so as long as you keep it installed and enabled, and don't play on any other devices, you should never need to use it.

### Re-check Warrior medals
Only visible if your Accomplishment Mode includes medals.

If you've recently installed the Warrior medals plugin by Ezio then you can use this button to read any earned Warrior medals directly from the save-data of that plugin. This should only take a second or two.

### Re-check leaderboards
Only visible if your Accomplishment Mode includes leaderboard records.

These buttons will check your medals one by one to see if any of those set times match regional records. This can take a very long time because the plugin needs to stay within certain rate limits in order to avoid overloading any servers.

I strongly advise you don't use these buttons unless you have a really good reason to.


# Credits
Written by SilPho

Massive thanks to the Openplanet Discord server for support and troubleshooting.

## Additional thanks:
A lot of inspiration and guidance was sourced from the following awesome plugins:
* Multiple plugins by XertroV
* MedalsDifficulty by zakergfx
* GrindingStats by Drek
* Ultimate Medals by Phlarx
* Champion Medals by NaNInf
* ManiaExchange Random Map Picker by Greep
* Warrior Medals by Ezio
