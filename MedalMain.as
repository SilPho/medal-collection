// Your completion time on a track is this by default
const uint MAX_INT = 4294967295;

bool showUI = false;
string currentMapId = "";
int currentMapMedal = NO_MEDAL_ID;
int currentMapLeaderboardId = NO_MEDAL_ID;
uint currentBestTimeOrScore = MAX_INT;
dictionary mapsToCheckLater = {};

void Main() {
    log("Medal Collection plugin initialising...");

    auto startedMs = Time::get_Now();
    // Set up HTTP access for downloading records
    NadeoServices::AddAudience("NadeoServices");
    NadeoServices::AddAudience("NadeoLiveServices");

    // Load any previous data
    int filesRead = readStorageFiles();

    if (filesRead == 0) {
        print("No existing MedalCollection JSON files found - Assuming first installation");
        UI::ShowNotification("Medal Collection", "Thank you for installing the Medal Collection plugin. Fetching your past medals now...");
        checkAllNadeoRecords();
        checkWarriorRecords(); // If plugin isn't installed, this returns quickly
    }

    // Start a co-routine to watch for race-finish events (This runs indefinitely)
    startnew(sequenceWatcher);

    // Start another one to keep an eye out for newly loaded maps (Also runs indefinitely)
    startnew(checkForMapLoad);

    // Double check the user's current leaderboard positions (Will terminate when it finishes)
    startnew(doLeaderboardChecks);

    // Check records again "later" in case the servers are busy, or when records change often in ToTD (Runs indefinitely, but sparsely)
    startnew(recheckPreviousMaps);

    print("Medal Collection initialised in " + (Time::get_Now() - startedMs) + " ms");
}

void checkForMapLoad() {
    while (true) {
        updateUiVisibility();

        if (isPlayerInGame()) {
            checkForNewMap();
        }
        else {
            if (currentMapId != "") {
                log("Player is in menu");
            }
            currentMapId = "";
        }

		sleep(1000);
	}
}

void checkForNewMap() {
    string mapId = getCurrentMapId();

    if (mapId != "" && mapId != currentMapId)
    {
        log("\\$f0fCurrent MapId changed to " + mapId);
        currentMapId = mapId;
        currentBestTimeOrScore = MAX_INT;

        // When loading a map, check to see if a medal was earned previously
        // For new maps this will trigger an "unfinished" medal to be saved
        // For maps you've played before, it's a sanity check
        checkForEarnedMedal();
    }
}

int checkMapLeaderboard(const string &in mapId, bool skipCache = false, uint bestRaceTime  = MAX_INT) {
    int leaderboardId = getPlayerLeaderboardRecord(mapId, skipCache, bestRaceTime);

    log("Leaderboard status for " + mapId + " is " + leaderboardId);
    updateSaveData(mapId, leaderboardId, RecordType::LEADERBOARD);
    return leaderboardId;
}

// Returns true if any valid time was located (not necessarily an improved time)
bool checkForEarnedMedal() {
    auto network = cast<CTrackManiaNetwork>(GetApp().Network);
    if (network is null || network.ClientManiaAppPlayground is null) {
        warn("Tried to check for earned medals when outside of a playground");
        return false;
    }
    auto scoreMgr = network.ClientManiaAppPlayground.ScoreMgr;
    auto userMgr = network.ClientManiaAppPlayground.UserMgr;
    auto map = GetApp().RootMap;

    MwId userId;
    if (userMgr.Users.Length > 0) {
        userId = userMgr.Users[0].Id;
    } else {
        userId.Value = uint(-1);
    }

    const string gameMode = getGameMode(map.MapType);
    if (gameMode == "") {
        return false;
    }

    // We don't really care about times, but it helps figure out the difference between played and finished
    uint bestTime = scoreMgr.Map_GetRecord_v2(userId, currentMapId, "PersonalBest", "", gameMode, "");

    // Cheaty way to make the math work out, because now "lower" scores are better for Stunt mode
    if (gameMode == "Stunt") {
        bestTime = -bestTime;
    }

    currentMapMedal = scoreMgr.Map_GetMedal(userId, currentMapId, "PersonalBest", "", gameMode, "");

    int pluginMedal = checkForPluginMedals(currentMapId, bestTime);
    if (pluginMedal > currentMapMedal) {
        print("You've earned a third-party medal: " + pluginMedal);
        currentMapMedal = pluginMedal;
    }

    log("Map type: " + gameMode + ". Best medal is " + currentMapMedal + ". Best time (or score) is " + bestTime);

    // Game will return 0 for unfinished maps AND for times slower than bronze. Checking for a time will differentiate it
    if (bestTime < currentBestTimeOrScore) {
        updateSaveData(currentMapId, currentMapMedal, RecordType::MEDAL);
        checkAgainLater(currentMapId);

        currentBestTimeOrScore = bestTime;
        if (gameMode == "TimeAttack") {
            currentMapLeaderboardId = checkMapLeaderboard(currentMapId, true, currentBestTimeOrScore);
        }
        else {
            currentMapLeaderboardId = checkMapLeaderboard(currentMapId, true);
        }
        return true;
    }

    // A time has been set, but it's not a new PB
    if (bestTime < MAX_INT) {
        return true;
    }

    // If we don't have a race time, then the map hasn't been finished
    currentMapMedal = UNFINISHED_MEDAL_ID;
    updateSaveData(currentMapId, UNFINISHED_MEDAL_ID, RecordType::MEDAL);
    return false;
}

