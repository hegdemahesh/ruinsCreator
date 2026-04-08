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
    dotNet.loadAssembly "Microsoft.VisualBasic"

    local interactionClass = dotNetClass "Microsoft.VisualBasic.Interaction"
    local promptText = "Inspect the FBX in the viewport and enter the target height in meters for:\n\n" + fileNameOnly + "\n\nCurrent height: " + (currentHeightMeters as string) + " m\n\nLeave blank to skip this file."
    local response = interactionClass.InputBox promptText "Set Real-World Height" (currentHeightMeters as string)

    if response == "" then
    (
        if queryBox ("Skip " + fileNameOnly + " and continue with the next file?") title:"Batch Scale FBX" then #skip else #cancel
    )
    else
    (
        local parsedHeight = undefined
        try (parsedHeight = response as float) catch ()

        if parsedHeight == undefined or parsedHeight <= 0 then
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