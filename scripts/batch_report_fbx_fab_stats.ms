inputFolder = @"D:\shared\3dModels\objects\"

global batchReportFbxFabStatsText = ""

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

fn appendUniqueString stringArray value =
(
    if value == undefined or value == "" then return stringArray
    if (findItem stringArray value) == 0 do append stringArray value
    stringArray
)

fn appendUniqueInteger integerArray value =
(
    if value == undefined then return integerArray
    if (findItem integerArray value) == 0 do append integerArray value
    integerArray
)

fn getNodeVertexCount node =
(
    local vertexCount = 0

    try (vertexCount = node.mesh.numverts) catch ()
    if vertexCount == 0 do try (vertexCount = getNumVerts node) catch ()
    if vertexCount == 0 do try (vertexCount = polyOp.getNumVerts node) catch ()

    vertexCount
)

fn getNodePolygonCount node =
(
    local polygonCount = 0

    try (polygonCount = polyOp.getNumFaces node) catch ()
    if polygonCount == 0 do try (polygonCount = getNumFaces node) catch ()
    if polygonCount == 0 do try (polygonCount = node.mesh.numfaces) catch ()

    polygonCount
)

fn getNodeTriangleCount node =
(
    local triangleCount = 0
    local snapshotMesh = undefined

    try
    (
        snapshotMesh = snapshotAsMesh node
        if snapshotMesh != undefined do triangleCount = snapshotMesh.numfaces
    )
    catch ()

    try (if snapshotMesh != undefined do free snapshotMesh) catch ()
    if triangleCount == 0 do triangleCount = getNodePolygonCount node

    triangleCount
)

fn getNodeBoundsSizeText node =
(
    local bounds = undefined
    try (bounds = nodeGetBoundingBox node (matrix3 1)) catch ()

    if bounds == undefined then "0.0x0.0x0.0"
    else
    (
        local sizeX = abs (bounds[2].x - bounds[1].x)
        local sizeY = abs (bounds[2].y - bounds[1].y)
        local sizeZ = abs (bounds[2].z - bounds[1].z)
        (formattedPrint sizeX format:".3f") + "x" + (formattedPrint sizeY format:".3f") + "x" + (formattedPrint sizeZ format:".3f")
    )
)

fn buildMeshSignature node =
(
    (getNodeVertexCount node as string) + "|" + (getNodePolygonCount node as string) + "|" + (getNodeTriangleCount node as string) + "|" + (getNodeBoundsSizeText node)
)

fn collectBitmapTexturePathsFromMap mapNode pathArray =
(
    if mapNode == undefined then return pathArray

    if isKindOf mapNode Bitmaptexture then
    (
        local filePath = ""
        try (filePath = pathConfig.convertPathToAbsolute mapNode.filename) catch (filePath = mapNode.filename)
        appendUniqueString pathArray filePath
    )

    local subMapCount = 0
    try (subMapCount = getNumSubTexmaps mapNode) catch ()

    for subMapIndex = 1 to subMapCount do
    (
        local subMap = undefined
        try (subMap = getSubTexmap mapNode subMapIndex) catch ()
        if subMap != undefined do collectBitmapTexturePathsFromMap subMap pathArray
    )

    pathArray
)

fn collectBitmapTexturePathsFromMaterial materialNode pathArray =
(
    if materialNode == undefined then return pathArray

    local subMapCount = 0
    try (subMapCount = getNumSubTexmaps materialNode) catch ()

    for subMapIndex = 1 to subMapCount do
    (
        local subMap = undefined
        try (subMap = getSubTexmap materialNode subMapIndex) catch ()
        if subMap != undefined do collectBitmapTexturePathsFromMap subMap pathArray
    )

    local subMaterialCount = 0
    try (subMaterialCount = getNumSubMtls materialNode) catch ()

    for subMaterialIndex = 1 to subMaterialCount do
    (
        local subMaterial = undefined
        try (subMaterial = getSubMtl materialNode subMaterialIndex) catch ()
        if subMaterial != undefined do collectBitmapTexturePathsFromMaterial subMaterial pathArray
    )

    pathArray
)

fn getBitmapResolution texturePath =
(
    local bitmapResolution = 0
    local bitmapHandle = undefined

    if texturePath == undefined or texturePath == "" then return 0
    if not doesFileExist texturePath then return 0

    try
    (
        bitmapHandle = openBitmap texturePath
        if bitmapHandle != undefined do bitmapResolution = amax bitmapHandle.width bitmapHandle.height
    )
    catch ()

    try (if bitmapHandle != undefined do close bitmapHandle) catch ()
    bitmapResolution
)

fn joinStringArray stringArray separatorText =
(
    local resultText = ""

    for itemIndex = 1 to stringArray.count do
    (
        if itemIndex > 1 do resultText += separatorText
        resultText += stringArray[itemIndex]
    )

    resultText
)

