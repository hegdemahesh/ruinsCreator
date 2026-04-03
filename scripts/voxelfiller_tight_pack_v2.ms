try(destroyDialog voxelFillTightV2UI)catch()

rollout voxelFillTightV2UI "Temple Voxel Fill Tool (Tight Pack V2)"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"

    groupBox packingGroup "Packing" width:230 height:72
    spinner subCellDivisorSpinner "Subcell Divisor" range:[1,2,4] type:#integer fieldwidth:48
    label packHint "2 = tighter pack, 1 = faster" width:200

    groupBox lookGroup "Look" width:230 height:52
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48

    groupBox debugGroup "Debug" width:230 height:72
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Placed Cells" checked:false

    button runFill "Run Tight Pack V2"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillTightV2] %\n" messageText
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

    fn createTempleSnapshot temple =
    (
        local snapshotNode = undefined

        try
        (
            snapshotNode = snapshot temple
            if snapshotNode != undefined do
            (
                snapshotNode.name = uniqueName "TightPackV2RaycastTarget"
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

    fn makeGridKey x y z =
    (
        (x as string) + "|" + (y as string) + "|" + (z as string)
    )

    fn setHashTrue hashTable key =
    (
        if not hashTable.ContainsKey key do hashTable.Add key true
    )

    fn hashHasKey hashTable key =
    (
        hashTable.ContainsKey key
    )

    fn updateProgress processed totalSteps createdCount =
    (
        local progressValue = if totalSteps > 0 then ((processed as float / totalSteps as float) * 100.0) else 0.0
        fillProgress.value = amin 100 (progressValue as integer)
        fillStatus.text = ("Steps: " + processed as string + " / " + totalSteps as string + " | Bricks: " + createdCount as string)
        windows.processPostedMessages()
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
            local rayOrigin = p - (dir * padding)
            local maxDistance = distance rayOrigin p
            local hitCount = countRayHitsToDistance obj rayOrigin dir maxDistance
            if (mod hitCount 2) == 1 do insideVotes += 1
        )

        insideVotes >= voteThreshold
    )

    fn getBoundsSamplePoints regionMin regionMax =
    (
        local center = (regionMin + regionMax) * 0.5
        local halfX = (regionMax.x - regionMin.x) * 0.5
        local halfY = (regionMax.y - regionMin.y) * 0.5
        local halfZ = (regionMax.z - regionMin.z) * 0.5

        #(
            center,
            center + [halfX, 0, 0],
            center + [-halfX, 0, 0],
            center + [0, halfY, 0],
            center + [0, -halfY, 0],
            center + [0, 0, halfZ],
            center + [0, 0, -halfZ],
            regionMin,
            [regionMax.x, regionMin.y, regionMin.z],
            [regionMin.x, regionMax.y, regionMin.z],
            [regionMin.x, regionMin.y, regionMax.z],
            [regionMax.x, regionMax.y, regionMin.z],
            [regionMax.x, regionMin.y, regionMax.z],
            [regionMin.x, regionMax.y, regionMax.z],
            regionMax
        )
    )

    fn classifyRegionInside regionMin regionMax raycastTarget templeBounds =
    (
        local samplePoints = getBoundsSamplePoints regionMin regionMax

        for samplePoint in samplePoints do
        (
            if not (evaluatePointInMesh samplePoint raycastTarget templeBounds) do return false
        )

        true
    )

    fn getSubCellSize bigSize mediumSize divisor =
    (
        [mediumSize.x / divisor, mediumSize.y / divisor, mediumSize.z / divisor]
    )

    fn getGridCounts templeBounds baseCellSize =
    (
        #(
            amax 1 ((ceil ((templeBounds[2].x - templeBounds[1].x) / baseCellSize.x)) as integer),
            amax 1 ((ceil ((templeBounds[2].y - templeBounds[1].y) / baseCellSize.y)) as integer),
            amax 1 ((ceil ((templeBounds[2].z - templeBounds[1].z) / baseCellSize.z)) as integer)
        )
    )

    fn getFootprintCounts brickSize baseCellSize =
    (
        #(
            amax 1 ((ceil (brickSize.x / baseCellSize.x)) as integer),
            amax 1 ((ceil (brickSize.y / baseCellSize.y)) as integer),
            amax 1 ((ceil (brickSize.z / baseCellSize.z)) as integer)
        )
    )

    fn getRegionMinFromGrid x y z gridOrigin baseCellSize =
    (
        [gridOrigin.x + (x * baseCellSize.x), gridOrigin.y + (y * baseCellSize.y), gridOrigin.z + (z * baseCellSize.z)]
    )

    fn getRegionCenter regionMin regionSize =
    (
        regionMin + (regionSize * 0.5)
    )

    fn getCellRangeForRegion regionMin regionMax gridOrigin baseCellSize =
    (
        local minX = amax 0 ((floor ((regionMin.x - gridOrigin.x) / baseCellSize.x)) as integer)
        local minY = amax 0 ((floor ((regionMin.y - gridOrigin.y) / baseCellSize.y)) as integer)
        local minZ = amax 0 ((floor ((regionMin.z - gridOrigin.z) / baseCellSize.z)) as integer)
        local maxX = ((ceil ((regionMax.x - gridOrigin.x) / baseCellSize.x)) as integer) - 1
        local maxY = ((ceil ((regionMax.y - gridOrigin.y) / baseCellSize.y)) as integer) - 1
        local maxZ = ((ceil ((regionMax.z - gridOrigin.z) / baseCellSize.z)) as integer) - 1

        #(#(minX, minY, minZ), #(maxX, maxY, maxZ))
    )

    fn regionFitsInGrid cellRange gridCounts =
    (
        cellRange[1][1] >= 0 and cellRange[1][2] >= 0 and cellRange[1][3] >= 0 and cellRange[2][1] < gridCounts[1] and cellRange[2][2] < gridCounts[2] and cellRange[2][3] < gridCounts[3]
    )

    fn regionIsFree cellRange occupiedCells =
    (
        for x = cellRange[1][1] to cellRange[2][1] do
        (
            for y = cellRange[1][2] to cellRange[2][2] do
            (
                for z = cellRange[1][3] to cellRange[2][3] do
                (
                    if hashHasKey occupiedCells (makeGridKey x y z) do return false
                )
            )
        )

        true
    )

    fn markRegionOccupied cellRange occupiedCells =
    (
        for x = cellRange[1][1] to cellRange[2][1] do
        (
            for y = cellRange[1][2] to cellRange[2][2] do
            (
                for z = cellRange[1][3] to cellRange[2][3] do
                (
                    setHashTrue occupiedCells (makeGridKey x y z)
                )
            )
        )
    )

    fn createPlacementRecord brickType position =
    (
        #(brickType, position)
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

    fn instantiatePlacement placementRecord bigBrick mediumBrick =
    (
        local sourceBrick = if placementRecord[1] == #big then bigBrick else mediumBrick
        local newBrick = instance sourceBrick
        newBrick.position = placementRecord[2]
        newBrick.rotation = sourceBrick.rotation
        newBrick.scale = sourceBrick.scale

        if materialVariationCheck.checked then
        (
            applyMaterialVariation newBrick sourceBrick.material materialTintSpinner.value
        )
        else
        (
            newBrick.material = sourceBrick.material
        )
    )

    fn getOffsetCandidates subCellSize =
    (
        #(
            [0,0,0],
            [subCellSize.x * 0.5, 0, 0],
            [0, subCellSize.y * 0.5, 0],
            [0, 0, subCellSize.z * 0.5],
            [subCellSize.x * 0.5, subCellSize.y * 0.5, 0],
            [subCellSize.x * 0.5, 0, subCellSize.z * 0.5]
        )
    )

    fn estimateTotalSteps gridCounts offsetCount =
    (
        (gridCounts[1] * gridCounts[2] * gridCounts[3] * 2 * offsetCount) as integer
    )

    fn validatePackingWorkload gridCounts totalSteps =
    (
        local totalCells = gridCounts[1] * gridCounts[2] * gridCounts[3]

        if totalCells > 400000 then
        (
            local warningMessage = "Subcell grid is too dense for interactive packing. Cells=" + totalCells as string + ". Lower the subcell divisor or simplify the mesh bounds."
            debugLog warningMessage
            messageBox warningMessage title:"Tight Pack V2"
            return false
        )

        if totalSteps > 4000000 then
        (
            local warningMessage = "Estimated checks are too high: " + totalSteps as string + ". Lower the subcell divisor or use larger bricks."
            debugLog warningMessage
            messageBox warningMessage title:"Tight Pack V2"
            return false
        )

        true
    )

    fn chooseBetterPlan bestPlan candidatePlan bigSize mediumSize =
    (
        local bestScore = (bestPlan[3] * (bigSize.x * bigSize.y * bigSize.z)) + (bestPlan[4] * (mediumSize.x * mediumSize.y * mediumSize.z))
        local candidateScore = (candidatePlan[3] * (bigSize.x * bigSize.y * bigSize.z)) + (candidatePlan[4] * (mediumSize.x * mediumSize.y * mediumSize.z))

        if candidateScore > bestScore then true else if candidateScore < bestScore then false else candidatePlan[2] > bestPlan[2]
    )

    fn buildPackingPlan offset gridMin gridCounts subCellSize raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps processedStart =
    (
        local occupiedCells = dotNetObject "System.Collections.Hashtable"
        local placements = #()
        local processed = processedStart
        local bigCreated = 0
        local mediumCreated = 0
        local gridOrigin = gridMin + offset
        local bigCandidatesX = amax 0 (gridCounts[1] - 1)
        local bigCandidatesY = amax 0 (gridCounts[2] - 1)
        local bigCandidatesZ = amax 0 (gridCounts[3] - 1)

        debugLog ("Offset plan start: offset=" + offset as string)

        for x = 0 to bigCandidatesX while not fillCancelled do
        (
            for y = 0 to bigCandidatesY while not fillCancelled do
            (
                for z = 0 to bigCandidatesZ while not fillCancelled do
                (
                    local regionMin = getRegionMinFromGrid x y z gridOrigin subCellSize
                    local regionMax = regionMin + bigSize
                    local cellRange = getCellRangeForRegion regionMin regionMax gridOrigin subCellSize

                    processed += 1

                    if regionFitsInGrid cellRange gridCounts and regionIsFree cellRange occupiedCells and classifyRegionInside regionMin regionMax raycastTarget templeBounds then
                    (
                        append placements (createPlacementRecord #big (getRegionCenter regionMin bigSize))
                        markRegionOccupied cellRange occupiedCells
                        bigCreated += 1
                        if debugSamplesCheck.checked do debugLog ("Placed big at offset cell " + #(x, y, z) as string + " offset=" + offset as string)
                    )

                    if (mod processed 100) == 0 or processed == totalSteps do updateProgress processed totalSteps (bigCreated + mediumCreated)
                )
            )
        )

        for x = 0 to (gridCounts[1] - 1) while not fillCancelled do
        (
            for y = 0 to (gridCounts[2] - 1) while not fillCancelled do
            (
                for z = 0 to (gridCounts[3] - 1) while not fillCancelled do
                (
                    local regionMin = getRegionMinFromGrid x y z gridOrigin subCellSize
                    local regionMax = regionMin + mediumSize
                    local cellRange = getCellRangeForRegion regionMin regionMax gridOrigin subCellSize

                    processed += 1

                    if regionFitsInGrid cellRange gridCounts and regionIsFree cellRange occupiedCells and classifyRegionInside regionMin regionMax raycastTarget templeBounds then
                    (
                        append placements (createPlacementRecord #medium (getRegionCenter regionMin mediumSize))
                        markRegionOccupied cellRange occupiedCells
                        mediumCreated += 1
                        if debugSamplesCheck.checked do debugLog ("Placed medium at offset cell " + #(x, y, z) as string + " offset=" + offset as string)
                    )

                    if (mod processed 100) == 0 or processed == totalSteps do updateProgress processed totalSteps (bigCreated + mediumCreated)
                )
            )
        )

        debugLog ("Offset plan end: offset=" + offset as string + " big=" + bigCreated as string + " medium=" + mediumCreated as string + " total=" + placements.count as string)
        #(placements, placements.count, bigCreated, mediumCreated, processed)
    )

    fn runTightPackV2 temple raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps divisor =
    (
        local subCellSize = getSubCellSize bigSize mediumSize divisor
        local gridCounts = getGridCounts templeBounds subCellSize
        local offsets = getOffsetCandidates subCellSize
        local bestPlan = undefined
        local processed = 0

        debugLog ("Subcell size=" + subCellSize as string + " grid counts=" + gridCounts as string + " offsets=" + offsets.count as string)

        for offset in offsets while not fillCancelled do
        (
            local plan = buildPackingPlan offset templeBounds[1] gridCounts subCellSize raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps processed
            processed = plan[5]

            if bestPlan == undefined or chooseBetterPlan bestPlan plan bigSize mediumSize do bestPlan = plan
        )

        if bestPlan != undefined then
        (
            for placementRecord in bestPlan[1] while not fillCancelled do instantiatePlacement placementRecord bigBrick mediumBrick
            #(bestPlan[2], processed, bestPlan[3], bestPlan[4])
        )
        else
        (
            #(0, processed, 0, 0)
        )
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
        if templeMesh != undefined and bigBrick != undefined and mediumBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local bigSize = getBrickSize bigBrick
            local mediumSize = getBrickSize mediumBrick
            local divisor = amax 1 subCellDivisorSpinner.value
            local subCellSize = getSubCellSize bigSize mediumSize divisor
            local gridCounts = getGridCounts templeBounds subCellSize
            local totalSteps = estimateTotalSteps gridCounts (getOffsetCandidates subCellSize).count
            local snapshotNode = createTempleSnapshot templeMesh

            if snapshotNode == undefined then
            (
                messageBox "Unable to snapshot the temple mesh."
                resetProgressState "Idle"
            )
            else if not (validatePackingWorkload gridCounts totalSteps) then
            (
                deleteSnapshot snapshotNode
                resetProgressState "Idle"
            )
            else
            (
                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Running tight pack v2..."

                debugLog "----- Tight Pack V2 Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Estimated steps=" + totalSteps as string + " bigSize=" + bigSize as string + " mediumSize=" + mediumSize as string + " divisor=" + divisor as string)

                local fillResult = runTightPackV2 templeMesh snapshotNode templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps divisor
                updateProgress fillResult[2] totalSteps fillResult[1]
                fillStatus.text = ("Fill complete. Total=" + fillResult[1] as string + " Big=" + fillResult[3] as string + " Medium=" + fillResult[4] as string)

                debugLog ("Fill complete. Total=" + fillResult[1] as string + " big=" + fillResult[3] as string + " medium=" + fillResult[4] as string + " processed=" + fillResult[2] as string)
                debugLog "----- Tight Pack V2 End -----"

                deleteSnapshot snapshotNode
                runFill.enabled = true
            )
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh, big brick mesh, and medium brick mesh first!"
        )
    )
)

createDialog voxelFillTightV2UI width:380 height:430