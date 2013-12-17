--[[
Author: Joel Van Eenwyk
Purpose: Controls the player, creates asteroids, and handles game score
--]]

DEBUG_DRAW = false

function OnExpose(self)
	self.MissileVelocity = 600
	self.MissileScale = 0.2
	self.MoveSpeed = 300
	self.RotateSpeed = 5
end

function OnAfterSceneLoaded(self)
	Debug:Enable(true)

	local kDeadzone = {deadzone = 0.1}
 
	G.screenWidth, G.screenHeight = Screen:GetViewportSize()

	self.playerInputMap = Input:CreateMap("InputMap")
	self.FontPath = "Fonts/agency52"
 
	-- Setup the WASD keyboard playerInputMap
	self.playerInputMap:MapTrigger("KeyLeft", "KEYBOARD", "CT_KB_A")
	self.playerInputMap:MapTrigger("KeyRight", "KEYBOARD", "CT_KB_D")
	self.playerInputMap:MapTrigger("KeyUp", "KEYBOARD", "CT_KB_W")
	self.playerInputMap:MapTrigger("Reset", "KEYBOARD", "CT_KB_R")
	self.playerInputMap:MapTrigger("KeyDown", "KEYBOARD", "CT_KB_S")
	self.playerInputMap:MapTrigger("KeyFire", "KEYBOARD", "CT_KB_SPACE", {once=true})

	self:SetUseEulerAngles(true)

	G.player = self
	
	local distance = 1600
	local p1 = Screen:Project3D(0, 0, distance)
	local p2 = Screen:Project3D(G.screenWidth, G.screenHeight, distance)
	G.extentX = math.abs((p2.x - p1.x) / 2)
	G.extentY = math.abs((p2.y - p1.y) / 2)

	G.missileEffectOffset = Vision.hkvVec3(1000, 1000, 1000)
	G.missilePosition = Vision.hkvVec3(0, 0, 0)
	G.missileEffect = Game:CreateEffect(
		Vision.hkvVec3(0, 0, 0),
		"Particles\\bulletTrail.xml",
		"astroidExplosion" )
		
	G.Reset = Reset
	G.Reset(0.0)
	
	self.bounceSound =  Fmod:CreateSound(Vision.hkvVec3(0,0,0), "Sounds/bounce.wav", false, "bounceSound")
	G.shipExplosionSound =  Fmod:CreateSound(Vision.hkvVec3(0,0,0), "Sounds/shipExplosion.wav", false, "shipExplosion")
	self.asteroidExplosionSound =  Fmod:CreateSound(Vision.hkvVec3(0,0,0), "Sounds/asteroidExplosion.wav", false, "asteroidExplosionSound")
end

function OnBeforeSceneUnloaded(self)
	Input:DestroyVirtualThumbStick()
	Input:DestroyMap(self.playerInputMap)
	
	-- #todo should this be removed?
	--if G.missileEffect then
	--	G.missileEffect:Remove()
	--end
end

function IsTriggered(self, key)
	return (self.playerInputMap:GetTrigger(key) > 0)
end

function OnThink(self)
	if not G.MainMenu then
		local dt = Timer:GetTimeDiff()
		Update(self, dt)
	end
end

--== Global game utility functions

