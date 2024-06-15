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
			updateUIState();
		}
		if(UI::MenuItem("Show window in main menu", "", settings_showInMenus)) {
			settings_showInMenus = !settings_showInMenus;
			updateUIState();
		}

		UI::Separator();

		if(UI::MenuItem("Check ALL medals (May be slow)", "", false)) {
			checkAllRecords();
		}

		UI::EndMenu();
	}
}

void updateUIState() {
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
			UI::Text("\\$888 " + app.LocalPlayerInfo.Name + "\\$888's Medal Collection");
			// UI::Text("\\$888My Medal Collection");
			UI::EndTable();
		}
	}

	int numMedals = allMedals.Length;
	if (!settings_showUnfinished) {
		numMedals--;
	}

	int numColumns = (1
				+ (settings_showColours ? 1 : 0)
				+ (settings_showNames ? 1 : 0)
				+ (settings_showRandomiserButtons ? 1 : 0)
				+ (settings_showTotals && !settings_horizontalMode ? 1 : 0)
			) * (settings_horizontalMode ? numMedals : 1);

	if (UI::BeginTable("medalTable", numColumns)) {
		UI::TableNextRow();

		int cumulative = 0;
		for(uint i = 0; i < allMedals.Length; i++) {
			int medalId = allMedals[i].medalId;

			if (!settings_showUnfinished && medalId == -1) {
				continue;
			}

			if (settings_showColours) {
				UI::TableNextColumn();
				UI::AlignTextToFramePadding();
				UI::Text(allMedals[i].color + (medalId <= 0 ? Icons::CircleO : Icons::Circle));
			}

			if (settings_showRandomiserButtons) {
				auto buttonColour = allMedals[i].buttonHsv;
				UI::TableNextColumn();
				UI::PushID("Improve" + medalId);
				if (UI::ButtonColored(Icons::Random, buttonColour[0], buttonColour[1], buttonColour[2])) {
					playRandomMap(medalId);
				}
				UI::PopID();
			}

			if (settings_showNames) {
				UI::TableNextColumn();
				UI::AlignTextToFramePadding();
				UI::Text("" + (currentMapMedal == medalId ? '\\$ff0' : '') + allMedals[i].name);
			}

			// Medal count
			UI::TableNextColumn();
			string countText = "";
			if (settings_showTotals && medalId != -1) {
				cumulative += allMedals[i].count;
				countText = "" + cumulative;
				string msgSoFar = "" + (currentMapMedal == medalId ? '\\$ff0' : '') + allMedals[i].count;
				string suffix = cumulative != allMedals[i].count ? ("(" + cumulative + ")") : "";

				if(settings_horizontalMode) {
					UI::Text(msgSoFar + " " + suffix);
				}
				else {
					UI::Text(msgSoFar);
					UI::TableNextColumn();
					UI::Text(suffix);
				}
			}
			else {
				countText = "" + allMedals[i].count;
				UI::Text("" + (currentMapMedal == medalId ? '\\$ff0' : '') + countText);
			}

			if (!settings_horizontalMode) {
				UI::TableNextRow();
			}
		}

		UI::EndTable();
	}

	// If a new next random map has been loaded, show the details and "Play" button
	if (nextRandomMap.mapName != "") {
		if (UI::BeginTable("NextMapTable", 1)) {
			UI::TableNextRow();
			UI::TableNextColumn();
			UI::AlignTextToFramePadding();
			if (!settings_horizontalMode) {
				UI::PushTextWrapPos(numColumns * 50);
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
			}
			UI::EndTable();
		}
	}
	UI::End();
}