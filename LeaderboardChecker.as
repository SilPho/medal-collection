// class WorldRecord {
// 	string playerId;
// 	uint bestTime; // Most modes
// 	uint bestScore; // Stunt mode

//     WorldRecord() {
//         // Empty constructor
//     }

// 	WorldRecord(const string &in playerId, const string &in gameMode, uint scoreOrTime){
//         this.playerId = playerId;

// 		if (gameMode == "TrackMania\\TM_Stunt") {
//             this.bestScore = scoreOrTime;
//         }
//         else {
//             // If new game modes are added in the future, time-based seems like the better default
//             this.bestTime = scoreOrTime;
//         }
// 	}
// }

bool recordCheckInProgress = false;

const int LEADERBOARD_RECORD_THROTTLE_MS = 2000; // Milliseconds to wait between Nadeo API calls

const dictionary ZONE_ORDER = {{"0", WORLD_ID}, {"1", CONTINENT_ID}, {"2", TERRITORY_ID}, {"3", REGION_ID}, {"4", DISTRICT_ID}};

int64 heldCheckEnded = -1;

bool authorCheckFinished = false;
bool goldCheckFinished = false;
bool silverCheckFinished = false;
bool bronzeCheckFinished = false;
bool noMedalsCheckFinished = false;

const string checkerStatusFile = IO::FromStorageFolder('collection_status.json');

// --------------------------------------------------------

// Fetch the player zone names from a Nadeo API and use that to rename the player zones
void getPlayerZones() {
    try {
        auto jsonToSend = Json::Parse("{ \"listPlayer\": [{ \"accountId\": \"" + GetApp().LocalPlayerInfo.WebServicesUserId + "\"}]}");
        auto zoneResponse = postToUrl(NadeoServices::BaseURLLive() + "/api/token/leaderboard/trophy/player", jsonToSend);

        Json::Value zoneDetails = Json::Parse(zoneResponse);

        // This isn't particularly well guarded against API changes (yet), hence the try block
        Json::Value zoneList = zoneDetails.Get("rankings")[0].Get("zones");

        int zoneId;

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
            // Check to see which leaderboard scans have been run before (and when)
            readCheckerStatus();

            // Check the user's medals to see if any of them are also leaderboard-topping records
            // After intial installation, this will probably return instantly
            scanForLeaderboardRecords();

            // If enough time has past since the last time we rescanned the leaderboard records
            if (isCheckRequired()) {
                checkLeaderboardRecordsStillHeld();
            }
            else {
                // [TODO] Enable me again // log("The last leaderboard check ended recently (" + Time::FormatString("%c", heldCheckEnded) + ") Too early to do another one");
                log("Too early to do another rescan");
            }
        }
        catch {
           warn("Problem during record check: " + getExceptionInfo());
        }

        recordCheckInProgress = false;
    }
    else {
        UI::ShowNotification("Unable to run", "Another leaderboard record check is in progress. Please try again later");
    }
}

void resetAllLeaderboardChecks() {
    authorCheckFinished = false;
    goldCheckFinished = false;
    silverCheckFinished = false;
    bronzeCheckFinished = false;
    noMedalsCheckFinished = false;
    writeCheckerStatus();
    doLeaderboardChecks();
}

// Initial scan for leaderboard records - This *should* only need to be done in first install, but users can manually request it
void scanForLeaderboardRecords() {
    log("Checking if any leaderboard scans are required");

    if (!authorCheckFinished) {
        print("Author check needed");
        // Get all of the AUTHOR (or better) medals - This covers the third party plugins too
        checkPool(getMapPoolsAtOrAbove(AUTHOR_MEDAL_ID, RecordType::MEDAL), "Author medals (& above)");
        authorCheckFinished = true;
        writeCheckerStatus();
    }

    if (!goldCheckFinished) {
        checkPool(getMapPool(GOLD_MEDAL_ID), "Gold medals");
        goldCheckFinished = true;
        writeCheckerStatus();
    }

    if (!silverCheckFinished) {
        checkPool(getMapPool(SILVER_MEDAL_ID), "Silver medals");
        silverCheckFinished = true;
        writeCheckerStatus();
    }

    if (!bronzeCheckFinished) {
        checkPool(getMapPool(BRONZE_MEDAL_ID), "Bronze medals");
        bronzeCheckFinished = true;
        writeCheckerStatus();
    }

    if (!noMedalsCheckFinished) {
        checkPool(getMapPool(FINISHED_MEDAL_ID), "finished tracks");
        noMedalsCheckFinished = true;
        writeCheckerStatus();
    }
}