function Update(self, dt)
	if IsTriggered(self, "Reset") then
		Reset(0)
	end	

	-- Handle resetting immediately as some things need to be initialized right away
	if G.reset then
		G.resetTime = G.resetTime - dt
		if G.resetTime <= 0 then
			HardReset()
			G.reset = false
		end
	end	
		
	Debug:PrintAt(
		50, 25,
		"Bounces: " .. G.missileBounces .. "/" .. G.maxBounces,
		Vision.V_RGBA_WHITE,
		self.FontPath )
	Debug:PrintAt(450, 25, "Round: " .. G.currentLevel, Vision.V_RGBA_WHITE, self.FontPath)
	
	local missiles = 1
	if G.missileFired then
		missiles = 0
	end
	Debug:PrintAt(700, 25, "Missles: " .. missiles, Vision.V_RGBA_WHITE, self.FontPath)

	UpdateAsteroids(self)
	
	if DEBUG_DRAW then
		Debug.Draw:Line(
			Vision.hkvVec3(-G.extentX, -G.extentY, 0),
			Vision.hkvVec3(G.extentX, -G.extentY, 0) )
		Debug.Draw:Line(
			Vision.hkvVec3(-G.extentX, G.extentY, 0),
			Vision.hkvVec3(G.extentX, G.extentY, 0) )
		Debug.Draw:Line(
			Vision.hkvVec3(-G.extentX, -G.extentY, 0),
			Vision.hkvVec3(-G.extentX, G.extentY, 0) )
		Debug.Draw:Line(
			Vision.hkvVec3(G.extentX, -G.extentY, 0),
			Vision.hkvVec3(G.extentX, G.extentY, 0) )
	end

	local moveSpeed = self.MoveSpeed * dt
	local rotateSpeed = self.RotateSpeed * dt
	
	local delta = Vision.hkvVec3(0, 0, 0)
	local rotate = 0
	
	if IsTriggered(self, "KeyUp") or IsTriggered(self, "TouchUp") then
		G.speed = G.speed + moveSpeed
	end

	if IsTriggered(self, "KeyLeft") or IsTriggered(self, "TouchLeft") then
		rotate = rotate - rotateSpeed
	end

	if IsTriggered(self, "KeyRight") or IsTriggered(self, "TouchRight") then
		rotate = rotate + rotateSpeed
	end
	
	local right = G.direction:cross(Vision.hkvVec3(0, 0, 1))
	
	G.direction = G.direction + right * rotate
	G.direction:normalize()
	
	local position = self:GetPosition() + G.direction * G.speed
	
	if position.x > G.extentX then
		position.x = G.extentX
	elseif position.x < -G.extentX then
		position.x = -G.extentX
	end
	
	if position.y > G.extentY then
		position.y = G.extentY
	elseif position.y < -G.extentY then
		position.y = -G.extentY
	end
	
	self:SetPosition(position)

	local angle = 0
	angle = math.atan2(G.direction.y, G.direction.x)
	self:SetOrientation(math.deg(angle) - 90, 0, 0)

	G.speed = G.speed * 0.9
		
	if (IsTriggered(self, "KeyFire") or IsTriggered(self, "TouchFire")) and
	   (not G.missileFired) and
	   (not G.asteroidSpawning) then		
		G.missileDirection = G.direction
		G.missileBounces = 0
		G.missileFired = true
		G.missilePath = {}
		
		ShowMissile()
		SetMissilePosition(position)
		
		table.insert(G.missilePath, G.missileDirection)
	end
	
	if G.missileFired then		
		local rayStart = G.missilePosition
		local rayEnd = rayStart + G.missileDirection * 50
		local iCollisionFilterInfo = Physics.CalcFilterInfo(Physics.LAYER_ALL, 0, 0, 0)
		local isHit, result = Physics.PerformRaycast(rayStart, rayEnd, iCollisionFilterInfo)

		local e = rayStart + G.missileDirectio;
		Debug.Draw:Box(rayStart, 10)
		Debug.Draw:Line(rayStart, rayEnd, Vision.V_RGBA_WHITE)
		
		local newMissilePosition = rayEnd
		
		if isHit == true then 
			newMissilePosition = result.ImpactPoint
			G.missileDirection = result.ImpactNormal
			G.missileDirection.z = 0
			G.missileDirection:normalize()
			G.missileBounces = G.missileBounces + 1
		
			DeleteAsteroid(result.HitObject)
			self.asteroidExplosionSound:Play()

			Debug.Draw:Line(rayStart, result.ImpactPoint, Vision.V_RGBA_BLUE)
		end
		
		if G.missilePosition.x > G.extentX then
			newMissilePosition.x = G.extentX
			G.missileDirection.x = -G.missileDirection.x
			G.missileBounces = G.missileBounces + 1
			self.bounceSound:Play()
		elseif G.missilePosition.x < -G.extentX then
			newMissilePosition.x = -G.extentX
			G.missileDirection.x = -G.missileDirection.x
			G.missileBounces = G.missileBounces + 1
			self.bounceSound:Play()
		elseif G.missilePosition.y > G.extentY then
			newMissilePosition.y = G.extentY
			G.missileDirection.y = -G.missileDirection.y
			G.missileBounces = G.missileBounces + 1
			self.bounceSound:Play()
		elseif G.missilePosition.y < -G.extentY then
			newMissilePosition.y = -G.extentY
			G.missileDirection.y = -G.missileDirection.y
			G.missileBounces = G.missileBounces + 1
			self.bounceSound:Play()
		end
		
		SetMissilePosition(newMissilePosition)
		
		if G.missileBounces >= G.maxBounces then
			Reset(2.0)
		elseif table.getn(G.asteroids) == 0 then
			G.currentLevel = G.currentLevel + 1
			G.missileFired = false
			G.asteroidSpawning = true
			G.maxBounces = G.maxBounces + 6
			G.asteroidCount = G.asteroidCount + 2
			G.asteroidTime = 0
			G.missileBounces = 0
			HideMissile()
			DeleteAsteroids()
		end
	end
