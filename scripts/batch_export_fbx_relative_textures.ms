inputFolder = @"D:\shared\3dModels\objects\"
outputFolder = @"D:\shared\3dModels\objects_relative\"

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

fn sanitizeFileToken rawValue =
(
    if rawValue == undefined then return ""

    local cleanedValue = rawValue as string
    cleanedValue = substituteString cleanedValue " " "_"
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

fn appendUniqueMap mapArray mapNode =
(
    if mapNode == undefined then return mapArray
    if (findItem mapArray mapNode) == 0 do append mapArray mapNode
    mapArray
)

fn resolveTexturePath texturePath =
(
    local resolvedPath = texturePath
    try (resolvedPath = pathConfig.convertPathToAbsolute texturePath) catch ()
    resolvedPath
)

fn normalizePathForComparison filePath =
(
    if filePath == undefined then return ""

    local normalizedPath = filePath as string
    try (normalizedPath = pathConfig.convertPathToAbsolute normalizedPath) catch ()
    pathConfig.convertPathToLowerCase normalizedPath
)

fn areSameFilePath leftPath rightPath =
(
    local normalizedLeft = normalizePathForComparison leftPath
    local normalizedRight = normalizePathForComparison rightPath
    normalizedLeft != "" and normalizedLeft == normalizedRight
)

fn collectBitmapTextureMapsFromMap mapNode mapArray =
(
    if mapNode == undefined then return mapArray

    if isKindOf mapNode Bitmaptexture then
    (
        appendUniqueMap mapArray mapNode
    )

    local subMapCount = 0
    try (subMapCount = getNumSubTexmaps mapNode) catch ()

    for subMapIndex = 1 to subMapCount do
    (
        local subMap = undefined
        try (subMap = getSubTexmap mapNode subMapIndex) catch ()
        if subMap != undefined do collectBitmapTextureMapsFromMap subMap mapArray
    )

    mapArray
)

fn collectBitmapTextureMapsFromMaterial materialNode mapArray =
(
    if materialNode == undefined then return mapArray

    local subMapCount = 0
    try (subMapCount = getNumSubTexmaps materialNode) catch ()

    for subMapIndex = 1 to subMapCount do
    (
        local subMap = undefined
        try (subMap = getSubTexmap materialNode subMapIndex) catch ()
        if subMap != undefined do collectBitmapTextureMapsFromMap subMap mapArray
    )

    local subMaterialCount = 0
    try (subMaterialCount = getNumSubMtls materialNode) catch ()

    for subMaterialIndex = 1 to subMaterialCount do
    (
        local subMaterial = undefined
        try (subMaterial = getSubMtl materialNode subMaterialIndex) catch ()
        if subMaterial != undefined do collectBitmapTextureMapsFromMaterial subMaterial mapArray
    )

    mapArray
)

fn collectSceneBitmapTextureMaps geometryNodes =
(
    local bitmapMaps = #()

    for node in geometryNodes where isValidNode node do
    (
        if node.material != undefined do collectBitmapTextureMapsFromMaterial node.material bitmapMaps
    )

    bitmapMaps
)

fn getCopiedTexturePath sourcePath sourcePaths copiedPaths =
(
    local sourceIndex = findItem sourcePaths sourcePath
    if sourceIndex > 0 then copiedPaths[sourceIndex] else undefined
)

fn registerTextureSearchPath texturesFolder =
(
    try (mapPaths.add texturesFolder) catch ()
)

fn copyAndRelinkBitmapTexture bitmapMap assetName texturesFolder sourcePaths copiedPaths logStream =
(
    if bitmapMap == undefined then return false

    local sourcePath = resolveTexturePath bitmapMap.filename
    if sourcePath == undefined or sourcePath == "" then
    (
        logLine logStream "    WARNING: Encountered a bitmap texture with no filename."
        return false
    )

    if not doesFileExist sourcePath then
    (
        logLine logStream ("    WARNING: Texture file not found: " + sourcePath)
        return false
    )

    local copiedPath = getCopiedTexturePath sourcePath sourcePaths copiedPaths

    if copiedPath == undefined then
    (
        local destinationName = sanitizeFileToken assetName + "__" + sanitizeFileToken (getFilenameFile sourcePath) + getFilenameType sourcePath
        copiedPath = texturesFolder + destinationName

        if areSameFilePath sourcePath copiedPath then
        (
            logLine logStream ("    Skipped texture copy because source and destination are the same file: " + copiedPath)
        )
        else
        (
            if doesFileExist copiedPath do deleteFile copiedPath

            if copyFile sourcePath copiedPath then
            (
                append sourcePaths sourcePath
                append copiedPaths copiedPath
                logLine logStream ("    Copied texture: " + copiedPath)
            )
            else
            (
                logLine logStream ("    WARNING: Failed to copy texture: " + sourcePath)
                return false
            )
        )
    )

    try
    (
        local relativeTexturePath = @"Textures\" + getFilenameFile copiedPath + getFilenameType copiedPath
        bitmapMap.filename = relativeTexturePath
        bitmapMap.name = getFilenameFile copiedPath
        true
    )
    catch
    (
        logLine logStream ("    WARNING: Failed to relink bitmap map: " + getExceptionText())
        false
    )
)

fn externalizeSceneTextures geometryNodes assetName texturesFolder logStream =
(
    local bitmapMaps = collectSceneBitmapTextureMaps geometryNodes
    local sourcePaths = #()
    local copiedPaths = #()
    local relinkedCount = 0

    for bitmapMap in bitmapMaps do
    (
        if copyAndRelinkBitmapTexture bitmapMap assetName texturesFolder sourcePaths copiedPaths logStream do relinkedCount += 1
    )

    #(relinkedCount, copiedPaths.count)
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
        FBXExporterSetParam "EmbedTextures" false
        logLine logStream "    FBX export configured for external texture references."
    )
    catch
    (
        logLine logStream ("    WARNING: Could not disable FBX EmbedTextures: " + getExceptionText())
    )
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
        local texturesFolder = ensureTrailingSlash (outputFolder + "Textures")
        if not doesDirectoryExist texturesFolder do makeDir texturesFolder
        registerTextureSearchPath texturesFolder

        local logFilePath = outputFolder + "batch_export_fbx_relative_textures_log.txt"
        local logStream = createFile logFilePath
        local fbxFiles = getFiles (inputFolder + "*.fbx")
        local exportedCount = 0
        local skippedCount = 0
        local errorCount = 0

        logLine logStream ("Found " + (fbxFiles.count as string) + " FBX files.")
        logLine logStream ("Writing output folder: " + outputFolder)
        logLine logStream ("Writing textures folder: " + texturesFolder)

        for f in fbxFiles do
        (
            local fileNameOnly = getFilenameFile f
            local outputFile = outputFolder + fileNameOnly + ".fbx"

            logLine logStream ""
            logLine logStream ("Processing: " + fileNameOnly)

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

            local textureStats = externalizeSceneTextures geometryNodes fileNameOnly texturesFolder logStream
            logLine logStream ("    Relinked bitmap maps: " + (textureStats[1] as string) + ", copied texture files: " + (textureStats[2] as string))

            configureFbxExporter logStream

            try
            (
                exportFile outputFile #noPrompt selectedOnly:false using:FBXEXP
                exportedCount += 1
                logLine logStream ("    Exported FBX: " + outputFile)
            )
            catch
            (
                errorCount += 1
                logLine logStream ("    ERROR: Export failed: " + getExceptionText())
            )
        )

        logLine logStream ""
        logLine logStream ("Summary: exported=" + (exportedCount as string) + ", skipped=" + (skippedCount as string) + ", errors=" + (errorCount as string))
        close logStream

        messageBox ("FBX external texture export complete.\n\nExported: " + (exportedCount as string) + "\nSkipped: " + (skippedCount as string) + "\nErrors: " + (errorCount as string) + "\n\nTextures folder: " + texturesFolder + "\nLog: " + logFilePath) title:"Process Complete"
    )
)