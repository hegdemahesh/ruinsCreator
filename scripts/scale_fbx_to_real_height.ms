inputFolder = @"D:\shared\3dModels\AImodels02\"
outputFolder = @"D:\shared\3dModels\AImodels03\"

fn ensureTrailingSlash folderPath =
(
    if folderPath.count == 0 then folderPath
    else if folderPath[folderPath.count] == '\\' then folderPath
    else folderPath + "\\"
)

fn getCombinedBounds nodes =
(
    if nodes.count == 0 then undefined
    else
    (
        local firstBounds = nodeGetBoundingBox nodes[1] (matrix3 1)
        local minPoint = firstBounds[1]
        local maxPoint = firstBounds[2]

        for nodeIndex = 2 to nodes.count do
        (
            local nodeBounds = nodeGetBoundingBox nodes[nodeIndex] (matrix3 1)
            minPoint = [amin minPoint.x nodeBounds[1].x, amin minPoint.y nodeBounds[1].y, amin minPoint.z nodeBounds[1].z]
            maxPoint = [amax maxPoint.x nodeBounds[2].x, amax maxPoint.y nodeBounds[2].y, amax maxPoint.z nodeBounds[2].z]
        )

        #(minPoint, maxPoint)
    )
)

fn getGeometryNodes =
(
    for node in geometry where isValidNode node collect node
)

fn getSceneNodes =
(
    local collectedNodes = #()

    for node in objects where isValidNode node do append collectedNodes node
    for node in helpers where isValidNode node do append collectedNodes node
    for node in shapes where isValidNode node do append collectedNodes node

    collectedNodes
)

fn promptForTargetHeight fileNameOnly currentHeightMeters =
(
    dotNet.loadAssembly "System.Windows.Forms"
    dotNet.loadAssembly "System.Drawing"

    local form = dotNetObject "System.Windows.Forms.Form"
    local label = dotNetObject "System.Windows.Forms.Label"
    local textBox = dotNetObject "System.Windows.Forms.TextBox"
    local okButton = dotNetObject "System.Windows.Forms.Button"
    local cancelButton = dotNetObject "System.Windows.Forms.Button"
    local dialogResultClass = dotNetClass "System.Windows.Forms.DialogResult"

    form.Text = "Set Real-World Height"
    form.Width = 420
    form.Height = 220
    form.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedDialog
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
    form.MaximizeBox = false
    form.MinimizeBox = false
    form.TopMost = true

    label.AutoSize = false
    label.Left = 12
    label.Top = 12
    label.Width = 380
    label.Height = 95
    label.Text = "Inspect the FBX in the viewport and enter the target height in meters for:" + "\r\n\r\n" + fileNameOnly + "\r\n\r\nCurrent height: " + (currentHeightMeters as string) + " m"

    textBox.Left = 12
    textBox.Top = 115
    textBox.Width = 380
    textBox.Text = currentHeightMeters as string

    okButton.Text = "OK"
    okButton.Left = 226
    okButton.Top = 145
    okButton.Width = 80
    okButton.DialogResult = dialogResultClass.OK

    cancelButton.Text = "Skip"
    cancelButton.Left = 312
    cancelButton.Top = 145
    cancelButton.Width = 80
    cancelButton.DialogResult = dialogResultClass.Cancel

    form.Controls.Add label
    form.Controls.Add textBox
    form.Controls.Add okButton
    form.Controls.Add cancelButton
    form.AcceptButton = okButton
    form.CancelButton = cancelButton

    local responseResult = form.ShowDialog()
    local response = textBox.Text

    if responseResult != dialogResultClass.OK then
    (
        if queryBox ("Skip " + fileNameOnly + " and continue with the next file?") title:"Batch Scale FBX" then #skip else #cancel
    )
    else
    (
        response = trimRight (trimLeft response)

        local parsedHeight = undefined
        try (parsedHeight = response as float) catch ()

        if response == "" then #skip
        else if parsedHeight == undefined or parsedHeight <= 0 then
        (
            messageBox "Please enter a positive number in meters." title:"Invalid Height"
            promptForTargetHeight fileNameOnly currentHeightMeters
        )
        else parsedHeight
    )
)

fn scaleNodesUniformly sceneNodes scaleFactor pivotPoint =
(
    local scaleRoot = point name:"BatchScaleRoot" pos:pivotPoint box:false cross:false centermarker:false size:1 wirecolor:(color 255 180 0)
    scaleRoot.isHidden = true

    for node in sceneNodes do node.parent = scaleRoot

    scaleRoot.scale = [scaleFactor, scaleFactor, scaleFactor]

    for node in sceneNodes do node.parent = undefined

    delete scaleRoot
)

selectedInputFolder = getSavePath caption:"Select FBX Input Folder" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No input folder selected." title:"Batch Cancelled"
)
else
(
    local selectedOutputFolder = getSavePath caption:"Select FBX Output Folder" initialDir:outputFolder

    if selectedOutputFolder == undefined then
    (
        messageBox "No output folder selected." title:"Batch Cancelled"
    )
    else
    (
        inputFolder = ensureTrailingSlash selectedInputFolder
        outputFolder = ensureTrailingSlash selectedOutputFolder

        if not doesDirectoryExist outputFolder do makeDir outputFolder

        local metersInSystemUnits = units.decodeValue "1m"
        local fbxFiles = getFiles (inputFolder + "*.fbx")
        local cancelBatch = false

        format "Found % FBX files.\n" fbxFiles.count

        for f in fbxFiles while not cancelBatch do
        (
    local fileNameOnly = getFilenameFile f
    format "\nProcessing: %\n" fileNameOnly

    resetMaxFile #noPrompt

    try (importFile f #noPrompt using:FBXIMP) catch
    (
        format "ERROR: Import failed for %.\n" fileNameOnly
        continue
    )

    local geometryNodes = getGeometryNodes()

    if geometryNodes.count == 0 then
    (
        format "WARNING: No geometry found in %.\n" fileNameOnly
        continue
    )

    select geometryNodes
    completeRedraw()
    try (max zoomext sel all) catch ()
    redrawViews()

    local combinedBounds = getCombinedBounds geometryNodes
    local currentHeight = combinedBounds[2].z - combinedBounds[1].z

    if currentHeight <= 0 then
    (
        format "WARNING: Height is zero for %, skipping.\n" fileNameOnly
        continue
    )

    local currentHeightMeters = currentHeight / metersInSystemUnits
    local targetHeightMeters = promptForTargetHeight fileNameOnly currentHeightMeters

    if targetHeightMeters == #cancel then
    (
        cancelBatch = true
        format "Batch cancelled by user.\n"
    )
    else if targetHeightMeters == #skip then
    (
        format "Skipped: %\n" fileNameOnly
    )
    else
    (
        local targetHeightSystemUnits = targetHeightMeters * metersInSystemUnits
        local scaleFactor = targetHeightSystemUnits / currentHeight
        local pivotPoint = point3 ((combinedBounds[1].x + combinedBounds[2].x) / 2.0) ((combinedBounds[1].y + combinedBounds[2].y) / 2.0) combinedBounds[1].z
        local sceneNodes = getSceneNodes()

        scaleNodesUniformly sceneNodes scaleFactor pivotPoint

        local outFile = outputFolder + fileNameOnly + ".fbx"

        try (exportFile outFile #noPrompt selectedOnly:false using:FBXEXP) catch
        (
            format "ERROR: Export failed for %.\n" fileNameOnly
            continue
        )

        format "Exported scaled FBX: %\n" outFile
    )
        )

        messageBox "FBX real-world scaling batch complete." title:"Process Complete"
    )
)