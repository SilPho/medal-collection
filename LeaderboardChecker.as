bool recordCheckInProgress = false;

const int LEADERBOARD_RECORD_THROTTLE_MS = 2000; // Milliseconds to wait between Nadeo API calls

const dictionary ZONE_ORDER = {{"0", WORLD_ID}, {"1", CONTINENT_ID}, {"2", TERRITORY_ID}, {"3", REGION_ID}, {"4", DISTRICT_ID}};

int64 heldCheckEnded = -1;

const string checkerStatusFile = IO::FromStorageFolder('collection_status.json');

string currentScanDescription = "";

// --------------------------------------------------------

// Fetch the player zone names from a Nadeo API and use that to rename the player zones and toggle their visibility
void getPlayerZones() {
    try {
        string accountId = GetApp().LocalPlayerInfo.WebServicesUserId;
        auto jsonToSend = Json::Parse("{ \"listPlayer\": [{ \"accountId\": \"" + accountId + "\"}]}");
        auto zoneResponse = postToUrl(NadeoServices::BaseURLLive() + "/api/token/leaderboard/trophy/player", jsonToSend);

        Json::Value zoneDetails = Json::Parse(zoneResponse);

        // This isn't particularly well guarded against API changes (yet), hence the try block
        Json::Value zoneList = zoneDetails.Get("rankings")[0].Get("zones");

        int zoneId;

        print("Your ID is " + accountId + ", and you are part of " + zoneList.Length + " regional zones");

        for (uint i = 0; i < zoneList.Length; i++) {
            string realName = string(zoneList[i].Get("zoneName"));
            for(uint j = 0; j < leaderboardRecords.Length; j++) {
                ZONE_ORDER.Get("" + i, zoneId);
                if (leaderboardRecords[j].medalId == zoneId) {
                    log(leaderboardRecords[j].name + " is \"" + realName + "\"");
                    leaderboardRecords[j].name = realName;

                    leaderboardRecords[j].isVisible = true;
                    break;
                }
            }
        }
    }
    catch {
        warn("Unable to finish getting player zones. " + getExceptionInfo());
    }
}

// --------------------------------------------------------

void doLeaderboardChecks() {
    if (!recordCheckInProgress) {
        recordCheckInProgress = true;

        try {
            // Check to see which leaderboard scans have been run before
            if (heldCheckEnded == -1) {
                log("First check since game launch: Time to read previous status");
                readCheckerStatus();
            }

            // Check the user's medals to see if any of them are also leaderboard-topping records
            // After intial installation, this will probably return instantly
            scanForLeaderboardRecords();

            // If enough time has past since the last time we rescanned the leaderboard records
            if (isCheckRequired()) {
                checkLeaderboardRecordsStillHeld();
            }
        }
        catch {
            // Catching the errors prevents the whole plugin from falling over (But we do lose stack info)
           warn("Problem during record check: " + getExceptionInfo());
        }

        recordCheckInProgress = false;
    }
    else {
        UI::ShowNotification("Unable to run", "Another leaderboard record check is in progress. Please try again later");
    }
}

// Initial scan for leaderboard records - This *should* only need to be done in first install, but users can manually request it
void scanForLeaderboardRecords() {
    log("Checking if any leaderboard scans are required");

    for (uint i = 0; i < medalRecords.Length; i++) {
        auto mc = medalRecords[i];
        if (mc.medalId == UNFINISHED_MEDAL_ID) {
            continue;
        }
        if (!mc.rescanCompleted) {
            print("Rescan required for " + mc.name);
            checkPool(getMapPool(mc.medalId), mc.name + " medals");

            mc.rescanCompleted = true;
            writeCheckerStatus();
        }
    }
}

