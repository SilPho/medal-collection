void checkAllRecords() {
    // Start on a new thread (ish)
    startnew(getMapMedals);
}

void getMapMedals() {
    print("Starting full history check");
    waitForNadeoAuthentication();

    dictionary medalLookup = getUserMedals();

    int numMedals = processMapIds(medalLookup);

    writeAllStorageFiles();

    UI::ShowNotification("Medal Collection", "Medal Collection updated with " + numMedals + " medals!");
}

dictionary getUserMedals() {
    string accountId = GetApp().LocalPlayerInfo.WebServicesUserId;
    string url = NadeoServices::BaseURLCore() + "/mapRecords/?accountIdList=" + accountId;

    string nadeoResponse = getFromUrl(url);

    Json::Value allRecordResults = Json::Parse(nadeoResponse);
    log("Total number of medals found: " + allRecordResults.Length);

    dictionary mapLookup;

    for (uint i = 0; i < allRecordResults.Length; i++) {
        string mapId = string(allRecordResults[i]["mapId"]);
        int medal = int(allRecordResults[i]["medal"]);
        mapLookup[mapId] = medal;
    }

    return mapLookup;
}

int processMapIds(dictionary mapLookup) {
    string url = getMapSearchUrl();

    string[] mapIds = mapLookup.GetKeys();
    bool uncheckedMaps = false;

    const int batchSize = 200;

    for (uint i = 0; i < mapIds.Length; i++) {
        url += mapIds[i];

        if (i > 0 && i % batchSize == 0) {
            log("Processing " + batchSize +" maps in batch " + (i / batchSize) + " of " + (mapIds.Length / batchSize));
            processBatch(url, mapLookup);
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
        updateSaveData(mapUid, medal, true);
    }
}