void checkPool(array<string> potentialMedalMaps, const string &in humanFriendlyScanName) {
    if (potentialMedalMaps.Length == 0) {
        log(humanFriendlyScanName + " pool is empty");
        return;
    }

    print("You have " + potentialMedalMaps.Length + " " + humanFriendlyScanName + ". Checking if any of those are top of any leaderboards...");
    // UI::ShowNotification("Scan starting", "Checking " + potentialMedalMaps.Length + " " + humanFriendlyScanName + " to see if you hold a record");

    uint changesMade = 0;

    // [TODO] - The min needs to be removed
    for (int i = 0; i < Math::Min(5, potentialMedalMaps.Length); i++) {
        string mapId = potentialMedalMaps[i];
        log("Checking if you're top of any boards on " + mapId);
        int leaderboardId = getPlayerLeaderboardRecord(mapId);

        if (leaderboardId != NO_MEDAL_ID) {
            // Yes the player has (or still has) the record
            updateSaveData(mapId, leaderboardId, RecordType::LEADERBOARD, true);
            changesMade++;
        }

        // Sequential saves for larger collections (Avoids loss of data during a close or crash)
        if (i % 50 == 0 && changesMade > 0) {
            log("Leaderboard scan " + i + "/" + potentialMedalMaps.Length + ". Saving " + changesMade + " change(s)");
            writeAllStorageFiles(RecordType::LEADERBOARD);
            writeCheckerStatus();
            changesMade = 0;
        }
        sleep(LEADERBOARD_RECORD_THROTTLE_MS);
    }

    print("Finished scanning for " + potentialMedalMaps.Length + " potential leadboard records for " + humanFriendlyScanName);
    const string suffix = changesMade > 0 ? (" You're top of " + changesMade + " leaderboard" + (changesMade == 1 ? '' : 's') + ". Nice driving!") : "";
    UI::ShowNotification("Scan complete", "Your " + potentialMedalMaps.Length + " " + humanFriendlyScanName + "have been checked." + suffix);

    if (changesMade > 0) {
        writeAllStorageFiles(RecordType::LEADERBOARD);
    }
}

// Subsequent re-check for existing records to see if they've been beaten. There's no way to manually trigger this, it happens automatically
void checkLeaderboardRecordsStillHeld() {
    recordCheckInProgress = true;
    log("Starting re-check of all held leaderboard records");

    array<string> currentRecords = getMapPoolsAtOrAbove(DISTRICT_ID, RecordType::LEADERBOARD);

    if (currentRecords.Length == 0) {
        print("You don't have any leaderboard records that need to be checked again - Keep grinding!");
        recordCheckInProgress = false;
        return;
    }

    // Shuffle the array to ensure very large collections won't scan the same records on every game boot
    if (currentRecords.Length > 50) {
        for (uint i = currentRecords.Length - 1; i >= 0; i--) {
            uint j = Math::Rand(0, i + 1);
            string temp = currentRecords[i];
            currentRecords[i] = currentRecords[j];
            currentRecords[j] = temp;
        }
    }

    print("Looks like you previously had " + currentRecords.Length + " leaderboard records. Let's see if they're still valid");

    uint changesMade = 0;

    // Make note of when the scan started
    heldCheckEnded = -1;
    writeCheckerStatus();

    for (uint i = 0; i < currentRecords.Length; i++) {
        string mapId = currentRecords[i];
        int leaderboardId = getPlayerLeaderboardRecord(mapId);

        if (leaderboardId != NO_MEDAL_ID) {
            // Record found, possibly different
            forceUpdateSaveDataa(mapId, RecordType::LEADERBOARD, leaderboardId, true);
            changesMade++;
        }

        if (i % 50 == 0 && changesMade > 0) {
            log("Leaderboard record re-scan " + i + "/" + currentRecords.Length + ". Saving " + changesMade + " change(s)");
            writeAllStorageFiles(RecordType::LEADERBOARD);
            changesMade = 0;
        }

        sleep(LEADERBOARD_RECORD_THROTTLE_MS); // Throttle down to make sure we don't trip over any rate limits
    }

    print("Check of " + currentRecords.Length + " medals is complete");

    if(changesMade > 0) {
        writeAllStorageFiles(RecordType::LEADERBOARD);
    }

    heldCheckEnded = Time::Stamp;
    writeCheckerStatus();

    recordCheckInProgress = false;
}

