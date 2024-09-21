class MedalCount {
    int medalId;
	string name;
	int count;
	string color;
    array<float> buttonHsv;
    string tooltipSuffix;

	MedalCount(int medalId, const string &in name="", const string &in color="$000", array<float> buttonHsv = { 0, 1, 1 }, const string &in tooltipSuffix = ""){
        this.medalId = medalId;
		this.name = name;
		this.count = 0;
		this.color = color;
        this.buttonHsv = buttonHsv;
        this.tooltipSuffix = tooltipSuffix;
	}
}

// The value of these is important - "Better" medals need higher numbers
const int WARRIOR_MEDAL_ID = 10;
const int AUTHOR_MEDAL_ID = 4; // This has to match what Nadeo uses (same for Gold, etc)
const int UNFINISHED_MEDAL_ID = -1;
const int NO_MEDAL_ID = -99;

// This is where we keep the really important numbers
auto warrior = MedalCount(WARRIOR_MEDAL_ID, "Warrior", "\\$000", { 0.34, 1, 0.47 }, "you earned a Warrior medal on");
auto author = MedalCount(AUTHOR_MEDAL_ID, "Author", "\\$071", { 0.34, 1, 0.47 }, "you earned an Author medal on");
auto gold = MedalCount(3, "Gold", "\\$db4", { 0.13, 0.70, 0.87}, "you earned a Gold medal on");
auto silver = MedalCount(2, "Silver", "\\$899", { 0.5, 0.11, 0.60}, "you earned a Silver medal on");
auto bronze = MedalCount(1, "Bronze", "\\$964", { 0.06, 0.57, 0.6}, "you earned a Bronze medal on");
auto finishes = MedalCount(0, "Finished", "\\$aaf", { 0.66, 0.32, 0.96}, "you have finished but didn't get a medal on");
auto unfinished = MedalCount(UNFINISHED_MEDAL_ID, "Played", "\\$ccc", { 0.5, 0.11, 0.60}, "you have played but not finished yet" );

// The order these are added will be the order they are displayed to the user
array<MedalCount@> allMedals = {author, gold, silver, bronze, finishes, unfinished };

// Mapping of mapUid to medalId
dictionary mapDict;

// Mapping of medals to mapUid[]
dictionary medalDict;

void initialiseStorage() {
#if DEPENDENCY_WARRIORMEDALS
    // Since the WarriorMedals plugin provides an interface for fetching colours, might as well use it
    warrior.color = WarriorMedals::GetColorStr();
    vec3 v = WarriorMedals::GetColorVec();
    v = UI::ToHSV(v.x, v.y, v.z);
    warrior.buttonHsv = { v.x, v.y, v.z };

    allMedals.InsertAt(0, warrior);
#endif

    print('Storage is good to go');
}

// Updates the save data if required. Returns true if a change is made, false otherwise
bool updateSaveData(const string &in mapId, int bestMedal, bool suppressWriting = false) {
    int currentMedal = int(mapDict[mapId]);
    bool improvedMedal = currentMedal < bestMedal;
    bool hadMedalAlready = mapDict.Exists(mapId);

    if (hadMedalAlready && !improvedMedal) {
        return false;
    }

    log("This is either a new medal: " + !hadMedalAlready + " OR it is an improvement: " + improvedMedal + " (" + currentMedal + "/" + bestMedal + ")");
    forceUpdateSaveDataa(mapId, bestMedal, suppressWriting);
    return true;
}

void forceUpdateSaveDataa(const string &in mapId, int bestMedal, bool suppressWriting = false) {
    bool hadMedalAlready = mapDict.Exists(mapId);
    int currentMedal = int(mapDict[mapId]);

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
            deleteFromMapPool(mapId, currentMedal);
        }
    }
    mapDict.Set(mapId, bestMedal);

    if (!suppressWriting) {
        writeSingleStorageFile(mapId);
    }
}

array<string> getMapPool(int medalId) {
    return cast<array<string>>(medalDict["" + medalId]);
}

/**
 * Permanently remove a map from storage (Designed for recovering from software bugs rather than expecting players to lose medals)
 */
void deleteMapFromStorage(const string &in mapId) {
    log("Deleting mapID (" + mapId + ") from storage");
    int previousMedal = NO_MEDAL_ID; // Temp value
    mapDict.Get(mapId, previousMedal);

    if (previousMedal == NO_MEDAL_ID) {
        warn("Tried to remove a map that doesn't seem to exist: " + mapId);
        return;
    }

    // Lower the current visible medal count (Superficial)
    for(uint i=0; i < allMedals.Length; i++){
        if (allMedals[i].medalId == previousMedal) {
            allMedals[i].count--;
        }
    }

    // Actually delete the map from the permanent record
    mapDict.Delete(mapId);
    writeSingleStorageFile(mapId);
}

/**
 * Remove a map from the in-memory storage (Usually to remove it from the random-map button pools)
 */
void deleteFromMapPool(const string &in mapUid, int currentMedal) {
    auto mapPoolForThisMedal = getMapPool(currentMedal);
    int mapIndex = mapPoolForThisMedal.Find(mapUid);

    if (mapIndex >= 0) {
        mapPoolForThisMedal.RemoveAt(mapIndex);
    }
    else {
        warn("Unable to locate " + mapUid + " in the old list");
    }
}

/*
 * Scans every medal from every map to find ones that you have a certain medal on. Should be used sparingly
 * This is usually used when the random map button has run out of options and needs to cycle round again
 */
