-- SERVICES
local pathFindingService = game:GetService("PathfindingService")
local runService = game:GetService("RunService")
local players = game:GetService("Players")

-- NPC
local npc = script.Parent
local hum = npc.Humanoid
local rootPart = npc.HumanoidRootPart
local animator = hum.Animator

local LeftH = npc.LeftHand
local RightH = npc.RightHand

-- FOLDERS
local candysFolder = script.Candys
local fxFolder = script.FX
local Modules = script.Modules

-- MODULES
local config = require(script.Config)

local Maid = require(Modules.Maid)
local SimplePath = require(Modules.SimplePath)

local agentParams = {
	AgentRadius = 22,
	AgentHeight = 40,
	AgentCanClimb = true,
	AgentCanJump = false,
}

local NPCMaid = Maid.new()
local path = SimplePath.new(npc, agentParams)
path.Visualize = true

-- VARS
local attacking = false
local dropInterval = false
local attackCooldown = false
local selectedPlayer = nil

local areaSize = Vector3.new(48, 1, 48)

-- FX
local attacksFXFolder = fxFolder:WaitForChild("Attacks")
local CiclePartZone = attacksFXFolder:WaitForChild("CicleZone")
local SKYHandle = script.HandleSky
local skydrop = script.SkyDrops.CANDY
skydrop.Parent = nil

-- CANDYs
local candyFolder = script.Candys
local candysArray = candyFolder:GetChildren()
local handle = script.Handle

-- TABLES
local tracks = {}

-- FUNCTIONS

local function generateRandomPosition(areaPart) -- Create the blocks in the randomly selected area
	local halfsize = areaPart.Size / 2
	local positionCenter = areaPart.Position
	local offsetRandom = Vector3.new(
		math.random() * areaSize.X - halfsize.X,
		math.random() * areaSize.Y - halfsize.Y,
		math.random() * areaSize.Z - halfsize.Z
	) -- Depending on the size of the area, it grabs it and looks for a random position.
	return positionCenter + offsetRandom
end

local function createRandomPart() -- Create the blocks in place by activating the position function
	local areaPart = SKYHandle
	if areaPart then
		local newpart = skydrop:Clone()
		newpart.Parent = game.Workspace
		newpart.Position = generateRandomPosition(areaPart)

		local thread = task.spawn(function()
			newpart.Touched:Connect(function(hit)
				local char = hit.Parent
				if char and char:FindFirstChild("Humanoid") and char ~= npc then
					local hum = char.Humanoid
					hum:TakeDamage(config.DropDamage)
				end
			end)
		end)

		task.delay(2, function()
			task.cancel(thread)
			newpart:Destroy()
		end)
	end
end

local function stopAnimation(Name)  -- Desactive animations
	if tracks[Name] and tracks[Name].IsPlaying then
		tracks[Name]:Stop()
	end
end

local function playAnimation(Name, waitForAnim) -- Active animations
	if tracks[Name] and not tracks[Name].IsPlaying then
		tracks[Name]:Play()
		if waitForAnim then
			tracks[Name].Ended:Wait()
			stopAnimation(Name)
		end
	end
end


local function onRunning(speed)
	if speed > 0.01 then
		playAnimation("Run")
	else
		stopAnimation("Run")
	end
end

local function getClosestPlayer() -- Check the position of the players that are connected and depending on this, select the one that is closest
	local closestPlayer = nil
	local shortestDistance = math.huge

	for _, player in pairs(players:GetPlayers()) do
		local character = player.Character
		if character then
			local targetHum = character:FindFirstChild("Humanoid")
			if targetHum and targetHum.Health > 0 then
				local distance = (npc.PrimaryPart.Position - character.PrimaryPart.Position).Magnitude
				if distance < shortestDistance then
					shortestDistance = distance
					closestPlayer = player
				end
			end
		end
	end

	return closestPlayer
end