void checkPool(array<string> potentialMedalMaps, const string &in humanFriendlyScanName) {
    if (potentialMedalMaps.Length == 0) {
        log(humanFriendlyScanName + " pool is empty");
        return;
    }

    print("You have " + potentialMedalMaps.Length + " " + humanFriendlyScanName + ". Checking if any of those are top of any leaderboards...");

    uint changesMade = 0;
    bool savePending = false;

    for (uint i = 0; i < potentialMedalMaps.Length; i++) {
        string mapId = potentialMedalMaps[i];
        log("Checking if you're top of any boards on " + mapId);
        int leaderboardId = getPlayerLeaderboardRecord(mapId);

        // Yes the player has (or still has) the record
        if (forceUpdateSaveData(mapId, leaderboardId, RecordType::LEADERBOARD, true)) {
            changesMade++;
            savePending = true;
        }

        // Sequential saves for larger collections (Avoids loss of data during a close or crash)
        if (i > 0 && i % 100 == 0 && changesMade > 0) {
            log("Leaderboard scan " + i + "/" + potentialMedalMaps.Length + ". Saving " + changesMade + " change(s)");
            writeAllStorageFiles(RecordType::LEADERBOARD);
            writeCheckerStatus();
            savePending = false;
        }

        currentScanDescription = "Scan in progress: " + humanFriendlyScanName + " - " + i + "/" + potentialMedalMaps.Length;
        sleep(LEADERBOARD_RECORD_THROTTLE_MS);
    }

    print("Finished scanning for " + potentialMedalMaps.Length + " potential leadboard records for " + humanFriendlyScanName);
    currentScanDescription = "Scan complete: " + humanFriendlyScanName + " yielded " + changesMade + " record" + (changesMade == 1 ? "" : "s");
    const string suffix = changesMade > 0 ? (" You're top of " + changesMade + " leaderboard" + (changesMade == 1 ? '' : 's') + ". Nice driving!") : "";

    if (changesMade > 0) {
        writeAllStorageFiles(RecordType::LEADERBOARD);
    }
}

// Subsequent re-check for existing records to see if they've been beaten. There's no way to manually trigger this, it happens automatically
void checkLeaderboardRecordsStillHeld() {
    recordCheckInProgress = true;
    print("Starting re-check of all held leaderboard records");

    array<string> currentRecords = getMapPoolsAtOrAbove(DISTRICT_ID, RecordType::LEADERBOARD);

    if (currentRecords.Length == 0) {
        print("You don't have any leaderboard records that need to be checked again - Keep grinding!");
        heldCheckEnded = Time::Stamp;
        return;
    }

    // Shuffle the array to ensure very large collections won't scan the same records on every game boot
    if (currentRecords.Length > 50) {
        for (uint i = currentRecords.Length - 1; i > 0; i--) {
            uint j = Math::Rand(0, i + 1);
            string temp = currentRecords[i];
            currentRecords[i] = currentRecords[j];
            currentRecords[j] = temp;
        }
        yield();
    }

    print("Looks like you previously had " + currentRecords.Length + " leaderboard records. Let's see if they're still valid");

    uint changesMade = 0;

    // Make note of when the scan started
    heldCheckEnded = -1;
    writeCheckerStatus();

    for (uint i = 0; i < currentRecords.Length; i++) {
        string mapId = currentRecords[i];
        int leaderboardId = getPlayerLeaderboardRecord(mapId);

        if (forceUpdateSaveData(mapId, leaderboardId, RecordType::LEADERBOARD, true)) {
            changesMade++;
        }

        if (i > 0 && i % 50 == 0 && changesMade > 0) {
            log("Leaderboard record re-scan " + i + "/" + currentRecords.Length + ". Saving " + changesMade + " change(s)");
            writeAllStorageFiles(RecordType::LEADERBOARD);
            changesMade = 0;
        }

        currentScanDescription = "Scan in progress: Existing record re-check - " + i + "/" + currentRecords.Length;
        sleep(LEADERBOARD_RECORD_THROTTLE_MS); // Throttle down to make sure we don't trip over any rate limits
    }

    print("Check of " + currentRecords.Length + " medals/records is complete");
    currentScanDescription = "";

    if(changesMade > 0) {
        writeAllStorageFiles(RecordType::LEADERBOARD);
    }

    heldCheckEnded = Time::Stamp;
    writeCheckerStatus();
}

dictionary leaderboardCache = {};