int getPlayerLeaderboardRecord(const string &in mapUid) {
    string currentPlayerId = GetApp().LocalPlayerInfo.WebServicesUserId;
    string url;

    // [TODO] Use a cache when racing
    // if (worldRecordCache.Exists(mapUid)) {
    //     WorldRecord currentRecord;
    //     worldRecordCache.Get(mapUid, currentRecord);
    //     if (currentRecord.playerId == currentPlayerId) {
    //         return true;
    //     }
    // }

    // Also, you could use a seasonal/campaign groupID to batch fetch leaderboards - It might cut down on searches
    url = NadeoServices::BaseURLLive() + "/api/token/leaderboard/group/Personal_Best/map/" + mapUid + "/top?/length=1";

    string response = getFromUrl(url);
    // print(response);
    Json::Value recordDetails = Json::Parse(response);
    log("Response for " + mapUid + " has " + recordDetails["tops"].Length + " zones to check");

    // print(string(recordDetails["tops"]));
    for (uint i= 0; i < recordDetails["tops"].Length; i++) {
        Json::Value zone = recordDetails["tops"][i];

        // If a record doesn't exist (and it won't for Platform mode) just carry on
        if (zone["top"].Length == 0) {
            continue;
        }

        Json::Value zoneLeader = zone["top"][0];
        auto leaderId = string(zoneLeader["accountId"]);
        // log(string(zone["zoneName"]) + ". Record is " + int(zoneLeader["score"]) + " by " + leaderId);

        // print("Comparing " + leaderId + " to " + currentPlayerId);
        if (leaderId == currentPlayerId) {
            print("You have the " + string(zone["zoneName"]) + " record on " + mapUid);
            return int(ZONE_ORDER["" + i]);
        }
    }

    return NO_MEDAL_ID;
}

// --------------------------------------------------------


bool isCheckRequired() {
    const int64 RECHECK_THRESHOLD = 1000 * 60 * 60 * 12; // Half a day

    int64 currentTime = Time::Stamp;

    if (heldCheckEnded > currentTime) {
        // This strange case seems to happen when the Json doesn't contain the right value
        return true;
    }

    log("Rescan check: Is " + currentTime + " - " + RECHECK_THRESHOLD + " = " + (currentTime - RECHECK_THRESHOLD) +" > " + heldCheckEnded + "?");
    return (currentTime - RECHECK_THRESHOLD) > heldCheckEnded;
}

void readCheckerStatus() {
    if (IO::FileExists(checkerStatusFile)) {
        auto content = Json::FromFile(checkerStatusFile);

        heldCheckEnded = readIntValue(content, "checkEnded");
        authorCheckFinished = readBoolValue(content, "authorCheckDone");
        goldCheckFinished = readBoolValue(content, "goldCheckDone");
        silverCheckFinished = readBoolValue(content, "silverCheckDone");
        bronzeCheckFinished = readBoolValue(content, "bronzeCheckDone");
        noMedalsCheckFinished = readBoolValue(content, "noMedalCheckDone");

        log("State of medal checks: A: " + authorCheckFinished + ". G: " + goldCheckFinished + ". S: " + silverCheckFinished + ". B: " + bronzeCheckFinished + ". O: " + noMedalsCheckFinished);
    }
}

void writeCheckerStatus() {
    dictionary toWrite = {
        { "checkEnded", heldCheckEnded },
        { "authorCheckDone", authorCheckFinished },
        { "goldCheckDone", goldCheckFinished },
        { "silverCheckDone", silverCheckFinished },
        { "bronzeCheckDone", bronzeCheckFinished },
        { "noMedalCheckDone", noMedalsCheckFinished }
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