[Setting hidden]
bool settings_horizontalMode = true;

[Setting hidden]
bool settings_showHeader = true;

[Setting hidden]
bool settings_showColours = true;

[Setting hidden]
bool settings_showNames = true;

[Setting hidden]
bool settings_showRandomiserButtons = true;

[Setting hidden]
bool settings_showTotals = false;

[Setting hidden]
bool settings_showPercentages = false;

[Setting hidden]
bool settings_showTotalPercentages = false;

[Setting hidden]
bool settings_showUnfinished = false;

[Setting hidden]
bool settings_showOnlyWithOpenplanet = false;

[Setting hidden]
bool settings_showInGame = true;

[Setting hidden]
bool settings_showInMenus = true;

// These values will be used as masks, so make sure the binary values are right
int DISPLAY_MODE_MEDALS = 1;
int DISPLAY_MODE_LEADERBOARDS = 2;
int DISPLAY_MODE_BOTH = 3;

[Setting hidden]
int settings_displayMode = DISPLAY_MODE_BOTH;

[Setting hidden]
bool settings_debugMode = false;

// --------------------------------------------------------------------------------------

array<int> DisplayModeOrder = { DISPLAY_MODE_MEDALS, DISPLAY_MODE_LEADERBOARDS, DISPLAY_MODE_BOTH };

dictionary DisplayModeLabels = {
    { "" + DISPLAY_MODE_MEDALS, "Medals only" },
    { "" + DISPLAY_MODE_LEADERBOARDS, "Leadboard records only" },
    { "" + DISPLAY_MODE_BOTH, "Medals and leaderboard records"}};

// Shortcut for making a checkbox with an optional help icon and tooltip
bool makeCheckbox(const string &in label, bool &in setting, const string &in tooltip = "") {
    auto returnValue = UI::Checkbox(label, setting);

    if (tooltip.Length > 0) {
        UI::SameLine();
        UI::Text("\\$666 " + Icons::QuestionCircle);
        if (UI::IsItemHovered()) {
            UI::BeginTooltip();
            UI::Text(tooltip);
            UI::EndTooltip();
        }
    }

    return returnValue;
}

// --------------------------------------------------------------------------------------

[SettingsTab name="Display Options" icon="Eye" order="1"]
void renderColumnsTab() {
    if (UI::Button("Reset to default")) {
        settings_horizontalMode = true;
        settings_showHeader = true;
        settings_showColours = true;
        settings_showNames = true;
        settings_showRandomiserButtons = true;
        settings_showTotals = false;
        settings_showPercentages = false;
        settings_showTotalPercentages = false;
        settings_showUnfinished = false;
        settings_displayMode = DISPLAY_MODE_BOTH;
    }

    settings_horizontalMode = makeCheckbox("Display in horizontal mode", settings_horizontalMode, "Gives more space for random map names to be shown");
    settings_showHeader = makeCheckbox("Show collection title", settings_showHeader);

    UI::Separator();
    UI::Text("");

    // Determine the string to show in the combo-box
    string currentDisplayModeString;
    DisplayModeLabels.Get("" + settings_displayMode, currentDisplayModeString);

    UI::Text("Which accomplishments do you want to show off?");
    if (UI::BeginCombo(" ", currentDisplayModeString)){
        // Create the dropdown list only when clicked

        for (uint i = 0; i < DisplayModeLabels.GetSize(); i++) {
            int value = DisplayModeOrder[i];
            string label;
            DisplayModeLabels.Get("" + value, label);

            if (UI::Selectable(label, settings_displayMode == value)) {
                settings_displayMode = value;
                log("Current display mode: " + settings_displayMode);
            }

            if (settings_displayMode == value) {
                UI::SetItemDefaultFocus();
            }
        }
        UI::EndCombo();
    }

    UI::Text("");
    UI::Separator();

    settings_showColours = makeCheckbox("Show medal colours", settings_showColours);
    settings_showNames = makeCheckbox("Show medal names", settings_showNames);
    settings_showRandomiserButtons = makeCheckbox("Show \"Play Random Map\" buttons", settings_showRandomiserButtons, "Play a random map from the ones with that earned medal - Improve your times!");
    settings_showTotals= makeCheckbox("Show cumulative totals", settings_showTotals, "Include the sum of all higher medal tiers as well (Shown in brackets)");
    settings_showPercentages = makeCheckbox("Show percentages", settings_showPercentages, "Show the percentage of medals earned at each tier");
    settings_showTotalPercentages = makeCheckbox("Show cumulative percentages", settings_showTotalPercentages, "Include the percentage of all higher medal tiers as well");
    settings_showUnfinished = makeCheckbox("Show \"Played\" map counter", settings_showUnfinished, "These are maps you have played but not finished. Doesn't count maps from before the plugin was installed");
}