fn showReportWindow reportText =
(
    dotNet.loadAssembly "System.Windows.Forms"
    dotNet.loadAssembly "System.Drawing"

    local form = dotNetObject "System.Windows.Forms.Form"
    local textBox = dotNetObject "System.Windows.Forms.TextBox"
    local copyButton = dotNetObject "System.Windows.Forms.Button"
    local closeButton = dotNetObject "System.Windows.Forms.Button"
    local messageBoxClass = dotNetClass "System.Windows.Forms.MessageBox"

    form.Text = "FBX Fab Stats Report"
    form.Width = 980
    form.Height = 760
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen

    textBox.Multiline = true
    textBox.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Both
    textBox.WordWrap = false
    textBox.ReadOnly = true
    textBox.Left = 12
    textBox.Top = 12
    textBox.Width = 940
    textBox.Height = 660
    textBox.Font = dotNetObject "System.Drawing.Font" "Consolas" 10
    textBox.Text = reportText

    copyButton.Text = "Copy Report"
    copyButton.Left = 700
    copyButton.Top = 685
    copyButton.Width = 120

    closeButton.Text = "Close"
    closeButton.Left = 832
    closeButton.Top = 685
    closeButton.Width = 120

    dotNet.addEventHandler copyButton "Click" (fn copyReport sender args =
    (
        local clipboardClass = dotNetClass "System.Windows.Forms.Clipboard"
        clipboardClass.SetText textBox.Text
        messageBoxClass.Show "Report copied to clipboard." "FBX Fab Stats"
    ))

    dotNet.addEventHandler closeButton "Click" (fn closeReport sender args =
    (
        form.Close()
    ))

    form.Controls.Add textBox
    form.Controls.Add copyButton
    form.Controls.Add closeButton
    form.ShowDialog()
)

