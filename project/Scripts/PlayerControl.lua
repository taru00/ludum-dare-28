--[[
Author: Joel Van Eenwyk, Ryan Monday
Purpose: Controls the player
--]]

function OnExpose(self)
	self.MissileVelocity = 600
	self.MissileFireTimer = 0.1
	self.MissileScale = 0.2
	self.MoveSpeed = 300
	self.RotateSpeed = 5
end

function OnAfterSceneLoaded(self)
	Debug:Enable(true)

	local kDeadzone = {deadzone = 0.1}
 
	G.screenWidth, G.screenHeight = Screen:GetViewportSize()

	self.playerInputMap = Input:CreateMap("InputMap")
 
	-- Setup the WASD keyboard playerInputMap
	self.playerInputMap:MapTrigger("KeyLeft", "KEYBOARD", "CT_KB_A")
	self.playerInputMap:MapTrigger("KeyRight", "KEYBOARD", "CT_KB_D")
	self.playerInputMap:MapTrigger("KeyUp", "KEYBOARD", "CT_KB_W")
	self.playerInputMap:MapTrigger("KeyDown", "KEYBOARD", "CT_KB_S")
	self.playerInputMap:MapTrigger("KeyFire", "KEYBOARD", "CT_KB_SPACE")

	-- Create a virtual thumbstick then setup playerInputMap for it
	if Application:GetPlatformName() ~= "WIN32DX9" and
	   Application:GetPlatformName() ~= "WIN32DX11" then	
		Input:CreateVirtualThumbStick()
		self.playerInputMap:MapTriggerAxis("TouchLeft", "VirtualThumbStick", "CT_PAD_LEFT_THUMB_STICK_LEFT", kDeadzone)
		self.playerInputMap:MapTriggerAxis("TouchRight", "VirtualThumbStick", "CT_PAD_LEFT_THUMB_STICK_RIGHT", kDeadzone)
		self.playerInputMap:MapTriggerAxis("TouchUp", "VirtualThumbStick", "CT_PAD_LEFT_THUMB_STICK_UP", kDeadzone)
		self.playerInputMap:MapTriggerAxis("TouchDown", "VirtualThumbStick", "CT_PAD_LEFT_THUMB_STICK_DOWN", kDeadzone)
		self.playerInputMap:MapTrigger(
			"TouchFire",
			{ (G.screenWidth * 0.5), (G.screenHeight * 0.5), G.screenWidth, G.screenHeight },
			"CT_TOUCH_ANY")
	end
	
	self.roll = 0
	self.missileFireTimer = 0
	
	self.position = self:GetPosition()
	self.direction = Vision.hkvVec3(0, 1, 0)
	self.speed = 0
	self.missilePosition = Vision.hkvVec3(0, 0, 0)
	self.missileDirection = Vision.hkvVec3(0, 0, 0)
	self.missileBounces = 0
	self.missileFired = false

	self.asteroids = {}
	
	self.asteroidTime = 0
	local distance = 1600
	local p1 = Screen:Project3D(0, 0, distance)
	local p2 = Screen:Project3D(G.screenWidth, G.screenHeight, distance)
	self.extentX = math.abs((p2.x - p1.x) / 2)
	self.extentY = math.abs((p2.y - p1.y) / 2)

	self:SetUseEulerAngles(true)
end

function OnBeforeSceneUnloaded(self)
	Input:DestroyVirtualThumbStick()
	Input:DestroyMap(self.playerInputMap)
end

function IsTriggered(self, key)
	return (self.playerInputMap:GetTrigger(key) > 0)
end

