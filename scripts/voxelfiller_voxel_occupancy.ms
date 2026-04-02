rollout voxelFillGridUI "Temple Voxel Fill Tool (Voxel Grid)"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"

    groupBox voxelGroup "Voxel Grid" width:210 height:64
    spinner cellSizeSpinner "Cell Size" range:[0.1,4.0,1000.0] type:#float fieldwidth:64 scale:0.1
    spinner shellPaddingSpinner "Surface Padding Cells" range:[0,1,3] type:#integer fieldwidth:64

    groupBox variationGroup "Variation" width:210 height:144
    checkbox randomRotationCheck "Random Z Rotation" checked:true
    spinner rotMinSpinner "Min Rot" range:[0,0,360] type:#integer fieldwidth:48
    spinner rotMaxSpinner "Max Rot" range:[0,180,360] type:#integer fieldwidth:48
    checkbox randomScaleCheck "Random Scale %" checked:false
    spinner scaleMinSpinner "Min Scale" range:[10,90,300] type:#integer fieldwidth:48
    spinner scaleMaxSpinner "Max Scale" range:[10,110,300] type:#integer fieldwidth:48
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48

    groupBox debugGroup "Debug" width:210 height:48
    checkbox debugCheck "Listener Debug" checked:true

    button runFill "Run Voxel Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillGrid] %\n" messageText
    )

    fn setHashTrue hashTable key =
    (
        if not hashTable.ContainsKey key do hashTable.Add key true
    )

    fn hashHasKey hashTable key =
    (
        hashTable.ContainsKey key
    )

    fn makeVoxelKey x y z =
    (
        (x as string) + "|" + (y as string) + "|" + (z as string)
    )

    fn isCellInBounds x y z counts =
    (
        x >= 0 and x < counts[1] and y >= 0 and y < counts[2] and z >= 0 and z < counts[3]
    )

    fn getBrickSize brickObj =
    (
        local bb = nodeGetBoundingBox brickObj brickObj.transform
        bb[2] - bb[1]
    )

    fn getTempleBounds temple =
    (
        nodeGetBoundingBox temple (matrix3 1)
    )

    fn getBoundsSize bounds =
    (
        bounds[2] - bounds[1]
    )

    fn validateGridSettings bounds counts paddingCells cellSize estimatedPlacementChecks =
    (
        local boundsSize = getBoundsSize bounds
        local minAxisCount = amin counts[1] (amin counts[2] counts[3])
        local effectiveInteriorAxis = minAxisCount - (paddingCells * 2)
        local totalGridCells = counts[1] * counts[2] * counts[3]

        if minAxisCount <= 3 then
        (
            local warningMessage = "Cell Size is too large for this mesh. Current grid counts are " + counts as string + ". Reduce Cell Size before running."
            debugLog warningMessage
            messageBox warningMessage title:"Voxel Fill"
            return false
        )

        if effectiveInteriorAxis <= 1 then
        (
            local warningMessage = "Surface Padding Cells is too high for the current grid. Reduce padding or use a smaller Cell Size."
            debugLog warningMessage
            messageBox warningMessage title:"Voxel Fill"
            return false
        )

        if cellSize >= (amax boundsSize.x (amax boundsSize.y boundsSize.z)) then
        (
            local warningMessage = "Cell Size is larger than the mesh dimensions. Use a much smaller Cell Size."
            debugLog warningMessage
            messageBox warningMessage title:"Voxel Fill"
            return false
        )

        if totalGridCells > 250000 then
        (
            local warningMessage = "Voxel grid is too dense for interactive use. Grid cells=" + totalGridCells as string + ". Increase Cell Size before running."
            debugLog warningMessage
            messageBox warningMessage title:"Voxel Fill"
            return false
        )

        if estimatedPlacementChecks > 2000000 then
        (
            local warningMessage = "Placement scan is too expensive. Estimated placement checks=" + estimatedPlacementChecks as string + ". Increase Cell Size or use larger bricks."
            debugLog warningMessage
            messageBox warningMessage title:"Voxel Fill"
            return false
        )

        true
    )

    fn getCellIndex value origin cellSize axisCount =
    (
        local rawIndex = floor ((value - origin) / cellSize)
        amin (axisCount - 1) (amax 0 rawIndex)
    )

    fn worldPointToCell point gridMin cellSize counts =
    (
        #(
            getCellIndex point.x gridMin.x cellSize counts[1],
            getCellIndex point.y gridMin.y cellSize counts[2],
            getCellIndex point.z gridMin.z cellSize counts[3]
        )
    )

    fn cellCenterToWorld x y z gridMin cellSize =
    (
        [gridMin.x + (((x as float) + 0.5) * cellSize), gridMin.y + (((y as float) + 0.5) * cellSize), gridMin.z + (((z as float) + 0.5) * cellSize)]
    )

    fn updateProgress processed totalSamples createdCount =
    (
        local progressValue = if totalSamples > 0 then ((processed as float / totalSamples as float) * 100.0) else 0.0
        fillProgress.value = progressValue as integer
        fillStatus.text = ("Steps: " + processed as string + " / " + totalSamples as string + " | Bricks: " + createdCount as string)
        windows.processPostedMessages()
    )

    fn buildGridInfo temple cellSize =
    (
        local bounds = getTempleBounds temple
        local gridMin = bounds[1] - [cellSize, cellSize, cellSize]
        local gridMax = bounds[2] + [cellSize, cellSize, cellSize]
        local counts = #(
            (amax 1 (ceil ((gridMax.x - gridMin.x) / cellSize))) as integer,
            (amax 1 (ceil ((gridMax.y - gridMin.y) / cellSize))) as integer,
            (amax 1 (ceil ((gridMax.z - gridMin.z) / cellSize))) as integer
        )

        #(bounds, gridMin, gridMax, counts)
    )

    fn markSurfaceNeighborhood surfaceVoxels baseCell counts paddingCells =
    (
        for xOffset = -paddingCells to paddingCells do
        (
            for yOffset = -paddingCells to paddingCells do
            (
                for zOffset = -paddingCells to paddingCells do
                (
                    local x = baseCell[1] + xOffset
                    local y = baseCell[2] + yOffset
                    local z = baseCell[3] + zOffset

                    if isCellInBounds x y z counts do setHashTrue surfaceVoxels (makeVoxelKey x y z)
                )
            )
        )
    )

    fn sampleTriangleIntoSurface meshNode faceIndex gridMin cellSize counts paddingCells surfaceVoxels =
    (
        local faceVerts = getFace meshNode.mesh faceIndex
        local v1 = (getVert meshNode.mesh faceVerts.x) * meshNode.transform
        local v2 = (getVert meshNode.mesh faceVerts.y) * meshNode.transform
        local v3 = (getVert meshNode.mesh faceVerts.z) * meshNode.transform
        local edge01 = distance v1 v2
        local edge12 = distance v2 v3
        local edge20 = distance v3 v1
        local maxEdge = amax edge01 (amax edge12 edge20)
        local steps = amax 1 (ceil (maxEdge / (cellSize * 0.5)))

        for i = 0 to steps do
        (
            local a = i as float / steps as float
            local remaining = steps - i

            for j = 0 to remaining do
            (
                local b = j as float / steps as float
                local c = 1.0 - a - b
                local samplePoint = (v1 * c) + (v2 * a) + (v3 * b)
                local sampleCell = worldPointToCell samplePoint gridMin cellSize counts
                markSurfaceNeighborhood surfaceVoxels sampleCell counts paddingCells
            )
        )
    )

    fn createTempleSnapshot temple =
    (
        local snapshotNode = undefined

        try
        (
            snapshotNode = snapshot temple
            if snapshotNode != undefined do
            (
                snapshotNode.name = uniqueName "VoxelSurfaceSnapshot"
                snapshotNode.isHidden = true
                snapshotNode.boxMode = true
            )
        )
        catch
        (
            snapshotNode = undefined
        )

        snapshotNode
    )

    fn deleteSnapshot snapshotNode =
    (
        if isValidNode snapshotNode do delete snapshotNode
    )

    fn buildSurfaceVoxels snapshotNode gridMin cellSize counts paddingCells totalSamples createdCount =
    (
        local surfaceVoxels = dotNetObject "System.Collections.Hashtable"
        local faceCount = snapshotNode.mesh.numfaces
        local processed = 0

        debugLog ("Rasterizing " + faceCount as string + " faces into surface voxels")

        for faceIndex = 1 to faceCount while not fillCancelled do
        (
            sampleTriangleIntoSurface snapshotNode faceIndex gridMin cellSize counts paddingCells surfaceVoxels
            processed += 1

            if (mod processed 50) == 0 or processed == faceCount do updateProgress processed totalSamples createdCount
        )

        #(surfaceVoxels, processed)
    )

    fn enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts x y z =
    (
        local key = makeVoxelKey x y z

        if isCellInBounds x y z counts and not (hashHasKey queuedVoxels key) and not (hashHasKey surfaceVoxels key) then
        (
            setHashTrue queuedVoxels key
            queue.Enqueue #(x, y, z)
        )
    )

    fn enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts x y z =
    (
        local key = makeVoxelKey x y z

        if isCellInBounds x y z counts and not (hashHasKey queuedVoxels key) and not (hashHasKey surfaceVoxels key) and not (hashHasKey exteriorVoxels key) then
        (
            setHashTrue queuedVoxels key
            queue.Enqueue #(x, y, z)
        )
    )

    fn floodFillExterior surfaceVoxels counts totalSamples processedCount createdCount =
    (
        local exteriorVoxels = dotNetObject "System.Collections.Hashtable"
        local queuedVoxels = dotNetObject "System.Collections.Hashtable"
        local queue = dotNetObject "System.Collections.Queue"
        local processed = processedCount
        local seedCount = 0

        for x = 0 to (counts[1] - 1) do
        (
            for y = 0 to (counts[2] - 1) do
            (
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts x y 0
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts x y (counts[3] - 1)
            )
        )

        for x = 0 to (counts[1] - 1) do
        (
            for z = 0 to (counts[3] - 1) do
            (
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts x 0 z
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts x (counts[2] - 1) z
            )
        )

        for y = 0 to (counts[2] - 1) do
        (
            for z = 0 to (counts[3] - 1) do
            (
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts 0 y z
                enqueueBoundaryCell queue queuedVoxels surfaceVoxels counts (counts[1] - 1) y z
            )
        )

        seedCount = queue.Count
        debugLog ("Flood fill start: boundary seeds=" + seedCount as string + " surface voxels=" + surfaceVoxels.Count as string)

        while queue.Count > 0 and not fillCancelled do
        (
            local cell = queue.Dequeue()
            local x = cell[1]
            local y = cell[2]
            local z = cell[3]
            local key = makeVoxelKey x y z

            if not (hashHasKey surfaceVoxels key) and not (hashHasKey exteriorVoxels key) then
            (
                setHashTrue exteriorVoxels key
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts (x + 1) y z
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts (x - 1) y z
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts x (y + 1) z
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts x (y - 1) z
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts x y (z + 1)
                enqueueFloodNeighbor queue queuedVoxels surfaceVoxels exteriorVoxels counts x y (z - 1)

                processed += 1
            )

            if (mod processed 250) == 0 do
            (
                debugLog ("Flood fill progress: exterior=" + exteriorVoxels.Count as string + " queue=" + queue.Count as string + " processed=" + processed as string)
                updateProgress processed totalSamples createdCount
            )
        )

        debugLog ("Flood fill end: exterior voxels=" + exteriorVoxels.Count as string + " processed=" + processed as string + " remaining queue=" + queue.Count as string)

        #(exteriorVoxels, processed)
    )

    fn buildInteriorVoxels surfaceVoxels exteriorVoxels counts totalSamples processedCount createdCount =
    (
        local interiorVoxels = dotNetObject "System.Collections.Hashtable"
        local processed = processedCount

        debugLog ("Interior build start: grid counts=" + counts as string)

        for x = 0 to (counts[1] - 1) while not fillCancelled do
        (
            for y = 0 to (counts[2] - 1) while not fillCancelled do
            (
                for z = 0 to (counts[3] - 1) while not fillCancelled do
                (
                    local key = makeVoxelKey x y z
                    if not (hashHasKey surfaceVoxels key) and not (hashHasKey exteriorVoxels key) do setHashTrue interiorVoxels key
                    processed += 1
                )
            )

            updateProgress processed totalSamples createdCount
            if (mod x 10) == 0 do debugLog ("Interior build progress: x=" + x as string + " interior=" + interiorVoxels.Count as string + " processed=" + processed as string)
        )

        debugLog ("Interior build end: interior voxels=" + interiorVoxels.Count as string + " processed=" + processed as string)

        #(interiorVoxels, processed)
    )

    fn getPlacementVariation =
    (
        local zRotation = 0.0
        local scaleMultiplier = 1.0

        if randomRotationCheck.checked do
        (
            local minRotation = amin rotMinSpinner.value rotMaxSpinner.value
            local maxRotation = amax rotMinSpinner.value rotMaxSpinner.value
            zRotation = random minRotation maxRotation
        )

        if randomScaleCheck.checked do
        (
            local minScale = amin scaleMinSpinner.value scaleMaxSpinner.value
            local maxScale = amax scaleMinSpinner.value scaleMaxSpinner.value
            scaleMultiplier = (random minScale maxScale) / 100.0
        )

        #(zRotation, scaleMultiplier)
    )

    fn getPlacementEnvelopeSize brickSize placementVariation =
    (
        local scaledSize = brickSize * placementVariation[2]
        local angleRadians = placementVariation[1] * pi / 180.0
        local cosValue = abs (cos angleRadians)
        local sinValue = abs (sin angleRadians)

        [(scaledSize.x * cosValue) + (scaledSize.y * sinValue), (scaledSize.x * sinValue) + (scaledSize.y * cosValue), scaledSize.z]
    )

    fn getFootprintCounts brickSize placementVariation cellSize =
    (
        local envelopeSize = getPlacementEnvelopeSize brickSize placementVariation

        #(
            amax 1 (ceil (envelopeSize.x / cellSize)),
            amax 1 (ceil (envelopeSize.y / cellSize)),
            amax 1 (ceil (envelopeSize.z / cellSize))
        )
    )

    fn applyMaterialVariation newBrick sourceMaterial tintPercent =
    (
        if sourceMaterial == undefined then return false

        local brickMaterial = copy sourceMaterial
        if isProperty brickMaterial #diffuse then
        (
            local tintRange = 255.0 * (tintPercent as float / 100.0)
            local tintOffset = random (-tintRange) tintRange
            local baseDiffuse = brickMaterial.diffuse
            brickMaterial.diffuse = color \
                (amin 255 (amax 0 ((baseDiffuse.r + tintOffset) as integer))) \
                (amin 255 (amax 0 ((baseDiffuse.g + tintOffset) as integer))) \
                (amin 255 (amax 0 ((baseDiffuse.b + tintOffset) as integer)))
        )

        newBrick.material = brickMaterial
        true
    )

    fn applyPlacementVariation newBrick sourceBrick placementVariation =
    (
        local baseRotation = sourceBrick.rotation
        local baseScale = sourceBrick.scale

        newBrick.rotation = baseRotation * (angleaxis placementVariation[1] [0,0,1])
        newBrick.scale = [baseScale.x * placementVariation[2], baseScale.y * placementVariation[2], baseScale.z * placementVariation[2]]

        if materialVariationCheck.checked then
        (
            applyMaterialVariation newBrick sourceBrick.material materialTintSpinner.value
        )
        else
        (
            newBrick.material = sourceBrick.material
        )
    )

    fn footprintFits x y z footprintCounts interiorVoxels occupiedVoxels counts =
    (
        local maxX = x + footprintCounts[1] - 1
        local maxY = y + footprintCounts[2] - 1
        local maxZ = z + footprintCounts[3] - 1

        if maxX >= counts[1] or maxY >= counts[2] or maxZ >= counts[3] then return false

        for ix = x to maxX do
        (
            for iy = y to maxY do
            (
                for iz = z to maxZ do
                (
                    local key = makeVoxelKey ix iy iz
                    if not (hashHasKey interiorVoxels key) or hashHasKey occupiedVoxels key do return false
                )
            )
        )

        true
    )

    fn markOccupied x y z footprintCounts occupiedVoxels =
    (
        for ix = x to (x + footprintCounts[1] - 1) do
        (
            for iy = y to (y + footprintCounts[2] - 1) do
            (
                for iz = z to (z + footprintCounts[3] - 1) do
                (
                    setHashTrue occupiedVoxels (makeVoxelKey ix iy iz)
                )
            )
        )
    )

    fn createPlacementPosition x y z footprintCounts gridMin cellSize =
    (
        [gridMin.x + (((x as float) + ((footprintCounts[1] as float) * 0.5)) * cellSize), gridMin.y + (((y as float) + ((footprintCounts[2] as float) * 0.5)) * cellSize), gridMin.z + (((z as float) + ((footprintCounts[3] as float) * 0.5)) * cellSize)]
    )

    fn collectFillJobs =
    (
        local jobs = #()

        if bigBrick != undefined do append jobs #(bigBrick, getBrickSize bigBrick)
        if mediumBrick != undefined do append jobs #(mediumBrick, getBrickSize mediumBrick)

        if jobs.count > 1 do
        (
            local firstVolume = jobs[1][2].x * jobs[1][2].y * jobs[1][2].z
            local secondVolume = jobs[2][2].x * jobs[2][2].y * jobs[2][2].z

            if secondVolume > firstVolume then
            (
                local tempJob = jobs[1]
                jobs[1] = jobs[2]
                jobs[2] = tempJob
            )
        )

        jobs
    )

    fn estimatePlacementChecks counts fillJobs cellSize =
    (
        local estimate = 0

        for fillJob in fillJobs do
        (
            local footprintCounts = getFootprintCounts fillJob[2] #(0.0, 1.0) cellSize
            estimate += amax 1 ((counts[1] - footprintCounts[1] + 1) * (counts[2] - footprintCounts[2] + 1) * (counts[3] - footprintCounts[3] + 1))
        )

        estimate
    )

    fn placeBricks fillJobs gridMin counts cellSize interiorVoxels totalSamples processedCount =
    (
        local occupiedVoxels = dotNetObject "System.Collections.Hashtable"
        local processed = processedCount
        local created = 0

        debugLog ("Placement phase start: interior voxels=" + interiorVoxels.Count as string + " counts=" + counts as string)

        for fillJob in fillJobs while not fillCancelled do
        (
            local brickObj = fillJob[1]
            local brickSize = fillJob[2]
            local baseFootprint = getFootprintCounts brickSize #(0.0, 1.0) cellSize
            local maxX = amax 0 (counts[1] - baseFootprint[1])
            local maxY = amax 0 (counts[2] - baseFootprint[2])
            local maxZ = amax 0 (counts[3] - baseFootprint[3])

            debugLog ("Placement job: brick=" + brickObj.name + " brickSize=" + brickSize as string + " baseFootprint=" + baseFootprint as string)

            for x = 0 to maxX while not fillCancelled do
            (
                for y = 0 to maxY while not fillCancelled do
                (
                    for z = 0 to maxZ while not fillCancelled do
                    (
                        local placementVariation = getPlacementVariation()
                        local footprintCounts = getFootprintCounts brickSize placementVariation cellSize

                        if footprintFits x y z footprintCounts interiorVoxels occupiedVoxels counts then
                        (
                            local newBrick = instance brickObj
                            newBrick.position = createPlacementPosition x y z footprintCounts gridMin cellSize
                            applyPlacementVariation newBrick brickObj placementVariation
                            markOccupied x y z footprintCounts occupiedVoxels
                            created += 1
                        )

                        processed += 1
                        if (mod processed 100) == 0 or processed == totalSamples do
                        (
                            updateProgress processed totalSamples created
                            if (mod processed 1000) == 0 do debugLog ("Placement progress: brick=" + brickObj.name + " created=" + created as string + " occupied=" + occupiedVoxels.Count as string + " processed=" + processed as string)
                        )
                    )
                )
            )
        )

        debugLog ("Placement phase end: created=" + created as string + " occupied voxels=" + occupiedVoxels.Count as string + " processed=" + processed as string)

        #(created, processed)
    )

    fn resetProgressState messageText =
    (
        fillProgress.value = 0
        fillStatus.text = messageText
    )

    on pickTemple pressed do
    (
        templeMesh = pickObject()
        if templeMesh != undefined do debugLog ("Picked temple: " + templeMesh.name)
    )

    on pickBigBrick pressed do
    (
        bigBrick = pickObject()
        if bigBrick != undefined do debugLog ("Picked big brick: " + bigBrick.name + " size=" + (getBrickSize bigBrick) as string)
    )

    on pickMediumBrick pressed do
    (
        mediumBrick = pickObject()
        if mediumBrick != undefined do debugLog ("Picked medium brick: " + mediumBrick.name + " size=" + (getBrickSize mediumBrick) as string)
    )

    on runFill pressed do
    (
        local fillJobs = collectFillJobs()

        if templeMesh != undefined and fillJobs.count > 0 then
        (
            local cellSize = amax 0.1 cellSizeSpinner.value
            local paddingCells = amax 0 shellPaddingSpinner.value
            local gridInfo = buildGridInfo templeMesh cellSize
            local templeBounds = gridInfo[1]
            local gridMin = gridInfo[2]
            local gridMax = gridInfo[3]
            local counts = gridInfo[4]
            local estimatedPlacementChecks = estimatePlacementChecks counts fillJobs cellSize
            local processed = 0
            local created = 0
            local snapshotNode = createTempleSnapshot templeMesh

            if not (validateGridSettings templeBounds counts paddingCells cellSize estimatedPlacementChecks) then
            (
                resetProgressState "Idle"
                if snapshotNode != undefined do deleteSnapshot snapshotNode
                return()
            )

            if snapshotNode == undefined then
            (
                messageBox "Unable to snapshot the temple mesh."
                resetProgressState "Idle"
            )
            else
            (
                local totalSamples = snapshotNode.mesh.numfaces + (counts[1] * counts[2] * counts[3] * 2) + estimatedPlacementChecks

                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Voxelizing temple..."

                debugLog "----- Voxel Fill Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Grid min=" + gridMin as string + " max=" + gridMax as string + " counts=" + counts as string + " cellSize=" + cellSize as string)
                debugLog ("Estimated steps=" + totalSamples as string + " placement checks=" + estimatedPlacementChecks as string)

                local surfaceBuildResult = buildSurfaceVoxels snapshotNode gridMin cellSize counts paddingCells totalSamples created
                local surfaceVoxels = surfaceBuildResult[1]
                processed = surfaceBuildResult[2]
                debugLog ("Surface raster end: voxels=" + surfaceVoxels.Count as string + " processed=" + processed as string)

                local exteriorResult = floodFillExterior surfaceVoxels counts totalSamples processed created
                local exteriorVoxels = exteriorResult[1]
                processed = exteriorResult[2]

                local interiorResult = buildInteriorVoxels surfaceVoxels exteriorVoxels counts totalSamples processed created
                local interiorVoxels = interiorResult[1]
                processed = interiorResult[2]

                debugLog ("Surface voxels=" + surfaceVoxels.Count as string + " exterior voxels=" + exteriorVoxels.Count as string + " interior voxels=" + interiorVoxels.Count as string)

                fillStatus.text = "Placing bricks..."
                local placementResult = placeBricks fillJobs gridMin counts cellSize interiorVoxels totalSamples processed
                created = placementResult[1]
                processed = placementResult[2]

                updateProgress processed totalSamples created
                fillStatus.text = ("Fill complete. Created " + created as string + " bricks.")
                debugLog ("Fill complete. Created " + created as string + " bricks.")
                debugLog "----- Voxel Fill End -----"

                deleteSnapshot snapshotNode
                runFill.enabled = true
            )
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh and at least one brick mesh first!"
        )
    )
)

createDialog voxelFillGridUI width:360 height:680