void rebuildMapPool(int medalIdForEmptyPool) {
    // Empty the list, if it wasn't already
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

/*
 * Returns something like "medalCollection_a.json" for all of the mapUids starting with a.
 * Similarly, will return "medalCollection_aa.json" for mapUids starting with a capital A.
 */
string getFileLocation(string &in fileSuffix) {
    // Turns capitals into doubles. Eg: G into gg
    string id = "" + fileSuffix.ToLower() + ((fileSuffix.ToLower() == fileSuffix) ? "" : fileSuffix.ToLower());
    return IO::FromStorageFolder("medalCollection_" + id + ".json");
}

void writeSingleStorageFile(string &in mapId) {
    // Temp dictionary just contains maps that start with the same letter as the given mapId
    dictionary alphaDict;
    string char = mapId.SubStr(0, 1);
    auto allMaps = mapDict.GetKeys();
    for (uint i=0; i < allMaps.Length; i++) {
        if (allMaps[i].StartsWith(char)) {
            int medalEarned;
            mapDict.Get(allMaps[i], medalEarned);
            alphaDict.Set(allMaps[i], medalEarned);
        }
    }

    writeDictionaryToFile(char, alphaDict);
}

void writeDictionaryToFile(string &in char, dictionary alphaDict) {
    string jsonFileLocation = getFileLocation(char);

    auto content = Json::Object();
    content["maps"] = alphaDict.ToJson();

    Json::ToFile(jsonFileLocation, content);

    log("Medal collection written to " + jsonFileLocation + ". (" + alphaDict.GetKeys().Length + " medals)");
}

// Honestly, this entire function feels really clunky and awkward - It does work, but I'm sure there's a cleaner way to write it
void writeAllStorageFiles() {
    dictionary alphaDict; // Dictionary of dictionaries

    log("About to write all storage files");

    // Part 1: Read the known list and group them into buckets
    auto allMaps = mapDict.GetKeys();
    for (uint i=0; i < allMaps.Length; i++) {
        string mapId = allMaps[i];
        string char = mapId.SubStr(0, 1);
        if (!alphaDict.Exists(char)) {
            dictionary emptyDict;
            alphaDict.Set(char, emptyDict);
        }
        dictionary letterDict;

        auto dictForThisLetter = cast<dictionary>(alphaDict[char]);
        int medalEarned;
        mapDict.Get(allMaps[i], medalEarned);
        dictForThisLetter.Set(mapId, medalEarned);
    }

    yield();

    // Part 2: Write each bucket into its own JSON file
    auto allLetters = alphaDict.GetKeys();
    for (uint i=0; i < allLetters.Length; i++) {
        string char = allLetters[i].SubStr(0, 1);
        auto content = Json::Object();

        dictionary dictForThisLetter;
        alphaDict.Get(char, dictForThisLetter);

        writeDictionaryToFile(char, dictForThisLetter);
        yield();
    }
}

/**
 * Examine every file in the PluginStorage folder, and if it seems like one of our collection JSONs, read it
 * Returns the number of successfully read files, so that you can check, for example, if 0 files were found
 */
int readStorageFiles() {
    // Reset the storage data
    for(uint i=0; i < allMedals.Length; i++) {
        medalDict.Set("" + allMedals[i].medalId, array<string>(0));
    }

    string rootPath = IO::FromStorageFolder("");
    log(rootPath);
    array<string> existingFiles = IO::IndexFolder(rootPath, false);
    log("Found " + existingFiles.Length + " potential record files to read");
    int numCollectionsFound = 0;
    for(uint i=0; i < existingFiles.Length; i++){
        string fileName = existingFiles[i];
        if (fileName.Contains("/medalCollection_") && fileName.EndsWith('.json')) {
            readStorageFile(fileName);
            numCollectionsFound++;
            yield();
        }
    }

    // Log the output (for development's sake)
    for(uint i=0; i < allMedals.Length; i++){
        log("Final number of " + allMedals[i].color + allMedals[i].name + "\\$g medals: " + allMedals[i].count);
    }

    return numCollectionsFound;
}

void readStorageFile(string &in jsonFile) {
    if (IO::FileExists(jsonFile)) {
        auto content = Json::FromFile(jsonFile);
        dictionary tempMedals;

        for(uint i=0; i < allMedals.Length; i++){
            tempMedals.Set("" + allMedals[i].medalId, 0);
        }

        auto mapList = content.Get("maps");

        // Quick guard to ensure the maps object exists in the file
        if (mapList.GetType() != 0) {
            auto allIds = mapList.GetKeys();
            for(uint i=0; i < allIds.Length; i++) {
                auto medalEarned = int(mapList.Get("" + allIds[i]));
#if !DEPENDENCY_WARRIORMEDALS
                // If the Warrior plugin was uninstalled then just revert to Author
                if (medalEarned == WARRIOR_MEDAL_ID) {
                    medalEarned = AUTHOR_MEDAL_ID;
                }
#endif
                mapDict.Set(allIds[i], medalEarned);
                auto newTotal = int(tempMedals["" + medalEarned]) + 1;
                tempMedals.Set("" + medalEarned, newTotal);

                // Add mapId to the per-medal list
                getMapPool(medalEarned).InsertLast(allIds[i]);
            }
        }

        // Add the results to the existing values
        for(uint i=0; i < allMedals.Length; i++){
            allMedals[i].count += int(tempMedals["" + allMedals[i].medalId]);
        }
    }
}