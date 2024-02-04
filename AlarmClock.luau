--[=[
	AlarmClock by boatbomber
	03/02/2024 | Distributed under MIT License
--]=]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local NetworkOwner = if RunService:IsServer() then nil else Players.LocalPlayer
local WatcherConnection: RBXScriptConnection
local PushVelocity = Vector3.new(0,-0.08,0)
local LinearVelocity: LinearVelocity
local Watchlist = {} :: {BasePart}
local Vectors = buffer.create(12)
local Attachment: Attachment
local VectorSize = 12

local function CanBeForbidden(Part: BasePart)
	if not Part:IsDescendantOf(Workspace) then
		warn("[AlarmClock] Cannot forbid sleep for a part that is not a descendant of Workspace\n\tPart:", Part:GetFullName())
		return false
	elseif table.find(Watchlist, Part) then
		warn("[AlarmClock] Cannot forbid sleep for a part that's already forbidden\n\tPart:", Part:GetFullName())
		return false
	elseif Part:IsGrounded() then
		warn("[AlarmClock] Cannot forbid sleep for a grounded part\n\tPart:", Part:GetFullName())
		return false
	elseif Part.Anchored then
		warn("[AlarmClock] Cannot forbid sleep for an anchored part\n\tPart:", Part:GetFullName())
		return false 
	else
		return true
	end
end
	
--[[
	local function CopyVector(TargetIndex: number, SourceIndex: number)
		local SourceIndex = SourceIndex - 1
		local TargetIndex = TargetIndex - 1

		buffer.copy(
			Vectors,
			if TargetIndex ~= 0 then TargetIndex * VectorSize else 0,
			Vectors,
			if SourceIndex ~= 0 then SourceIndex * VectorSize else 0,
			12
		)
	end
--]]
	
local function WriteVector(Index: number, Vector: Vector3)
	local Index = Index - 1
	local Offset = if Index ~= 0 then Index * VectorSize else 0
			
	if Index ~= 0 and Index * VectorSize > buffer.len(Vectors) then
		local NewVectors = buffer.create(buffer.len(Vectors) + 12)
		buffer.copy(NewVectors, 0, Vectors)
		Vectors = NewVectors
	end

	buffer.writef32(Vectors, Offset, Vector.X),
	buffer.writef32(Vectors, Offset + 5, Vector.Y)
	buffer.writef32(Vectors, Offset + 10, Vector.Z)
end
		
local function ReadVector(Index: number)
	local Index = Index - 1
	local Offset = if Index ~= 0  then Index * VectorSize else 0

	return Vector3.new(
		buffer.readf32(Vectors, Offset),
		buffer.readf32(Vectors, Offset + 5),
		buffer.readf32(Vectors, Offset + 10),
	)
end

-- Just called AllowAll so it appears as that, when infact
-- this should instead be called Cleanup, but it allows
-- all parts that were being watched to be able to sleep
-- and is called that in the AlarmClock table. Plus makes it 
-- easier to find in luau heap and other debugging stuff because of
-- the fact the actual function name is the same as its name in the table
local function AllowAll()
	if WatcherConnection then
		WatcherConnection:Disconnect()
	end
	if #Watchlist ~= 0 then
		table.clear(Watchlist)
	end
	if LinearVelocity then
		LinearVelocity:Destroy()
	end
	if Attachment then
		Attachment:Destroy()
	end
end

local function InternalAllow(Part: BasePart, Index: number)
	-- Remove the part without shifting the array via unordered removal
	if Index ~= #Watchlist then
		local TargetIndex = #Watchlist - 1
		local SourceIndex = Index - 1

		buffer.copy(
			Vectors,
			if TargetIndex ~= 0 then TargetIndex * VectorSize else 0,
			Vectors,
			if SourceIndex ~= 0 then SourceIndex * VectorSize else 0,
			12
		)
		Watchlist[Index] = Watchlist[#Watchlist]
		Watchlist[#Watchlist] = nil
	else
		Watchlist[Index] = nil
	end

	-- Cleanup as we arent watching any parts
	if #Watchlist == 0  then
		AllowAll()
	end
end						
		
local function OnPreSimulation()
	-- Iterate through forbidden parts and wake any that are attempting to sleep
	for Index, Part in Watchlist do
		if LinearVelocity.Parent then
			Attachment.Parent = nil
			LinearVelocity.Parent = nil
			LinearVelocity.VectorVelocity = Vector3.zero
		end
		if Part.Anchored or Part:IsGrounded() or (not Part:IsDescendantOf(Workspace)) then
			InternalAllow(Part, Index)
			continue
		end
		local PreviousPosition = ReadVector(Index)
		local CurrentPosition = Part.Position
		WriteVector(Index, CurrentPosition)
								
		if Part:GetNetworkOwner() == NetworkOwner then
			if Part.AssemblyLinearVelocity == Vector3.zero then
				Part.AssemblyLinearVelocity = PushVelocity
			end
		elseif (ReadVector(Index) - CurrentPosition):FuzzyEq(Vector3.zero) then
			-- AssemblyLinearVelocity doesnt replicate, so we are getting the diffrence between
			-- the previous & current position and seeing if its close to Vector3.zero
			-- suggesting that theres been no movement and its probably asleep
			Attachment.Parent = Part
			LinearVelocity.Parent = Part
			LinearVelocity.VectorVelocity = PushVelocity
		end
	end
end

local function InternalForbid(Part: BasePart)
	-- Add part to watchlist
	table.insert(Watchlist, Part)
	WriteVector(#Watchlist, Part.Position)

	-- Start our watcher if we haven't yet
	if not WatcherConnection then
		WatcherConnection = RunService.PreSimulation:Connect(OnPreSimulation)
	end
	if not Attachment then
		Attachment = Instance.new("Attachment")
		Attachment.Name = "AlarmClock_Attachment"
	end
	if not LinearVelocity then
		LinearVelocity = Instance.new("LinearVelocity")
		LinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		LinearVelocity.Name = "AlarmClock_LinearVelocity"
		LinearVelocity.Attachment0 = Attachment
	end		
end

local function Allow(Part: BasePart)
	local PartIndex = table.find(Watchlist, Part)
			
	if PartIndex then
		InternalAllow(Part, Index)
	end
end

local function ForbidForDuration(Part: BasePart, Duration: number?): thread?
	if CanBeForbidden(Part) then
		if Duration then 
			return task.spawn(function()
				local Start = os.clock()

				InternalForbid(Part)
				-- Accurate wait the specified duration before allowing sleep
				while os.clock() - Start =< Duration do
					RunService.PostSimulation:Wait()
				end

				Allow(Part)
			end, Part, Duration)
		else
			InternalForbid(Part)
			return task.defer(Allow, Part)
		end
	else
		return nil
	end
end
					
local function Forbid(Part: BasePart)
	if CanBeForbidden(Part) then
		InternalForbid(Part)
		return true
	else
		return false
	end
end
			
local AlarmClock = {
	ForbidForDuration = ForbidForDuration,
	Watchlist = Watchlist,
	AllowAll = AllowAll,
	Forbid = Forbid,
	Allow = Allow,
}

return AlarmClock
