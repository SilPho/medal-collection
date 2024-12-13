void checkAllNadeoRecords() {
    startnew(getMapMedals);
}

void getMapMedals() {
    print("Starting full history check");
    MEDAL_CHECK_STATUS.recordCheckInProgress = true;
    MEDAL_CHECK_STATUS.currentScanDescription = "Medal check is starting...";
    waitForNadeoAuthentication();

    dictionary medalLookup = getUserMedals();

    int numMedals = processMapIds(medalLookup);

    MEDAL_CHECK_STATUS.currentScanDescription = "Medal check is finishing...";
    writeAllStorageFiles(RecordType::MEDAL);

    UI::ShowNotification("Medal Collection", "Medal Collection updated with " + numMedals + " medals!");
    MEDAL_CHECK_STATUS.currentScanDescription = "Medal check found " + numMedals + " medals";
    MEDAL_CHECK_STATUS.recordCheckInProgress = false;
}

dictionary getUserMedals() {
    string accountId = GetApp().LocalPlayerInfo.WebServicesUserId;
    string url = NadeoServices::BaseURLCore() + "/v2/accounts/" + accountId + "/mapRecords";

    string raceResponse = getFromUrl(url);
    string stuntResponse = getFromUrl(url + "?gameMode=Stunt");
    string platformResponse = getFromUrl(url + "?gameMode=Platform");

    Json::Value raceResults = Json::Parse(raceResponse);
    Json::Value stuntResults = Json::Parse(stuntResponse);
    Json::Value platformResults = Json::Parse(platformResponse);
    log("Total number of medals found: " + (raceResults.Length + stuntResults.Length + platformResults.Length) + ". (" + raceResults.Length + " Race. " + stuntResults.Length + " Stunt. " + platformResults.Length + " Platform)");

    dictionary mapLookup;

    // There's probably a DRYer way to parse these lists, but this will do
    for (uint i = 0; i < raceResults.Length; i++) {
        string mapId = string(raceResults[i]["mapId"]);
        int medal = int(raceResults[i]["medal"]);
        mapLookup[mapId] = medal;
    }
    for (uint i = 0; i < stuntResults.Length; i++) {
        string mapId = string(stuntResults[i]["mapId"]);
        int medal = int(stuntResults[i]["medal"]);
        mapLookup[mapId] = medal;
    }
    for (uint i = 0; i < platformResults.Length; i++) {
        string mapId = string(platformResults[i]["mapId"]);
        int medal = int(platformResults[i]["medal"]);
        mapLookup[mapId] = medal;
    }

    return mapLookup;
}

int processMapIds(dictionary mapLookup) {
    string url = getMapSearchUrl();

    string[] mapIds = mapLookup.GetKeys();
    bool uncheckedMaps = false;

    const int batchSize = 200;

    MEDAL_CHECK_STATUS.currentScanDescription = "Medal check has processed 0 /" + mapLookup.GetSize() + " maps";

    for (uint i = 0; i < mapIds.Length; i++) {
        url += mapIds[i];

        if (i % batchSize == 0) {
            log("Processing " + batchSize +" maps in batch " + (i / batchSize) + " of " + ((mapIds.Length / batchSize) + 1));
            MEDAL_CHECK_STATUS.currentScanDescription = "Medal check has counted " + i + " /" + mapLookup.GetSize() + " medals";
            processBatch(url, mapLookup);

            // The sleeps aren't necessary, but help prevent FPS drops
            sleep(500);
            uncheckedMaps = false;
            url = getMapSearchUrl();
        }
        else if (i < mapIds.Length - 1) {
            url += ",";
            uncheckedMaps = true;
        }
    }

    if (uncheckedMaps) {
        log("Processing final batch of " + mapIds.Length % batchSize + " maps");
        processBatch(url, mapLookup);
    }

    return mapIds.Length;
}

void processBatch(string &in nadeoUrl, dictionary mapLookup) {
    string response = getFromUrl(nadeoUrl);

    Json::Value mapResults = Json::Parse(response);
    log("Map batch size results: " + mapResults.Length);

    for (uint i = 0; i < mapResults.Length; i++) {
        string mapId = string(mapResults[i]["mapId"]);
        string mapUid = string(mapResults[i]["mapUid"]);
        int medal = int(mapLookup[mapId]);

        // log("About to check " + mapUid + " with medal " + medal);
        updateSaveData(mapUid, medal, RecordType::MEDAL, true);
    }
}

