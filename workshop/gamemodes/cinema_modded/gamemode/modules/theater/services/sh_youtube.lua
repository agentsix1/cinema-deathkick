--[[
Credits to veitikka (https://github.com/veitikka) for fixing YouTube service and writing the
Workaround with a Metadata parser.
--]]

local SERVICE = {}

SERVICE.Name = "YouTube"
SERVICE.IsTimed = true

local METADATA_URL = "https://www.youtube.com/watch?v=%s"
local THEATER_URL = "https://gmod-cinema.pages.dev/cinema/youtube.html?v=%s&t=%s"

function SERVICE:Match( url )
	return url.host and url.host:match("youtu.?be[.com]?")
end

if (CLIENT) then
	function SERVICE:LoadProvider( Video, panel )

		panel:OpenURL( THEATER_URL:format(
			Video:Data(),
			math.Round(CurTime() - Video:StartTime())
		))

		panel.OnDocumentReady = function(pnl)
			self:LoadExFunctions(pnl)
		end
	end
end

---
-- Get the value for an attribute from a html element
--
local function ParseElementAttribute( element, attribute )
	if not element then return end
	-- Find the desired attribute
	local output = string.match( element, attribute .. "%s-=%s-%b\"\"" )
	if not output then return end
	-- Remove the 'attribute=' part
	output = string.gsub( output, attribute .. "%s-=%s-", "" )
	-- Trim the quotes around the value string
	return string.sub( output, 2, -2 )
end

---
-- Get the contents of a html element by removing tags
-- Used as fallback for when title cannot be found
--
local function ParseElementContent( element )
	if not element then return end
	-- Trim start
	local output = string.gsub( element, "^%s-<%w->%s-", "" )
	-- Trim end
	return string.gsub( output, "%s-</%w->%s-$", "" )
end

-- Lua search patterns to find metadata from the html
local patterns = {
	["title"] = "<meta%sproperty=\"og:title\"%s-content=%b\"\">",
	["title_fallback"] = "<title>.-</title>",
	["thumb"] = "<meta%sproperty=\"og:image\"%s-content=%b\"\">",
	["thumb_fallback"] = "<link%sitemprop=\"thumbnailUrl\"%s-href=%b\"\">",
	["duration"] = "<meta%sitemprop%s-=%s-\"duration\"%s-content%s-=%s-%b\"\">",
	["live"] = "<meta%sitemprop%s-=%s-\"isLiveBroadcast\"%s-content%s-=%s-%b\"\">",
	["live_enddate"] = "<meta%sitemprop%s-=%s-\"endDate\"%s-content%s-=%s-%b\"\">",
	["age_restriction"] = "<meta%sproperty=\"og:restrictions:age\"%s-content=%b\"\">"
}

function SERVICE:GetURLInfo( url )

	local info = {}

	-- http://www.youtube.com/watch?v=(videoId)
	if url.query and url.query.v and string.len(url.query.v) > 0 then
		info.Data = url.query.v

	-- http://www.youtube.com/v/(videoId)
	elseif url.path and string.match(url.path, "^/v/([%a%d-_]+)") then
		info.Data = string.match(url.path, "^/v/([%a%d-_]+)")

		-- http://www.youtube.com/shorts/(videoId)
	elseif url.path and string.match(url.path, "^/shorts/([%a%d-_]+)") then
		info.Data = string.match(url.path, "^/shorts/([%a%d-_]+)")

	-- http://youtu.be/(videoId)
	elseif string.match(url.host, "youtu.be") and
		url.path and string.match(url.path, "^/([%a%d-_]+)$") and
		( not info.query or #info.query == 0 ) then -- short url
		info.Data = string.match(url.path, "^/([%a%d-_]+)$")
	end

	-- Start time, ?t=123s
	if (url.query and url.query.t and url.query.t ~= "") then
		local time = util.ISO_8601ToSeconds(url.query.t)
		if time and time ~= 0 then
			info.StartTime = time
		end
	end

	if info.Data then
		return info
	else
		return false
	end

end

---
-- Function to parse video metadata straight from the html instead of using the API
--
function SERVICE:ParseYTMetaDataFromHTML( html )
	--MetaData table to return when we're done
	local metadata = {}

	-- Fetch title and thumbnail, with fallbacks if needed
	metadata.title = ParseElementAttribute(string.match(html, patterns["title"]), "content")
		or ParseElementContent(string.match(html, patterns["title_fallback"]))

	-- Parse HTML entities in the title into symbols
	metadata.title = url.htmlentities_decode(metadata.title)

	metadata.thumbnail = ParseElementAttribute(string.match(html, patterns["thumb"]), "content")
		or ParseElementAttribute(string.match(html, patterns["thumb_fallback"]), "href")

	metadata.familyfriendly = ParseElementAttribute(string.match(html, patterns["age_restriction"]), "content") or ""

	-- See if the video is an ongoing live broadcast
	-- Set duration to 0 if it is, otherwise use the actual duration
	local isLiveBroadcast = tobool(ParseElementAttribute(string.match(html, patterns["live"]), "content"))
	local broadcastEndDate = string.match(html, patterns["live_enddate"])
	if isLiveBroadcast and not broadcastEndDate then
		-- Mark as live video
		metadata.duration = 0
	else
		local durationISO8601 = ParseElementAttribute(string.match(html, patterns["duration"]), "content")
		if isstring(durationISO8601) then
			metadata.duration = math.max(1, convertISO8601Time(durationISO8601))
		end
	end

	return metadata
end

function SERVICE:GetVideoInfo( data, onSuccess, onFailure )

	local onReceive = function( body, length, headers, code )
		local status, metadata = pcall(self.ParseYTMetaDataFromHTML, self, body)
		if not status  then
			return onFailure( "Theater_RequestFailed" )
		end

		local info = {}
		info.title = metadata["title"]
		info.thumbnail = metadata["thumbnail"]

		local isLive = metadata["duration"] == 0
		local familyFriendly = metadata["familyfriendly"] ~= "18+"


		if isLive then
			info.type = "youtubelive"
			info.duration = 0
		else
			if not familyFriendly then
				info.type = "youtubensfw"
			end

			info.duration = metadata["duration"]
		end

		if onSuccess then
			pcall(onSuccess, info)
		end

	end

	local url = METADATA_URL:format( data )
	self:Fetch( url, onReceive, onFailure )

end

theater.RegisterService( "youtube", SERVICE )


--[[
	Uncomment this line below to restrict Livestreaming
	only to Private Theaters.
]]--
-- SERVICE.TheaterType = THEATER_PRIVATE

-- Implementation is found in 'youtube' service.
-- GetVideoInfo switches to 'youtubelive'

theater.RegisterService( "youtubelive", {
	Name = "YouTube Live",
	IsTimed = false,
	Hidden = true,
	LoadProvider = CLIENT and SERVICE.LoadProvider or function() end
} )