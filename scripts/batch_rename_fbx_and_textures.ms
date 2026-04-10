inputFolder = @"D:\shared\3dModels\objects\"
mapsFolder = @"D:\shared\3dModels\PainterExports\"
outputFolder = @"D:\shared\3dModels\RenamedAssets\"

global batchRenameFbxState = undefined
global batchRenameFbxRollout = undefined

struct BatchRenameFbxSessionState
(
    fileNameOnly,
    requestedAction = #skip,
    requestedName = ""
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

fn logLine logStream text =
(
    format "%\n" text
    if logStream != undefined do format "%\n" text to:logStream
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

fn sanitizeAssetName rawValue =
(
    if rawValue == undefined then return ""

    local cleanedValue = trimRight (trimLeft (rawValue as string))
    cleanedValue = substituteString cleanedValue "/" "_"
    cleanedValue = substituteString cleanedValue "\\" "_"
    cleanedValue = substituteString cleanedValue ":" "_"
    cleanedValue = substituteString cleanedValue "*" ""
    cleanedValue = substituteString cleanedValue "?" ""
    cleanedValue = substituteString cleanedValue "\"" ""
    cleanedValue = substituteString cleanedValue "<" ""
    cleanedValue = substituteString cleanedValue ">" ""
    cleanedValue = substituteString cleanedValue "|" ""
    cleanedValue
)

fn startsWithText sourceText prefixText =
(
    if sourceText == undefined or prefixText == undefined then false
    else if prefixText.count > sourceText.count then false
    else (substring sourceText 1 prefixText.count) == prefixText
)

fn findTextureFile textureFolder assetName textureSuffix =
(
    local matches = #()

    matches = getFiles (textureFolder + assetName + "_" + textureSuffix + ".*")

    if matches.count == 0 then
    (
        matches = getFiles (textureFolder + assetName + "*_" + textureSuffix + ".*")
    )

    if matches.count > 0 then matches[1] else undefined
)

fn createBitmapMap texturePath =
(
    local textureMap = Bitmaptexture filename:texturePath
    textureMap.name = getFilenameFile texturePath
    textureMap
)

fn createNormalBumpMap texturePath logStream =
(
    local normalBitmap = createBitmapMap texturePath
    local normalWrapper = undefined

    try
    (
        normalWrapper = Normal_Bump()
        normalWrapper.name = getFilenameFile texturePath
        try (normalWrapper.normal_map = normalBitmap) catch ()
        try (normalWrapper.method = 1) catch ()
        normalWrapper
    )
    catch
    (
        logLine logStream ("    WARNING: Could not create Normal_Bump wrapper, falling back to bitmap normal: " + getExceptionText())
        normalBitmap
    )
)

fn assignMapPropertyCandidates targetMaterial propertyNames enabledPropertyNames textureMap logStream label =
(
    if textureMap == undefined then return false

    local assigned = false

    for propertyName in propertyNames while not assigned do
    (
        try
        (
            setProperty targetMaterial propertyName textureMap
            assigned = true
        )
        catch ()
    )

    if not assigned then
    (
        logLine logStream ("    WARNING: Could not assign " + label + ": " + getExceptionText())
    )

    if assigned and enabledPropertyNames != undefined do
    (
        for enabledPropertyName in enabledPropertyNames do
        (
            try (setProperty targetMaterial enabledPropertyName true) catch ()
        )
    )

    assigned
)

fn getOrCreatePhysicalMaterial geometryNodes fileNameOnly logStream =
(
    for node in geometryNodes where isValidNode node do
    (
        if node.material != undefined and isKindOf node.material PhysicalMaterial then
        (
            logLine logStream ("    Reusing Physical Material from " + node.name + ".")
            return node.material
        )
    )

    local createdMaterial = PhysicalMaterial()
    createdMaterial.name = fileNameOnly + "_Mat"
    createdMaterial.base_color = color 255 255 255
    createdMaterial.roughness = 1.0
    logLine logStream "    Created new Physical Material."
    createdMaterial
)

fn assignMaterialToGeometry geometryNodes materialToAssign =
(
    for node in geometryNodes where isValidNode node do node.material = materialToAssign
)

fn applyPbrMaps targetMaterial textureFolder assetName logStream =
(
    local baseColorPath = findTextureFile textureFolder assetName "BaseColor"
    local normalPath = findTextureFile textureFolder assetName "Normal"
    local roughnessPath = findTextureFile textureFolder assetName "Roughness"
    local metallicPath = findTextureFile textureFolder assetName "Metallic"
    local heightPath = findTextureFile textureFolder assetName "Height"
    local aoPath = findTextureFile textureFolder assetName "AO"

    if baseColorPath == undefined then
    (
        logLine logStream ("    WARNING: Missing BaseColor map for " + assetName + ".")
        return false
    )

    local baseColorMap = createBitmapMap baseColorPath
    local normalMap = if normalPath != undefined then createNormalBumpMap normalPath logStream else undefined
    local roughnessMap = if roughnessPath != undefined then createBitmapMap roughnessPath else undefined
    local metallicMap = if metallicPath != undefined then createBitmapMap metallicPath else undefined
    local heightMap = if heightPath != undefined then createBitmapMap heightPath else undefined

    assignMapPropertyCandidates targetMaterial #(#base_color_map) #(#base_color_map_on) baseColorMap logStream "BaseColor"

    if normalMap != undefined then
    (
        assignMapPropertyCandidates targetMaterial #(#bump_map) #(#bump_map_on) normalMap logStream "Normal"
    )
    else
    (
        logLine logStream ("    WARNING: Missing Normal map for " + assetName + ".")
    )

    if roughnessMap != undefined then
    (
        assignMapPropertyCandidates targetMaterial #(#roughness_map) #(#roughness_map_on) roughnessMap logStream "Roughness"
    )
    else
    (
        logLine logStream ("    WARNING: Missing Roughness map for " + assetName + ".")
    )

    if metallicMap != undefined then
    (
        assignMapPropertyCandidates targetMaterial #(#metalness_map, #metallic_map) #(#metalness_map_on, #metallic_map_on) metallicMap logStream "Metallic"
    )
    else
    (
        logLine logStream ("    WARNING: Missing Metallic map for " + assetName + ".")
    )

    if heightMap != undefined then
    (
        assignMapPropertyCandidates targetMaterial #(#displacement_map, #displacement_texmap) #(#displacement_map_on, #displacement_texmap_on) heightMap logStream "Height"
    )
    else
    (
        logLine logStream ("    WARNING: Missing Height map for " + assetName + ".")
    )

    if aoPath != undefined then
    (
        logLine logStream ("    INFO: AO map copied for reference only: " + aoPath)
    )

    true
)

fn configureFbxExporter logStream =
(
    try (FBXExporterSetParam "ResetExport") catch ()
    try (FBXExporterSetParam "Animation" false) catch ()
    try (FBXExporterSetParam "Cameras" false) catch ()
    try (FBXExporterSetParam "Lights" false) catch ()
    try (FBXExporterSetParam "ASCII" false) catch ()

    try
    (
        FBXExporterSetParam "EmbedTextures" true
        logLine logStream "    FBX export configured with embedded textures."
    )
    catch
    (
        logLine logStream ("    WARNING: Could not enable FBX EmbedTextures: " + getExceptionText())
    )
)

fn gatherMatchingTextures textureFolder sourceAssetName =
(
    local matchedFiles = #()
    local candidates = getFiles (textureFolder + sourceAssetName + "*.*")

    for filePath in candidates do
    (
        local fileNameOnly = getFilenameFile filePath
        if startsWithText fileNameOnly sourceAssetName do append matchedFiles filePath
    )

    matchedFiles
)

fn copyRenamedTextures sourceTexturePaths sourceAssetName newAssetName destinationTexturesFolder logStream =
(
    local copiedFiles = #()

    for sourceTexturePath in sourceTexturePaths do
    (
        local sourceFileName = getFilenameFile sourceTexturePath
        local sourceExtension = getFilenameType sourceTexturePath
        local suffixText = if sourceFileName.count > sourceAssetName.count then substring sourceFileName (sourceAssetName.count + 1) (sourceFileName.count - sourceAssetName.count) else ""
        local renamedFilePath = destinationTexturesFolder + newAssetName + suffixText + sourceExtension

        if doesFileExist renamedFilePath do deleteFile renamedFilePath

        if copyFile sourceTexturePath renamedFilePath then
        (
            append copiedFiles renamedFilePath
            logLine logStream ("    Copied texture: " + renamedFilePath)
        )
        else
        (
            logLine logStream ("    WARNING: Could not copy texture: " + sourceTexturePath)
        )
    )

    copiedFiles
)

fn renameGeometryNodes geometryNodes newAssetName =
(
    local nodeIndex = 1
    for node in geometryNodes where isValidNode node do
    (
        local nodeSuffix = if geometryNodes.count > 1 then ("_mesh" + (formattedPrint nodeIndex format:"02d")) else ""
        try (node.name = newAssetName + nodeSuffix) catch ()
        nodeIndex += 1
    )
)

rollout batchRenameFbxRollout "Rename FBX" width:420 height:185
(
    label infoLabel "Inspect the FBX on screen, then enter the new asset name." pos:[12,12] width:390 height:34
    label sourceLabel "" pos:[12,50] width:390 height:18
    label nameLabel "New file name:" pos:[12,82] width:95 height:18
    editText nameEdit "" pos:[110,78] width:292 height:24
    button saveButton "Save Renamed" pos:[110,120] width:92 height:28
    button skipButton "Skip" pos:[210,120] width:92 height:28
    button cancelButton "Cancel Batch" pos:[310,120] width:92 height:28

    on batchRenameFbxRollout open do
    (
        if batchRenameFbxState != undefined then
        (
            sourceLabel.text = "Source: " + batchRenameFbxState.fileNameOnly
            nameEdit.text = batchRenameFbxState.fileNameOnly
            previewGeometryNodes (collectGeometryNodes())
        )
    )

    on saveButton pressed do
    (
        local cleanedName = sanitizeAssetName nameEdit.text
        if cleanedName == "" then
        (
            messageBox "Enter a valid file name." title:"Missing Name"
        )
        else
        (
            batchRenameFbxState.requestedName = cleanedName
            batchRenameFbxState.requestedAction = #save
            destroyDialog batchRenameFbxRollout
        )
    )

    on skipButton pressed do
    (
        batchRenameFbxState.requestedAction = #skip
        destroyDialog batchRenameFbxRollout
    )

    on cancelButton pressed do
    (
        batchRenameFbxState.requestedAction = #cancel
        destroyDialog batchRenameFbxRollout
    )

    on batchRenameFbxRollout close do
    (
        if batchRenameFbxState != undefined and batchRenameFbxState.requestedAction == undefined do batchRenameFbxState.requestedAction = #cancel
    )
)

fn promptForNewName fileNameOnly geometryNodes =
(
    batchRenameFbxState = BatchRenameFbxSessionState fileNameOnly:fileNameOnly requestedAction:undefined requestedName:fileNameOnly
    previewGeometryNodes geometryNodes
    createDialog batchRenameFbxRollout modal:true style:#(#style_titlebar, #style_sysmenu)

    local resultAction = batchRenameFbxState.requestedAction
    local resultName = batchRenameFbxState.requestedName
    batchRenameFbxState = undefined

    if resultAction == undefined then resultAction = #cancel
    #(resultAction, resultName)
)

selectedInputFolder = getSavePath caption:"Select FBX Input Folder" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No FBX input folder selected." title:"Batch Cancelled"
)
else
(
    local selectedMapsFolder = getSavePath caption:"Select Source Texture Folder" initialDir:mapsFolder

    if selectedMapsFolder == undefined then
    (
        messageBox "No source texture folder selected." title:"Batch Cancelled"
    )
    else
    (
        local selectedOutputFolder = getSavePath caption:"Select Output Folder" initialDir:outputFolder

        if selectedOutputFolder == undefined then
        (
            messageBox "No output folder selected." title:"Batch Cancelled"
        )
        else
        (
            inputFolder = ensureTrailingSlash selectedInputFolder
            mapsFolder = ensureTrailingSlash selectedMapsFolder
            outputFolder = ensureTrailingSlash selectedOutputFolder

            if not doesDirectoryExist outputFolder do makeDir outputFolder
            local texturesOutputFolder = ensureTrailingSlash (outputFolder + "Textures")
            if not doesDirectoryExist texturesOutputFolder do makeDir texturesOutputFolder

            local logFilePath = outputFolder + "batch_rename_fbx_and_textures_log.txt"
            local logStream = createFile logFilePath
            local fbxFiles = getFiles (inputFolder + "*.fbx")
            local renamedCount = 0
            local skippedCount = 0
            local errorCount = 0
            local cancelBatch = false

            logLine logStream ("Found " + (fbxFiles.count as string) + " FBX files.")
            logLine logStream ("Using source texture folder: " + mapsFolder)
            logLine logStream ("Writing output folder: " + outputFolder)
            logLine logStream ("Writing texture folder: " + texturesOutputFolder)

            for f in fbxFiles while not cancelBatch do
            (
                local sourceAssetName = getFilenameFile f
                local sourceTexturePaths = #()
                local renamedTexturePaths = #()
                local promptResult = undefined
                local newAssetName = ""
                local outFile = ""

                logLine logStream ""
                logLine logStream ("Processing: " + sourceAssetName)

                resetMaxFile #noPrompt

                try (importFile f #noPrompt using:FBXIMP) catch
                (
                    errorCount += 1
                    logLine logStream ("    ERROR: Import failed: " + getExceptionText())
                    continue
                )

                local geometryNodes = collectGeometryNodes()
                if geometryNodes.count == 0 then
                (
                    skippedCount += 1
                    logLine logStream "    WARNING: No geometry found."
                    continue
                )

                promptResult = promptForNewName sourceAssetName geometryNodes

                if promptResult[1] == #cancel then
                (
                    cancelBatch = true
                    logLine logStream "    Batch cancelled by user."
                    continue
                )

                if promptResult[1] == #skip then
                (
                    skippedCount += 1
                    logLine logStream "    Skipped by user."
                    continue
                )

                newAssetName = promptResult[2]
                outFile = outputFolder + newAssetName + ".fbx"

                sourceTexturePaths = gatherMatchingTextures mapsFolder sourceAssetName
                renamedTexturePaths = copyRenamedTextures sourceTexturePaths sourceAssetName newAssetName texturesOutputFolder logStream

                local targetMaterial = getOrCreatePhysicalMaterial geometryNodes newAssetName logStream
                targetMaterial.name = newAssetName + "_Mat"

                if renamedTexturePaths.count > 0 then
                (
                    if not applyPbrMaps targetMaterial texturesOutputFolder newAssetName logStream then
                    (
                        logLine logStream "    WARNING: PBR maps could not be fully rebuilt after rename."
                    )
                )
                else
                (
                    logLine logStream "    WARNING: No matching source textures were found to copy."
                )

                assignMaterialToGeometry geometryNodes targetMaterial
                renameGeometryNodes geometryNodes newAssetName
                configureFbxExporter logStream

                try
                (
                    exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
                    renamedCount += 1
                    logLine logStream ("    Exported renamed FBX: " + outFile)
                )
                catch
                (
                    errorCount += 1
                    logLine logStream ("    ERROR: Export failed: " + getExceptionText())
                )
            )

            logLine logStream ""
            logLine logStream ("Summary: renamed=" + (renamedCount as string) + ", skipped=" + (skippedCount as string) + ", errors=" + (errorCount as string))
            close logStream

            messageBox ("FBX rename batch complete.\n\nRenamed: " + (renamedCount as string) + "\nSkipped: " + (skippedCount as string) + "\nErrors: " + (errorCount as string) + "\n\nLog: " + logFilePath) title:"Process Complete"
        )
    )
)