class MedalCount {
    int medalId;
	string name;
	int count;
	string color;
    array<float> buttonHsv;
    string tooltipSuffix;
    bool isVisible = false; // This will be set by getPlayerZones() on first boot
    bool rescanCompleted = false; // This will be set by readCheckerStatus()
    bool isEligibleForScans = false;

	MedalCount(int medalId, const string &in name="", const string &in color="$000", array<float> buttonHsv = { 0, 1, 1 }, const string &in tooltipSuffix = ""){
        this.medalId = medalId;
		this.name = name;
		this.count = 0;
		this.color = color;
        this.buttonHsv = buttonHsv;
        this.tooltipSuffix = tooltipSuffix;
        this.isVisible = false;
        this.rescanCompleted = false;
	}
}

enum RecordType { LEADERBOARD, MEDAL };

// The value of these is important - "Better" medals need higher numbers
const int WORLD_ID = 100;
const int CONTINENT_ID = 90;
const int TERRITORY_ID = 80;
const int REGION_ID = 70;
const int DISTRICT_ID = 60;

const int CHAMPION_MEDAL_ID = 20; // Maybe coming soon
const int WARRIOR_MEDAL_ID = 10;
const int AUTHOR_MEDAL_ID = 4; // This has to match what Nadeo uses (same for Gold, etc)
const int GOLD_MEDAL_ID = 3;
const int SILVER_MEDAL_ID = 2;
const int BRONZE_MEDAL_ID = 1;
const int FINISHED_MEDAL_ID = 0; // Not really a "medal" but that name will do
const int UNFINISHED_MEDAL_ID = -1;
const int NO_MEDAL_ID = -99;

// Create holders for each different type of record and medal
auto world = MedalCount(WORLD_ID, "World", "\\$333", { 0, 0, 0.2 }, "that you have the World Record on");
auto continent = MedalCount(CONTINENT_ID, "Continent", "\\$c11", { 0, 0.9, 0.7}, "that you have the Continental on");
auto territory = MedalCount(TERRITORY_ID, "Territory", "\\$35e", { 0.63, 0.8, 0.9}, "that you hold the National record on");
auto region = MedalCount(REGION_ID, "Region", "\\$3b6", { 0.4, 0.7, 0.7}, "that you have the Regional record on");
auto district = MedalCount(DISTRICT_ID, "District", "\\$bbb", { 1, 0, 0.7}, "that you have the Local District record on");

auto champion = MedalCount(CHAMPION_MEDAL_ID, "Champion", "\\$901", { 0, 0.7, 0.8}, "that you earned a Champion medal on");
auto warrior = MedalCount(WARRIOR_MEDAL_ID, "Warrior", "\\$000", { 0, 0, 0 }, "that you earned a Warrior medal on"); // Colours sourced from actual plugin
auto author = MedalCount(AUTHOR_MEDAL_ID, "Author", "\\$071", { 0.34, 1, 0.47 }, "that you earned an Author medal on");
auto gold = MedalCount(GOLD_MEDAL_ID, "Gold", "\\$db4", { 0.13, 0.70, 0.87}, "that you earned a Gold medal on");
auto silver = MedalCount(SILVER_MEDAL_ID, "Silver", "\\$899", { 0.5, 0.11, 0.60}, "that you earned a Silver medal on");
auto bronze = MedalCount(BRONZE_MEDAL_ID, "Bronze", "\\$964", { 0.06, 0.57, 0.6}, "that you earned a Bronze medal on");
auto finishes = MedalCount(FINISHED_MEDAL_ID, "Finished", "\\$aaf", { 0.66, 0.32, 0.96}, "that you have finished but didn't get a medal on");
auto unfinished = MedalCount(UNFINISHED_MEDAL_ID, "Played", "\\$ccc", { 0.5, 0.11, 0.60}, "that you have played but not finished yet" );

// This is what gets shown in the UI - The order is important
array<MedalCount@> leaderboardRecords = { world, continent, territory, region, district };
array<MedalCount@> medalRecords = { author, gold, silver, bronze, finishes, unfinished };

