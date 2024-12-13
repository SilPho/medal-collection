class AsyncCheckStatus {
    bool recordCheckInProgress = false;
    bool interruptCurrentScan = false;
    int64 heldCheckEnded = -1;
    string currentScanDescription = "";
    int currentScanId = NO_MEDAL_ID;
}

class LeaderboardResult {
    int leaderboardId;
    bool usedCache;

    LeaderboardResult(int leaderboardId) {
        this.leaderboardId = leaderboardId;
        this.usedCache = false;
    }

    LeaderboardResult(int leaderboardId, bool usedCache) {
        this.leaderboardId = leaderboardId;
        this.usedCache = usedCache;
    }
}

AsyncCheckStatus LEADERBOARD_STATUS = AsyncCheckStatus();
AsyncCheckStatus MEDAL_CHECK_STATUS = AsyncCheckStatus();

const int LEADERBOARD_RECORD_THROTTLE_MS = 2000; // Milliseconds to wait between Nadeo API calls

const dictionary ZONE_ORDER = {{"0", WORLD_ID}, {"1", CONTINENT_ID}, {"2", TERRITORY_ID}, {"3", REGION_ID}, {"4", DISTRICT_ID}};

const string checkerStatusFile = IO::FromStorageFolder('collection_status.json');

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
    if (settings_displayMode & DISPLAY_MODE_LEADERBOARDS == 0) {
        print("Not checking leaderboards because the results aren't visible anyway");
    }
    else if (!LEADERBOARD_STATUS.recordCheckInProgress) {
        LEADERBOARD_STATUS.recordCheckInProgress = true;

        try {
            // Check to see which leaderboard scans have been run before
            if (LEADERBOARD_STATUS.heldCheckEnded == -1) {
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
           LEADERBOARD_STATUS.currentScanDescription = "Error during scan. Please check logs for more info";
        }

        LEADERBOARD_STATUS.recordCheckInProgress = false;
        LEADERBOARD_STATUS.currentScanId = NO_MEDAL_ID;
        LEADERBOARD_STATUS.interruptCurrentScan = false;
    }
    else {
        UI::ShowNotification("Already scanning", "A leaderboard record check is already in progress");
    }

}

