inputFolder = @"D:\shared\3dModels\AImodels04\"
outputFolder = @"D:\shared\3dModels\AImodels05\"

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

fn getExceptionText =
(
    local exceptionText = "Unknown error"
    try (exceptionText = (getCurrentException() as string)) catch ()
    exceptionText
)

fn logLine logStream text =
(
    format "%\n" text
    if logStream != undefined do format "%\n" text to:logStream
)

fn processUiEvents =
(
    try (windows.processPostedMessages()) catch ()
    completeRedraw()
)

fn getNodeFaceCount node =
(
    local faceCount = 0

    try (faceCount = node.mesh.numfaces) catch ()
    if faceCount == 0 do try (faceCount = getNumFaces node) catch ()
    if faceCount == 0 do try (faceCount = polyOp.getNumFaces node) catch ()

    faceCount
)

fn getNodeVertexCount node =
(
    local vertexCount = 0

    try (vertexCount = node.mesh.numverts) catch ()
    if vertexCount == 0 do try (vertexCount = getNumVerts node) catch ()
    if vertexCount == 0 do try (vertexCount = polyOp.getNumVerts node) catch ()

    vertexCount
)

fn buildNodeStatsText node =
(
    "verts=" + (getNodeVertexCount node as string) + ", faces=" + (getNodeFaceCount node as string)
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

fn collapseSelectionToMesh logStream stepName =
(
    try
    (
        macros.run "Modifier Stack" "Convert_to_Mesh"
        processUiEvents()
        logLine logStream ("    Collapsed stack after " + stepName + ".")
        true
    )
    catch
    (
        logLine logStream ("    ERROR: Collapse failed after " + stepName + ": " + getExceptionText())
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

fn runFlattenMap unwrapInterface logStream =
(
    local flattenSucceeded = false

    try
    (
        unwrapInterface.flattenMap 45.0 0.02 true 0 true true
        flattenSucceeded = true
        logLine logStream "    Flatten map applied through unwrap interface signature A."
    )
    catch
    (
        logLine logStream ("    Flatten signature A failed: " + getExceptionText())
    )

    if not flattenSucceeded then
    (
        try
        (
            unwrapInterface.flattenMap 45.0 0.02 true 0 true true true
            flattenSucceeded = true
            logLine logStream "    Flatten map applied through unwrap interface signature B."
        )
        catch
        (
            logLine logStream ("    Flatten signature B failed: " + getExceptionText())
        )
    )

    flattenSucceeded
)

fn prepareUnwrapModifier unwrapModifier node logStream =
(
    local unwrapInterface = getUnwrapInterface unwrapModifier

    try (unwrapInterface.setFreeFormMode on) catch ()
    try (unwrapModifier.texMapList.count = 0) catch ()
    try (unwrapModifier.texMapIDList.count = 0) catch ()
    try (unwrapModifier.baseMaterial_list.count = 1) catch ()
    try (unwrapModifier.baseMaterial_list[1] = node.material) catch ()
    try (unwrapModifier.texMapList.count = 0) catch ()
    try (unwrapModifier.texMapIDList.count = 0) catch ()
    try (unwrapModifier.texMapList.count = 1) catch ()
    try (unwrapModifier.texMapIDList.count = 1) catch ()
    try (unwrapModifier.texMapList[1] = Checker()) catch ()
    try (unwrapModifier.TextureCheckerMaterial = PhysicalMaterial()) catch ()

    logLine logStream "    Unwrap UVW material/checker setup applied."
)

fn applyProOptimizer node vertexPercent logStream =
(
    if not isValidNode node then return false

    select node
    max modify mode

    local optimizer = undefined
    local beforeVertexCount = getNodeVertexCount node
    logLine logStream ("    Before ProOptimizer: " + buildNodeStatsText node)

    try
    (
        modPanel.addModToSelection (ProOptimizer()) ui:on
        optimizer = node.modifiers[#ProOptimizer]
        modPanel.setCurrentObject optimizer

        optimizer.Calculate = on
        logLine logStream "    ProOptimizer calculation triggered."
        processUiEvents()

        optimizer.VertexPercent = vertexPercent
        logLine logStream ("    ProOptimizer VertexPercent set to " + (vertexPercent as string) + ".")
        processUiEvents()

        logLine logStream ("    After ProOptimizer stack eval: " + buildNodeStatsText node)

        if not collapseSelectionToMesh logStream "ProOptimizer" then return false

        local afterVertexCount = getNodeVertexCount node
        logLine logStream ("    After ProOptimizer collapse: " + buildNodeStatsText node)

        if beforeVertexCount > 0 and afterVertexCount >= beforeVertexCount then
        (
            logLine logStream "    WARNING: Vertex count did not go down after ProOptimizer."
        )

        true
    )
    catch
    (
        logLine logStream ("    ERROR: ProOptimizer failed: " + getExceptionText())
        false
    )
)

fn applyFlattenMapping node logStream =
(
    if not isValidNode node then return false

    select node
    max modify mode

    local unwrapModifier = undefined
    local unwrapInterface = undefined
    logLine logStream ("    Before Unwrap UVW: " + buildNodeStatsText node)

    try
    (
        modPanel.addModToSelection (Unwrap_UVW()) ui:on
        try (unwrapModifier = node.modifiers[#unwrap_uvw]) catch ()
        if unwrapModifier == undefined do try (unwrapModifier = node.modifiers[#Unwrap_UVW]) catch ()

        if unwrapModifier == undefined then
        (
            logLine logStream "    ERROR: Could not add Unwrap UVW modifier."
            return false
        )

        unwrapInterface = getUnwrapInterface unwrapModifier
        modPanel.setCurrentObject unwrapModifier
        prepareUnwrapModifier unwrapModifier node logStream

        subObjectLevel = 3

        local faceCount = getNodeFaceCount node
        logLine logStream ("    Preparing flatten mapping for " + (faceCount as string) + " faces.")

        if unwrapInterface != undefined do try (unwrapInterface.setMapChannel 1) catch ()
        if unwrapInterface != undefined and faceCount > 0 do try (unwrapInterface.selectFaces #{1..faceCount}) catch ()

        local flattenSucceeded = false

        try
        (
            actionMan.executeAction 2077580866 "40047"
            flattenSucceeded = true
            logLine logStream "    Flatten map action executed through Action Manager."
        )
        catch
        (
            logLine logStream ("    Action Manager flatten failed: " + getExceptionText())
        )

        if not flattenSucceeded and unwrapInterface != undefined then
        (
            flattenSucceeded = runFlattenMap unwrapInterface logStream
        )

        if unwrapInterface != undefined do try (unwrapInterface.setFreeFormMode on) catch ()

        subObjectLevel = 0

        if not flattenSucceeded then return false

        if not collapseSelectionToMesh logStream "Unwrap UVW" then return false

        logLine logStream ("    After Unwrap collapse: " + buildNodeStatsText node)
        true
    )
    catch
    (
        subObjectLevel = 0
        logLine logStream ("    ERROR: Unwrap UVW failed: " + getExceptionText())
        false
    )
)

fn processGeometryNode node vertexPercent logStream =
(
    if not isValidNode node then return false

    if superclassof node != GeometryClass then return true

    logLine logStream ("  Node: " + node.name)
    logLine logStream ("    Imported state: " + buildNodeStatsText node)

    if not collapseNodeToMesh node then
    (
        logLine logStream "    ERROR: Initial convertToMesh failed."
        return false
    )

    logLine logStream ("    After initial convertToMesh: " + buildNodeStatsText node)

    if not applyProOptimizer node vertexPercent logStream then return false
    if not applyFlattenMapping node logStream then return false

    logLine logStream ("    Final node state: " + buildNodeStatsText node)

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
        local vertexPercent = 2.0
        local logFilePath = outputFolder + "batch_optimize_fbx_lod_log_" + (timeStamp as string) + ".txt"
        local logStream = undefined

        try (logStream = createFile logFilePath) catch ()

        logLine logStream ("Batch optimize log: " + logFilePath)
        logLine logStream ("Input folder: " + inputFolder)
        logLine logStream ("Output folder: " + outputFolder)
        logLine logStream ("ProOptimizer target percent: " + (vertexPercent as string))
        logLine logStream ("Found " + (fbxFiles.count as string) + " FBX files.")

        for f in fbxFiles do
        (
            local fileNameOnly = getFilenameFile f
            local outFile = outputFolder + fileNameOnly + "_LLOD.fbx"

            logLine logStream ""
            logLine logStream ("Processing file: " + fileNameOnly)
            logLine logStream ("Source: " + f)
            logLine logStream ("Output: " + outFile)

            resetMaxFile #noPrompt

            try (importFile f #noPrompt using:FBXIMP) catch
            (
                logLine logStream ("ERROR: Import failed for " + fileNameOnly + ": " + getExceptionText())
                continue
            )

            local geometryNodes = collectGeometryNodes()

            if geometryNodes.count == 0 then
            (
                logLine logStream ("WARNING: No geometry found in " + fileNameOnly + ".")
                continue
            )

            logLine logStream ("Geometry node count: " + (geometryNodes.count as string))

            local fileSucceeded = true

            for node in geometryNodes while fileSucceeded do
            (
                if not processGeometryNode node vertexPercent logStream then
                (
                    logLine logStream ("ERROR: Failed processing node " + node.name + " in " + fileNameOnly + ".")
                    fileSucceeded = false
                )
            )

            if not fileSucceeded then
            (
                logLine logStream ("Skipping export because processing failed for " + fileNameOnly + ".")
                continue
            )

            try
            (
                exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
                logLine logStream ("Exported optimized FBX: " + outFile)
            )
            catch
            (
                logLine logStream ("ERROR: Export failed for " + fileNameOnly + ": " + getExceptionText())
            )
        )

        if logStream != undefined do close logStream

        messageBox ("FBX batch optimization complete.\nLog file: " + logFilePath) title:"Process Complete"
    )
)