// This is for internal use. The order is not important
array<MedalCount@> allRecords = {champion, warrior, author, gold, silver, bronze, finishes, unfinished, world, continent, territory, region, district };

// Mapping of mapId to medalId (not leaderboards)
dictionary mapMedalDict;

// Mapping of mapId to leaderboardId
dictionary mapLeaderboardDict;

// Mapping of medals to mapUid[] (Includes medal and leaderboard pools)
dictionary randomMapPools;

bool isInitialised = false;

void initialiseStorage() {
    // Make sure you don't accidentally do this twice
    if (isInitialised) {
        return;
    }

#if DEPENDENCY_WARRIORMEDALS
    // Since the WarriorMedals plugin provides an interface for fetching colours, might as well use it
    warrior.color = WarriorMedals::GetColorStr();
    vec3 v = WarriorMedals::GetColorVec();
    v = UI::ToHSV(v.x, v.y, v.z);
    warrior.buttonHsv = { v.x, v.y, v.z };

    // Add the warrior medal counter to the front of the list
    medalRecords.InsertAt(0, warrior);
#endif

#if DEPENDENCY_CHAMPIONMEDALS
    medalRecords.InsertAt( 0, champion);
#endif

    startnew(asyncInitialise);
}

void asyncInitialise() {
    // Find the zones that this player is in (Sets names and visibility accordingly)
    getPlayerZones();

    // Now that we know which learderboards we can show, we can turn on the medal display too (avoids jumping UI)
    for(uint j = 0; j < medalRecords.Length; j++) {
        medalRecords[j].isVisible = true;
        medalRecords[j].isEligibleForScans = medalRecords[j].medalId != UNFINISHED_MEDAL_ID;
    }

    isInitialised = true;
    log("Medal Collection storage is initialised");
}

// Updates the save data if required. Returns true if a change is made, false otherwise
bool updateSaveData(const string &in mapId, int newBestMedal, RecordType recordType, bool suppressWriting = false) {
    dictionary@ sourceDict = recordType == RecordType::LEADERBOARD ? mapLeaderboardDict : mapMedalDict;
    int oldCurrentMedal = NO_MEDAL_ID;
    if (sourceDict.Exists(mapId)) {
        sourceDict.Get(mapId, oldCurrentMedal);
    }
    bool improvedMedal = newBestMedal > oldCurrentMedal;
    bool hadAnyMedalAlready = sourceDict.Exists(mapId);
    bool forceSaveDueTo3rdParty = recordType == RecordType::MEDAL && newBestMedal != oldCurrentMedal && oldCurrentMedal > author.medalId;

    // Only do a full-save if the medal has actually been improved (or )
    if (newBestMedal != NO_MEDAL_ID && (forceSaveDueTo3rdParty || !hadAnyMedalAlready || improvedMedal)) {
        const string typeAsStr = recordType == RecordType::LEADERBOARD ? 'leaderboard record' : 'medal';

        if (forceSaveDueTo3rdParty) {
            log("Forcing a save of this " + typeAsStr + " because we might need to overwrite a 3rd party medal");
        }
        else if (!hadAnyMedalAlready) {
            log("Forcing a save because this is the first " + typeAsStr + " for this map");
        }
        else {
            log("Forcing a save because the player has improved an existing " + typeAsStr);
        }
        // log("This is either a new " + typeAsStr + ": " + !hadAnyMedalAlready + " OR it is an improvement: " + improvedMedal + " (" + newBestMedal + " > " + oldCurrentMedal + ")");
        forceUpdateSaveData(mapId, newBestMedal, recordType, suppressWriting);
        return true;
    }

    return false;
}