end

function HideMissile()
	G.missileEffect:SetPaused(true)
	G.missileEffect:SetVisible(false)
	SetMissilePosition(G.missileEffectOffset)
end

function ShowMissile()
	if not G.missileEffect:IsVisible() then
		SetMissilePosition(-G.missileEffectOffset)
		G.missileEffect:SetVisible(true)
		G.missileEffect:SetPaused(false)
	end
end

function SetMissilePosition(position)	
	G.missileEffect:IncPosition(position - G.missilePosition)
	G.missilePosition = position
end

function Reset(delay)
	HideMissile()
	G.missileFired = false

	G.reset = true
	G.resetTime = delay
end

function HardReset()
	DeleteAsteroids()

	G.missileFired = false
	G.missileFireTimer = 0
	
	G.direction = Vision.hkvVec3(0, 1, 0)
	G.speed = 0
	G.missileDirection = Vision.hkvVec3(0, 0, 0)
	G.missileBounces = 0
	G.missilePath = {}
	G.missileFireTimer = 0.1

	G.currentLevel = 1
	G.asteroidCount = 2
	G.asteroidSpawning = true
	G.maxBounces = 12
	G.asteroidTime = 0

	G.directionChangeTime = 0.3

	G.player:SetPosition( Vision.hkvVec3(0, 0, 0) )
	G.player:SetVisible(true)

	G.ResetMenu = true
	G.MainMenu = true
end

--== Asteroid helper functions

function UpdateAsteroids(self)
	local dt = Timer:GetTimeDiff()

	for i, asteroid in pairs(G.asteroids) do		
		local position = asteroid.entity:GetPosition()
		position = position + asteroid.direction * asteroid.speed * dt
		
		if position.x > G.extentX then
			position.x = G.extentX
			asteroid.direction.x = -asteroid.direction.x
		elseif position.x < -G.extentX then
			position.x = -G.extentX
			asteroid.direction.x = -asteroid.direction.x
		elseif position.y > G.extentY then
			position.y = G.extentY
			asteroid.direction.y = -asteroid.direction.y
		elseif position.y < -G.extentY then
			position.y = -G.extentY
			asteroid.direction.y = -asteroid.direction.y
		end
		
		asteroid.rotation = asteroid.rotation + asteroid.rotationSpeed * dt
		
		if DISABLE_RIGID_BODIES then
			asteroid.entity:SetPosition(position)
		else
			asteroid.rigidBody:SetOrientation( Vision.hkvVec3(0, 0, asteroid.rotation) )
			asteroid.rigidBody:SetPosition(position)
		end
		
		asteroid.changeDirectionTimer = asteroid.changeDirectionTimer + dt
	end
	
	G.asteroidTime = G.asteroidTime + dt
	if G.asteroidTime > Util:GetRandFloat(2) + 0.5 and
	   G.asteroidSpawning then
		CreateAsteroid(self)
		G.asteroidTime = 0
		G.asteroidSpawning = (table.getn(G.asteroids) < G.asteroidCount)
	end