// Initial scan for leaderboard records - This *should* only need to be done in first install, but users can manually request it
// This is designed to ONLY be called as part of doLeaderboardChecks(). The state machine will probably break otherwise
void scanForLeaderboardRecords() {
    log("Checking if any leaderboard scans are required");

    for (uint i = 0; i < medalRecords.Length; i++) {
        auto mc = medalRecords[i];
        if (mc.medalId == UNFINISHED_MEDAL_ID || LEADERBOARD_STATUS.interruptCurrentScan) {
            continue;
        }
        if (!mc.rescanCompleted) {
            print("Rescan required for " + mc.name);
            LEADERBOARD_STATUS.currentScanId = mc.medalId;
            checkPool(getMapPool(mc.medalId), mc.name + " medals");

            if (!LEADERBOARD_STATUS.interruptCurrentScan) {
                mc.rescanCompleted = true;
            }
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
        LeaderboardResult@ leaderboardResult = getPlayerLeaderboardRecord(mapId);

        // Yes the player has (or still has) the record
        if (forceUpdateSaveData(mapId, leaderboardResult.leaderboardId, RecordType::LEADERBOARD, true)) {
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

        if (LEADERBOARD_STATUS.interruptCurrentScan) {
            print("Leaderboard scan interrupted by user");
            LEADERBOARD_STATUS.currentScanDescription = humanFriendlyScanName + " check was interrupted";
            return;
        }

        const int minsRemaining = ((LEADERBOARD_RECORD_THROTTLE_MS * (potentialMedalMaps.Length - i) / 60000) + 1);
        LEADERBOARD_STATUS.currentScanDescription = "Checking " + humanFriendlyScanName + " - " + (i + 1) + "/" + potentialMedalMaps.Length
         + " (About " + minsRemaining + " minute" + (minsRemaining == 1 ? '' : 's') + " remaining)";

        // Allow for faster iteration if we have a cached result
        if (!leaderboardResult.usedCache) {
            sleep(LEADERBOARD_RECORD_THROTTLE_MS);
        }
    }

    print("Finished scanning for " + potentialMedalMaps.Length + " potential leadboard records for " + humanFriendlyScanName);
    LEADERBOARD_STATUS.currentScanDescription = "Check of " + humanFriendlyScanName + " completed successfully and made " + changesMade + " change" + (changesMade == 1 ? "" : "s");

    if (changesMade > 0) {
        writeAllStorageFiles(RecordType::LEADERBOARD);
    }
}

// Subsequent re-check for existing records to see if they've been beaten. There's no way to manually trigger this, it happens automatically
void checkLeaderboardRecordsStillHeld() {
    LEADERBOARD_STATUS.recordCheckInProgress = true;
    print("Starting re-check of all held leaderboard records");

    array<string> currentRecords = getMapPoolsAtOrAbove(DISTRICT_ID, RecordType::LEADERBOARD);

    if (currentRecords.Length == 0) {
        print("You don't have any leaderboard records that need to be checked again - Keep grinding!");
        LEADERBOARD_STATUS.heldCheckEnded = Time::Stamp;
        return;
    }

    // Shuffle the array to ensure very large collections won't scan the same records on every game boot
    if (currentRecords.Length > 50) {
        for (uint i = currentRecords.Length - 1; i > 0; i--) {
            uint j = Math::Rand(0, i + 1);
            string temp = currentRecords[i];
            currentRecords[i] = currentRecords[j];
            currentRecords[j] = temp;

            // Be considerate of slower machines
            if (i % 200 == 0) {
                yield();
            }
        }
    }

    // Reset the end timestamp, so if it gets interrupted we know to resume it
    LEADERBOARD_STATUS.heldCheckEnded = -1;
    writeCheckerStatus();

    checkPool(currentRecords, "your existing leaderboard records");

    if (!LEADERBOARD_STATUS.interruptCurrentScan) {
        LEADERBOARD_STATUS.heldCheckEnded = Time::Stamp;
        writeCheckerStatus();
    }
}

dictionary leaderboardCache = {};

LeaderboardResult getPlayerLeaderboardRecord(const string &in mapUid, bool skipCache = false, uint bestRaceTime = MAX_INT) {
    // Check the cache if possible
    if (!skipCache && leaderboardCache.Exists(mapUid)) {
        log("Found cache entry for " + mapUid);
        int output;
        leaderboardCache.Get(mapUid, output);
        return LeaderboardResult(output, true);
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
        return LeaderboardResult(NO_MEDAL_ID, false);
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
        uint score = int(zoneLeader["score"]);
        // log(string(zone["zoneName"]) + ". Record is " + int(zoneLeader["score"]) + " by " + leaderId);

        // Either the server will say you have the record, or the current time is better
        // Checking for an improved time does mean we assume the zones remain ordered from widest to narrowest (From World to district)
        if (leaderId == currentPlayerId || bestRaceTime < score) {
            log("\\$fffYou have the " + string(zone["zoneName"]) + " record on " + mapUid + " (" + bestRaceTime + " < " + score + ")");
            int leaderboardId = int(ZONE_ORDER["" + i]);
            leaderboardCache.Set(mapUid, leaderboardId);
            return LeaderboardResult(leaderboardId);
        }
    }

    leaderboardCache.Set(mapUid, NO_MEDAL_ID);
    return LeaderboardResult(NO_MEDAL_ID);
}

// --------------------------------------------------------

bool isCheckRequired() {
    if (LEADERBOARD_STATUS.interruptCurrentScan) {
        log("Interrupt flag is set, ignoring rescan timer");
        return false;
    }

    const int64 RECHECK_THRESHOLD = 60 * 60 * 24 * 7; // Once a week is probably fine

    int64 currentTime = Time::Stamp;

    if (LEADERBOARD_STATUS.heldCheckEnded > currentTime) {
        // This strange case seems to happen when the Json doesn't contain the right value
        return true;
    }

    bool result = (currentTime - RECHECK_THRESHOLD) > LEADERBOARD_STATUS.heldCheckEnded;
    log("Rescan timer check: Is " + (currentTime - RECHECK_THRESHOLD) +" > " + LEADERBOARD_STATUS.heldCheckEnded + "? " + (result ? "YES! Time to check held records" : "Nope, we can wait"));
    return result;
}

void readCheckerStatus() {
    if (IO::FileExists(checkerStatusFile)) {
        auto content = Json::FromFile(checkerStatusFile);

        LEADERBOARD_STATUS.heldCheckEnded = readIntValue(content, "checkEnded");
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
        { "checkEnded", LEADERBOARD_STATUS.heldCheckEnded },
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