local function attack(victim) -- It is a function to be able to select the 3 types of attacks
	local victimchar = victim.Character
	local randomIndex = math.random(1, 3)

	local attacks = {
		[1] = function() -- Activates damage in a specific area within the area
			task.delay(0.05, function() CiclePartZone.Transparency = 0.75 end)

			task.delay(0.75, function()
				CiclePartZone.Transparency = 1
				local distance = (npc.PrimaryPart.Position - victimchar.PrimaryPart.Position).Magnitude
				if distance < config.AttackDistance then
					local humVictim = victimchar.Humanoid
					humVictim:TakeDamage(config.Damage)
				end
			end)

			attacking = true
			playAnimation(randomIndex, true)
		end,

		[2] = function() -- Hit the player who is closest
			local animIndex = math.random(1, 2)
			task.delay(0.75, function()
				local distance = (npc.PrimaryPart.Position - victimchar.PrimaryPart.Position).Magnitude
				if distance < config.AttackDistance then
					local humVictim = victimchar.Humanoid
					humVictim:TakeDamage(config.Damage)
				end
			end)

			attacking = true
			tracks["SecundaryAttacks"][animIndex]:Play()
			tracks["SecundaryAttacks"][animIndex].Ended:Wait()
		end,

		[3] = function()  -- Activate the attack of falling cubes from the sky that remove damage
			local thread
			task.delay(0.5, function()
				thread = task.spawn(function()
					while true do
						createRandomPart()
						task.wait(0.25)
					end
				end)
			end)

			attacking = true
			playAnimation(randomIndex, true)
			task.cancel(thread)
		end,
	}

	if attacks[randomIndex] then attacks[randomIndex]() end

	npc.PrimaryPart.Anchored = false
	attackCooldown = true
	attacking = true

	if not tracks["Run"].IsPlaying then
		playAnimation("Run")
	end

	task.delay(config.AttackCooldown, function()
		attackCooldown = false
	end)
end

local function dropCandy() -- Drop the candy, which in this case is a test of red cubes.
	if dropInterval then return end

	local randomIndex = math.random(1, #candysArray)
	local candy = candysArray[randomIndex]

	if candy then
		task.spawn(function()
			local candyClone = candy:Clone()
			candyClone.Parent = candyFolder
			candyClone.Position = handle.Position

			candyClone.Touched:Connect(function(hit)
				local char = hit.Parent
				if char and char:FindFirstChild("Humanoid") and char ~= npc then
					local hum = char.Humanoid
					hum:TakeDamage(config.DropDamage)
				end
			end)

			dropInterval = true
			task.delay(config.DropLifetime, function()
				candyClone:Destroy()
			end)

			task.wait(config.DropInterval)
			dropInterval = false
		end)
	end
end

local function verifyPlayer() -- Check the player's distance for attacks
	local char = selectedPlayer.Character

	if char then
		local distance = (npc.PrimaryPart.Position - char.PrimaryPart.Position).Magnitude

		if distance <= config.AttackDistance and not attackCooldown then
			npc.PrimaryPart.Anchored = true
			stopAnimation("Run")
			attack(selectedPlayer)
		elseif distance > config.MaximunDistance then
			selectedPlayer = nil
		end
	end
end

for i, id in pairs(config.Animations) do -- Depending on the player's status, one or another animation is active.
	if id ~= 0 then
		if typeof(id) == "table" then
			tracks[i] = {}
			for index, idt in pairs(id) do
				local track = Instance.new("Animation")
				track.AnimationId = "rbxassetid://" .. idt
				tracks[i][index] = animator:LoadAnimation(track)
			end
		else
			local track = Instance.new("Animation")
			track.AnimationId = "rbxassetid://" .. id
			tracks[i] = animator:LoadAnimation(track)
			if i == "WakeUp" then
				tracks[i].Looped = false
				tracks[i].Priority = Enum.AnimationPriority.Action
			end
			if i == "Sleepping" then
				tracks[i].Priority = Enum.AnimationPriority.Idle
			end
			if i == "Run" then
				tracks[i].Priority = Enum.AnimationPriority.Movement
			end
		end
	else
		warn("Error on load Animation, Animation is 0")
	end
end

warn(tracks)

-- CONNECTIONS
hum.Running:Connect(onRunning)

path.Blocked:Connect(function() -- Activates the movement of the npc if he has a player nearby
	if selectedPlayer and selectedPlayer.Character and selectedPlayer.Character.Parent ~= nil then
		path:Run(selectedPlayer.Character.PrimaryPart)
	end
end)

NPCMaid:GiveTask(task.spawn(function()
	while true do
		task.wait()

		selectedPlayer = getClosestPlayer()

		if selectedPlayer then
			-- Check if the npc is asleep and also if there is a player nearby to activate wake up
			if path.Status ~= SimplePath.StatusType.Active and not attacking and tracks["Sleepping"].IsPlaying then
				stopAnimation("Sleepping")
				playAnimation("WakeUp", true)
			end

			verifyPlayer()
			dropCandy()
			
			-- Activate npc movement
			if selectedPlayer and selectedPlayer.Character and selectedPlayer.Character.Parent ~= nil then
				playAnimation("Run")
				path:Run(selectedPlayer.Character.PrimaryPart)
			end
		else
			-- Verify that there is no player nearby and enter sleep state
			if path.Status == SimplePath.StatusType.Active then
				stopAnimation("Run")
				path:Stop()
			end

			if not attacking then
				playAnimation("Sleepping")
			end
			
			-- Heal your life
			if hum.Health < hum.MaxHealth then
				hum.Health += 5
				task.wait(1)
			end
		end
	end
end))
