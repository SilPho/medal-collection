void Render() {
	// bool hudRule = !settings_showOnlyWithHud || UI::IsGameUIVisible();
	bool openplanetRule = !settings_showOnlyWithOpenplanet || UI::IsOverlayShown();

	if (showUI && openplanetRule) {
		displayUI();
	}
}

void RenderMenu() {
	if (UI::BeginMenu("\\$db4" + Icons::Trophy + "\\$g Medal Collection")) {
		if(UI::MenuItem("Show window in game", "", settings_showInGame)) {
			settings_showInGame = !settings_showInGame;
			updateUiVisibility();
		}
		if(UI::MenuItem("Show window in main menu", "", settings_showInMenus)) {
			settings_showInMenus = !settings_showInMenus;
			updateUiVisibility();
		}

		UI::Separator();

		if(UI::MenuItem("Re-check Nadeo medals", "", false)) {
			checkAllNadeoRecords();
		}

		UI::Separator();
		UI::Text("\\$999(Lots more options in Settings)");

		UI::EndMenu();
	}
}

void updateUiVisibility() {
	if (isPlayerInGame()) {
		showUI = settings_showInGame;
	}
	else {
		showUI = settings_showInMenus;
	}
}

void displayUI() {
	if (!showUI) {
		return;
	}

	// Seemingly standard flag options
	int windowFlags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoDocking;

	// Only allow resizing when Openplanet overlay is open
	if (!UI::IsOverlayShown()) {
		windowFlags |= UI::WindowFlags::NoMove;
	}

	UI::Begin("Medal Collection", windowFlags);

	if (settings_showHeader) {
		if (UI::BeginTable("headerTable", 1)) {
			UI::TableNextRow();
			UI::TableNextColumn();

			auto app = cast<CTrackMania>(GetApp());
			string collectionName = "Medal Collection";
			if (settings_displayMode == DISPLAY_MODE_LEADERBOARDS) {
				collectionName = "Leaderboard Records";
			}
			else if (settings_displayMode == DISPLAY_MODE_BOTH) {
				collectionName = "Records & Medals";
			}
			UI::Text("\\$888 " + app.LocalPlayerInfo.Name + "\\$888's " + collectionName);
			UI::EndTable();
		}
	}

	int numMedals = medalRecords.Length;
	int numRecords = leaderboardRecords.Length;

	if (!settings_showUnfinished) {
		numMedals--;
	}

	int numColumnsPerEntry = (1
				+ (settings_showColours ? 1 : 0)
				+ (settings_showNames ? 1 : 0)
				+ (settings_showRandomiserButtons ? 1 : 0)
				+ (settings_showPercentages && !settings_horizontalMode ? 1 : 0)
				+ (settings_showTotals && !settings_horizontalMode ? 1 : 0)
				+ (settings_showTotalPercentages && !settings_horizontalMode ? 1 : 0)
			);

	int numMedalColumns = numColumnsPerEntry * (settings_horizontalMode ? numMedals : 1);
	int numRecordColumns = numColumnsPerEntry * (settings_horizontalMode ? numRecords : 1);

	int totalMedals = 0; // Leaderboard records calculate their percentage based on total medals, not just leaderboard records
	for(uint i = 0; i < medalRecords.Length; i++) {
		if (medalRecords[i].medalId != UNFINISHED_MEDAL_ID || settings_showUnfinished) {
			totalMedals += medalRecords[i].count;
		}
	}

	if (settings_displayMode & DISPLAY_MODE_LEADERBOARDS > 0 && UI::BeginTable("recordTable", numRecordColumns)) {
		insertRow(leaderboardRecords, totalMedals);
		UI::EndTable();
	}

	if (settings_displayMode == DISPLAY_MODE_BOTH) {
		UI::Separator();
	}

	if (settings_displayMode & DISPLAY_MODE_MEDALS > 0 && UI::BeginTable("medalTable", numMedalColumns)) {
		UI::TableNextRow();
		insertRow(medalRecords, totalMedals);
		UI::EndTable();
	}

	// If a new next random map has been loaded, show the details and "Play" button
	if (nextRandomMap.mapName != "") {
		if (UI::BeginTable("NextMapTable", 1)) {
			UI::TableNextRow();
			UI::TableNextColumn();
			UI::AlignTextToFramePadding();
			if (!settings_horizontalMode) {
				// Enforce some wrapping on the narrower vertical mode
				UI::PushTextWrapPos(numColumnsPerEntry * 50);
				UI::Text(Text::OpenplanetFormatCodes(nextRandomMap.mapName));
				UI::PopTextWrapPos();
			}
			else {
				UI::Text(Text::OpenplanetFormatCodes(nextRandomMap.mapName));
				UI::SameLine();
			}

			if (nextRandomMap.mapFileUrl != "") {
				if (UI::Button("Play")) {
					startnew(loadMap);
				}
				UI::SameLine();
				UI::Dummy(vec2(5, 5));
				UI::SameLine();
			}

			if (UI::ButtonColored("Hide", 0, 0, 0.2)) {
				clearNextRandomMap();
			}
			UI::EndTable();
		}
	}
	UI::End();
}

