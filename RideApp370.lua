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

	local config = require(HQ:WaitForChild("Configuration"))

	HQ:SetAttribute("RideGroup", config.Group)

	local Tablet = HQ:WaitForChild("RideAppTablet").Union2.SurfaceGui
	local QueueScreen = HQ:WaitForChild("QueueScreen").Screen.SurfaceGui
	local Barrier = HQ:WaitForChild("Barrier")
	local parkConfig = HQ.Parent.Parent:WaitForChild("Configuration")

	local QT = 0
	local Status = "Closed"
	local Throughput = 0

	local function getLocalTime()
		local offset = parkConfig.TimezoneOffset.Value
		local utc = os.time()
		local adjusted = utc + (offset * 3600)
		return os.date("*t", adjusted)
	end

	local function getTimes()
		return parkConfig.OpenHour.Value, parkConfig.OpenMinute.Value, parkConfig.CloseHour.Value, parkConfig.CloseMinute.Value
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

		return (t.hour * 60 + t.min) >= (ch * 60 + cm)
	end

	local function updateThroughputDisplay()
		Tablet.Application.NumberOfRiders.Number.Text = tostring(Throughput)
	end

	local function updateQueueDisplay()
		if Status == "Open" then
			QueueScreen.TextLabel.Text = QT .. " Minutes"
			QueueScreen.ClosedReason.Text = ""
		else
			QueueScreen.TextLabel.Text = "Closed"
		end
	end

	local function updateOpeningTimesDisplay()
		local oh, om, ch, cm = getTimes()

		Tablet.Application.Heading.OpeningTimes.Text =
			string.format("Open: %02d:%02d | Close: %02d:%02d", oh, om, ch, cm)
	end

	local function OpenQueue()
		if not isWithinOperatingHours() then return end

		Status = "Open"
		HQ:SetAttribute("AttractionStatus", "Open")

		Barrier.CanCollide = false

		Tablet.Application.Heading.AttractionStatus.BackgroundColor3 = Color3.fromRGB(93, 214, 93)
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
		local actualreason = reason

		HQ:SetAttribute("AttractionStatus", "Closed")
		Barrier.CanCollide = true

		if reason ~= "Today" and reason ~= "Opening Soon" and reason ~= "Weather Delay" then
			reason = "Back Soon!"
		end

		Tablet.Application.Heading.AttractionStatus.BackgroundColor3 = Color3.fromRGB(255, 95, 89)
		Tablet.Application.Heading.AttractionStatus.Text = "Closed - " .. actualreason

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

	local function forceCloseIfNeeded()
		if isAfterCloseTime() and Status == "Open" then
			CloseQueue("Today")
		end
	end

	task.spawn(function()
		while HQ.Parent do
			forceCloseIfNeeded()
			task.wait(60)
		end
	end)

	local function AddQueue()
		if not isWithinOperatingHours() then return end

		QT += 5
		HQ:SetAttribute("AttractionQTime", QT)

		Tablet.Application.QueueTimes.QueueTime.Text = tostring(QT)
		updateQueueDisplay()
	end

	local function SubtractQueue()
		if QT <= 0 then return end

		QT -= 5
		HQ:SetAttribute("AttractionQTime", QT)

		Tablet.Application.QueueTimes.QueueTime.Text = tostring(QT)
		updateQueueDisplay()
	end

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

	if config.StartUpStatus == "Closed" then
		CloseQueue("Opening Soon")
	else
		OpenQueue()
	end

	Tablet.Application.Heading.TextLabel.Text = config.AttractionName
	HQ:SetAttribute("AttractionName", config.AttractionName)
	updateOpeningTimesDisplay()

	parkConfig.OpenHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.OpenMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)

	Tablet.Application.Buttons.OpenRide.MouseButton1Click:Connect(OpenQueue)
	Tablet.Application.Buttons.CloseRide.MouseButton1Click:Connect(PromptClosure)

	Tablet.Application.QueueTimes.Add.MouseButton1Click:Connect(AddQueue)
	Tablet.Application.QueueTimes.Subtract.MouseButton1Click:Connect(SubtractQueue)
	Tablet.Application.Heading.AttractionStatus.MouseButton1Click:Connect(PromptClosure)

	print("RideApp | Loaded successfully for", HQ.Name)
end

return RideApp