selectedInputFolder = getSavePath caption:"Select FBX Folder" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No input folder selected." title:"Batch Cancelled"
)
else
(
    inputFolder = ensureTrailingSlash selectedInputFolder

    local fbxFiles = getFiles (inputFolder + "*.fbx")
    local totalFileCount = fbxFiles.count
    local filesWithGeometry = 0
    local totalGeometryNodes = 0
    local totalVertices = 0
    local totalTriangles = 0
    local totalPolygons = 0
    local minVerticesPerFile = undefined
    local maxVerticesPerFile = 0
    local minTrianglesPerFile = undefined
    local maxTrianglesPerFile = 0
    local minPolygonsPerFile = undefined
    local maxPolygonsPerFile = 0
    local minVerticesPerMesh = undefined
    local maxVerticesPerMesh = 0
    local minTrianglesPerMesh = undefined
    local maxTrianglesPerMesh = 0
    local minPolygonsPerMesh = undefined
    local maxPolygonsPerMesh = 0
    local uniqueTexturePaths = #()
    local uniqueTextureResolutions = #()
    local totalTextureReferences = 0
    local maxTextureResolution = 0
    local uniqueMeshSignatures = #()
    local perFileLines = #()
    local failedFiles = #()

    if totalFileCount == 0 then
    (
        messageBox "No FBX files were found in the selected folder." title:"No Files"
    )
    else
    (
        format "Found % FBX files.\n" totalFileCount

        for f in fbxFiles do
        (
            local fileNameOnly = getFilenameFile f
            local fileVertices = 0
            local fileTriangles = 0
            local filePolygons = 0
            local fileTexturePaths = #()
            local fileMaxTextureResolution = 0

            format "\nProcessing: %\n" fileNameOnly
            resetMaxFile #noPrompt

            try (importFile f #noPrompt using:FBXIMP) catch
            (
                append failedFiles (fileNameOnly + " (import failed: " + getExceptionText() + ")")
                continue
            )

            local geometryNodes = collectGeometryNodes()
            if geometryNodes.count == 0 then
            (
                append perFileLines (fileNameOnly + " | meshes=0 | verts=0 | tris=0 | polys=0 | textures=0 | maxTex=0")
                continue
            )

            filesWithGeometry += 1
            totalGeometryNodes += geometryNodes.count
            previewGeometryNodes geometryNodes

            for node in geometryNodes do
            (
                local nodeVertices = getNodeVertexCount node
                local nodeTriangles = getNodeTriangleCount node
                local nodePolygons = getNodePolygonCount node

                fileVertices += nodeVertices
                fileTriangles += nodeTriangles
                filePolygons += nodePolygons

                totalVertices += nodeVertices
                totalTriangles += nodeTriangles
                totalPolygons += nodePolygons

                if minVerticesPerMesh == undefined or nodeVertices < minVerticesPerMesh do minVerticesPerMesh = nodeVertices
                if minTrianglesPerMesh == undefined or nodeTriangles < minTrianglesPerMesh do minTrianglesPerMesh = nodeTriangles
                if minPolygonsPerMesh == undefined or nodePolygons < minPolygonsPerMesh do minPolygonsPerMesh = nodePolygons

                if nodeVertices > maxVerticesPerMesh do maxVerticesPerMesh = nodeVertices
                if nodeTriangles > maxTrianglesPerMesh do maxTrianglesPerMesh = nodeTriangles
                if nodePolygons > maxPolygonsPerMesh do maxPolygonsPerMesh = nodePolygons

                appendUniqueString uniqueMeshSignatures (buildMeshSignature node)

                if node.material != undefined do collectBitmapTexturePathsFromMaterial node.material fileTexturePaths
            )

            if minVerticesPerFile == undefined or fileVertices < minVerticesPerFile do minVerticesPerFile = fileVertices
            if minTrianglesPerFile == undefined or fileTriangles < minTrianglesPerFile do minTrianglesPerFile = fileTriangles
            if minPolygonsPerFile == undefined or filePolygons < minPolygonsPerFile do minPolygonsPerFile = filePolygons

            if fileVertices > maxVerticesPerFile do maxVerticesPerFile = fileVertices
            if fileTriangles > maxTrianglesPerFile do maxTrianglesPerFile = fileTriangles
            if filePolygons > maxPolygonsPerFile do maxPolygonsPerFile = filePolygons

            for texturePath in fileTexturePaths do
            (
                appendUniqueString uniqueTexturePaths texturePath
                local textureResolution = getBitmapResolution texturePath
                appendUniqueInteger uniqueTextureResolutions textureResolution
                if textureResolution > fileMaxTextureResolution do fileMaxTextureResolution = textureResolution
                if textureResolution > maxTextureResolution do maxTextureResolution = textureResolution
            )

            totalTextureReferences += fileTexturePaths.count

            append perFileLines (
                fileNameOnly +
                " | meshes=" + (geometryNodes.count as string) +
                " | verts=" + (fileVertices as string) +
                " | tris=" + (fileTriangles as string) +
                " | polys=" + (filePolygons as string) +
                " | textures=" + (fileTexturePaths.count as string) +
                " | maxTex=" + (fileMaxTextureResolution as string)
            )
        )

        local uniqueTextureCount = uniqueTexturePaths.count
        local minTextureResolution = undefined

        for textureResolution in uniqueTextureResolutions do
        (
            if textureResolution > 0 and (minTextureResolution == undefined or textureResolution < minTextureResolution) do minTextureResolution = textureResolution
        )

        local reportLines = #()
        append reportLines "FAB FBX REPORT"
        append reportLines "================"
        append reportLines ("Folder: " + inputFolder)
        append reportLines ("Total FBX files: " + (totalFileCount as string))
        append reportLines ("FBX files with geometry: " + (filesWithGeometry as string))
        append reportLines ("Total mesh objects: " + (totalGeometryNodes as string))
        append reportLines ("Estimated unique meshes: " + (uniqueMeshSignatures.count as string))
        append reportLines ("Total vertices: " + (totalVertices as string))
        append reportLines ("Total triangles: " + (totalTriangles as string))
        append reportLines ("Total polygons: " + (totalPolygons as string))
        append reportLines ("Vertices per file range: min=" + ((if minVerticesPerFile == undefined then 0 else minVerticesPerFile) as string) + ", max=" + (maxVerticesPerFile as string))
        append reportLines ("Triangles per file range: min=" + ((if minTrianglesPerFile == undefined then 0 else minTrianglesPerFile) as string) + ", max=" + (maxTrianglesPerFile as string))
        append reportLines ("Polygons per file range: min=" + ((if minPolygonsPerFile == undefined then 0 else minPolygonsPerFile) as string) + ", max=" + (maxPolygonsPerFile as string))
        append reportLines ("Vertices per mesh range: min=" + ((if minVerticesPerMesh == undefined then 0 else minVerticesPerMesh) as string) + ", max=" + (maxVerticesPerMesh as string))
        append reportLines ("Triangles per mesh range: min=" + ((if minTrianglesPerMesh == undefined then 0 else minTrianglesPerMesh) as string) + ", max=" + (maxTrianglesPerMesh as string))
        append reportLines ("Polygons per mesh range: min=" + ((if minPolygonsPerMesh == undefined then 0 else minPolygonsPerMesh) as string) + ", max=" + (maxPolygonsPerMesh as string))
        append reportLines ("Total texture references: " + (totalTextureReferences as string))
        append reportLines ("Unique texture files: " + (uniqueTextureCount as string))
        append reportLines ("Texture resolution range: min=" + ((if minTextureResolution == undefined then 0 else minTextureResolution) as string) + ", max=" + (maxTextureResolution as string))
        append reportLines ("Max texture resolution: " + (maxTextureResolution as string))
        append reportLines ""
        append reportLines "PER FILE"
        append reportLines "--------"
        for fileLine in perFileLines do append reportLines fileLine

        if failedFiles.count > 0 then
        (
            append reportLines ""
            append reportLines "FAILED FILES"
            append reportLines "------------"
            for failedLine in failedFiles do append reportLines failedLine
        )

        batchReportFbxFabStatsText = joinStringArray reportLines "\r\n"
        showReportWindow batchReportFbxFabStatsText
    )
)