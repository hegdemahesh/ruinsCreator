inputFolder = @"D:\shared\3dModels\fbx_input\"
outputFolder = @"D:\shared\3dModels\fbx_output\"

fn ensureTrailingSlash folderPath =
(
    if folderPath == undefined or folderPath.count == 0 then ""
    else if folderPath[folderPath.count] == '\\' then folderPath
    else folderPath + "\\"
)

fn collectGeometryNodes =
(
    for node in geometry where isValidNode node collect node
)

fn collapseNodeToMesh node =
(
    if not isValidNode node then return false

    select node

    try
    (
        convertToMesh node
        true
    )
    catch
    (
        false
    )
)

fn getUnwrapInterface unwrapModifier =
(
    local unwrapInterface = undefined

    try (unwrapInterface = unwrapModifier.unwrap6) catch ()
    if unwrapInterface == undefined do try (unwrapInterface = unwrapModifier.unwrap5) catch ()
    if unwrapInterface == undefined do try (unwrapInterface = unwrapModifier.unwrap2) catch ()

    unwrapInterface
)

fn getNodeFaceCount node =
(
    local faceCount = 0

    try (faceCount = node.mesh.numfaces) catch ()
    if faceCount == 0 do try (faceCount = getNumFaces node) catch ()

    faceCount
)

fn runFlattenMap unwrapInterface =
(
    local flattenSucceeded = false

    try
    (
        unwrapInterface.flattenMap 45.0 0.02 true 0 true true
        flattenSucceeded = true
    )
    catch ()

    if not flattenSucceeded then
    (
        try
        (
            unwrapInterface.flattenMap 45.0 0.02 true 0 true true true
            flattenSucceeded = true
        )
        catch ()
    )

    flattenSucceeded
)

fn applyProOptimizer node vertexPercent =
(
    if not isValidNode node then return false

    local optimizer = ProOptimizer()
    addModifier node optimizer

    try
    (
        optimizer.Calculate = on
        completeRedraw()
        optimizer.VertexPercent = vertexPercent
        completeRedraw()
        collapseNodeToMesh node
    )
    catch
    (
        false
    )
)

fn applyFlattenMapping node =
(
    if not isValidNode node then return false

    local unwrapModifier = Unwrap_UVW()
    addModifier node unwrapModifier

    local unwrapInterface = getUnwrapInterface unwrapModifier
    if unwrapInterface == undefined then return false

    try
    (
        select node
        modPanel.setCurrentObject unwrapModifier
        subObjectLevel = 3

        local faceCount = getNodeFaceCount node

        try (unwrapInterface.setMapChannel 1) catch ()
        if faceCount > 0 do try (unwrapInterface.selectFaces #{1..faceCount}) catch ()

        local flattenSucceeded = runFlattenMap unwrapInterface

        if not flattenSucceeded then
        (
            try
            (
                actionMan.executeAction 2077580866 "40047"
                flattenSucceeded = true
            )
            catch ()
        )

        subObjectLevel = 0

        if not flattenSucceeded then return false

        collapseNodeToMesh node
    )
    catch
    (
        subObjectLevel = 0
        false
    )
)

fn processGeometryNode node vertexPercent =
(
    if not isValidNode node then return false

    if superclassof node != GeometryClass then return true

    if not collapseNodeToMesh node then return false
    if not applyProOptimizer node vertexPercent then return false
    if not applyFlattenMapping node then return false

    true
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

        local fbxFiles = getFiles (inputFolder + "*.fbx")
        local vertexPercent = 0.02

        format "Found % FBX files.\n" fbxFiles.count

        for f in fbxFiles do
        (
            local fileNameOnly = getFilenameFile f
            local outFile = outputFolder + fileNameOnly + "_LLOD.fbx"

            format "\nProcessing: %\n" fileNameOnly

            resetMaxFile #noPrompt

            try (importFile f #noPrompt using:FBXIMP) catch
            (
                format "ERROR: Import failed for %.\n" fileNameOnly
                continue
            )

            local geometryNodes = collectGeometryNodes()

            if geometryNodes.count == 0 then
            (
                format "WARNING: No geometry found in %.\n" fileNameOnly
                continue
            )

            local fileSucceeded = true

            for node in geometryNodes while fileSucceeded do
            (
                format "  Optimizing node: %\n" node.name

                if not processGeometryNode node vertexPercent then
                (
                    format "ERROR: Failed processing node % in %.\n" node.name fileNameOnly
                    fileSucceeded = false
                )
            )

            if not fileSucceeded then continue

            try
            (
                exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
                format "Exported optimized FBX: %\n" outFile
            )
            catch
            (
                format "ERROR: Export failed for %.\n" fileNameOnly
            )
        )

        messageBox "FBX batch optimization complete." title:"Process Complete"
    )
)