void insertRow(array<MedalCount@> recordArray, const int totalMedals) {
	int cumulative = 0;

	for(uint i = 0; i < recordArray.Length; i++) {
		if (!recordArray[i].isVisible) {
			continue;
		}

		int medalId = recordArray[i].medalId;

		if (!settings_showUnfinished && medalId == UNFINISHED_MEDAL_ID) {
			continue;
		}

		// Show a coloured disk if the settings allow (or to replace a random button when the counter is at 0)
		if (settings_showColours || (settings_showRandomiserButtons && recordArray[i].count == 0)) {
			UI::TableNextColumn();
			UI::AlignTextToFramePadding();
			UI::Text(recordArray[i].color + (medalId <= 0 ? Icons::CircleO : Icons::Circle));
		}

		// Randomiser buttons (Only visible if there's something to play)
		if (settings_showRandomiserButtons && recordArray[i].count > 0) {
			array<float> blackBg = { 0.0, 0.0, 0.0 };
			auto buttonColour = settings_showColours ? blackBg : recordArray[i].buttonHsv;
			UI::TableNextColumn();
			UI::PushID("Improve" + medalId);
			if (UI::ButtonColored(Icons::Random, buttonColour[0], buttonColour[1], buttonColour[2])) {
				playRandomMap(medalId);
			}
			if (UI::IsItemHovered()) {
				UI::BeginTooltip();
				UI::Text("Click here to find a random map " + recordArray[i].tooltipSuffix);
				UI::EndTooltip();
			}
			UI::PopID();
		}

		// Fix a column alignment issue when a randomiser button is hidden but still needs to take up space
		if (!settings_horizontalMode && settings_showColours && settings_showRandomiserButtons && recordArray[i].count == 0) {
			UI::TableNextColumn();
		}

		bool shouldHighlightMedal = currentMapMedal == medalId || currentMapLeaderboardId == medalId;

		if (shouldHighlightMedal) {
			UI::PushStyleColor(UI::Col::Text, vec4(1, 1, 0, 1));
		}

		if (settings_showNames) {
			UI::TableNextColumn();
			UI::AlignTextToFramePadding();
			UI::Text(recordArray[i].name);
		}

		// Medal count
		UI::TableNextColumn();
		string countText = "";
		cumulative += recordArray[i].count;
		countText = "" + cumulative;
		string medalCount = "" + recordArray[i].count;

		// Use ceil because it prevents rounding to 0, which wouldn't be shown
		float percent = totalMedals > 0 ? Math::Ceil(recordArray[i].count / float(totalMedals) * 100) : 0;
		float cumulativePercent = totalMedals > 0 ? Math::Ceil(cumulative / float(totalMedals) * 100) : 0;

		// Only show cumulative if it is enabled and different to the regular perecentage if that's enabled too
		bool showCumulativePercent = settings_showTotalPercentages && (!settings_showPercentages || cumulative != recordArray[i].count) && recordArray[i].medalId != UNFINISHED_MEDAL_ID;

		if(settings_horizontalMode) {
			if (settings_showPercentages) {
				medalCount += " (" + percent + "%)";
			}
			if (settings_showTotals && cumulative != recordArray[i].count) {
				medalCount += " [" + cumulative + "]";
			}
			if (showCumulativePercent && cumulativePercent > 0 && cumulativePercent != 100) {
				medalCount += " [" + cumulativePercent + "%]";
			}

			UI::Text(medalCount);
		}
		else {
			UI::Text(medalCount);
			if (settings_showPercentages) {
				UI::TableNextColumn();
				UI::Text("" + percent + "%");
			}
			if (settings_showTotals) {
				UI::TableNextColumn();
				UI::Text(cumulative != recordArray[i].count ? "" + cumulative + "" : "");
			}
			if (showCumulativePercent) {
				UI::TableNextColumn();
				UI::Text((cumulativePercent > 0 && cumulativePercent < 100) ? "[" + cumulativePercent + "%]" : "");
			}
		}

		if (shouldHighlightMedal) {
			UI::PopStyleColor();
		}

		if (!settings_horizontalMode) {
			UI::TableNextRow();
		}
	}
}