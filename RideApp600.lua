local Vault = require(89336655405102)

local RideApp = {}

function RideApp.Start(HQ)
	if not HQ then
		warn("RideApp | No ride model was passed into RideApp.Start()")
		return
	end

	if not Vault:WhitelistAync({
		productUUID = "774c8ef5-def6-4288-9eba-39da694732b4",
		vaultUUID = "a385fb95-68de-450b-8b05-1551d4703676",
		blockStudio = false,
		alerts = true
	}) then
		print("RideApp | So, someone has found an unlicensed product!")
		HQ:Destroy()
		return
	end

	local config = require(HQ.Configuration)

	local Tablet = HQ.RideAppTablet.Union2.SurfaceGui
	local QueueScreen = HQ.QueueScreen.Screen.SurfaceGui
	local Barrier = HQ.Barrier
	local parkConfig = HQ.Parent.Parent.Configuration

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")

	local remotes = ReplicatedStorage:FindFirstChild("RideApp")

	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "RideApp"
		remotes.Parent = ReplicatedStorage
	end

	local LoginRequest = remotes:FindFirstChild("LoginRequest")

	if not LoginRequest then
		LoginRequest = Instance.new("RemoteEvent")
		LoginRequest.Name = "LoginRequest"
		LoginRequest.Parent = remotes
	end

	local LoginResult = remotes:FindFirstChild("LoginResult")

	if not LoginResult then
		LoginResult = Instance.new("RemoteEvent")
		LoginResult.Name = "LoginResult"
		LoginResult.Parent = remotes
	end

	local QT = 0
	local Status = "Closed"

	local unitCount = 0
	local totalSeats = 0
	local maxSeats = config.UnitCount * config.SeatsPerUnit

	local Throughput = 0

	local ManualOverride = false
	local AutoCloseDone = false
	local CurrentDay = ""

	local SignedInStaff = {}

	HQ:SetAttribute("RideGroup", config.Group)
	HQ:SetAttribute("AttractionName", config.AttractionName)
	HQ:SetAttribute("ManualOverride", ManualOverride)

	if Tablet:FindFirstChild("Login") then
		Tablet.Login.Visible = false
	end

	--------------------------------------------------
	-- STAFF LOGIN
	--------------------------------------------------

	local function getAvailableRoles(player)
		local qualifications = player:FindFirstChild("Qualifications")

		if not qualifications then
			return {}
		end

		local roles = {}

		for roleName, qualificationName in pairs(config.RequiredQualifications or {}) do
			local qualification = qualifications:FindFirstChild(qualificationName)

			if qualification
				and qualification:IsA("BoolValue")
				and qualification.Value then

				table.insert(roles, {
					Role = roleName,
					Qualification = qualificationName
				})
			end
		end

		return roles
	end

	local function getStaffCount()
		local count = 0

		for _ in pairs(SignedInStaff) do
			count += 1
		end

		return count
	end

	LoginRequest.OnServerEvent:Connect(function(player, action, value)
		if action == "Login" then
			local qualifications = player:FindFirstChild("Qualifications")

			if not qualifications then
				LoginResult:FireClient(player, false, "Qualifications not found")
				return
			end

			local pin = qualifications:FindFirstChild("Pin")

			if not pin then
				LoginResult:FireClient(player, false, "PIN not found")
				return
			end

			if tostring(value) ~= tostring(pin.Value) then
				LoginResult:FireClient(player, false, "Incorrect PIN")
				return
			end

			if SignedInStaff[player] then
				LoginResult:FireClient(player, false, "You are already signed in")
				return
			end

			if config.MaxStaff and getStaffCount() >= config.MaxStaff then
				LoginResult:FireClient(player, false, "Maximum staff reached")
				return
			end

			local roles = getAvailableRoles(player)

			if #roles == 0 then
				LoginResult:FireClient(
					player,
					false,
					"You are not qualified for this attraction"
				)
				return
			end

			LoginResult:FireClient(player, true, "ChooseRole", roles)
			return
		end

		if action == "SelectRole" then
			if SignedInStaff[player] then
				LoginResult:FireClient(player, false, "You are already signed in")
				return
			end

			if config.MaxStaff and getStaffCount() >= config.MaxStaff then
				LoginResult:FireClient(player, false, "Maximum staff reached")
				return
			end

			local roles = getAvailableRoles(player)
			local selectedRole

			for _, role in ipairs(roles) do
				if role.Role == value then
					selectedRole = role
					break
				end
			end

			if not selectedRole then
				LoginResult:FireClient(player, false, "Invalid role")
				return
			end

			SignedInStaff[player] = selectedRole.Role

			player:SetAttribute("RideAppSignedIn", true)
			player:SetAttribute("RideAppRole", selectedRole.Role)
			player:SetAttribute("RideAppAttraction", config.AttractionName)

			LoginResult:FireClient(
				player,
				true,
				"LoggedIn",
				selectedRole.Role,
				selectedRole.Qualification
			)

			print(
				"RideApp | "
					.. player.Name
					.. " signed into "
					.. config.AttractionName
					.. " as "
					.. selectedRole.Role
			)

			return
		end

		if action == "Logout" then
			if not SignedInStaff[player] then
				return
			end

			SignedInStaff[player] = nil

			player:SetAttribute("RideAppSignedIn", false)
			player:SetAttribute("RideAppRole", nil)
			player:SetAttribute("RideAppAttraction", nil)

			LoginResult:FireClient(player, true, "LoggedOut")

			print(
				"RideApp | "
					.. player.Name
					.. " logged out of "
					.. config.AttractionName
			)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		SignedInStaff[player] = nil
	end)

	--------------------------------------------------
	-- TIME
	--------------------------------------------------

	local function getLocalTime()
		local offset = parkConfig.TimezoneOffset.Value
		local utc = os.time()
		local adjusted = utc + (offset * 3600)

		return os.date("*t", adjusted)
	end

	local function getTimes()
		return parkConfig.OpenHour.Value,
			parkConfig.OpenMinute.Value,
			parkConfig.CloseHour.Value,
			parkConfig.CloseMinute.Value
	end

	local function getDayKey()
		local t = getLocalTime()

		return string.format(
			"%04d-%02d-%02d",
			t.year,
			t.month,
			t.day
		)
	end

	local function isWithinOperatingHours()
		local oh, om, ch, cm = getTimes()
		local t = getLocalTime()

		local current = t.hour * 60 + t.min
		local open = oh * 60 + om
		local close = ch * 60 + cm

		return current >= open and current < close
	end

	local function isAfterCloseTime()
		local _, _, ch, cm = getTimes()
		local t = getLocalTime()

		local current = t.hour * 60 + t.min
		local close = ch * 60 + cm

		return current >= close
	end

	--------------------------------------------------
	-- DISPLAY
	--------------------------------------------------

	local function updateThroughputDisplay()
		Tablet.Application.NumberOfRiders.Number.Text = tostring(Throughput)
	end

	local function updateQueueDisplay()
		if Status == "Open" then
			QueueScreen.TextLabel.Text = QT .. "\nMinutes"
			QueueScreen.ClosedReason.Text = ""
		else
			QueueScreen.TextLabel.Text = "Closed"
		end
	end

	local function updateOpeningTimesDisplay()
		local oh, om, ch, cm = getTimes()

		Tablet.Application.Heading.OpeningTimes.Text =
			string.format(
				"Open: %02d:%02d | Close: %02d:%02d",
				oh,
				om,
				ch,
				cm
			)
	end

	--------------------------------------------------
	-- RIDE
	--------------------------------------------------

	local function OpenQueue()
		local afterClose = isAfterCloseTime()

		if config.CloseLock == true and not isWithinOperatingHours() then
			return
		end

		if afterClose then
			ManualOverride = true
			HQ:SetAttribute("ManualOverride", true)
		end

		Status = "Open"
		HQ:SetAttribute("AttractionStatus", "Open")

		Barrier.CanCollide = false

		Tablet.Application.Heading.AttractionStatus.BackgroundColor3 =
			Color3.fromRGB(93, 214, 93)

		Tablet.Application.Heading.AttractionStatus.Text = "Open"

		Tablet.Application.Buttons.OpenRide.Interactable = false
		Tablet.Application.Buttons.CloseRide.Interactable = true

		Tablet.Application.Buttons.OpenRide.ImageTransparency = 0.7
		Tablet.Application.Buttons.CloseRide.ImageTransparency = 0

		Throughput = 0

		updateThroughputDisplay()
		updateQueueDisplay()
	end

	local function CloseQueue(reason)
		Status = "Closed"

		ManualOverride = false
		HQ:SetAttribute("ManualOverride", false)

		local actualreason = reason

		HQ:SetAttribute("AttractionStatus", "Closed")

		Barrier.CanCollide = true

		if reason ~= "Today"
			and reason ~= "Opening Soon"
			and reason ~= "Weather Delay" then
			reason = "Back Soon!"
		end

		Tablet.Application.Heading.AttractionStatus.BackgroundColor3 =
			Color3.fromRGB(255, 95, 89)

		Tablet.Application.Heading.AttractionStatus.Text =
			"Closed - " .. actualreason

		Tablet.Application.Buttons.OpenRide.ImageTransparency = 0
		Tablet.Application.Buttons.CloseRide.ImageTransparency = 0.7

		Tablet.Application.Buttons.CloseRide.Interactable = false
		Tablet.Application.Buttons.OpenRide.Interactable = true

		Throughput = 0

		updateThroughputDisplay()

		QueueScreen.ClosedReason.Text = reason
		QueueScreen.TextLabel.Text = "Closed"

		HQ:SetAttribute("CloseReason", reason)
	end

	--------------------------------------------------
	-- AUTOMATIC CLOSE
	--------------------------------------------------

	local function forceCloseIfNeeded()
		local day = getDayKey()

		if CurrentDay == "" then
			CurrentDay = day
		elseif CurrentDay ~= day then
			CurrentDay = day
			AutoCloseDone = false
			ManualOverride = false

			HQ:SetAttribute("ManualOverride", false)
		end

		if isAfterCloseTime()
			and Status == "Open"
			and not AutoCloseDone
			and not ManualOverride then

			AutoCloseDone = true
			CloseQueue("Today")
		end
	end

	CurrentDay = getDayKey()

	task.spawn(function()
		while HQ.Parent do
			forceCloseIfNeeded()
			task.wait(60)
		end
	end)

	--------------------------------------------------
	-- QUEUE
	--------------------------------------------------

	local function AddQueue()
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		QT += 5

		HQ:SetAttribute("AttractionQTime", QT)

		Tablet.Application.QueueTimes.QueueTime.Text = tostring(QT)

		updateQueueDisplay()
	end

	local function SubtractQueue()
		if QT <= 0 then
			return
		end

		QT -= 5

		HQ:SetAttribute("AttractionQTime", QT)

		Tablet.Application.QueueTimes.QueueTime.Text = tostring(QT)

		updateQueueDisplay()
	end

	--------------------------------------------------
	-- CLOSURE
	--------------------------------------------------

	local function PromptClosure()
		local frame = Tablet.Application.ClosureFrame
		local b = frame.Buttons

		frame.Visible = true

		frame.Close.MouseButton1Click:Connect(function()
			frame.Visible = false
		end)

		b.Fault.MouseButton1Click:Connect(function()
			CloseQueue("Technical Fault")
			frame.Visible = false
		end)

		b.Capacity.MouseButton1Click:Connect(function()
			CloseQueue("Capacity Adjustment")
			frame.Visible = false
		end)

		b.ClosedToday.MouseButton1Click:Connect(function()
			CloseQueue("Today")
			frame.Visible = false
		end)

		b.Delay.MouseButton1Click:Connect(function()
			CloseQueue("Operational Delay")
			frame.Visible = false
		end)

		b.EStopP.MouseButton1Click:Connect(function()
			CloseQueue("Emergency Stop Pressed")
			frame.Visible = false
		end)

		b.GuestA.MouseButton1Click:Connect(function()
			CloseQueue("Guest Action")
			frame.Visible = false
		end)

		b.OpeningS.MouseButton1Click:Connect(function()
			CloseQueue("Opening Soon")
			frame.Visible = false
		end)

		b.PowerF.MouseButton1Click:Connect(function()
			CloseQueue("Power Interruption")
			frame.Visible = false
		end)

		b.StaffA.MouseButton1Click:Connect(function()
			CloseQueue("Staff Action")
			frame.Visible = false
		end)

		b.TempC.MouseButton1Click:Connect(function()
			CloseQueue("Temporary Closure")
			frame.Visible = false
		end)

		b.Weather.MouseButton1Click:Connect(function()
			CloseQueue("Weather Delay")
			frame.Visible = false
		end)

		b.EssentialC.MouseButton1Click:Connect(function()
			CloseQueue("Essential Cleaning")
			frame.Visible = false
		end)
	end

	--------------------------------------------------
	-- CAPACITY
	--------------------------------------------------

	local function updateCapacityDisplay()
		Tablet.Application.RideCapacity.Unit.Text = tostring(unitCount)
		Tablet.Application.RideCapacity.Seats.Text = tostring(totalSeats)
	end

	local function addSeat()
		if totalSeats >= maxSeats then
			return
		end

		totalSeats += 1
		updateCapacityDisplay()
	end

	local function removeSeat()
		if totalSeats <= 0 then
			return
		end

		totalSeats -= 1
		updateCapacityDisplay()
	end

	local function addUnit()
		if unitCount >= config.UnitCount then
			return
		end

		unitCount += 1
		totalSeats += config.SeatsPerUnit

		if totalSeats > maxSeats then
			totalSeats = maxSeats
		end

		updateCapacityDisplay()
	end

	local function removeUnit()
		if unitCount <= 0 then
			return
		end

		unitCount -= 1
		totalSeats -= config.SeatsPerUnit

		if totalSeats < 0 then
			totalSeats = 0
		end

		updateCapacityDisplay()
	end

	local function submitCapacity()
		if totalSeats == 0 then
			print("Submit blocked: no seats")
			return
		end

		print("\n=== " .. config.AttractionName .. " CAPACITY LOG ===")
		print("Units: " .. unitCount)
		print("Seats Used: " .. totalSeats)
		print("==========================")

		unitCount = 0
		totalSeats = 0

		updateCapacityDisplay()
	end

	--------------------------------------------------
	-- THROUGHPUT
	--------------------------------------------------

	local function appendDigit(digit)
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		if Throughput >= 999 then
			return
		end

		local newValue

		if Throughput == 0 then
			newValue = tonumber(digit)
		else
			newValue = tonumber(tostring(Throughput) .. digit)
		end

		if #tostring(newValue) > 3 then
			return
		end

		Throughput = newValue
		updateThroughputDisplay()
	end

	local function addThroughput()
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		if Throughput >= 999 then
			return
		end

		Throughput += 1
		updateThroughputDisplay()
	end

	local function backspaceThroughput()
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		local text = tostring(Throughput)
		text = string.sub(text, 1, #text - 1)

		if text == "" then
			Throughput = 0
		else
			Throughput = tonumber(text)
		end

		updateThroughputDisplay()
	end

	local function submitThroughput()
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		if Throughput == 0 then
			return
		end

		print("\n=== " .. config.AttractionName .. " RIDER LOG ===")
		print("Riders:", Throughput)
		print("==========================")

		Throughput = 0
		updateThroughputDisplay()
	end

	--------------------------------------------------
	-- STARTUP
	--------------------------------------------------

	if config.StartUpStatus == "Closed" then
		CloseQueue("Opening Soon")
	else
		OpenQueue()
	end

	Tablet.Application.Heading.TextLabel.Text = config.AttractionName

	updateOpeningTimesDisplay()
	updateCapacityDisplay()
	updateThroughputDisplay()

	--------------------------------------------------
	-- TIME UPDATES
	--------------------------------------------------

	parkConfig.OpenHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.OpenMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)

	--------------------------------------------------
	-- CAPACITY BUTTONS
	--------------------------------------------------

	Tablet.Application.RideCapacity.AddUnit.MouseButton1Click:Connect(addUnit)
	Tablet.Application.RideCapacity.SubtractUnit.MouseButton1Click:Connect(removeUnit)
	Tablet.Application.RideCapacity.AddSeats.MouseButton1Click:Connect(addSeat)
	Tablet.Application.RideCapacity.SubtractSeats.MouseButton1Click:Connect(removeSeat)
	Tablet.Application.RideCapacity.Submit.MouseButton1Click:Connect(submitCapacity)

	--------------------------------------------------
	-- THROUGHPUT BUTTONS
	--------------------------------------------------

	Tablet.Application.NumberOfRiders.Plus.MouseButton1Click:Connect(addThroughput)

	Tablet.Application.NumberOfRiders.Numbers.One.MouseButton1Click:Connect(function()
		appendDigit(1)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Two.MouseButton1Click:Connect(function()
		appendDigit(2)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Three.MouseButton1Click:Connect(function()
		appendDigit(3)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Four.MouseButton1Click:Connect(function()
		appendDigit(4)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Five.MouseButton1Click:Connect(function()
		appendDigit(5)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Six.MouseButton1Click:Connect(function()
		appendDigit(6)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Seven.MouseButton1Click:Connect(function()
		appendDigit(7)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Eight.MouseButton1Click:Connect(function()
		appendDigit(8)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Nine.MouseButton1Click:Connect(function()
		appendDigit(9)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Zero.MouseButton1Click:Connect(function()
		if config.CloseLock == true and Status == "Closed" then
			return
		end

		if Throughput == 0 then
			return
		end

		appendDigit(0)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Backspace.MouseButton1Click:Connect(backspaceThroughput)
	Tablet.Application.NumberOfRiders.Submit.MouseButton1Click:Connect(submitThroughput)

	--------------------------------------------------
	-- RIDE CONTROLS
	--------------------------------------------------

	Tablet.Application.Buttons.OpenRide.MouseButton1Click:Connect(OpenQueue)
	Tablet.Application.Buttons.CloseRide.MouseButton1Click:Connect(PromptClosure)

	--------------------------------------------------
	-- QUEUE CONTROLS
	--------------------------------------------------

	Tablet.Application.QueueTimes.Add.MouseButton1Click:Connect(AddQueue)
	Tablet.Application.QueueTimes.Subtract.MouseButton1Click:Connect(SubtractQueue)
	Tablet.Application.Heading.AttractionStatus.MouseButton1Click:Connect(PromptClosure)
end

return RideApp
