local version = '1.0.0'
local max_camio_version = 2;
local min_camio_version = 2;
local DEBUG = false
local run_loop = true
local should_cancel = false

local function console_debug(message)
	if DEBUG then
		print('[' .. os.date('%d-%m-%y %X') .. '] ' .. message)
	end
end

local function console_error(message)
	print("ERROR: " .. message)
end

local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)

local width, height = 300, 100
local win = disp:AddWindow({
	ID = 'MyWin',
	WindowTitle = 'HLAE_CamIO_To_Davinci',
	Geometry = { 100, 100, width, height },
	Spacing = 10,
	ui:VGroup {
		ID = 'Root',
		ui:Label { ID = 'Version', Text = 'HLAE_CamIO_To_Davinci v' .. version, Alignment = { AlignHCenter = true, AlignTop = true } },
		ui:Label { ID = 'T0', Text = '0) Make sure clip fps is correct', Alignment = { AlignHLeft = true, AlignTop = true } },
		ui:Label { ID = 'T1', Text = '1) Open Fusion composition', Alignment = { AlignHLeft = true, AlignTop = true } },
		ui:Label { ID = 'T2', Text = '2) Select file to import', Alignment = { AlignHLeft = true, AlignTop = true } },
		ui:Label { ID = 'T2', Text = '3) Set data in solid plane', Alignment = { AlignHLeft = true, AlignTop = true } },
		ui:Button { Text = "Select file", ID = "FileSelect" },
		ui:VGroup { ID = 'Status' },
	},
})

local itms = win:GetItems()
itms.Root:Update()
win:RecalcLayout()
win.Geometry = { 100, 100, width, height }

function win.On.MyWin.Close()
	should_cancel = true
end

