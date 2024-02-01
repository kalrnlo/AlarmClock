--[=[
	AlarmClock by boatbomber
	31/01/2024 | Distributed under MIT License
--]=]

local RunService = game:GetService("RunService")

local DestroyConnections = {} :: {[BasePart]: RBXScriptConnection}
local Watchlist = {} :: {BasePart}
local WatcherConnection: RBXScriptConnection

local function OnPreSimulation()
	-- Iterate through forbidden parts and wake any that are attempting to sleep
	for _, Part in Watchlist do
		if Part.Velocity == Vector3.zero then
			Part.Velocity = Vector3.new(0,-0.08,0)
		end
	end
end

local function AllowSleep(Part: BasePart)
	-- Find the part within our watchlist
	local PartIndex = table.find(Watchlist, Part)
	if not PartIndex then return end

	-- Remove the part without shifting the array via unordered removal
	if PartIndex ~= #Watchlist then
		Watchlist[PartIndex] = Watchlist[#Watchlist]
		Watchlist[#Watchlist] = nil
	else
		Watchlist[PartIndex] = nil
	end
	local DestroyingConnection = DestroyConnections[Part]
		
	-- Clear our part destroy connection
	if DestroyingConnection then
		DestroyingConnection:Disconnect()
		DestroyConnections[Part] = nil
	end

	-- Stop our watcher if we no longer need it
	if #Watchlist < 1 and WatcherConnection then
		WatcherConnection:Disconnect()
	end
end

local function ForbidSleep(Part: BasePart)
	if table.find(Watchlist, Part) then
		warn("Attempt to forbid a part that's already forbidden")
		return
	end

	-- Add part to watchlist
	table.insert(Watchlist, Part)

	-- Start our watcher if we haven't yet
	if not WatcherConnection then
		WatcherConnection = RunService.PreSimulation:Connect(OnPreSimulation)
	end

	-- Create a destroy watcher if one doesn't exist
	if not DestroyConnections[Part] then
		DestroyConnections[Part] = Part.Destroying:Connect(function()
			AllowSleep(Part)
		end)
	end
end

local function ForbidSleepForDuration(Part: BasePart, Duration: number?)
	local Duration = Duration or 1

	task.spawn(function(Part, Duration)
		local Start = os.clock()

		ForbidSleep(Part)
		-- Accurate wait the specified duration before allowing sleep
		while true do
			if os.clock() - Start >= Duration then
				break
			end
			RunService.PostSimulation:Wait()
		end

		AllowSleep(Part)
	end, Part, Duration)
end

local function AllowAllSleep()
	-- Free all watched parts
	table.clear(Watchlist)

	-- Stop our watcher as we no longer need it
	if WatcherConnection then
		WatcherConnection:Disconnect()
		WatcherConnection = nil
	end

	-- Clear destroy connections
	for _, Connection in DestroyConnections do
		Connect:Disconnect()
	end
	table.clear(DestroyConnections)
end

local AlarmClock = {
	ForbidSleepForDuration = ForbidSleepForDuration,
	AllowAllSleep = AllowAllSleep,
	ForbidSleep = ForbidSleep,
	AllowSleep = AllowSleep,
	Watchlist = Watchlist,
}

return AlarmClock