// Keep an eye on the game state. There are certain conditions that will warrant a re-check of records and medals
void sequenceWatcher() {
    int prevUiSequence = 0;
    bool playgroundLoaded = false;

    while(true) {
        auto playground = GetApp().CurrentPlayground;

        // Only check if we are in-game and on a map that the plugin supports (Eg: Not Royal)
        if (playground !is null && playground.GameTerminals.Length > 0) {
            if (playgroundLoaded == false) {
                log("Player loaded a new map");
                playgroundLoaded = true;

                // If we loaded a map we don't need to show a random one any more
                clearNextRandomMap();
            }

            // This state probably means we're playing Royal
            if (currentMapId == "") {
                 yield();
                continue;
            }

            auto terminal = playground.GameTerminals[0];
            auto uiSequence = terminal.UISequence_Current;

            // On first load of a map, check again because sometimes it doesn't catch it on map switch
            if (prevUiSequence != uiSequence && uiSequence == CGamePlaygroundUIConfig::EUISequence::Intro) {
                bool timeSet = checkForEarnedMedal();
                if (timeSet && currentMapLeaderboardId == NO_MEDAL_ID) {
                    currentMapLeaderboardId = checkMapLeaderboard(currentMapId);
                }
            }

            // Trigger when the player crosses the finish line
            if (prevUiSequence != uiSequence && uiSequence == CGamePlaygroundUIConfig::EUISequence::Finish) {
                // This sometimes isn't ready, which is why we check again later. But it's the only chance we have during Random Map Challenge
                checkForEarnedMedal();
            }

            // If an improved time wasn't ready when we did a check on finish, it might be ready during the EndRound sequence
            // This should help catch medal improvements, but won't get triggered during a Random Map Challenge
            if (prevUiSequence != uiSequence && (uiSequence == CGamePlaygroundUIConfig::EUISequence::EndRound || uiSequence == CGamePlaygroundUIConfig::EUISequence::UIInteraction)) {
                checkForEarnedMedal();
            }

            if (uiSequence != prevUiSequence) {
                log("UI Sequence changed: " + uiSequence + ". Prev: " + prevUiSequence);
                prevUiSequence = uiSequence;
            }
        }
        else if (playgroundLoaded == true) {
            log("Player is heading back to main menu");
            playgroundLoaded = false;
            currentMapMedal = NO_MEDAL_ID;
            currentMapLeaderboardId = NO_MEDAL_ID;
        }
        yield();
    }
}

void checkAgainLater(const string &in mapId) {
    mapsToCheckLater.Set(mapId, Time::Stamp + 60);
}

/*
 * Sometimes it takes a while for records to filter through the back-end systems. This will keep things up to date
 * This will wake periodically, but is only likely to make an API request once per minute at most
 */
void recheckPreviousMaps() {
    while(true) {
        sleep(10 * 1000); // 10 seconds between possible checks

        auto keys = mapsToCheckLater.GetKeys();
        int64 targetTime;
        for (uint i = 0; i < keys.Length; i++) {
            auto mapId = keys[i];
            mapsToCheckLater.Get(mapId, targetTime);
            if (targetTime < Time::Stamp) {
                log("Time to re-check a previous map: " + mapId);
                // checkForEarnedMedal(); - This won't work, it uses the current ScoreManager
                int newLeaderboardState = checkMapLeaderboard(mapId, true);

                if (mapId == currentMapId) {
                    currentMapLeaderboardId = newLeaderboardState;
                }
                mapsToCheckLater.Delete(mapId);
            }
        }
    }
}