local function read_data(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local header = file:read("l")
	if header ~= "advancedfx Cam" then
		console_error("Invalid header.")
		file:close()
		return nil
	end

	local version_str = file:read("l")
	if not string.match(version_str, "version") then
		console_error("Invalid version.")
		file:close()
		return nil
	end

	local file_version = tonumber(string.sub(version_str, 9, 9))

	if file_version > max_camio_version then
		console_error("File Version " .. file_version .. " is not supported.")
		file:close()
		return nil
	end

	if file_version < min_camio_version then
		console_error("File Version " .. file_version .. " is not supported.")
		file:close()
		return nil
	end

	local _ = file:read("l")
	local data_start = file:read("l")
	if data_start ~= "DATA" then
		console_error("Expected DATA, got " .. data_start)
		file:close()
		return nil
	end

	local frames = {}
	local i = 0
	for line in file:lines() do
		local j = 0
		local data = {}

		for t in string.gmatch(line, "[^%s]+") do
			data[j] = tonumber(t)
			j = j + 1
		end

		frames[i] = data
		i = i + 1
	end

	file:close()

	return frames
end

local function set_plane_controls(fu_comp, tool_name)
	local tool = fu_comp:FindTool(tool_name)

	tool.UserControls = {
		PosRotData = {
			INP_External = false,
			LINKS_Name = "Position/rotation data",
			LINKID_DataType = "Text",
			INPID_InputControl = "TextEditControl",
			TEC_Wrap = true,
			TEC_ReadOnly = false,
		},
		ApplyPosRotData = {
			LINKS_Name = "Apply data",
			LINKID_DataType = "Number",
			INPID_InputControl = "ButtonControl",
			INP_Integer = false,
			INP_SplineType = "Default",
			BTNCS_Execute = [[
				local function split(str, delim)
					local result = {}
					delim = delim or "%s"
					for part in string.gmatch(str, "([^" .. delim .. "]+)") do
						table.insert(result, part)
					end
					return result
				end

				local tool = comp:FindTool("]] .. tool_name .. [[")
				-- probably could do checks here and print stuff to console, 
				-- but I hope people are not that stupid and can copypaste it normally
				local data = split(tool:GetInput("PosRotData"), ";")
				local pos = split(data[1], " ")
				local rot = split(data[2], " ")

				local x = tonumber(pos[2])
				local y = tonumber(pos[3])
				local z = tonumber(pos[4])
				-- the order from console command is different from HLAE .cam file
				local rx = tonumber(rot[4])
				local ry = tonumber(rot[2])
				local rz = tonumber(rot[3])

				tool.Transform3DOp.Translate.X = -y
				tool.Transform3DOp.Translate.Y = z
				tool.Transform3DOp.Translate.Z = -x
				tool.Transform3DOp.Rotate.X = ry -- it seems no need to negate this one here
				tool.Transform3DOp.Rotate.Y = rz
				tool.Transform3DOp.Rotate.Z = -rx
				tool.Transform3DOp.Scale.X = 100

				tool.PosRotData = "Transform was set."
			]],
			INP_External = false,
		}
	}

	tool:Refresh()

	tool = fu_comp:FindTool(tool_name)

	local str = [[Paste here output of 'getpos' command from game.
Example:
setpos 0.000000 0.000000 0.000000;setang 0.000000 0.000000 0.000000
]]
	tool.PosRotData = str
	bmd.wait(0.1)
	fu_comp:SetActiveTool(tool)
	tool:ShowControlPage("User")
end

function win.On.FileSelect.Clicked()
	local isError = false

	if itms.Status:Find("Progress") then
		itms.Status:RemoveChild("Progress")
	end

	local item = ui:Label { ID = "Progress", Text = "Importing..." }
	itms.Status:AddChild(item)
	itms = win:GetItems()

	-- TODO: check if there's better way. This one returns cached one too
	local fu_comp = fu:GetCurrentComp()
	if fu_comp == nil then
		local msg = "Error: fusion composition not found."
		console_error(msg)
		itms.Progress.Text = msg
		itms.Root:Update()
		win:RecalcLayout()
		return
	end

	itms.Root:Update()
	win:RecalcLayout()

	local file_path = fu:RequestFile()
	if file_path == nil then
		itms.Progress.Text = "File selection canceled."
		itms.Root:Update()
		win:RecalcLayout()
		return
	end
	console_debug("file_read start")
	local data = read_data(file_path)
	console_debug("file_read end")
	if data == nil then
		isError = true
		itms.Progress.Text = "Got nil data, see console."
	else
		itms.Progress.Text = "Setting keyframes..."
	end

	itms.Root:Update()
	win:RecalcLayout()

	if isError then
		fu_comp:EndUndo(true)
		return
	end

	local end_frame = fu_comp:GetAttrs("COMPN_GlobalEnd")

	bmd.wait(0.1)
	fu_comp.CurrentTime = 0
	fu_comp:StartUndo("Import Camera")

	local camera3d = fu_comp:AddTool("Camera3D", false, 2, 1)
	camera3d:SetAttrs({ TOOLS_Name = "MyCamera3D" })

	local merge3d = fu_comp:AddTool("Merge3D", false, 3, 1)
	merge3d:SetAttrs({ TOOLS_Name = "MyMerge3D" })

	local solid = fu_comp:AddTool("Background", false, 2, 2)
	solid:SetAttrs({ TOOLS_Name = "Solid" })
	local solid_plane = fu_comp:AddTool("ImagePlane3D", false, 3, 2)
	solid_plane:SetAttrs({ TOOLS_Name = "MyImagePlane" })

	local renderer3d = fu_comp:AddTool("Renderer3D", false, 4, 1)
	renderer3d:SetAttrs({ TOOLS_Name = "MyRenderer3D" })

	merge3d.SceneInput1 = camera3d.Output
	renderer3d.SceneInput = merge3d.Output
	merge3d.SceneInput2 = solid_plane.Output
	solid_plane.MaterialInput = solid.Output

	local mediain = fu_comp:FindTool("MediaIn1")
	if mediain ~= nil then
		camera3d.ImageInput = mediain.Output
	end

	local mediaout = fu_comp:FindTool("MediaOut1")
	mediaout.Input = renderer3d.Output

	camera3d.Transform3DOp.Translate.X = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Translate.Y = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Translate.Z = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Rotate.X = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Rotate.Y = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Rotate.Z = fu_comp.BezierSpline()
	camera3d.Transform3DOp.Rotate.RotOrder = "ZXY"

	camera3d.AovType = 1
	camera3d.AoV = fu_comp.BezierSpline()

	local position = { x = {}, y = {}, z = {} }
	local rotation = { x = {}, y = {}, z = {} }
	local fov = {}

	console_debug("frames loop start")
	for i = 0, end_frame do
		-- Davinci Z = -forward, X = right, Y = up // The Visual Effects Guide to DaVinci Resolve 18 (Navigating in 3D)
		-- HLAE is quake coordinates where X = forward, Y = left, Z = up
		local frame = data[i]
		if frame == nil then
			goto skip
		end
		local t = i
		local x = frame[1]
		local y = frame[2]
		local z = frame[3]
		local rx = frame[4]
		local ry = frame[5]
		local rz = frame[6]
		local f = frame[7]

		position.x[t] = { -y, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		position.y[t] = { z, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		position.z[t] = { -x, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		rotation.x[t] = { -ry, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		rotation.y[t] = { rz, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		rotation.z[t] = { -rx, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		fov[t] = { f, LH = { 0.0, 0.0 }, RH = { 0.0, 0.0 } }
		::skip::
	end
	console_debug("frames loop end")

	local pos_x_spline = camera3d.Transform3DOp.Translate.X:GetConnectedOutput():GetTool()
	local pos_y_spline = camera3d.Transform3DOp.Translate.Y:GetConnectedOutput():GetTool()
	local pos_z_spline = camera3d.Transform3DOp.Translate.Z:GetConnectedOutput():GetTool()
	local rot_x_spline = camera3d.Transform3DOp.Rotate.X:GetConnectedOutput():GetTool()
	local rot_y_spline = camera3d.Transform3DOp.Rotate.Y:GetConnectedOutput():GetTool()
	local rot_z_spline = camera3d.Transform3DOp.Rotate.Z:GetConnectedOutput():GetTool()
	local fov_spline = camera3d.AoV:GetConnectedOutput():GetTool()

	console_debug("set keyframes start")
	pos_x_spline:SetKeyFrames(position.x, true)
	pos_y_spline:SetKeyFrames(position.y, true)
	pos_z_spline:SetKeyFrames(position.z, true)

	rot_x_spline:SetKeyFrames(rotation.x, true)
	rot_y_spline:SetKeyFrames(rotation.y, true)
	rot_z_spline:SetKeyFrames(rotation.z, true)

	fov_spline:SetKeyFrames(fov, true)
	console_debug("set keyframes end")

	camera3d:SetInput("PerspFarClip", 10000)
	camera3d:SetInput("IDepth", 3000)

	set_plane_controls(fu_comp, "MyImagePlane")

	fu_comp:EndUndo(true)

	itms.Progress.Text = "Done."
	itms.Root:Update()
	win:RecalcLayout()
end

win:Show()

while run_loop == true do
	if should_cancel == true then
		run_loop = false
		disp:ExitLoop()
	end

	disp:StepLoop()
end

win:Hide()
