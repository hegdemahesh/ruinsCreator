inputFolder = @"D:\shared\3dModels\AImodels03\"
mapsFolder = @"D:\shared\3dModels\PainterExports\"
outputFolder = @"D:\shared\3dModels\AImodels07\"

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

fn sanitizeTextureToken rawValue =
(
    if rawValue == undefined then return ""

    local cleanedValue = trimRight (trimLeft (rawValue as string))
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

fn getMaterialToken geometryNodes logStream =
(
    for node in geometryNodes where isValidNode node do
    (
        if node.material != undefined then
        (
            local token = sanitizeTextureToken node.material.name
            if token != "" then
            (
                logLine logStream ("    Using material token: " + token)
                return token
            )
        )
    )

    logLine logStream "    INFO: No source material name found on mesh."
    undefined
)

fn findTextureFile textureFolder assetName materialToken textureSuffix =
(
    local matches = #()

    if materialToken != undefined and materialToken != "" then
    (
        matches = getFiles (textureFolder + assetName + "_" + materialToken + "_" + textureSuffix + ".*")
    )

    if matches.count == 0 then
    (
        matches = getFiles (textureFolder + assetName + "_" + textureSuffix + ".*")
    )

    if matches.count > 0 then matches[1] else undefined
)

fn createBitmapMap texturePath =
(
    local textureMap = Bitmaptexture filename:texturePath
    textureMap.name = getFilenameFile texturePath
    textureMap
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
    for node in geometryNodes where isValidNode node do
    (
        node.material = materialToAssign
    )
)

fn applyPbrMaps targetMaterial textureFolder assetName materialToken logStream =
(
    local baseColorPath = findTextureFile textureFolder assetName materialToken "BaseColor"
    local normalPath = findTextureFile textureFolder assetName materialToken "Normal"
    local roughnessPath = findTextureFile textureFolder assetName materialToken "Roughness"
    local metallicPath = findTextureFile textureFolder assetName materialToken "Metallic"
    local heightPath = findTextureFile textureFolder assetName materialToken "Height"
    local aoPath = findTextureFile textureFolder assetName materialToken "AO"

    if baseColorPath == undefined then
    (
        logLine logStream ("    WARNING: Missing BaseColor map for " + assetName + ".")
        return false
    )

    local baseColorMap = createBitmapMap baseColorPath
    local normalMap = if normalPath != undefined then createBitmapMap normalPath else undefined
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
        logLine logStream ("    INFO: AO map found but not assigned yet: " + aoPath)
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

selectedInputFolder = getSavePath caption:"Select FBX Input Folder" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No FBX input folder selected." title:"Batch Cancelled"
)
else
(
    local selectedMapsFolder = getSavePath caption:"Select PBR Maps Folder" initialDir:mapsFolder

    if selectedMapsFolder == undefined then
    (
        messageBox "No maps folder selected." title:"Batch Cancelled"
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
            mapsFolder = ensureTrailingSlash selectedMapsFolder
            outputFolder = ensureTrailingSlash selectedOutputFolder

            if not doesDirectoryExist outputFolder do makeDir outputFolder

            local logFilePath = outputFolder + "batch_embed_fbx_pbr_maps_log.txt"
            local logStream = createFile logFilePath
            local exportedCount = 0
            local skippedCount = 0
            local errorCount = 0
            local fbxFiles = getFiles (inputFolder + "*.fbx")

            logLine logStream ("Found " + (fbxFiles.count as string) + " FBX files.")
            logLine logStream ("Using maps folder: " + mapsFolder)
            logLine logStream ("Writing output folder: " + outputFolder)

            for f in fbxFiles do
            (
                local fileNameOnly = getFilenameFile f
                local outFile = outputFolder + fileNameOnly + ".fbx"

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

                local materialToken = getMaterialToken geometryNodes logStream
                local targetMaterial = getOrCreatePhysicalMaterial geometryNodes fileNameOnly logStream

                if not applyPbrMaps targetMaterial mapsFolder fileNameOnly materialToken logStream then
                (
                    skippedCount += 1
                    logLine logStream "    Skipping export because BaseColor is missing."
                    continue
                )

                assignMaterialToGeometry geometryNodes targetMaterial
                configureFbxExporter logStream

                try
                (
                    exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
                    exportedCount += 1
                    logLine logStream ("    Exported: " + outFile)
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

            messageBox ("FBX PBR batch complete.\n\nExported: " + (exportedCount as string) + "\nSkipped: " + (skippedCount as string) + "\nErrors: " + (errorCount as string) + "\n\nLog: " + logFilePath) title:"Process Complete"
        )
    )
)