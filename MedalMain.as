// Your completion time on a track is this by default
uint MAX_INT = 4294967295;

string accountId; // Set once after init

bool showUI = false;
string currentMapId = "";
int currentMapMedal = -99; // Can't use -1, because we use that for unfinished maps

void Main() {
    // Set up HTTP access for downloading records
    NadeoServices::AddAudience("NadeoServices");

    // Load any previous data
    int filesRead = readStorageFiles();

    if (filesRead == 0) {
        print("No existing MedalCollection JSON files found - Assuming first installation");
        UI::ShowNotification("Medal Collection", "Thank you for installing the Medal Collection plugin. Fetching your past medals now...");
        checkAllRecords();
    }

    // Start a co-routine to watch for race-finish events
    startnew(checkForFinish);

    // Finally, keep an eye out for newly loaded maps
    startnew(checkForMapLoad);

    print("Medal Collection initialised");
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
        log("Current MapId changed to " + mapId);
        showUI = true;
        currentMapId = mapId;

        // When loading a map, check to see if a medal was earned previously
        // For new maps this will trigger an "unfinished" medal to be saved
        // For maps you've played before, it's a sanity check
        checkForEarnedMedal();
    }
}

// Returns true if a valid time was located
bool checkForEarnedMedal() {
    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto scoreMgr = network.ClientManiaAppPlayground.ScoreMgr;
    auto userMgr = network.ClientManiaAppPlayground.UserMgr;

    MwId userId;
    if (userMgr.Users.Length > 0) {
        userId = userMgr.Users[0].Id;
    } else {
        userId.Value = uint(-1);
    }

    uint time = scoreMgr.Map_GetRecord_v2(userId, currentMapId, "PersonalBest", "", "TimeAttack", "");
    uint medal = scoreMgr.Map_GetMedal(userId, currentMapId, "PersonalBest", "", "TimeAttack", "");
    log("Best medal is " + medal + ". Best time is " + time);

    // Medal is 0 if the map is unfinished OR if you didn't reach bronze. So, check for a time to ensure medal 0 means finished.
    if (time < MAX_INT) {
        currentMapMedal = medal;
        updateSaveData(currentMapId, medal);
        return true;
    }

    currentMapMedal = -1;
    updateSaveData(currentMapId, -1);
    return false;
}

void checkForFinish() {
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
                clearNextMap();
            }

            // This state probably means we're playing Royal
            if (currentMapId == "") {
                continue;
            }

            auto terminal = playground.GameTerminals[0];
            auto uiSequence = terminal.UISequence_Current;

            bool stopChecking = true;

            if (prevUiSequence != uiSequence && uiSequence == CGamePlaygroundUIConfig::EUISequence::Finish) {
                // If the time has yet to be registered, wait until next tick
                // This works great for the first earned medal, but doesn't help for medal improvements
                stopChecking = checkForEarnedMedal();
            }

            // If the new time wasn't ready when we did a check on finish, it might be ready during the EndRound sequence
            // This should help catch medal improvements, but won't get triggered during Random Map Challenge
            if (prevUiSequence != uiSequence && uiSequence == CGamePlaygroundUIConfig::EUISequence::EndRound) {
                checkForEarnedMedal();
            }

            if (uiSequence != prevUiSequence && stopChecking) {
                log("UI Sequence changed: " + uiSequence + ". Prev: " + prevUiSequence);
                prevUiSequence = uiSequence;
            }
        }
        else if (playgroundLoaded == true) {
            log("Played is heading back to main menu");
            playgroundLoaded = false;
            currentMapMedal = -99;
        }
        yield();
    }
}