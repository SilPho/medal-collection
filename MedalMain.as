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
        if (playground !is null && playground.GameTerminals.Length > 0) {
            if (playgroundLoaded == false) {
                log("Player loaded a new map");
                playgroundLoaded = true;

                // If we loaded a map we don't need to show a random one any more
                clearNextMap();
            }

            auto terminal = playground.GameTerminals[0];
            auto uiSequence = terminal.UISequence_Current;
                bool holdForMedalCheck = false;
                if (prevUiSequence != uiSequence && uiSequence == CGamePlaygroundUIConfig::EUISequence::Finish) {
                    log('Finish detected');

                    // If the time has yet to be registered, wait until next tick
                    // This works great for the first earned medal, but getting a new medal can sometimes go unnoticed if playing Random Map Challenge
                    holdForMedalCheck = !checkForEarnedMedal();
                }

                if (uiSequence != prevUiSequence && !holdForMedalCheck) {
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