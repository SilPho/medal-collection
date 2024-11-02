class NextRandomMap {
    string mapUid;
    string mapFileUrl;
    string mapName;
    string currentMedal;
}

NextRandomMap nextRandomMap = NextRandomMap();

void clearNextRandomMap() {
    nextRandomMap.mapName = "";
    nextRandomMap.mapFileUrl = "";
}

void playRandomMap(int medalType) {
    log("Time to play a random " + medalType + " map");
    nextRandomMap.mapFileUrl = "";

    auto availableMaps = getMapPool(medalType);

    if (availableMaps.Length <= 0) {
        nextRandomMap.mapName = "No more maps. Clicking the button will cycle through them again";
        rebuildMapPool(medalType);
        return;
    }

    nextRandomMap.mapName = "Randomising...";

    auto index = Math::Rand(0, availableMaps.Length);

    auto mapUid = availableMaps[index];
    availableMaps.RemoveAt(index);
    log("Time to download details for  " + mapUid + ". There are " + availableMaps.Length + " maps left");

    nextRandomMap.mapUid = mapUid;
    startnew(getMapDetails);
}

void getMapDetails() {
    string url = getMapSearchUrl(true) + nextRandomMap.mapUid;
    string nadeoResponse = getFromUrl(url);
    Json::Value mapDetails = Json::Parse(nadeoResponse);

    const string mapType = string(mapDetails[0]["mapType"]);
    const string mapName = string(mapDetails[0]["name"]);

    if (mapDetails.Length != 1) {
        nextRandomMap.mapName = "Something went wrong. Please try again";
    }
    else if (!isValidMapType(mapType)) {
        // Invalid map type found - Somehow some dodgy data got into the Storage
        nextRandomMap.mapName = "Oops, " + mapName + "$g is a " + mapType + " map. Removed it from your collection to keep things tidy";
        deleteMapFromStorage(nextRandomMap.mapUid, RecordType::LEADERBOARD);
        deleteMapFromStorage(nextRandomMap.mapUid, RecordType::MEDAL);

        // We don't need to remove it from the random map pool because it was already removed when it was randomly chosen
    }
    else {
        // Map is valid and good to go
        nextRandomMap.mapName = mapName;
        nextRandomMap.mapFileUrl = mapDetails[0]["fileUrl"];
        log("Map name: " + mapName + ". Map URL: " + nextRandomMap.mapFileUrl);
    }

}

// Actually requests the map to be played
void loadMap() {
    if (nextRandomMap.mapFileUrl == "") {
        warn("Somehow requested to play a map while not having one queued up");
        return;
    }

    if (!Permissions::PlayLocalMap()) {
        UI::ShowNotification("Permissions issue", "Sorry, you don't have permission for that. You probably need Club access");
        return;
    }

    log("File URL to play: " + nextRandomMap.mapFileUrl);

    CTrackMania@ app = cast<CTrackMania@>(GetApp());

    // Try to close the pause menu, if it is visible, before we kick back to the main menu
    if (app.Network.PlaygroundClientScriptAPI.IsInGameMenuDisplayed) {
        log("Closing pause menu");
        app.Network.PlaygroundInterfaceScriptHandler.CloseInGameMenu(CGameScriptHandlerPlaygroundInterface::EInGameMenuResult::Quit);
    }

    // Return to the main menu first (Otherwise PlayMap doesn't work)
    app.BackToMainMenu();

    while (!app.ManiaTitleControlScriptAPI.IsReady) {
        yield();
    }

    app.ManiaTitleControlScriptAPI.PlayMap(nextRandomMap.mapFileUrl, "TrackMania/TM_PlayMap_Local", "");
    clearNextRandomMap();
}