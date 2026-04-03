try(destroyDialog voxelFillTightUI)catch()

rollout voxelFillTightUI "Temple Voxel Fill Tool (Tight Pack)"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"

    groupBox lookGroup "Look" width:220 height:70
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48
    label packNote "Tight pack keeps fixed scale/rotation." width:200

    groupBox debugGroup "Debug" width:220 height:72
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Accepted Cells" checked:false

    button runFill "Run Tight Pack Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillTight] %\n" messageText
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
                snapshotNode.name = uniqueName "TightPackRaycastTarget"
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

    fn getRegionMinFromGrid x y z gridMin baseCellSize =
    (
        [gridMin.x + (x * baseCellSize.x), gridMin.y + (y * baseCellSize.y), gridMin.z + (z * baseCellSize.z)]
    )

    fn getRegionMaxFromGrid x y z footprintCounts gridMin baseCellSize =
    (
        [gridMin.x + ((x + footprintCounts[1]) * baseCellSize.x), gridMin.y + ((y + footprintCounts[2]) * baseCellSize.y), gridMin.z + ((z + footprintCounts[3]) * baseCellSize.z)]
    )

    fn footprintFits x y z footprintCounts gridCounts occupiedCells =
    (
        local maxX = x + footprintCounts[1] - 1
        local maxY = y + footprintCounts[2] - 1
        local maxZ = z + footprintCounts[3] - 1

        if maxX >= gridCounts[1] or maxY >= gridCounts[2] or maxZ >= gridCounts[3] then return false

        for ix = x to maxX do
        (
            for iy = y to maxY do
            (
                for iz = z to maxZ do
                (
                    if hashHasKey occupiedCells (makeGridKey ix iy iz) do return false
                )
            )
        )

        true
    )

    fn markOccupied x y z footprintCounts occupiedCells =
    (
        for ix = x to (x + footprintCounts[1] - 1) do
        (
            for iy = y to (y + footprintCounts[2] - 1) do
            (
                for iz = z to (z + footprintCounts[3] - 1) do
                (
                    setHashTrue occupiedCells (makeGridKey ix iy iz)
                )
            )
        )
    )

    fn getRegionCenter regionMin regionMax =
    (
        (regionMin + regionMax) * 0.5
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

    fn applyPackedPlacement newBrick sourceBrick =
    (
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

    fn estimateTotalSteps gridCounts bigFootprint =
    (
        local bigCandidates = amax 1 ((gridCounts[1] - bigFootprint[1] + 1) * (gridCounts[2] - bigFootprint[2] + 1) * (gridCounts[3] - bigFootprint[3] + 1))
        local mediumCandidates = gridCounts[1] * gridCounts[2] * gridCounts[3]
        bigCandidates + mediumCandidates
    )

    fn validatePackingWorkload gridCounts totalSteps =
    (
        local totalCells = gridCounts[1] * gridCounts[2] * gridCounts[3]

        if totalCells > 300000 then
        (
            local warningMessage = "Base grid is too dense for interactive packing. Cells=" + totalCells as string + ". Use a larger medium brick or simplify the bounds."
            debugLog warningMessage
            messageBox warningMessage title:"Tight Pack Fill"
            return false
        )

        if totalSteps > 3000000 then
        (
            local warningMessage = "Estimated packing checks are too high: " + totalSteps as string + ". Use larger bricks or a smaller temple volume."
            debugLog warningMessage
            messageBox warningMessage title:"Tight Pack Fill"
            return false
        )

        true
    )

    fn runTightPack temple raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps =
    (
        local occupiedCells = dotNetObject "System.Collections.Hashtable"
        local created = 0
        local processed = 0
        local bigCreated = 0
        local mediumCreated = 0
        local gridMin = templeBounds[1]
        local gridCounts = getGridCounts templeBounds mediumSize
        local bigFootprint = getFootprintCounts bigSize mediumSize

        debugLog ("Packing grid counts=" + gridCounts as string + " big footprint=" + bigFootprint as string + " base cell=" + mediumSize as string)
        debugLog "Big pass start"

        for x = 0 to (gridCounts[1] - bigFootprint[1]) while not fillCancelled do
        (
            for y = 0 to (gridCounts[2] - bigFootprint[2]) while not fillCancelled do
            (
                for z = 0 to (gridCounts[3] - bigFootprint[3]) while not fillCancelled do
                (
                    processed += 1

                    if footprintFits x y z bigFootprint gridCounts occupiedCells then
                    (
                        local regionMin = getRegionMinFromGrid x y z gridMin mediumSize
                        local regionMax = getRegionMaxFromGrid x y z bigFootprint gridMin mediumSize

                        if classifyRegionInside regionMin regionMax raycastTarget templeBounds then
                        (
                            local newBrick = instance bigBrick
                            newBrick.position = getRegionCenter regionMin regionMax
                            applyPackedPlacement newBrick bigBrick
                            markOccupied x y z bigFootprint occupiedCells
                            created += 1
                            bigCreated += 1

                            if debugSamplesCheck.checked do debugLog ("Placed big at cell " + #(x, y, z) as string)
                        )
                    )

                    if (mod processed 100) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

        debugLog ("Big pass end: created=" + bigCreated as string + " occupied=" + occupiedCells.Count as string + " processed=" + processed as string)
        debugLog "Medium pass start"

        for x = 0 to (gridCounts[1] - 1) while not fillCancelled do
        (
            for y = 0 to (gridCounts[2] - 1) while not fillCancelled do
            (
                for z = 0 to (gridCounts[3] - 1) while not fillCancelled do
                (
                    processed += 1

                    if not (hashHasKey occupiedCells (makeGridKey x y z)) then
                    (
                        local regionMin = getRegionMinFromGrid x y z gridMin mediumSize
                        local regionMax = getRegionMaxFromGrid x y z #(1,1,1) gridMin mediumSize

                        if classifyRegionInside regionMin regionMax raycastTarget templeBounds then
                        (
                            local newMediumBrick = instance mediumBrick
                            newMediumBrick.position = getRegionCenter regionMin regionMax
                            applyPackedPlacement newMediumBrick mediumBrick
                            markOccupied x y z #(1,1,1) occupiedCells
                            created += 1
                            mediumCreated += 1

                            if debugSamplesCheck.checked do debugLog ("Placed medium at cell " + #(x, y, z) as string)
                        )
                    )

                    if (mod processed 100) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

        debugLog ("Medium pass end: created=" + mediumCreated as string + " occupied=" + occupiedCells.Count as string + " processed=" + processed as string)
        #(created, processed, bigCreated, mediumCreated)
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
            local gridCounts = getGridCounts templeBounds mediumSize
            local bigFootprint = getFootprintCounts bigSize mediumSize
            local totalSteps = estimateTotalSteps gridCounts bigFootprint
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
                resetProgressState "Running tight pack fill..."

                debugLog "----- Tight Pack Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Estimated steps=" + totalSteps as string + " bigSize=" + bigSize as string + " mediumSize=" + mediumSize as string)

                local fillResult = runTightPack templeMesh snapshotNode templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps
                updateProgress fillResult[2] totalSteps fillResult[1]
                fillStatus.text = ("Fill complete. Total=" + fillResult[1] as string + " Big=" + fillResult[3] as string + " Medium=" + fillResult[4] as string)

                debugLog ("Fill complete. Total=" + fillResult[1] as string + " big=" + fillResult[3] as string + " medium=" + fillResult[4] as string + " processed=" + fillResult[2] as string)
                debugLog "----- Tight Pack End -----"

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

createDialog voxelFillTightUI width:360 height:420