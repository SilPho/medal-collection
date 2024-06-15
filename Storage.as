class MedalCount {
    int medalId;
	string name;
	int count;
	string color;
    array<float> buttonHsv;

	MedalCount(int medalId, const string &in name="", const string &in color="$000", array<float> buttonHsv = { 0, 1, 1 }){
        this.medalId = medalId;
		this.name = name;
		this.count = 0;
		this.color = color;
        this.buttonHsv = buttonHsv;
	}
}

// This is where we keep the really important numbers
auto author = MedalCount(4, "Author", "\\$071", { 0.34, 1, 0.47 });
auto gold = MedalCount(3, "Gold", "\\$db4", { 0.13, 0.70, 0.87});
auto silver = MedalCount(2, "Silver", "\\$899", { 0.5, 0.11, 0.60});
auto bronze = MedalCount(1, "Bronze", "\\$964", { 0.06, 0.57, 0.6});
auto finishes = MedalCount(0, "Finished", "\\$aaf", { 0.66, 0.32, 0.96});
auto unfinished = MedalCount(-1, "Unfinished", "\\$ccc", { 0.5, 0.11, 0.60} );

// The order these are added will be the order they are displayed to the user
array<MedalCount@> allMedals = {author, gold, silver, bronze, finishes, unfinished };

string jsonFile = IO::FromStorageFolder("") + 'medalCollection.json';

// Mapping of mapUid to medalId
dictionary mapDict = {};

// Mapping of medals to mapUid[]
dictionary medalDict = {};

void updateSaveData(string &in mapId, int bestMedal, bool suppressWriting = false) {
    bool hadMedalAlready = mapDict.Exists(mapId);
    int currentMedal = int(mapDict[mapId]);
    bool improvedMedal = currentMedal < bestMedal;

    // Only make changes (and write the file) if necessary
    if (!hadMedalAlready || improvedMedal) {
        log("Is this a NEW medal? " + !hadMedalAlready + " OR is it an improvement: " + improvedMedal);

        for(uint i=0; i < allMedals.Length; i++){
            if (allMedals[i].medalId == bestMedal) {
                print("New record on " + mapId + ". Medal earned: " + allMedals[i].name);
                // Increase count for new medal type
                allMedals[i].count++;
                getMapPool(bestMedal).InsertLast(mapId);
            }
            if (hadMedalAlready && allMedals[i].medalId == currentMedal) {
                // Since there was an old medal, better remove that first
                log("Removing old medal: " + allMedals[i].name);
                allMedals[i].count--;

                // Also need to remove it from the random map pool
                auto mapPoolForThisMedal = getMapPool(currentMedal);
                int mapIndex = mapPoolForThisMedal.Find(mapId);
                log("Found map to remove at index " + mapIndex);
                if (mapIndex >= 0) {
                    mapPoolForThisMedal.RemoveAt(mapIndex);
                }
            }
        }
        mapDict.Set(mapId, bestMedal);

        if (!suppressWriting) {
            writeStorageFile();
        }
    }
}

array<string> getMapPool(int medalId) {
    return cast<array<string>>(medalDict["" + medalId]);
}

// Scans every medal from every map to find ones that you have a certain medal on. Should be used VERY sparingly
void rebuildMapPool(int medalIdForEmptyPool) {
    medalDict.Set("" + medalIdForEmptyPool, array<string>(0));
    auto mapPool = getMapPool(medalIdForEmptyPool);

    auto allMaps = mapDict.GetKeys();
    for (uint i=0; i < allMaps.Length; i++) {
        int medalEarned;
        mapDict.Get(allMaps[i], medalEarned);
        if (medalEarned == medalIdForEmptyPool) {
            mapPool.InsertLast(allMaps[i]);
        }
    }

    log("Map pool rebuilt: Has "+ mapPool.Length + " maps in it again");
}

void writeStorageFile() {
    // I write the summary to the JSON for brevity's sake, but never trust it when reloading
    auto summary = Json::Object();
    for(uint i=0; i < allMedals.Length; i++){
        summary["" + allMedals[i].medalId] = allMedals[i].count;
    }

    auto content = Json::Object();
    content["summary"] = summary;
    content["maps"] = mapDict.ToJson();

    Json::ToFile(jsonFile, content);

    log("Medal collection written to " + jsonFile);
}

void readStorageFile() {
    for(uint i=0; i < allMedals.Length; i++) {
        medalDict.Set("" + allMedals[i].medalId, array<string>(0));
    }

    if (IO::FileExists(jsonFile)) {
        auto content = Json::FromFile(jsonFile);
        dictionary tempMedals = {};

        for(uint i=0; i < allMedals.Length; i++){
            tempMedals.Set("" + allMedals[i].medalId, 0);
        }

        auto mapList = content.Get("maps");

        // Quick guard to ensure the maps object exists in the file
        if (mapList.GetType() != 0) {
            auto allIds = mapList.GetKeys();
            for(uint i=0; i < allIds.Length; i++) {
                auto medalEarned = int(mapList.Get("" + allIds[i]));
                mapDict.Set(allIds[i], medalEarned);
                auto newTotal = int(tempMedals["" + medalEarned]) + 1;
                tempMedals.Set("" + medalEarned, newTotal);

                // Add mapId to the per-medal list
                getMapPool(medalEarned).InsertLast(allIds[i]);
            }
        }

        // Set (and log) the results
        for(uint i=0; i < allMedals.Length; i++){
            allMedals[i].count = int(tempMedals["" + allMedals[i].medalId]);
            log("Set number of " + allMedals[i].color + allMedals[i].name + "\\$g medals to " + allMedals[i].count);
        }
    }
    else {
        log("Medal collection log file doesn't exist. Write a temporary file");
        writeStorageFile();
        checkAllRecords();
    }
}