end

function DeleteAsteroid(asteroidToDelete)
	if G.asteroids then
		for asteroidIndex, asteroid in pairs(G.asteroids) do
			if asteroid.entity == asteroidToDelete then
				local explosion = Game:CreateEffect(
					asteroid.entity:GetPosition(),
					"Particles\\asteroidExplosion.xml",
					"asteroidExplosion" )
				explosion:SetScaling( asteroid.entity:GetScaling().x )
				asteroid.entity:Remove()
				table.remove(G.asteroids, asteroidIndex)
				break
			end
		end
	end
end

function DeleteAsteroids()
	if G.asteroids then
		for _, asteroid in pairs(G.asteroids) do
			asteroid.entity:Remove()
		end
	end

	G.asteroids = {}
end

function CreateAsteroid()
	local position = Vision.hkvVec3(0, 0, -5.0)
	local variation = Util:GetRandInt(3) + 1
	local model = "Models/asteroid0" .. variation .. ".model"
	local collision = "Models/asteroid_collision.hkt"

	local asteroid = {}
	
	asteroid.direction = Vision.hkvVec3(0, 0, 0)
	
	if Util:GetRandFloat() > 0.5 then
		if Util:GetRandFloat() > 0.5 then
			position.x = G.extentX * -1
			asteroid.direction.x = 1
		else
			position.x = G.extentX
			asteroid.direction.x = -1
		end
		asteroid.direction.y = Util:GetRandFloat(2) - 1
		position.y = Util:GetRandFloat(G.extentY)
	else
		if Util:GetRandFloat() > 0.5 then
			position.y = G.extentY * -1
			asteroid.direction.y = 1
		else
			position.y = G.extentY
			asteroid.direction.y = -1
		end	
		asteroid.direction.x = Util:GetRandFloat(2) - 1
		position.x = Util:GetRandFloat(G.extentX)
	end

	asteroid.direction:normalize()
	
	asteroid.scale = Util:GetRandFloat(2) + 1.5
	asteroid.entity = Game:CreateEntity(
		position,
		"VisBaseEntity_cl",
		"",
		"Asteroid" )
	asteroid.entity:SetScaling(asteroid.scale)
	asteroid.rotationSpeed = Util:GetRandFloat(200) - 100
	asteroid.rotation = 0

	asteroid.entity:AddComponentOfType("VScriptComponent", "AsteroidControlScript")
	asteroid.entity.AsteroidControlScript:SetProperty("ScriptFile", "Scripts/Asteroid.lua")
	asteroid.entity.AsteroidControlScript:SetOwner(asteroid.entity)
	
	asteroid.speed = Util:GetRandFloat(100) + 100
	asteroid.changeDirectionTimer = 0

	asteroid.rigidBody = asteroid.entity:AddComponentOfType("vHavokRigidBody")
	asteroid.rigidBody:SetDebugRendering(DEBUG_DRAW)

	-- set the mesh after the rigid body is created so that a default rigid body isn't generated
	asteroid.entity:SetMesh(model)
	
	local aabb = asteroid.entity:GetCollisionBoundingBox()	
	local radius = math.max(aabb:getSizeX(), aabb:getSizeY()) / 2.0
	local success = asteroid.rigidBody:InitFromFile(collision, radius / 100.0)
	
	table.insert(G.asteroids, asteroid)
end
