// Your completion time on a track is this by default
uint MAX_INT = 4294967295;

bool showUI = false;
string currentMapId = "";
int currentMapMedal = NO_MEDAL_ID;

void Main() {
    // Set up HTTP access for downloading records
    NadeoServices::AddAudience("NadeoServices");

    // Prepare the Storage class - It needs to check for some dependency stuff
    initialiseStorage();

    // Load any previous data
    int filesRead = readStorageFiles();

    if (filesRead == 0) {
        print("No existing MedalCollection JSON files found - Assuming first installation");
        UI::ShowNotification("Medal Collection", "Thank you for installing the Medal Collection plugin. Fetching your past medals now...");
        recheckNormalRecords();
        recheckWarriorRecords(); // If plugin isn't installed, this returns quickly
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
    auto network = cast<CTrackManiaNetwork>(GetApp().Network);
    auto scoreMgr = network.ClientManiaAppPlayground.ScoreMgr;
    auto userMgr = network.ClientManiaAppPlayground.UserMgr;

    MwId userId;
    if (userMgr.Users.Length > 0) {
        userId = userMgr.Users[0].Id;
    } else {
        userId.Value = uint(-1);
    }

    // We don't really care about times, but it helps figure out the difference between played and finished
    uint raceTime = scoreMgr.Map_GetRecord_v2(userId, currentMapId, "PersonalBest", "", "TimeAttack", "");
    uint stuntTime = scoreMgr.Map_GetRecord_v2(userId, currentMapId, "PersonalBest", "", "Stunt", "");
    uint raceMedal = scoreMgr.Map_GetMedal(userId, currentMapId, "PersonalBest", "", "TimeAttack", "");
    uint stuntMedal = scoreMgr.Map_GetMedal(userId, currentMapId, "PersonalBest", "", "Stunt", "");

    log("Best medal is " + raceMedal + " or " + stuntMedal + ". Best time is " + raceTime + " or " + stuntTime);

    currentMapMedal = Math::Max(raceMedal, stuntMedal);
    // Math::Min doesn't seem to work with MAX_INT, so we'll just check both times separately

    // Game will return 0 for unfinished maps AND for times slower than bronze. Checking for a time will differentiate it
    if (raceTime < MAX_INT || stuntTime < MAX_INT) {
        log("Earned " + currentMapMedal);
        int pluginMedal = checkForPluginMedals(currentMapId, raceTime);
        if (pluginMedal > currentMapMedal) {
            print("You've earned a third-party medal: " + pluginMedal);
            currentMapMedal = pluginMedal;
        }
        updateSaveData(currentMapId, currentMapMedal);
        return true;
    }

    // If we don't have a race time, then the map hasn't been finished
    currentMapMedal = UNFINISHED_MEDAL_ID;
    updateSaveData(currentMapId, UNFINISHED_MEDAL_ID);
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
                 yield();
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
            if (prevUiSequence != uiSequence && (uiSequence == CGamePlaygroundUIConfig::EUISequence::EndRound || uiSequence == CGamePlaygroundUIConfig::EUISequence::UIInteraction)) {
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
            currentMapMedal = NO_MEDAL_ID;
        }
        yield();
    }
}