-- Author      : Potdisc
-- Create Date : 8/6/2015
-- DefaultModule
-- lootHistory.lua	Adds the interface for displaying the collected loot history

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local LootHistory = addon:NewModule("RCLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("RCLootCouncil")
local AceGUI = LibStub("AceGUI-3.0")
local lootDB, scrollCols, data, db, numLootWon;
--[[ data structure:
data[date][playerName] = {
	["class"] = CLASS,
	[i] = { -- Num item given to player, lowest first
		-- Remaining content in lootDB[playerName]
	}
}
]]
local selectedDate, selectedName, filterMenu, moreInfo
local ROW_HEIGHT = 20;
local NUM_ROWS = 15;

function LootHistory:OnInitialize()
	scrollCols = {
		{name = "",					width = ROW_HEIGHT, },			-- Class icon, should be same row as player
		{name = L["Name"],		width = 100, 				},		-- Name of the player
		{name = "",					width = ROW_HEIGHT, },			-- Item at index icon
		{name = L["Item"],		width = 250, 				}, 	-- Item string
		{name = L["Reason"],		width = 230, comparesort = self.ResponseSort, sort = "asc", sortnext = 2},	-- Response aka the text supplied to lootDB...response
	}
	filterMenu = CreateFrame("Frame", "RCLootCouncil_LootHistory_FilterMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	Lib_UIDropDownMenu_Initialize(filterMenu, self.FilterMenu, "MENU")
	--MoreInfo
	self.moreInfo = CreateFrame( "GameTooltip", "RCLootHistoryMoreInfo", nil, "GameTooltipTemplate" )

	-- Definir el popup para exportación CSV
	if not StaticPopupDialogs["RCLOOTCOUNCIL_EXPORT_CSV"] then
		StaticPopupDialogs["RCLOOTCOUNCIL_EXPORT_CSV"] = {
			text = "Datos CSV para exportar:",
			button1 = "Cerrar",
			hasEditBox = true,
			editBoxWidth = 350,
			maxLetters = 0,
			OnShow = function(self, data)
				self.editBox:SetText(data)
				self.editBox:HighlightText()
				self.editBox:SetFocus()
			end,
			EditBoxOnEscapePressed = function(self)
				self:GetParent():Hide()
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	end
end

function LootHistory:OnEnable()
	addon:Debug("OnEnable()")
	moreInfo = true
	db = addon:Getdb()
	lootDB = addon:GetHistoryDB()
	self.frame = self:GetFrame()
	self:BuildData()
	self:Show()
end

function LootHistory:OnDisable()
	self:Hide()
	self.frame:SetParent(nil)
	self.frame = nil
	data = {}
end

function LootHistory:Show()
	self.frame:Show()
end

function LootHistory:Hide()
	self.frame:Hide()
	self.moreInfo:Hide()
	moreInfo = false
end

function LootHistory:BuildData()
	addon:Debug("LootHistory:BuildData()")
	data = {}
	numLootWon = {} -- playerName = #
	local date
	-- We want to rebuild lootDB to the "data" format:
	for name, v in pairs(lootDB) do
		numLootWon[name] = 0
		-- Now we actually add the data
		for i = 1, #v do
			numLootWon[name] = numLootWon[name] + 1
			date = v[i].date
			if not date then -- Unknown date
				date = L["Unknown date"]
			end
			if not data[date] then -- We haven't added the date to data, do it
				data[date] = {}
			end
			if not data[date][name] then
				data[date][name] = {}
				data[date][name].items = {}
			end
			-- Store class at the player level
			if v[i].class then
				data[date][name].class = v[i].class
			end
			-- Store item data sequentially
			local itemIndex = #data[date][name].items + 1
			data[date][name].items[itemIndex] = {}
			for k, t in pairs(v[i]) do
				if k ~= "class" and k ~= "date" then
					data[date][name].items[itemIndex][k] = t
				end
			end
			if not data[date][name].items[itemIndex].instance then
				data[date][name].items[itemIndex].instance = L["Unknown"]
			end
		end
	end

	-- Sort dates in reverse chronological order
	local dates = {}
	for date in pairs(data) do
		tinsert(dates, date)
	end
	table.sort(dates, function(a,b)
		local d1, m1, y1 = strsplit("/", a, 3)
		local d2, m2, y2 = strsplit("/", b, 3)
		local t1 = time({year = "20"..y1, month = m1, day = d1})
		local t2 = time({year = "20"..y2, month = m2, day = d2})
		return t1 > t2
	end)

	-- Now create the rows for lib-st
	self.frame.rows = {}
	local dateData, nameData, insertedNames = {}, {}, {}
	local row = 1

	for _, date in ipairs(dates) do
		for name, playerData in pairs(data[date]) do
			if playerData.items then
				for itemIndex, itemData in ipairs(playerData.items) do
					self.frame.rows[row] = {
						date = date,
						class = playerData.class,
						name = name,
						num = itemIndex,
						response = itemData.responseID,
						cols = {
							{DoCellUpdate = addon.SetCellClassIcon, args = {playerData.class}},
							{value = name, color = addon:GetClassColor(playerData.class)},
							{DoCellUpdate = self.SetCellGear, args = {itemData.lootWon}},
							{value = itemData.lootWon},
							{DoCellUpdate = self.SetCellResponse, args = {
								color = itemData.color,
								response = itemData.response,
								responseID = itemData.responseID or 0,
								isAwardReason = itemData.isAwardReason
							}}
						}
					}
					row = row + 1
				end
			end

			if not tContains(insertedNames, name) then
				tinsert(nameData, {
					{DoCellUpdate = addon.SetCellClassIcon, args = {playerData.class}},
					{value = name, color = addon:GetClassColor(playerData.class), name = name}
				})
				tinsert(insertedNames, name)
			end
		end
		tinsert(dateData, {date})
	end

	self.frame.st:SetData(self.frame.rows)
	self.frame.date:SetData(dateData, true)
	self.frame.name:SetData(nameData, true)
end

function LootHistory.FilterFunc(table, row)
	local nameAndDate = true -- default to show everything
	if selectedName and selectedDate then
		nameAndDate = row.name == selectedName and row.date == selectedDate
	elseif selectedName then
		nameAndDate = row.name == selectedName
	elseif selectedDate then
		nameAndDate = row.date == selectedDate
	end

	local responseFilter = true -- default to show
	if not db.modules["RCLootHistory"].filters then return nameAndDate end -- db hasn't been initialized
	local response = row.response
	if response == "AUTOPASS" or response == "PASS" or type(response) == "number" then
		responseFilter = db.modules["RCLootHistory"].filters[response]
	else -- Filter out the status texts
		responseFilter = db.modules["RCLootHistory"].filters["STATUS"]
	end

	return nameAndDate and responseFilter -- Either one can filter the entry
end

function LootHistory.SetCellGear(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local gear = data[realrow].cols[column].args[1] -- gear1 or gear2
	if gear then
		local texture = select(10, GetItemInfo(gear))
		frame:SetNormalTexture(texture)
		frame:SetScript("OnEnter", function() addon:CreateHypertip(gear) end)
		frame:SetScript("OnLeave", function() addon:HideTooltip() end)
		frame:Show()
	else
		frame:Hide()
	end
end

function LootHistory.SetCellResponse(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local args = data[realrow].cols[column].args
	if args.responseID and args.responseID ~= 0 and not args.isAwardReason then
		frame.text:SetText((addon.db.profile.buttons[args.responseID] or addon.responses[args.responseID]).text)
	else
		frame.text:SetText(args.response)
	end
	if args.color then -- Never version saves the color with the entry
		frame.text:SetTextColor(unpack(args.color))
	elseif args.responseID > 0 then -- try to recreate color from ID
		frame.text:SetTextColor(addon:GetResponseColor(args.responseID))
	else -- default to white
		frame.text:SetTextColor(1,1,1,1)
	end
end

function LootHistory.DateSort(table, rowa, rowb, sortbycol)
	local column = table.cols[sortbycol]
	rowa, rowb = table:GetRow(rowa), table:GetRow(rowb);
	local a, b = rowa[1], rowb[1]
	if not (a and b) then return false end
	local d, m, y = strsplit("/", a, 3)
	local aTime = time({year = "20"..y, month = m, day = d})
	d, m, y = strsplit("/", b, 3)
	local bTime = time({year = "20"..y, month = m, day = d})
	local direction = column.sort or column.defaultsort or "asc";
	if direction:lower() == "asc" then
		return aTime < bTime;
	else
		return aTime > bTime;
	end
end

function LootHistory.ResponseSort(table, rowa, rowb, sortbycol)
	local column = table.cols[sortbycol]
	rowa, rowb = table:GetRow(rowa), table:GetRow(rowb);
	local a,b

	-- Acceder a los datos de manera segura con la nueva estructura
	local dataA = data[rowa.date] and data[rowa.date][rowa.name] and data[rowa.date][rowa.name].items and data[rowa.date][rowa.name].items[rowa.num]
	local dataB = data[rowb.date] and data[rowb.date][rowb.name] and data[rowb.date][rowb.name].items and data[rowb.date][rowb.name].items[rowb.num]

	local aID = dataA and dataA.responseID
	local bID = dataB and dataB.responseID

	if aID and aID ~= 0 then
		if dataA.isAwardReason then
			a = db.awardReasons[aID] and db.awardReasons[aID].sort or 500
		else
			a = addon:GetResponseSort(aID)
		end
	else
		a = 500
	end

	if bID and bID ~= 0 then
		if dataB.isAwardReason then
			b = db.awardReasons[bID] and db.awardReasons[bID].sort or 500
		else
			b = addon:GetResponseSort(bID)
		end
	else
		b = 500
	end

	local direction = column.sort or column.defaultsort or "asc";
	if direction:lower() == "asc" then
		return a < b;
	else
		return a > b;
	end
end

---------------------------------------------------
-- Visauls
---------------------------------------------------
function LootHistory:Update()
	self.frame.st:SortData()
end

function LootHistory:GetFrame()
	if self.frame then return self.frame end
	local f = addon:CreateFrame("DefaultRCLootHistoryFrame", "history", L["RCLootCouncil Loot History"], 250, 480)
	local st = LibStub("ScrollingTable"):CreateST(scrollCols, NUM_ROWS, ROW_HEIGHT, { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 }, f.content)
	st.frame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
	st:SetFilter(self.FilterFunc)
	st:EnableSelection(true)
	st:RegisterEvents({
		["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
			if row or realrow then
				self:UpdateMoreInfo(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
			end
			return false
		end
	})
	f.st = st

	--Date selection
	f.date = LibStub("ScrollingTable"):CreateST({{name = L["Date"], width = 70, comparesort = self.DateSort, sort = "desc"}}, 5, ROW_HEIGHT, { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 }, f.content)
	f.date.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -20)
	f.date:EnableSelection(true)
	f.date:RegisterEvents({
		["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
			if button == "LeftButton" and row then
				selectedDate = data[realrow][column] ~= selectedDate and data[realrow][column] or nil
				self:Update()
			end
			return false
		end
	})

	--Name selection
	f.name = LibStub("ScrollingTable"):CreateST({{name = "", width = ROW_HEIGHT},{name = L["Name"], width = 100, sort = "desc"}}, 5, ROW_HEIGHT, { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 }, f.content)
	f.name.frame:SetPoint("TOPLEFT", f.date.frame, "TOPRIGHT", 20, 0)
	f.name:EnableSelection(true)
	f.name:RegisterEvents({
		["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
			if button == "LeftButton" and row then
				selectedName = selectedName ~= data[realrow][column].name and data[realrow][column].name or nil
				self:Update()
			end
			return false
		end
	})

	-- Abort button
	local b1 = addon:CreateButton(L["Close"], f.content)
	b1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -100)
	b1:SetScript("OnClick", function() self:Disable() end)
	f.closeBtn = b1

	-- More info button
	local b2 = CreateFrame("Button", nil, f.content, "UIPanelButtonTemplate")
	b2:SetSize(25,25)
	b2:SetPoint("BOTTOMRIGHT", b1, "TOPRIGHT", 0, 10)
	b2:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	b2:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
	b2:SetScript("OnClick", function(button)
		moreInfo = not moreInfo
		self.frame.st:ClearSelection()
		self:UpdateMoreInfo()
		if moreInfo then -- show the more info frame
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
			self.moreInfo:Show()
		else -- hide it
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
			self.moreInfo:Hide()
		end
		addon:Debug("moreInfo =",moreInfo)
	end)
	b2:SetScript("OnEnter", function() addon:CreateTooltip(L["Click to expand/collapse more info"]) end)
	b2:SetScript("OnLeave", addon.HideTooltip)
	f.moreInfoBtn = b2

	-- Filter
	local b3 = addon:CreateButton(L["Filter"], f.content)
	b3:SetPoint("RIGHT", b1, "LEFT", -10, 0)
	b3:SetScript("OnClick", function(self) Lib_ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0) end )
	b3:SetScript("OnEnter", function() addon:CreateTooltip(L["Deselect responses to filter them"]) end)
	b3:SetScript("OnLeave", addon.HideTooltip)
	f.filter = b3
	Lib_UIDropDownMenu_Initialize(b3, self.FilterMenu)

	-- Export CSV button
	local b4 = addon:CreateButton("Exportar CSV", f.content)
	b4:SetPoint("RIGHT", b3, "LEFT", -10, 0)
	b4:SetScript("OnClick", function() self:ExportToCSV() end)
	b4:SetScript("OnEnter", function() addon:CreateTooltip("Exportar el historial filtrado a CSV") end)
	b4:SetScript("OnLeave", addon.HideTooltip)
	f.exportCSV = b4

	-- Set a proper width
	f:SetWidth(st.frame:GetWidth() + 20)
	return f;
end

function LootHistory:UpdateMoreInfo(rowFrame, cellFrame, dat, cols, row, realrow, column, table, button, ...)
	if not dat then return end
	local tip = self.moreInfo -- shortening
	tip:SetOwner(self.frame, "ANCHOR_RIGHT")
	local row = dat[realrow]
	local color = addon:GetClassColor(row.class)
	local data = data[row.date][row.name][row.num]
	tip:AddLine(row.name, color.r, color.g, color.b)
	tip:AddLine("")
	tip:AddDoubleLine(L["Time:"], (data.time or L["Unknown"]) .." ".. row.date or L["Unknown"], 1,1,1, 1,1,1)
	tip:AddDoubleLine(L["Loot won:"], data.lootWon or L["Unknown"], 1,1,1, 1,1,1)
	if data.itemReplaced1 then
		tip:AddDoubleLine(L["Item(s) replaced:"], data.itemReplaced1, 1,1,1)
		if data.itemReplaced2 then
			tip:AddDoubleLine(" ", data.itemReplaced2)
		end
	end
	tip:AddDoubleLine(L["Dropped by:"], data.boss or L["Unknown"], 1,1,1, 0.862745, 0.0784314, 0.235294)
	tip:AddDoubleLine(L["From:"], data.instance or L["Unknown"], 1,1,1, 0.823529, 0.411765, 0.117647)
	tip:AddDoubleLine(L["Votes"]..":", data.votes or L["Unknown"], 1,1,1, 1,1,1)
	tip:AddDoubleLine(L["Total items won:"], numLootWon[row.name], 1,1,1, 0,1,0)

	-- Debug stuff
	if addon.debug then
		tip:AddLine("\nDebug:")
		tip:AddDoubleLine("ResponseID", tostring(data.responseID), 1,1,1, 1,1,1)
		tip:AddDoubleLine("Response:", data.response, 1,1,1, 1,1,1)
		tip:AddDoubleLine("isAwardReason:", tostring(data.isAwardReason), 1,1,1, 1,1,1)
		tip:AddDoubleLine("color:", data.color and data.color[1]..", "..data.color[2]..", "..data.color[3] or "none", 1,1,1, 1,1,1)
	end
	tip:SetScale(db.UI.history.scale)
	tip:Show()
	tip:SetAnchorType("ANCHOR_RIGHT", 0, -tip:GetHeight())
end

function LootHistory:ExportToCSV()
	-- Crear el encabezado del CSV
	local csv = "character,date,itemID,itemName,note\n"

	-- Obtener las filas filtradas actuales
	local rows = {}
	for i = 1, #self.frame.rows do
		local row = self.frame.rows[i]
		if self.FilterFunc(self.frame.st, row) then
			tinsert(rows, row)
		end
	end

	-- Procesar cada fila
	for _, row in ipairs(rows) do
		local itemData = data[row.date][row.name].items[row.num]

		-- Extraer el itemID del link
		local itemID = itemData.lootWon:match("item:(%d+)")

		-- Extraer el nombre del item (eliminar los códigos de color y el resto del link)
		local itemName = itemData.lootWon:match("|h%[(.-)%]|h")

		-- Formatear la fecha de dd/mm/yy a yyyy-mm-dd
		local day, month, year = row.date:match("(%d+)/(%d+)/(%d+)")
		local formattedDate = string.format("20%s-%s-%s", year, month, day)

		-- Determinar la nota (OS si responseID es 3, vacío en otro caso)
		local note = itemData.responseID == 3 and "OS" or ""

		-- Escapar comillas en el nombre del item
		itemName = itemName:gsub('"', '""')

		-- Añadir la línea al CSV
		csv = csv .. string.format('%s,%s,%s,"%s",%s\n',
			row.name,
			formattedDate,
			itemID,
			itemName,
			note
		)
	end

	-- Mostrar el popup con los datos CSV
	StaticPopup_Show("RCLOOTCOUNCIL_EXPORT_CSV", nil, nil, csv)
end

---------------------------------------------------
-- Dropdowns
---------------------------------------------------
function LootHistory.FilterMenu(menu, level)
	local info = Lib_UIDropDownMenu_CreateInfo()
		if level == 1 then -- Redundant
			-- Build the data table:
			local data = {["STATUS"] = true, ["PASS"] = true, ["AUTOPASS"] = true}
			for i = 1, addon.mldb.numButtons or db.numButtons do
				data[i] = i
			end
			if not db.modules["RCLootHistory"].filters then -- Create the db entry
				addon:DebugLog("Created LootHistory filters")
				db.modules["RCLootHistory"].filters = {}
			end
			for k in pairs(data) do -- Update the db entry to make sure we have all buttons in it
				if type(db.modules["RCLootHistory"].filters[k]) ~= "boolean" then
					addon:Debug("Didn't contain "..k)
					db.modules["RCLootHistory"].filters[k] = true -- Default as true
				end
			end
			info.text = L["Filter"]
			info.isTitle = true
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			for k in ipairs(data) do -- Make sure normal responses are on top
				info.text = addon:GetResponseText(k)
				info.colorCode = "|cff"..addon:RGBToHex(addon:GetResponseColor(k))
				info.func = function()
					addon:Debug("Update Filter")
					db.modules["RCLootHistory"].filters[k] = not db.modules["RCLootHistory"].filters[k]
					LootHistory:Update()
				end
				info.checked = db.modules["RCLootHistory"].filters[k]
				Lib_UIDropDownMenu_AddButton(info, level)
			end
			for k in pairs(data) do -- A bit redundency, but it makes sure these "specials" comes last
				if type(k) == "string" then
					if k == "STATUS" then
						info.text = L["Status texts"]
						info.colorCode = "|cffde34e2" -- purpleish
					else
						info.text = addon:GetResponseText(k)
						info.colorCode = "|cff"..addon:RGBToHex(addon:GetResponseColor(k))
					end
					info.func = function()
						addon:Debug("Update Filter")
						db.modules["RCLootHistory"].filters[k] = not db.modules["RCLootHistory"].filters[k]
						LootHistory:Update()
					end
					info.checked = db.modules["RCLootHistory"].filters[k]
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end