function OnThink(self)
	local dt = Timer:GetTimeDiff()
	local moveSpeed = self.MoveSpeed * dt
	local rotateSpeed = self.RotateSpeed * dt
	
	local delta = Vision.hkvVec3(0, 0, 0)
	local rotate = 0

	Debug.Draw:Line(
		Vision.hkvVec3(-self.extentX, -self.extentY, 0),
		Vision.hkvVec3(self.extentX, -self.extentY, 0) )
	Debug.Draw:Line(
		Vision.hkvVec3(-self.extentX, self.extentY, 0),
		Vision.hkvVec3(self.extentX, self.extentY, 0) )
	Debug.Draw:Line(
		Vision.hkvVec3(-self.extentX, -self.extentY, 0),
		Vision.hkvVec3(-self.extentX, self.extentY, 0) )
	Debug.Draw:Line(
		Vision.hkvVec3(self.extentX, -self.extentY, 0),
		Vision.hkvVec3(self.extentX, self.extentY, 0) )

	if IsTriggered(self, "KeyUp") or IsTriggered(self, "TouchUp") then
		self.speed = self.speed + moveSpeed
	end

	--if IsTriggered(self, "KeyDown") or IsTriggered(self, "TouchDown") then
	--	self.speed = self.speed - moveSpeed
	--end
	
	if IsTriggered(self, "KeyLeft") or IsTriggered(self, "TouchLeft") then
		rotate = rotate - rotateSpeed
	end

	if IsTriggered(self, "KeyRight") or IsTriggered(self, "TouchRight") then
		rotate = rotate + rotateSpeed
	end
	
	local right = self.direction:cross(Vision.hkvVec3(0, 0, 1))
	
	self.direction = self.direction + right * rotate
	self.direction:normalize()
	
	self.position = self.position + self.direction * self.speed
	
	if self.position.x > self.extentX then
		self.position.x = self.extentX
	elseif self.position.x < -self.extentX then
		self.position.x = -self.extentX
	end
	
	if self.position.y > self.extentY then
		self.position.y = self.extentY
	elseif self.position.y < -self.extentY then
		self.position.y = -self.extentY
	end
	
	self:SetPosition(self.position)

	local angle = 0
	angle = math.atan2(self.direction.y, self.direction.x)
	self:SetOrientation(math.deg(angle) - 90, 0, 0)

	self.speed = self.speed * 0.9
		
	if (IsTriggered(self, "KeyFire") or IsTriggered(self, "TouchFire")) then
		self.missilePosition = self.position
		self.missileDirection = self.direction
		self.missileBounces = 0
		self.missileFired = true
	end
	
	if self.missileFired then		
		local rayStart = self.missilePosition
		local rayEnd = rayStart + self.missileDirection * self.MissileVelocity * dt
		local iCollisionFilterInfo = Physics.CalcFilterInfo(Physics.LAYER_ALL, 0, 0, 0)
		local isHit, result = Physics.PerformRaycast(rayStart, rayEnd, iCollisionFilterInfo)

		local e = rayStart + self.missileDirection * 100
		Debug.Draw:Line(rayStart, e)
		Debug.Draw:Box(rayStart, 10)
		
		if isHit == true then 
			Debug.Draw:Line(rayStart, result["ImpactPoint"], Vision.V_RGBA_BLUE)
			Debug:PrintLine("Hit type: " ..result["HitType"])

			if result["HitType"] == "Entity" then
				Debug:PrintLine("Mesh of hit entity: " ..result["HitObject"]:GetMesh():GetName())
			end 

			Debug:PrintLine("Hit fraction: " ..result["HitFraction"])
			Debug:PrintLine("Hit position: " ..result["ImpactPoint"])
			Debug:PrintLine("Hit normal: " ..result["ImpactNormal"])
			Debug:PrintLine("Dynamic friction of hit object: " ..result["DynamicFriction"])
			Debug:PrintLine("Restitution of hit object: " ..result["Restitution"])
			Debug:PrintLine("Physics user data of hit object: " ..result["UserData"])

			self.missilePosition = result["ImpactPoint"]
			self.missileDirection = result["ImpactNormal"]
			self.missileDirection.z = 0
			self.missileDirection:normalize()
			self.missileBounces = self.missileBounces + 1
		else
			self.missilePosition = rayEnd
		end
		
		if self.missilePosition.x > self.extentX then
			self.missilePosition.x = self.extentX
			self.missileDirection.x = -self.missileDirection.x
			self.missileBounces = self.missileBounces + 1
		elseif self.missilePosition.x < -self.extentX then
			self.missilePosition.x = -self.extentX
			self.missileDirection.x = -self.missileDirection.x
			self.missileBounces = self.missileBounces + 1
		elseif self.missilePosition.y > self.extentY then
			self.missilePosition.y = self.extentY
			self.missileDirection.y = -self.missileDirection.y
			self.missileBounces = self.missileBounces + 1
		elseif self.missilePosition.y < -self.extentY then
			self.missilePosition.y = -self.extentY
			self.missileDirection.y = -self.missileDirection.y
			self.missileBounces = self.missileBounces + 1
		end
	end
	
	UpdateAsteroids(self)
end

function UpdateAsteroids(self)
	local dt = Timer:GetTimeDiff()
	for i, asteroid in pairs(self.asteroids) do		
		local position = asteroid.entity:GetPosition()
		position = position + asteroid.direction * asteroid.speed * dt
		asteroid.entity:SetPosition(position)
	end
	
	self.asteroidTime = self.asteroidTime + dt
	if self.asteroidTime > Util:GetRandFloat(2) + 0.5 then
		CreateAsteroid(self)
		self.asteroidTime = 0
	end
end

function CreateAsteroid(self)
	local xMax = self.extentX 
	local yMax = 500
	local position = Vision.hkvVec3(0, 0, 0)
	local model = "Models/asteroidProxy.model"

	if Util:GetRandFloat() > 0.5 then
		if Util:GetRandFloat() > 0.5 then
			position.x = self.extentX * -1
		else
			position.x = self.extentX
		end
		position.y = Util:GetRandFloat(self.extentY)
	else
		if Util:GetRandFloat() > 0.5 then
			position.y = self.extentY * -1
		else
			position.y = self.extentY
		end	
		position.x = Util:GetRandFloat(self.extentX)
	end
	
	local asteroid = {}

	asteroid.entity = Game:CreateEntity(
		position,
		"VisBaseEntity_cl",
		model,
		"Asteroid" )
	asteroid.rigidBody = asteroid.entity:AddComponentOfType("vHavokRigidBody")
	--asteroid.rigidBody:InitCylinder(
	asteroid.rigidBody:SetMotionType(Physics.MOTIONTYPE_KEYFRAMED)
	
	local x = Util:GetRandFloat(2) - 1
	local y = Util:GetRandFloat(2) - 1
	asteroid.direction = Vision.hkvVec3(x, y, 0)
	asteroid.direction:normalize()
	
	asteroid.speed = Util:GetRandFloat(50) + 100
	
	table.insert(self.asteroids, asteroid)
end