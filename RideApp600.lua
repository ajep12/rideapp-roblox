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

	local QT = 0
	local Status = "Closed"

	local unitCount = 0
	local totalSeats = 0
	local maxSeats = config.UnitCount * config.SeatsPerUnit

	local Throughput = 0

	HQ:SetAttribute("RideGroup", config.Group)

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
			QueueScreen.TextLabel.Text = QT .. "\nMinutes"
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

	if config.StartUpStatus == "Open" then
		OpenQueue()
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

	local function updateCapacityDisplay()
		Tablet.Application.RideCapacity.Unit.Text = tostring(unitCount)
		Tablet.Application.RideCapacity.Seats.Text = tostring(totalSeats)
	end

	local function addSeat()
		if totalSeats >= maxSeats then return end

		totalSeats += 1
		updateCapacityDisplay()
	end

	local function removeSeat()
		if totalSeats <= 0 then return end

		totalSeats -= 1
		updateCapacityDisplay()
	end

	local function addUnit()
		if unitCount >= config.UnitCount then return end

		unitCount += 1
		totalSeats += config.SeatsPerUnit

		if totalSeats > maxSeats then
			totalSeats = maxSeats
		end

		updateCapacityDisplay()
	end

	local function removeUnit()
		if unitCount <= 0 then return end

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

	local function appendDigit(digit)
		if Status == "Closed" then return end
		if Throughput >= 999 then return end

		local newValue

		if Throughput == 0 then
			newValue = tonumber(digit)
		else
			newValue = tonumber(tostring(Throughput) .. digit)
		end

		if #tostring(newValue) > 3 then return end

		Throughput = newValue
		updateThroughputDisplay()
	end

	local function addThroughput()
		if Status == "Closed" then return end
		if Throughput >= 999 then return end

		Throughput += 1
		updateThroughputDisplay()
	end

	local function backspaceThroughput()
		if Status == "Closed" then return end

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
		if Status == "Closed" then return end
		if Throughput == 0 then return end

		print("\n=== " .. config.AttractionName .. " RIDER LOG ===")
		print("Riders:", Throughput)
		print("==========================")

		Throughput = 0
		updateThroughputDisplay()
	end

	if config.StartUpStatus == "Closed" then
		CloseQueue("Opening Soon")
	else
		OpenQueue()
	end

	Tablet.Application.Heading.TextLabel.Text = config.AttractionName
	HQ:SetAttribute("AttractionName", config.AttractionName)

	updateOpeningTimesDisplay()
	updateCapacityDisplay()
	updateThroughputDisplay()

	parkConfig.OpenHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.OpenMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseHour:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)
	parkConfig.CloseMinute:GetPropertyChangedSignal("Value"):Connect(updateOpeningTimesDisplay)

	Tablet.Application.RideCapacity.AddUnit.MouseButton1Click:Connect(addUnit)
	Tablet.Application.RideCapacity.SubtractUnit.MouseButton1Click:Connect(removeUnit)
	Tablet.Application.RideCapacity.AddSeats.MouseButton1Click:Connect(addSeat)
	Tablet.Application.RideCapacity.SubtractSeats.MouseButton1Click:Connect(removeSeat)
	Tablet.Application.RideCapacity.Submit.MouseButton1Click:Connect(submitCapacity)

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
		if Status == "Closed" then return end
		if Throughput == 0 then return end

		appendDigit(0)
	end)

	Tablet.Application.NumberOfRiders.Numbers.Backspace.MouseButton1Click:Connect(backspaceThroughput)
	Tablet.Application.NumberOfRiders.Submit.MouseButton1Click:Connect(submitThroughput)

	Tablet.Application.Buttons.OpenRide.MouseButton1Click:Connect(OpenQueue)
	Tablet.Application.Buttons.CloseRide.MouseButton1Click:Connect(PromptClosure)

	Tablet.Application.QueueTimes.Add.MouseButton1Click:Connect(AddQueue)
	Tablet.Application.QueueTimes.Subtract.MouseButton1Click:Connect(SubtractQueue)
	Tablet.Application.Heading.AttractionStatus.MouseButton1Click:Connect(PromptClosure)
end

return RideApp
