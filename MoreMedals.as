uint checkForPluginMedals(const string &in currentMapId, int bestTime) {
    int output = 0;
#if DEPENDENCY_WARRIORMEDALS
    // log("Checking for Warrior medals");
    int targetTime = WarriorMedals::GetWMTime(currentMapId);
    if (targetTime > 0 && bestTime <= targetTime) {
        log("You did it! You got the Warrior medal");
        output = WARRIOR_MEDAL_ID;
    }
#endif

    return output;
}

void checkWarriorRecords() {
#if DEPENDENCY_WARRIORMEDALS
    startnew(getWarriorMedals);
#else
    log("Can't check Warrior medals - Dependency not installed");
#endif
}

void getWarriorMedals() {
    bool didSomethingChange = false;
    MEDAL_CHECK_STATUS.currentScanDescription = "Warrior medal check in progress (This should only take a second)";

#if DEPENDENCY_WARRIORMEDALS
    dictionary warriorData = WarriorMedals::GetMaps();
    array<string> mapUids = warriorData.GetKeys();
    int medalsFound = 0;

    for(uint i = 0; i < mapUids.Length; i++) {
        string mapUid = mapUids[i];
        auto warriorResult = cast<WarriorMedals::Map>(warriorData[mapUid]);

        if (warriorResult.get_hasWarrior()) {
            bool newInformation = updateSaveData(mapUid, WARRIOR_MEDAL_ID, RecordType::MEDAL, true);
            didSomethingChange = didSomethingChange || newInformation;
            medalsFound++;
        }
    }
#endif

    if (didSomethingChange) {
        print("One or more 3rd-party plugins changed something. Re-saving the data");
        writeAllStorageFiles(RecordType::MEDAL);
    }
    else {
        print("Warrior medals are unchanged. No save required");
    }

    MEDAL_CHECK_STATUS.currentScanDescription = "Warrior medal check found " + medalsFound + " medal" + (medalsFound == 1 ? "" : "s");
}