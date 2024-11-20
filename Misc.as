string getCurrentMapId() {
	auto app = cast<CTrackMania>(GetApp());
	auto map = app.RootMap;

	if (map !is null && app.Editor is null && isValidMapType(map.MapType)) {
		return map.MapInfo.MapUid;
	}
	return "";
}

// We could just accept anything that isn't Royal, but it's safer to be explicit
bool isValidMapType(const string &in mapType) {
    return mapType == "TrackMania\\TM_Race" || mapType == "TrackMania\\TM_Stunt" || mapType == "TrackMania\\TM_Platform";
}

// Reminder: GameMode and Map Type are not always the same thing. TM_Race is a map type. TimeAttack is a game mode.
string getGameMode(const string &in mapType) {
    if (!isValidMapType(mapType)) {
        return "";
    }
    if (mapType == "TrackMania\\TM_Stunt") {
        return "Stunt";
    }
    if (mapType == "TrackMania\\TM_Platform") {
        return "Platform";
    }
    return "TimeAttack";
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

    // Live endpoint required for leaderboard checks
    log("Checking Live Nadeo authentication");
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

    log("\\$0afAbout to GET: " + url);
    auto audience = url.Contains(NadeoServices::BaseURLCore()) ? "NadeoServices" : "NadeoLiveServices";
    Net::HttpRequest@ mapReq = NadeoServices::Get(audience, url);
    mapReq.Start();
    while (!mapReq.Finished()) {
        yield();
    }

    if (mapReq.ResponseCode() != 200) {
        log("Trackmania API might be broken. Status: " + mapReq.ResponseCode() + ". Response was: " + mapReq.Body);
        throw("Unable to fetch " + url);
    }

    // Maybe consider if you can pre-parse this response into a Json
    return mapReq.String();
}

string postToUrl(string &in url, Json::Value content) {
    waitForNadeoAuthentication();

    log("\\$0afAbout to POST: " + url);
    auto audience = url.Contains(NadeoServices::BaseURLCore()) ? "NadeoServices" : "NadeoLiveServices";
    Net::HttpRequest@ request = NadeoServices::Post(audience, url, Json::Write(content));
    request.Start();

    while (!request.Finished()) {
        yield();
    }

    if (request.ResponseCode() != 200) {
        log("Trackmania API might be broken. Status: " + request.ResponseCode() + ". Response was: " + request.Body);
        throw("Unable to post to " + url);
    }

    return request.String();
}