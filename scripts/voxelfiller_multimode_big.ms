try(destroyDialog voxelFillMultiModeUI)catch()

rollout voxelFillMultiModeUI "Temple Fill Tool (Voxel Or Slice)"
(
    local templeMesh
    local bigBrick
    local fillCancelled = false
    local placementDebugLogsRemaining = 0
    local rejectionDebugLogsRemaining = 0

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"

    groupBox modeGroup "Placement Mode" width:320 height:96
    dropdownList modeDropdown "Mode" items:#("Voxel Occupancy","Slice Fill") selection:1 width:190
    spinner cellSizeSpinner "Cell Size" range:[0.1,1.0,1000.0] type:#float fieldwidth:64 scale:0.1
    spinner paddingCellsSpinner "Padding Cells" range:[0,0,4] type:#integer fieldwidth:64

    groupBox debugGroup "Debug" width:320 height:88
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Placement Samples" checked:false

    button runFill "Run Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillMulti] %\n" messageText
    )

    fn debugBounds prefix boundsValue =
    (
        debugLog (prefix + " min=" + boundsValue[1] as string + " max=" + boundsValue[2] as string)
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

    fn getTempleBounds temple =
    (
        nodeGetBoundingBox temple (matrix3 1)
    )

    fn getBrickWorldBounds brickObj =
    (
        nodeGetBoundingBox brickObj (matrix3 1)
    )

    fn getBrickSize brickObj =
    (
        local bounds = getBrickWorldBounds brickObj
        bounds[2] - bounds[1]
    )

    fn getBrickBoundsCenter brickObj =
    (
        local bounds = getBrickWorldBounds brickObj
        (bounds[1] + bounds[2]) * 0.5
    )

    fn getBrickCenterOffset brickObj =
    (
        getBrickBoundsCenter brickObj - brickObj.position
    )

    fn getRecommendedCellSize templeBounds brickSize =
    (
        local boundsSize = templeBounds[2] - templeBounds[1]
        local minBrickAxis = amin brickSize.x (amin brickSize.y brickSize.z)
        local paddedVolume = (boundsSize.x + minBrickAxis) * (boundsSize.y + minBrickAxis) * (boundsSize.z + minBrickAxis)
        local budgetCellSize = amax 0.1 (paddedVolume / 200000.0) ^ (1.0 / 3.0)
        local detailCellSize = amax 0.1 (minBrickAxis / 3.0)

        amax detailCellSize budgetCellSize
    )

    fn updateAutoCellSize =
    (
        if templeMesh != undefined and bigBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local brickSize = getBrickSize bigBrick
            local recommendedCellSize = getRecommendedCellSize templeBounds brickSize
            cellSizeSpinner.value = recommendedCellSize
            debugLog ("Auto cell size=" + recommendedCellSize as string + " brickSize=" + brickSize as string)
        )
    )

    fn getBoundsCorners boundsValue =
    (
        #(
            [boundsValue[1].x, boundsValue[1].y, boundsValue[1].z],
            [boundsValue[2].x, boundsValue[1].y, boundsValue[1].z],
            [boundsValue[1].x, boundsValue[2].y, boundsValue[1].z],
            [boundsValue[2].x, boundsValue[2].y, boundsValue[1].z],
            [boundsValue[1].x, boundsValue[1].y, boundsValue[2].z],
            [boundsValue[2].x, boundsValue[1].y, boundsValue[2].z],
            [boundsValue[1].x, boundsValue[2].y, boundsValue[2].z],
            [boundsValue[2].x, boundsValue[2].y, boundsValue[2].z]
        )
    )

    fn updateProgress processed totalSteps createdCount =
    (
        local progressValue = if totalSteps > 0 then ((processed as float / totalSteps as float) * 100.0) else 0.0
        fillProgress.value = amin 100 (progressValue as integer)
        fillStatus.text = ("Steps: " + processed as string + " / " + totalSteps as string + " | Bricks: " + createdCount as string)
        windows.processPostedMessages()
    )

    fn resetProgressState messageText =
    (
        fillProgress.value = 0
        fillStatus.text = messageText
    )

    fn createTempleSnapshot temple =
    (
        local snapshotNode = undefined

        try
        (
            snapshotNode = snapshot temple
            if snapshotNode != undefined do
            (
                snapshotNode.name = uniqueName "VoxelFillMultiTarget"
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

    fn buildGridInfo templeBounds cellSize =
    (
        local gridMin = templeBounds[1] - [cellSize, cellSize, cellSize]
        local gridMax = templeBounds[2] + [cellSize, cellSize, cellSize]
        local counts = #(
            (amax 1 (ceil ((gridMax.x - gridMin.x) / cellSize))) as integer,
            (amax 1 (ceil ((gridMax.y - gridMin.y) / cellSize))) as integer,
            (amax 1 (ceil ((gridMax.z - gridMin.z) / cellSize))) as integer
        )

        #(gridMin, gridMax, counts)
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

    fn getWorldBoundsForPlacement targetCenter brickSize =
    (
        local halfSize = brickSize * 0.5
        #(targetCenter - halfSize, targetCenter + halfSize)
    )

    fn getFootprintCounts brickSize cellSize =
    (
        #(
            amax 1 (ceil (brickSize.x / cellSize)),
            amax 1 (ceil (brickSize.y / cellSize)),
            amax 1 (ceil (brickSize.z / cellSize))
        )
    )

    fn createPlacementPosition x y z footprintCounts gridMin cellSize =
    (
        [gridMin.x + (((x as float) + ((footprintCounts[1] as float) * 0.5)) * cellSize), gridMin.y + (((y as float) + ((footprintCounts[2] as float) * 0.5)) * cellSize), gridMin.z + (((z as float) + ((footprintCounts[3] as float) * 0.5)) * cellSize)]
    )

    fn getCellRangeForBounds worldBounds gridMin cellSize counts =
    (
        local minCell = worldPointToCell worldBounds[1] gridMin cellSize counts
        local maxPoint = worldBounds[2] - [0.0001, 0.0001, 0.0001]
        local maxCell = worldPointToCell maxPoint gridMin cellSize counts
        #(minCell, maxCell)
    )

    fn countRayHitsToDistance obj rayOrigin rayDir maxDistance maxHits:128 epsilon:0.5 =
    (
        local hitCount = 0
        local normalizedDir = normalize rayDir
        local sampleOrigin = rayOrigin
        local travelledDistance = 0.0
        local hit = intersectRay obj (ray sampleOrigin normalizedDir)

        while hit != undefined and hitCount < maxHits do
        (
            local hitDistance = distance sampleOrigin hit.pos
            travelledDistance += hitDistance

            if travelledDistance > (maxDistance + epsilon) then exit

            hitCount += 1
            sampleOrigin = hit.pos + (normalizedDir * epsilon)
            travelledDistance += epsilon
            hit = intersectRay obj (ray sampleOrigin normalizedDir)
        )

        hitCount
    )

    fn evaluatePointInMesh p obj bounds =
    (
        local directions = #(
            normalize [1.0, 0.371, 0.173],
            normalize [-0.529, 1.0, 0.241],
            normalize [0.193, -0.317, 1.0],
            normalize [1.0, 1.0, 0.411],
            normalize [-0.707, 0.223, 1.0]
        )
        local insideVotes = 0
        local voteThreshold = amax 1 (ceil (directions.count as float * 0.5))
        local bbMin = bounds[1]
        local bbMax = bounds[2]
        local boundsSize = bbMax - bbMin
        local padding = (amax boundsSize.x (amax boundsSize.y boundsSize.z)) + 10.0

        for dir in directions do
        (
            local forwardOrigin = p - (dir * padding)
            local backwardOrigin = p + (dir * padding)
            local forwardDistance = distance forwardOrigin p
            local backwardDistance = distance backwardOrigin p
            local forwardHitCount = countRayHitsToDistance obj forwardOrigin dir forwardDistance
            local backwardHitCount = countRayHitsToDistance obj backwardOrigin (-dir) backwardDistance

            if ((mod forwardHitCount 2) == 1) or ((mod backwardHitCount 2) == 1) do insideVotes += 1
        )

        insideVotes >= voteThreshold
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

    fn buildSurfaceVoxels snapshotNode gridMin cellSize counts paddingCells totalSteps processedCount createdCount =
    (
        local surfaceVoxels = dotNetObject "System.Collections.Hashtable"
        local faceCount = snapshotNode.mesh.numfaces
        local processed = processedCount

        debugLog ("Surface raster start: faces=" + faceCount as string)

        for faceIndex = 1 to faceCount while not fillCancelled do
        (
            sampleTriangleIntoSurface snapshotNode faceIndex gridMin cellSize counts paddingCells surfaceVoxels
            processed += 1

            if (mod faceIndex 50) == 0 or faceIndex == faceCount do updateProgress processed totalSteps createdCount
        )

        debugLog ("Surface raster end: surface voxels=" + surfaceVoxels.Count as string)
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

    fn floodFillExterior surfaceVoxels counts totalSteps processedCount createdCount =
    (
        local exteriorVoxels = dotNetObject "System.Collections.Hashtable"
        local queuedVoxels = dotNetObject "System.Collections.Hashtable"
        local queue = dotNetObject "System.Collections.Queue"
        local processed = processedCount

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

        debugLog ("Flood fill start: queue seeds=" + queue.Count as string)

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

            if (mod processed 250) == 0 do updateProgress processed totalSteps createdCount
        )

        debugLog ("Flood fill end: exterior voxels=" + exteriorVoxels.Count as string)
        #(exteriorVoxels, processed)
    )

    fn buildInteriorVoxels surfaceVoxels exteriorVoxels counts totalSteps processedCount createdCount =
    (
        local interiorVoxels = dotNetObject "System.Collections.Hashtable"
        local processed = processedCount

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

            if (mod x 5) == 0 or x == (counts[1] - 1) do updateProgress processed totalSteps createdCount
        )

        debugLog ("Interior build end: interior voxels=" + interiorVoxels.Count as string)
        #(interiorVoxels, processed)
    )

    fn buildSliceInteriorVoxels snapshotNode templeBounds gridMin cellSize counts totalSteps processedCount createdCount =
    (
        local interiorVoxels = dotNetObject "System.Collections.Hashtable"
        local processed = processedCount

        debugLog ("Slice fill start: counts=" + counts as string)

        for z = 0 to (counts[3] - 1) while not fillCancelled do
        (
            for x = 0 to (counts[1] - 1) while not fillCancelled do
            (
                for y = 0 to (counts[2] - 1) while not fillCancelled do
                (
                    local samplePoint = cellCenterToWorld x y z gridMin cellSize
                    if evaluatePointInMesh samplePoint snapshotNode templeBounds do setHashTrue interiorVoxels (makeVoxelKey x y z)
                    processed += 1
                )
            )

            updateProgress processed totalSteps createdCount
        )

        debugLog ("Slice fill end: interior voxels=" + interiorVoxels.Count as string)
        #(interiorVoxels, processed)
    )

    fn buildInteriorByMode modeName snapshotNode templeBounds gridMin cellSize counts paddingCells totalSteps =
    (
        local processed = 0

        case modeName of
        (
            "Voxel Occupancy":
            (
                local surfaceResult = buildSurfaceVoxels snapshotNode gridMin cellSize counts paddingCells totalSteps processed 0
                local surfaceVoxels = surfaceResult[1]
                processed = surfaceResult[2]
                local floodResult = floodFillExterior surfaceVoxels counts totalSteps processed 0
                local exteriorVoxels = floodResult[1]
                processed = floodResult[2]
                local interiorResult = buildInteriorVoxels surfaceVoxels exteriorVoxels counts totalSteps processed 0
                #(interiorResult[1], interiorResult[2])
            )
            default:
            (
                buildSliceInteriorVoxels snapshotNode templeBounds gridMin cellSize counts totalSteps processed 0
            )
        )
    )

    fn cellRangeFitsInterior cellRange interiorVoxels counts =
    (
        local minCell = cellRange[1]
        local maxCell = cellRange[2]

        if not (isCellInBounds minCell[1] minCell[2] minCell[3] counts) then return false
        if not (isCellInBounds maxCell[1] maxCell[2] maxCell[3] counts) then return false

        for x = minCell[1] to maxCell[1] do
        (
            for y = minCell[2] to maxCell[2] do
            (
                for z = minCell[3] to maxCell[3] do
                (
                    if not (hashHasKey interiorVoxels (makeVoxelKey x y z)) do return false
                )
            )
        )

        true
    )

    fn footprintFitsInterior x y z footprintCounts interiorVoxels occupiedVoxels counts =
    (
        local maxX = x + footprintCounts[1] - 1
        local maxY = y + footprintCounts[2] - 1
        local maxZ = z + footprintCounts[3] - 1

        if not (isCellInBounds x y z counts) then return false
        if not (isCellInBounds maxX maxY maxZ counts) then return false

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

    fn getFirstMissingInteriorCell cellRange interiorVoxels counts =
    (
        local minCell = cellRange[1]
        local maxCell = cellRange[2]

        if not (isCellInBounds minCell[1] minCell[2] minCell[3] counts) then return #(#outOfBounds, minCell)
        if not (isCellInBounds maxCell[1] maxCell[2] maxCell[3] counts) then return #(#outOfBounds, maxCell)

        for x = minCell[1] to maxCell[1] do
        (
            for y = minCell[2] to maxCell[2] do
            (
                for z = minCell[3] to maxCell[3] do
                (
                    if not (hashHasKey interiorVoxels (makeVoxelKey x y z)) do return #(#missingInterior, #(x, y, z))
                )
            )
        )

        #(#ok, undefined)
    )

    fn logPlacementRejection targetCenter worldBounds cellRange gridMin cellSize counts interiorVoxels =
    (
        if rejectionDebugLogsRemaining > 0 then
        (
            local missingInfo = getFirstMissingInteriorCell cellRange interiorVoxels counts
            local missingState = missingInfo[1]
            local missingCell = missingInfo[2]

            debugLog ("Rejected placement targetCenter=" + targetCenter as string + " cellRange=" + cellRange as string)
            debugBounds "Rejected placement worldBounds" worldBounds

            if missingState == #missingInterior then
            (
                local missingCellCenter = cellCenterToWorld missingCell[1] missingCell[2] missingCell[3] gridMin cellSize
                debugLog ("Rejected missing interior cell=" + missingCell as string + " center=" + missingCellCenter as string)
            )
            else if missingState == #outOfBounds then
            (
                debugLog ("Rejected out-of-bounds cell=" + missingCell as string + " counts=" + counts as string)
            )
            else
            (
                debugLog "Rejected placement reason unresolved"
            )

            rejectionDebugLogsRemaining -= 1
        )
    )

    fn logPlacementSample sourceBrick targetCenter worldBounds newBrick =
    (
        if debugSamplesCheck.checked and placementDebugLogsRemaining > 0 then
        (
            local newBounds = nodeGetBoundingBox newBrick (matrix3 1)
            local newBoundsCenter = (newBounds[1] + newBounds[2]) * 0.5
            local targetCorners = getBoundsCorners worldBounds
            local actualCorners = getBoundsCorners newBounds

            debugLog ("Placement source=" + sourceBrick.name + " targetCenter=" + targetCenter as string + " finalPos=" + newBrick.position as string)
            debugBounds "Placement targetBounds" worldBounds
            debugBounds "Placement actualBounds" newBounds
            debugLog ("Placement centerDelta=" + (newBoundsCenter - targetCenter) as string)
            debugLog ("Placement firstCornerDelta=" + (actualCorners[1] - targetCorners[1]) as string + " lastCornerDelta=" + (actualCorners[8] - targetCorners[8]) as string)

            placementDebugLogsRemaining -= 1
        )
    )

    fn placeBigBricks templeBounds gridMin counts cellSize sourceBrick brickSize interiorVoxels totalSteps processedStart =
    (
        local occupiedVoxels = dotNetObject "System.Collections.Hashtable"
        local created = 0
        local processed = processedStart
        local footprintCounts = getFootprintCounts brickSize cellSize
        local maxX = amax 0 (counts[1] - footprintCounts[1])
        local maxY = amax 0 (counts[2] - footprintCounts[2])
        local maxZ = amax 0 (counts[3] - footprintCounts[3])
        local centerOffset = getBrickCenterOffset sourceBrick

        placementDebugLogsRemaining = 10
    rejectionDebugLogsRemaining = 14

        debugLog ("Placement grid counts=" + #(maxX + 1, maxY + 1, maxZ + 1) as string + " brickSize=" + brickSize as string + " footprint=" + footprintCounts as string)

        for xIndex = 0 to maxX while not fillCancelled do
        (
            for yIndex = 0 to maxY while not fillCancelled do
            (
                for zIndex = 0 to maxZ while not fillCancelled do
                (
                    local targetCenter = createPlacementPosition xIndex yIndex zIndex footprintCounts gridMin cellSize
                    local worldBounds = getWorldBoundsForPlacement targetCenter brickSize
                    local cellRange = #(#(xIndex, yIndex, zIndex), #(xIndex + footprintCounts[1] - 1, yIndex + footprintCounts[2] - 1, zIndex + footprintCounts[3] - 1))

                    processed += 1

                    if footprintFitsInterior xIndex yIndex zIndex footprintCounts interiorVoxels occupiedVoxels counts then
                    (
                        local newBrick = instance sourceBrick
                        newBrick.rotation = sourceBrick.rotation
                        newBrick.scale = sourceBrick.scale
                        newBrick.position = targetCenter - centerOffset
                        newBrick.material = sourceBrick.material
                        markOccupied xIndex yIndex zIndex footprintCounts occupiedVoxels
                        logPlacementSample sourceBrick targetCenter worldBounds newBrick
                        created += 1
                    )
                    else if debugSamplesCheck.checked do
                    (
                        logPlacementRejection targetCenter worldBounds cellRange gridMin cellSize counts interiorVoxels
                    )

                    if (mod processed 25) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

        #(created, processed)
    )

    fn estimateTotalSteps modeName snapshotNode counts templeBounds brickSize =
    (
        local placementCountX = amax 1 ((floor ((templeBounds[2].x - templeBounds[1].x) / brickSize.x)) as integer)
        local placementCountY = amax 1 ((floor ((templeBounds[2].y - templeBounds[1].y) / brickSize.y)) as integer)
        local placementCountZ = amax 1 ((floor ((templeBounds[2].z - templeBounds[1].z) / brickSize.z)) as integer)
        local placementSteps = placementCountX * placementCountY * placementCountZ

        if modeName == "Voxel Occupancy" then
        (
            snapshotNode.mesh.numfaces + (counts[1] * counts[2] * counts[3] * 2) + placementSteps
        )
        else
        (
            (counts[1] * counts[2] * counts[3]) + placementSteps
        )
    )

    fn validateSettings counts cellSize =
    (
        local totalGridCells = counts[1] * counts[2] * counts[3]

        if cellSize <= 0.0 then
        (
            messageBox "Cell Size must be greater than zero." title:"Temple Fill"
            return false
        )

        if totalGridCells > 350000 then
        (
            messageBox ("Grid is too dense for interactive use. Cells=" + totalGridCells as string + ". Increase Cell Size.") title:"Temple Fill"
            return false
        )

        true
    )

    on pickTemple pressed do
    (
        templeMesh = pickObject()
        if templeMesh != undefined do
        (
            debugLog ("Picked temple: " + templeMesh.name)
            debugBounds "Picked temple bounds" (getTempleBounds templeMesh)
            updateAutoCellSize()
        )
    )

    on pickBigBrick pressed do
    (
        bigBrick = pickObject()
        if bigBrick != undefined do
        (
            debugLog ("Picked big brick: " + bigBrick.name + " size=" + (getBrickSize bigBrick) as string)
            debugBounds "Picked big brick bounds" (getBrickWorldBounds bigBrick)
            updateAutoCellSize()
        )
    )

    on runFill pressed do
    (
        if templeMesh != undefined and bigBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local brickSize = getBrickSize bigBrick
            local cellSize = getRecommendedCellSize templeBounds brickSize
            local paddingCells = amax 0 paddingCellsSpinner.value
            local modeName = modeDropdown.items[modeDropdown.selection]
            local gridInfo = buildGridInfo templeBounds cellSize
            local gridMin = gridInfo[1]
            local gridMax = gridInfo[2]
            local counts = gridInfo[3]
            local snapshotNode = createTempleSnapshot templeMesh

            cellSizeSpinner.value = cellSize

            debugBounds "Temple bounds" templeBounds
            debugLog ("Grid min=" + gridMin as string + " max=" + gridMax as string + " counts=" + counts as string)
            debugLog ("Mode=" + modeName + " autoCellSize=" + cellSize as string + " brickCenterOffset=" + (getBrickCenterOffset bigBrick) as string)

            if not (validateSettings counts cellSize) then
            (
                resetProgressState "Idle"
                if snapshotNode != undefined do deleteSnapshot snapshotNode
                return()
            )

            if snapshotNode == undefined then
            (
                messageBox "Unable to snapshot the temple mesh." title:"Temple Fill"
                resetProgressState "Idle"
            )
            else
            (
                local totalSteps = estimateTotalSteps modeName snapshotNode counts templeBounds brickSize
                local interiorResult = undefined
                local placementResult = undefined

                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Building interior volume..."

                debugLog "----- Multi-Mode Fill Start -----"
                debugLog ("Mode=" + modeName + " cellSize=" + cellSize as string + " paddingCells=" + paddingCells as string + " brickSize=" + brickSize as string)

                interiorResult = buildInteriorByMode modeName snapshotNode templeBounds gridMin cellSize counts paddingCells totalSteps
                placementResult = placeBigBricks templeBounds gridMin counts cellSize bigBrick brickSize interiorResult[1] totalSteps interiorResult[2]

                updateProgress totalSteps totalSteps placementResult[1]
                fillStatus.text = ("Fill complete. Total=" + placementResult[1] as string)

                debugLog ("Fill complete. Total=" + placementResult[1] as string + " processed=" + placementResult[2] as string)
                debugLog "----- Multi-Mode Fill End -----"

                deleteSnapshot snapshotNode
                runFill.enabled = true
            )
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh and big brick mesh first!" title:"Temple Fill"
        )
    )
)

createDialog voxelFillMultiModeUI width:520 height:460