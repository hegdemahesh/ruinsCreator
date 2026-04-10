inputFolder = @"D:\shared\3dModels\objects\"

global batchRotateFbxState = undefined
global batchRotateFbxRollout = undefined

struct BatchRotateFbxSessionState
(
    fileNameOnly,
    rotationRoot,
    geometryNodes,
    currentAngle = 0.0,
    requestedAction = #skip
)

fn ensureTrailingSlash folderPath =
(
    if folderPath == undefined or folderPath.count == 0 then ""
    else if folderPath[folderPath.count] == '\\' then folderPath
    else folderPath + "\\"
)

fn getExceptionText =
(
    local exceptionText = "Unknown error"
    try (exceptionText = (getCurrentException() as string)) catch ()
    exceptionText
)

fn collectGeometryNodes =
(
    for node in geometry where isValidNode node collect node
)

fn previewGeometryNodes geometryNodes =
(
    if geometryNodes.count == 0 then return false

    select geometryNodes
    try (max tool zoomextents all) catch ()
    completeRedraw()
    try (max zoomext sel all) catch ()
    redrawViews()
    try (windows.processPostedMessages()) catch ()
    true
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

fn buildRotationRoot geometryNodes =
(
    local combinedBounds = getCombinedBounds geometryNodes
    if combinedBounds == undefined then return undefined

    local pivotPoint = point3 ((combinedBounds[1].x + combinedBounds[2].x) / 2.0) ((combinedBounds[1].y + combinedBounds[2].y) / 2.0) combinedBounds[1].z
    local rotationRoot = point name:"BatchRotateRoot" pos:pivotPoint box:false cross:false centermarker:false size:1 wirecolor:(color 255 180 0)
    rotationRoot.isHidden = true

    for node in geometryNodes where isValidNode node do node.parent = rotationRoot

    rotationRoot
)

fn releaseRotationRoot rotationRoot geometryNodes =
(
    if rotationRoot != undefined then
    (
        for node in geometryNodes where isValidNode node do node.parent = undefined
        try (delete rotationRoot) catch ()
    )
)

fn setCurrentRotation angleValue =
(
    if batchRotateFbxState == undefined then return false
    if batchRotateFbxState.rotationRoot == undefined then return false

    batchRotateFbxState.currentAngle = angleValue
    batchRotateFbxState.rotationRoot.rotation = eulerangles 0 0 angleValue
    if batchRotateFbxState.geometryNodes != undefined do select batchRotateFbxState.geometryNodes
    completeRedraw()
    try (max zoomext sel all) catch ()
    redrawViews()
    try (windows.processPostedMessages()) catch ()

    if batchRotateFbxRollout != undefined do
    (
        batchRotateFbxRollout.angleValueLabel.text = ((formattedPrint angleValue format:".1f") + " deg")
    )

    true
)

fn applyRotationDelta deltaValue =
(
    if batchRotateFbxState == undefined then return false
    setCurrentRotation (batchRotateFbxState.currentAngle + deltaValue)
)

fn resetGeometryXForms geometryNodes =
(
    for node in geometryNodes where isValidNode node do
    (
        try (resetXForm node) catch ()
        try (collapseStack node) catch ()
    )
)

fn configureFbxExporter =
(
    try (FBXExporterSetParam "ResetExport") catch ()
    try (FBXExporterSetParam "Animation" false) catch ()
    try (FBXExporterSetParam "Cameras" false) catch ()
    try (FBXExporterSetParam "Lights" false) catch ()
    try (FBXExporterSetParam "ASCII" false) catch ()
)

rollout batchRotateFbxRollout "Rotate FBX" width:360 height:220
(
    label infoLabel "Inspect the FBX and rotate around world Z before saving." pos:[12,12] width:330 height:34
    label fileLabel "" pos:[12,48] width:330 height:18
    label stepLabel "Step (degrees):" pos:[12,78] width:90 height:18
    spinner stepSpinner "" pos:[110,76] width:70 range:[1,180,1] type:#float scale:1
    label angleLabel "Current rotation:" pos:[12,108] width:95 height:18
    label angleValueLabel "0.0 deg" pos:[110,108] width:100 height:18
    button rotateLeftButton "Rotate CCW" pos:[12,138] width:100 height:28
    button rotateRightButton "Rotate CW" pos:[120,138] width:100 height:28
    button resetButton "Reset 0" pos:[228,138] width:100 height:28
    button saveButton "Save + Next" pos:[12,176] width:100 height:28
    button skipButton "Skip" pos:[120,176] width:100 height:28
    button cancelButton "Cancel Batch" pos:[228,176] width:100 height:28

    on batchRotateFbxRollout open do
    (
        if batchRotateFbxState != undefined then
        (
            fileLabel.text = batchRotateFbxState.fileNameOnly
            stepSpinner.value = 1
            angleValueLabel.text = ((formattedPrint batchRotateFbxState.currentAngle format:".1f") + " deg")
            previewGeometryNodes batchRotateFbxState.geometryNodes
        )
    )

    on rotateLeftButton pressed do
    (
        applyRotationDelta stepSpinner.value
    )

    on rotateRightButton pressed do
    (
        applyRotationDelta (-stepSpinner.value)
    )

    on resetButton pressed do
    (
        setCurrentRotation 0
    )

    on saveButton pressed do
    (
        batchRotateFbxState.requestedAction = #save
        destroyDialog batchRotateFbxRollout
    )

    on skipButton pressed do
    (
        batchRotateFbxState.requestedAction = #skip
        destroyDialog batchRotateFbxRollout
    )

    on cancelButton pressed do
    (
        batchRotateFbxState.requestedAction = #cancel
        destroyDialog batchRotateFbxRollout
    )

    on batchRotateFbxRollout close do
    (
        if batchRotateFbxState != undefined and batchRotateFbxState.requestedAction == undefined do batchRotateFbxState.requestedAction = #cancel
    )
)

fn promptForRotation fileNameOnly geometryNodes =
(
    local rotationRoot = buildRotationRoot geometryNodes
    if rotationRoot == undefined then return #skip

    batchRotateFbxState = BatchRotateFbxSessionState fileNameOnly:fileNameOnly rotationRoot:rotationRoot geometryNodes:geometryNodes currentAngle:0.0 requestedAction:undefined
    createDialog batchRotateFbxRollout modal:true style:#(#style_titlebar, #style_sysmenu)

    local requestedAction = batchRotateFbxState.requestedAction
    if requestedAction == undefined then requestedAction = #cancel

    releaseRotationRoot batchRotateFbxState.rotationRoot batchRotateFbxState.geometryNodes
    batchRotateFbxState = undefined
    requestedAction
)

selectedInputFolder = getSavePath caption:"Select FBX Folder To Rotate" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No FBX folder selected." title:"Batch Cancelled"
)
else
(
    inputFolder = ensureTrailingSlash selectedInputFolder

    local fbxFiles = getFiles (inputFolder + "*.fbx")
    local processedCount = 0
    local savedCount = 0
    local skippedCount = 0
    local errorCount = 0
    local cancelBatch = false

    format "Found % FBX files.\n" fbxFiles.count

    for f in fbxFiles while not cancelBatch do
    (
        local fileNameOnly = getFilenameFile f
        format "\nProcessing: %\n" fileNameOnly
        processedCount += 1

        resetMaxFile #noPrompt

        try (importFile f #noPrompt using:FBXIMP) catch
        (
            errorCount += 1
            format "ERROR: Import failed for %: %\n" fileNameOnly (getExceptionText())
            continue
        )

        local geometryNodes = collectGeometryNodes()

        if geometryNodes.count == 0 then
        (
            skippedCount += 1
            format "WARNING: No geometry found in %.\n" fileNameOnly
            continue
        )

        previewGeometryNodes geometryNodes

        local promptResult = promptForRotation fileNameOnly geometryNodes

        if promptResult == #cancel then
        (
            cancelBatch = true
            format "Batch cancelled by user.\n"
        )
        else if promptResult == #skip then
        (
            skippedCount += 1
            format "Skipped: %\n" fileNameOnly
        )
        else
        (
            resetGeometryXForms geometryNodes
            configureFbxExporter()

            try
            (
                exportFile f #noPrompt selectedOnly:false using:FBXEXP
                savedCount += 1
                format "Saved rotated FBX: %\n" f
            )
            catch
            (
                errorCount += 1
                format "ERROR: Export failed for %: %\n" fileNameOnly (getExceptionText())
            )
        )
    )

    messageBox ("FBX rotation batch complete.\n\nProcessed: " + (processedCount as string) + "\nSaved: " + (savedCount as string) + "\nSkipped: " + (skippedCount as string) + "\nErrors: " + (errorCount as string)) title:"Process Complete"
)