// Updates the save data even if the accomplishment is a downgrade. Makes no change if it matches what is already saved.
bool forceUpdateSaveData(const string &in mapId, int bestMedal, RecordType recordType, bool suppressWriting = false) {
    dictionary@ targetDict = recordType == RecordType::LEADERBOARD ? mapLeaderboardDict : mapMedalDict;

    // log("Target dict has " + targetDict.GetSize() + " entries in it already");
    bool hadMedalAlready = targetDict.Exists(mapId);
    int currentMedal = NO_MEDAL_ID;
    if (hadMedalAlready) {
        targetDict.Get(mapId, currentMedal);
    }

    // If you had something before and nothing has changed, or you didn't have anything and you still don't, we can end early
    if ((hadMedalAlready && currentMedal == bestMedal) || (!hadMedalAlready && bestMedal == NO_MEDAL_ID)) {
        log("Skip medal save - It's a match");
        return false;
    }

    // Adjust the counters that are shown on screen (This is not what changes the files on disk)
    for(uint i=0; i < allRecords.Length; i++) {
        // Increase count for new medal type (unless it's NO_MEDAL_ID, which is handled later)
        if (allRecords[i].medalId == bestMedal) {
            print("Storing record on " + mapId + ". Medal earned: " + allRecords[i].name);
            allRecords[i].count++;

            // Add the map to the random pool for this medal
            getMapPool(bestMedal).InsertLast(mapId);
        }
        // If there was an old medal, better remove that to avoid duplicate counts
        if (hadMedalAlready && allRecords[i].medalId == currentMedal) {
            log("Removing old medal: " + allRecords[i].name);
            allRecords[i].count--;

            // Also need to remove it from the random map pool
            deleteFromMapPool(mapId, currentMedal);
        }
    }

    // This is what changes the contents of the JSON files we'll write to disk later
    if (bestMedal == NO_MEDAL_ID) {
        // Deleting from the dictionary will also prevent it being saved to the JSON file
        targetDict.Delete(mapId);
    }
    else {
        targetDict.Set(mapId, bestMedal);
    }

    if (!suppressWriting) {
        writeSingleStorageFile(mapId, recordType);
    }

    return true;
}

array<string> getMapPool(int medalId) {
    if (randomMapPools.Exists("" + medalId)) {
        return cast<array<string>>(randomMapPools["" + medalId]);
    }

    warn("Tried to open an invalid map pool: " + medalId);
    return {};
}

array<string> truncateMapPool(int medalId) {
    randomMapPools.Set("" + medalId, array<string>(0));
    return getMapPool(medalId);
}

    // Note that this doesn't reset the pool before iterating through it
    array<string> getMapPoolsAtOrAbove(int minMedalId, RecordType recordType) {
    array<string> combinedPool = {};

    array<MedalCount@>@ sourceList = recordType == RecordType::LEADERBOARD ? leaderboardRecords : medalRecords;

    for(uint i=0; i < sourceList.Length; i++) {
        int currentMedalId = sourceList[i].medalId;
        if (currentMedalId >= minMedalId) {
            rebuildMapPool(currentMedalId);
            // auto validPool = cast<array<string>>(randomMapPools["" + currentMedalId]);
            auto validPool = getMapPool(currentMedalId);
            combinedPool.InsertAt(0, validPool);
            log("Added " + validPool.Length + " " + sourceList[i].name + " medals to combined list (" + currentMedalId + " vs " + minMedalId + " vs " + AUTHOR_MEDAL_ID + ")");
        }
    }

    return combinedPool;
}

/**
 * Permanently remove a map from storage (Designed for recovering from software bugs rather than expecting players to lose medals)
 */
