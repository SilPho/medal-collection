string getCurrentMapId() {
	auto app = cast<CTrackMania>(GetApp());
	auto map = app.RootMap;

	if (map !is null && app.Editor is null && isValidMapType(map.MapType)) {
		return map.MapInfo.MapUid;
	}
	return "";
}

// For now I'm assuming that only TM_Race is a valid map type
bool isValidMapType(const string &in mapType) {
    return mapType == "TrackMania\\TM_Race";
}

bool isPlayerInGame() {
	try {
		auto app = cast<CTrackMania>(GetApp());
		return !(app.RootMap is null) && app.Editor is null;
	}
	catch {
		return false;
	}
}

void log(string &in message) {
	if (settings_debugMode) {
    	trace(message);
	}
}

void waitForNadeoAuthentication() {
    log("Checking Nadeo authentication");
    while (!NadeoServices::IsAuthenticated("NadeoServices")) {
        yield();
    }
    log("Nadeo authentication in progress");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) {
        yield();
    }
    log("Nadeo authentication confirmed");
}

string getMapSearchUrl(bool useMapUidEndpoint = false) {
    return NadeoServices::BaseURLCore() + "/maps/?" + (useMapUidEndpoint ? "mapUid" : "mapId") + "List=";
}

string getFromUrl(string &in url) {
	waitForNadeoAuthentication();

    log("About to query: " + url);
    Net::HttpRequest@ mapReq = NadeoServices::Get("NadeoServices", url);
    mapReq.Start();
    while (!mapReq.Finished()) {
        yield();
    }

    if (mapReq.ResponseCode() != 200) {
        log("Trackmania API might be broken " + mapReq.ResponseCode() + ". Response was " + mapReq.Body);
        throw("Unable to fetch " + url);
    }

    return mapReq.String();
}