// --------------------------------------------------------

[SettingsTab name="Window Options" icon="WindowMaximize" order="1"]
void renderWindowTab() {
    if (UI::Button("Reset to default")) {
        settings_showOnlyWithOpenplanet = false;
        settings_showInGame = true;
        settings_showInMenus = true;
    }
    settings_showOnlyWithOpenplanet = makeCheckbox("Only show collection when Openplanet menu is visible", settings_showOnlyWithOpenplanet);
    settings_showInGame = makeCheckbox("Show collection while racing", settings_showInGame);
    settings_showInMenus = makeCheckbox("Show collection while in the main menu", settings_showInMenus);
}

// --------------------------------------------------------

[SettingsTab name="Advanced" icon="Laptop" order="3"]
void renderAdvancedTab() {
    if (UI::Button("Reset to default")) {
        settings_debugMode = false;
    }

    settings_debugMode = makeCheckbox("Developer mode", settings_debugMode, "Prints more lines to the Openplanet log to aid development");

    UI::Text("");
    UI::Separator();
    UI::Text("");
    UI::Text("I only recommend using these buttons if you've played on other devices or had the plugin disabled for a while");

    if(settings_displayMode & DISPLAY_MODE_MEDALS > 0 && UI::Button("Re-check Nadeo medals")) {
        checkAllNadeoRecords();
    }

#if DEPENDENCY_WARRIORMEDALS
    if(settings_displayMode & DISPLAY_MODE_MEDALS > 0 && UI::Button("Re-check Warrior medals")) {
        checkWarriorRecords();
    }
#endif

    if(settings_displayMode == DISPLAY_MODE_BOTH) {
        UI::Separator();
    }

    if(settings_displayMode & DISPLAY_MODE_LEADERBOARDS > 0) {
        // if (UI::Button("Re-check ALL Leaderboard Records")) {
        //     startnew(resetAllLeaderboardChecks);
        // }
        // UI::SameLine();
        // UI::Text("\\$f00(Not recommended - It takes a LONG time)");

        // In a perfect world these would be generated by iterating a proper data structure, but this'll do for now
        if (UI::ButtonColored("Re-check Author medal Records", author.buttonHsv[0], author.buttonHsv[1], author.buttonHsv[2])) {
            authorCheckFinished = false;
            startnew(doLeaderboardChecks);
        }
        if (UI::ButtonColored("Re-check Gold medal Records", gold.buttonHsv[0], gold.buttonHsv[1], gold.buttonHsv[2])) {
            goldCheckFinished = false;
            startnew(doLeaderboardChecks);
        }
        if (UI::ButtonColored("Re-check Silver medal Records", silver.buttonHsv[0], silver.buttonHsv[1], silver.buttonHsv[2])) {
            silverCheckFinished = false;
            startnew(doLeaderboardChecks);
        }
        if (UI::ButtonColored("Re-check Bronze medal Records", bronze.buttonHsv[0], bronze.buttonHsv[1], bronze.buttonHsv[2])) {
            bronzeCheckFinished = false;
            startnew(doLeaderboardChecks);
        }
        if (UI::ButtonColored("Re-check non-medal Records", finishes.buttonHsv[0], finishes.buttonHsv[1], finishes.buttonHsv[2])) {
            noMedalsCheckFinished = false;
            startnew(doLeaderboardChecks);
        }
    }
}