void deleteMapFromStorage(const string &in mapId, RecordType recordType) {
    dictionary@ sourceDict = recordType == RecordType::LEADERBOARD ? mapLeaderboardDict : mapMedalDict;

    log("Deleting mapID (" + mapId + ") from storage");
    int previousMedal = NO_MEDAL_ID; // Temp value
    sourceDict.Get(mapId, previousMedal);

    if (previousMedal == NO_MEDAL_ID) {
        // Gracefully ignore the case where it can't be found
        return;
    }

    // Lower the current visible medal count (Superficial)
    for(uint i=0; i < allRecords.Length; i++){
        if (allRecords[i].medalId == previousMedal) {
            allRecords[i].count--;
        }
    }

    // Actually delete the map from the permanent record
    sourceDict.Delete(mapId);
    writeSingleStorageFile(mapId, recordType);
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
 * Scans every medal from every map to find ones that you have a certain medal on
 * This is usually used when the random map button has run out of options and needs to cycle round again
 * But is also used when we need the entire pool for a certain medal, and not one that might have some randomly removed
 */
void rebuildMapPool(int medalIdForEmptyPool) {
    auto mapPool = truncateMapPool(medalIdForEmptyPool);

    dictionary@ sourceDict = medalIdForEmptyPool >= DISTRICT_ID ? mapLeaderboardDict : mapMedalDict;

    auto allMaps = sourceDict.GetKeys();

    for (uint i=0; i < allMaps.Length; i++) {
        int medalEarned;
        sourceDict.Get(allMaps[i], medalEarned);
        if (medalEarned == medalIdForEmptyPool) {
            mapPool.InsertLast(allMaps[i]);
        }
    }

    log("Map pool #" + medalIdForEmptyPool + " rebuilt: Has "+ mapPool.Length + " maps in it again (Sanity: " + getMapPool(medalIdForEmptyPool).Length + ")");
}

/*
 * Returns something like "medalCollection_a.json" for all of the mapUids starting with a.
 * Similarly, will return "medalCollection_aa.json" for mapUids starting with a capital A.
 */
string getFileLocation(string &in fileSuffix, RecordType recordType) {
    // Turns capitals into doubles. Eg: G into gg
    string id = "" + fileSuffix.ToLower() + ((fileSuffix.ToLower() == fileSuffix) ? "" : fileSuffix.ToLower());
    string prefix = recordType == RecordType::MEDAL ? "medalCollection_" : "recordCollection_";
    return IO::FromStorageFolder(prefix + id + ".json");
}

void writeSingleStorageFile(string &in mapId, RecordType recordType) {
    dictionary@ sourceDict = recordType == RecordType::LEADERBOARD ? mapLeaderboardDict : mapMedalDict;

    // Temp dictionary just contains maps that start with the same letter as the given mapId
    dictionary alphaDict;
    string char = mapId.SubStr(0, 1);
    auto allMaps = sourceDict.GetKeys();
    for (uint i=0; i < allMaps.Length; i++) {
        if (allMaps[i].StartsWith(char)) {
            int medalEarned;
            sourceDict.Get(allMaps[i], medalEarned);
            alphaDict.Set(allMaps[i], medalEarned);
        }
    }

    writeDictionaryToFile(char, alphaDict, recordType);
}

void writeDictionaryToFile(string &in char, dictionary alphaDict, RecordType recordType) {
    string jsonFileLocation = getFileLocation(char, recordType);

    auto content = Json::Object();
    content["maps"] = alphaDict.ToJson();

    Json::ToFile(jsonFileLocation, content);

    log("\\$f0fMedal collection written to " + jsonFileLocation + ". (" + alphaDict.GetKeys().Length + " medals)");
}

// Honestly, this entire function feels really clunky and awkward - It does work, but I'm sure there's a cleaner way to write it
void writeAllStorageFiles(RecordType recordType) {
    dictionary@ sourceDict = recordType == RecordType::LEADERBOARD ? mapLeaderboardDict : mapMedalDict;

    dictionary alphaDict; // Dictionary of dictionaries

    log("About to write all storage files");

    // Part 1: Read the known list and group them into buckets
    auto allMaps = sourceDict.GetKeys();
    for (uint i=0; i < allMaps.Length; i++) {
        string mapId = allMaps[i];
        string char = mapId.SubStr(0, 1);
        if (!alphaDict.Exists(char)) {
            dictionary emptyDict;
            alphaDict.Set(char, emptyDict);
        }

        auto dictForThisLetter = cast<dictionary>(alphaDict[char]);
        int medalEarned;
        sourceDict.Get(allMaps[i], medalEarned);
        dictForThisLetter.Set(mapId, medalEarned);
    }

    yield();

    // Part 2: Write each bucket into its own JSON file
    auto allLetters = alphaDict.GetKeys();
    for (uint i=0; i < allLetters.Length; i++) {
        string char = allLetters[i].SubStr(0, 1);

        dictionary dictForThisLetter;
        alphaDict.Get(char, dictForThisLetter);

        writeDictionaryToFile(char, dictForThisLetter, recordType);
        yield();
    }
}

/**
 * Examine every file in the PluginStorage folder, and if it seems like one of our collection JSONs, read it
 * Returns the number of successfully read files, so that you can check, for example, if 0 files were found
 */
int readStorageFiles() {
    // On first load we need to do some checks
    initialiseStorage();

    // Reset the storage data (This is the first time it gets initialised)
    for(uint i=0; i < allRecords.Length; i++) {
        truncateMapPool(allRecords[i].medalId);
    }

    string rootPath = IO::FromStorageFolder("");
    log(rootPath);
    array<string> existingFiles = IO::IndexFolder(rootPath, false);
    log("Found " + existingFiles.Length + " potential record files to read");
    int numCollectionsFound = 0;
    for(uint i=0; i < existingFiles.Length; i++){
        string fileName = existingFiles[i];
        if (fileName.EndsWith('.json')) {
            // log("Attempting to read " + fileName);
            if (fileName.Contains("/recordCollection_") || fileName.Contains("/medalCollection_")) {
                readStorageFile(fileName);
                numCollectionsFound++;
            }
            yield();
        }
    }

    // Log the output (for development's sake)
    for(uint i=0; i < allRecords.Length; i++){
        print("Current number of " + allRecords[i].color + allRecords[i].name + "\\$g medals: " + allRecords[i].count);
    }

    log("Medal map size: " + mapMedalDict.GetSize());
    log("Leaderboard map size: " + mapLeaderboardDict.GetSize());

    return numCollectionsFound;
}

void readStorageFile(string &in jsonFile) {
    if (IO::FileExists(jsonFile)) {
        //try {
            auto content = Json::FromFile(jsonFile);
            dictionary tempMedals;

            for(uint i=0; i < allRecords.Length; i++){
                tempMedals.Set("" + allRecords[i].medalId, 0);
            }

            auto mapList = content.Get("maps");

            dictionary@ sourceDict = jsonFile.Contains('recordCollection') ? mapLeaderboardDict : mapMedalDict;

            // Quick guard to ensure the maps object exists in the file
            if (!(mapList is null) && mapList.GetType() != 0) {
                auto allIds = mapList.GetKeys();
                for(uint i=0; i < allIds.Length; i++) {
                    auto medalEarned = int(mapList.Get("" + allIds[i]));
#if !DEPENDENCY_WARRIORMEDALS
                    // If the Warrior Medals plugin was uninstalled then just revert to Author
                    if (medalEarned == WARRIOR_MEDAL_ID) {
                        medalEarned = AUTHOR_MEDAL_ID;
                    }
#endif
#if !DEPENDENCY_CHAMPIONMEDALS
                    // Similarly, if the Champion Medals plugin was uninstalled then just revert to Author
                    // [TODO] Might need to check if they have the Warrior medal instead
                    if (medalEarned == CHAMPION_MEDAL_ID) {
                        medalEarned = AUTHOR_MEDAL_ID;
                    }
#endif
                    sourceDict.Set(allIds[i], medalEarned);

                    auto newTotal = int(tempMedals["" + medalEarned]) + 1;
                    tempMedals.Set("" + medalEarned, newTotal);

                    // Add mapId to the per-medal list
                    getMapPool(medalEarned).InsertLast(allIds[i]);
                }
            }

            // Add the results to the existing values
            for(uint i=0; i < allRecords.Length; i++){
                allRecords[i].count += int(tempMedals["" + allRecords[i].medalId]);
            }
        // }
        // catch {
        //     warn("Unable to read from " + jsonFile + ". " + getExceptionInfo());
        // }
    }
}