int getPlayerLeaderboardRecord(const string &in mapUid, bool skipCache = false) {
    // Check the cache if possible
    if (!skipCache && leaderboardCache.Exists(mapUid)) {
        log("Found cache entry for " + mapUid);
        int output;
        leaderboardCache.Get(mapUid, output);
        return output;
    }

    string currentPlayerId = GetApp().LocalPlayerInfo.WebServicesUserId;
    string url;

    // Also, you could use a seasonal/campaign groupID to batch fetch leaderboards - It might cut down on searches
    url = NadeoServices::BaseURLLive() + "/api/token/leaderboard/group/Personal_Best/map/" + mapUid + "/top?/length=1";

    string response = getFromUrl(url);
    // print(response);

    Json::Value recordDetails = Json::Parse(response);

    if (!recordDetails.HasKey("tops")) {
        log("It looks like " + mapUid + " might not exist");
        leaderboardCache.Set(mapUid, NO_MEDAL_ID);
        return NO_MEDAL_ID;
    }

    log("Response for " + mapUid + " has " + recordDetails["tops"].Length + " zones to check");
    // print(string(recordDetails["tops"]));

    for (uint i= 0; i < recordDetails["tops"].Length; i++) {
        Json::Value zone = recordDetails["tops"][i];

        // If a record doesn't exist (and it won't for Platform mode) just carry on
        if (!zone.HasKey("top") || zone["top"].Length == 0) {
            continue;
        }

        Json::Value zoneLeader = zone["top"][0];
        auto leaderId = string(zoneLeader["accountId"]);
        // log(string(zone["zoneName"]) + ". Record is " + int(zoneLeader["score"]) + " by " + leaderId);

        // print("Comparing " + leaderId + " to " + currentPlayerId);
        if (leaderId == currentPlayerId) {
            log("\\$fffYou have the " + string(zone["zoneName"]) + " record on " + mapUid);
            int leaderboardId = int(ZONE_ORDER["" + i]);
            leaderboardCache.Set(mapUid, leaderboardId);
            return leaderboardId;
        }
    }

    leaderboardCache.Set(mapUid, NO_MEDAL_ID);
    return NO_MEDAL_ID;
}

// --------------------------------------------------------

bool isCheckRequired() {
    const int64 RECHECK_THRESHOLD = 60 * 60 * 24 * 7; // Once a week is probably fine

    int64 currentTime = Time::Stamp;

    if (heldCheckEnded > currentTime) {
        // This strange case seems to happen when the Json doesn't contain the right value
        return true;
    }

    bool result = (currentTime - RECHECK_THRESHOLD) > heldCheckEnded;
    log("Rescan timer check: Is " + (currentTime - RECHECK_THRESHOLD) +" > " + heldCheckEnded + "? " + (result ? "YES! Time to check held records" : "Nope, we can wait"));
    return result;
}

void readCheckerStatus() {
    if (IO::FileExists(checkerStatusFile)) {
        auto content = Json::FromFile(checkerStatusFile);

        heldCheckEnded = readIntValue(content, "checkEnded");
        warrior.rescanCompleted = readBoolValue(content, "warriorCheckDone");
        author.rescanCompleted = readBoolValue(content, "authorCheckDone");
        gold.rescanCompleted = readBoolValue(content, "goldCheckDone");
        silver.rescanCompleted = readBoolValue(content, "silverCheckDone");
        bronze.rescanCompleted = readBoolValue(content, "bronzeCheckDone");
        finishes.rescanCompleted = readBoolValue(content, "noMedalCheckDone");

        log("State of medal checks:");
        for (uint i = 0; i < medalRecords.Length; i++) {
            if (medalRecords[i].medalId == UNFINISHED_MEDAL_ID) {
                continue;
            }

            log("  - " + medalRecords[i].name + ": " + medalRecords[i].rescanCompleted);
        }
    }
}

void writeCheckerStatus() {
    dictionary toWrite = {
        { "checkEnded", heldCheckEnded },
        { "warriorCheckDone", warrior.rescanCompleted },
        { "authorCheckDone", author.rescanCompleted },
        { "goldCheckDone", gold.rescanCompleted },
        { "silverCheckDone", silver.rescanCompleted },
        { "bronzeCheckDone", bronze.rescanCompleted },
        { "noMedalCheckDone", finishes.rescanCompleted }
    };

    log("CheckerStatus to be written to disk: " + Json::Write(toWrite));
    auto content = toWrite.ToJson();

    Json::ToFile(checkerStatusFile, content);
    yield();
}

int64 readIntValue(Json::Value@ content, string &in keyName) {
    if (content.GetType() != Json::Type::Null && content.HasKey(keyName)) {
        // Convert from Json:Value to string to int64
        auto value = Text::ParseInt64(Json::Write(content.Get(keyName)));
        return (value > 0) ? value : -1;
    }

    log(keyName + " does not exist yet");
    return -1;
}

bool readBoolValue(Json::Value@ content, string &in keyName) {
    if (content.GetType() != Json::Type::Null && content.HasKey(keyName)) {
        return Json::Write(content.Get(keyName)) == 'true';
    }

    log(keyName + " does not exist yet");
    return false;
}