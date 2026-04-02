rollout voxelFillHybridUI "Temple Voxel Fill Tool (Hybrid)"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"

    groupBox variationGroup "Variation" width:210 height:144
    checkbox randomRotationCheck "Random Z Rotation" checked:true
    spinner rotMinSpinner "Min Rot" range:[0,0,360] type:#integer fieldwidth:48
    spinner rotMaxSpinner "Max Rot" range:[0,180,360] type:#integer fieldwidth:48
    checkbox randomScaleCheck "Random Scale %" checked:false
    spinner scaleMinSpinner "Min Scale" range:[10,90,300] type:#integer fieldwidth:48
    spinner scaleMaxSpinner "Max Scale" range:[10,110,300] type:#integer fieldwidth:48
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48

    groupBox debugGroup "Debug" width:210 height:72
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Sample Classifications" checked:false

    button runFill "Run Hybrid Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillHybrid] %\n" messageText
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
                snapshotNode.name = uniqueName "HybridRaycastTarget"
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
        local hitCounts = #()
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
            append hitCounts hitCount
            if (mod hitCount 2) == 1 do insideVotes += 1
        )

        #((insideVotes >= voteThreshold), insideVotes, voteThreshold, hitCounts)
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

    fn getPlacementBounds placementPosition brickSize placementVariation =
    (
        local envelopeSize = getPlacementEnvelopeSize brickSize placementVariation
        local halfSize = envelopeSize * 0.5
        #(placementPosition - halfSize, placementPosition + halfSize)
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

    fn boundsInsideRegion boundsToCheck regionMin regionMax =
    (
        boundsToCheck[1].x >= regionMin.x and boundsToCheck[1].y >= regionMin.y and boundsToCheck[1].z >= regionMin.z and boundsToCheck[2].x <= regionMax.x and boundsToCheck[2].y <= regionMax.y and boundsToCheck[2].z <= regionMax.z
    )

    fn classifyBounds regionMin regionMax raycastTarget templeBounds =
    (
        local samplePoints = getBoundsSamplePoints regionMin regionMax
        local insideCount = 0
        local outsideCount = 0
        local sampleTotal = samplePoints.count

        for samplePoint in samplePoints do
        (
            local pointResult = evaluatePointInMesh samplePoint raycastTarget templeBounds
            if pointResult[1] then insideCount += 1 else outsideCount += 1
        )

        if insideCount == sampleTotal then
        (
            #(#inside, insideCount, outsideCount)
        )
        else if outsideCount == sampleTotal then
        (
            #(#outside, insideCount, outsideCount)
        )
        else
        (
            #(#boundary, insideCount, outsideCount)
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

    fn getAxisSampleCount axisMin axisMax stepSize =
    (
        amax 1 ((ceil ((axisMax - axisMin) / stepSize)) as integer)
    )

    fn estimateTotalSteps templeBounds bigSize mediumSize =
    (
        local bigCounts = #(
            getAxisSampleCount templeBounds[1].x templeBounds[2].x bigSize.x,
            getAxisSampleCount templeBounds[1].y templeBounds[2].y bigSize.y,
            getAxisSampleCount templeBounds[1].z templeBounds[2].z bigSize.z
        )
        local bigSteps = bigCounts[1] * bigCounts[2] * bigCounts[3]
        local refineFactor = amax 1 (((bigSize.x / mediumSize.x) as integer) * ((bigSize.y / mediumSize.y) as integer) * ((bigSize.z / mediumSize.z) as integer))

        bigSteps + (bigSteps * refineFactor)
    )

    fn fillHybrid temple raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps =
    (
        local boundaryCells = #()
        local mediumOccupied = dotNetObject "System.Collections.Hashtable"
        local processed = 0
        local created = 0

        local bigCountX = getAxisSampleCount templeBounds[1].x templeBounds[2].x bigSize.x
        local bigCountY = getAxisSampleCount templeBounds[1].y templeBounds[2].y bigSize.y
        local bigCountZ = getAxisSampleCount templeBounds[1].z templeBounds[2].z bigSize.z

        debugLog ("Large pass start: counts=" + #(bigCountX, bigCountY, bigCountZ) as string + " bigSize=" + bigSize as string)

        for xIndex = 0 to (bigCountX - 1) while not fillCancelled do
        (
            local coarseCenterX = templeBounds[1].x + ((xIndex as float + 0.5) * bigSize.x)

            for yIndex = 0 to (bigCountY - 1) while not fillCancelled do
            (
                local coarseCenterY = templeBounds[1].y + ((yIndex as float + 0.5) * bigSize.y)

                for zIndex = 0 to (bigCountZ - 1) while not fillCancelled do
                (
                    local coarseCenterZ = templeBounds[1].z + ((zIndex as float + 0.5) * bigSize.z)
                    local coarseCenter = [coarseCenterX, coarseCenterY, coarseCenterZ]
                    local coarseRegionMin = coarseCenter - (bigSize * 0.5)
                    local coarseRegionMax = coarseCenter + (bigSize * 0.5)
                    local placementVariation = getPlacementVariation()
                    local placementBounds = getPlacementBounds coarseCenter bigSize placementVariation
                    local classification = undefined

                    processed += 1

                    if boundsInsideRegion placementBounds coarseRegionMin coarseRegionMax then
                    (
                        classification = classifyBounds placementBounds[1] placementBounds[2] raycastTarget templeBounds

                        if debugSamplesCheck.checked and classification[1] != #outside do debugLog ("Large sample " + #(xIndex, yIndex, zIndex) as string + " state=" + classification[1] as string + " in=" + classification[2] as string + " out=" + classification[3] as string)

                        case classification[1] of
                        (
                            #inside:
                            (
                                local newBrick = instance bigBrick
                                newBrick.position = coarseCenter
                                applyPlacementVariation newBrick bigBrick placementVariation
                                created += 1
                            )
                            #boundary:
                            (
                                append boundaryCells #(coarseRegionMin, coarseRegionMax)
                            )
                            default:
                            (
                            )
                        )
                    )
                    else
                    (
                        append boundaryCells #(coarseRegionMin, coarseRegionMax)
                    )

                    if (mod processed 50) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

        debugLog ("Large pass end: created=" + created as string + " boundary cells=" + boundaryCells.count as string + " processed=" + processed as string)

        if mediumBrick != undefined then
        (
            debugLog ("Medium pass start: boundary cells=" + boundaryCells.count as string + " mediumSize=" + mediumSize as string)

            for boundaryCell in boundaryCells while not fillCancelled do
            (
                local regionMin = boundaryCell[1]
                local regionMax = boundaryCell[2]
                local mediumCountX = getAxisSampleCount regionMin.x regionMax.x mediumSize.x
                local mediumCountY = getAxisSampleCount regionMin.y regionMax.y mediumSize.y
                local mediumCountZ = getAxisSampleCount regionMin.z regionMax.z mediumSize.z

                for xIndex = 0 to (mediumCountX - 1) while not fillCancelled do
                (
                    local mediumCenterX = regionMin.x + ((xIndex as float + 0.5) * mediumSize.x)

                    for yIndex = 0 to (mediumCountY - 1) while not fillCancelled do
                    (
                        local mediumCenterY = regionMin.y + ((yIndex as float + 0.5) * mediumSize.y)

                        for zIndex = 0 to (mediumCountZ - 1) while not fillCancelled do
                        (
                            local mediumCenterZ = regionMin.z + ((zIndex as float + 0.5) * mediumSize.z)
                            local placementCenter = [mediumCenterX, mediumCenterY, mediumCenterZ]
                            local mediumPlacementVariation = getPlacementVariation()
                            local mediumPlacementBounds = getPlacementBounds placementCenter mediumSize mediumPlacementVariation
                            local mediumKey = makeGridKey (floor ((placementCenter.x - templeBounds[1].x) / mediumSize.x)) (floor ((placementCenter.y - templeBounds[1].y) / mediumSize.y)) (floor ((placementCenter.z - templeBounds[1].z) / mediumSize.z))

                            processed += 1

                            if not (hashHasKey mediumOccupied mediumKey) and boundsInsideRegion mediumPlacementBounds regionMin regionMax then
                            (
                                local mediumClassification = classifyBounds mediumPlacementBounds[1] mediumPlacementBounds[2] raycastTarget templeBounds

                                if debugSamplesCheck.checked and mediumClassification[1] == #inside do debugLog ("Medium sample " + mediumKey + " state=" + mediumClassification[1] as string)

                                if mediumClassification[1] == #inside then
                                (
                                    local newMediumBrick = instance mediumBrick
                                    newMediumBrick.position = placementCenter
                                    applyPlacementVariation newMediumBrick mediumBrick mediumPlacementVariation
                                    setHashTrue mediumOccupied mediumKey
                                    created += 1
                                )
                            )

                            if (mod processed 50) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                        )
                    )
                )
            )
        )

        debugLog ("Medium pass end: created=" + created as string + " processed=" + processed as string)
        #(created, processed, boundaryCells.count)
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
            local totalSteps = estimateTotalSteps templeBounds bigSize mediumSize
            local snapshotNode = createTempleSnapshot templeMesh

            if snapshotNode == undefined then
            (
                messageBox "Unable to snapshot the temple mesh."
                resetProgressState "Idle"
            )
            else
            (
                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Running hybrid fill..."

                debugLog "----- Hybrid Fill Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Estimated steps=" + totalSteps as string + " bigSize=" + bigSize as string + " mediumSize=" + mediumSize as string)

                local fillResult = fillHybrid templeMesh snapshotNode templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps
                updateProgress fillResult[2] totalSteps fillResult[1]
                fillStatus.text = ("Fill complete. Created " + fillResult[1] as string + " bricks. Boundary cells: " + fillResult[3] as string)

                debugLog ("Fill complete. Created=" + fillResult[1] as string + " boundary cells=" + fillResult[3] as string + " processed=" + fillResult[2] as string)
                debugLog "----- Hybrid Fill End -----"

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

createDialog voxelFillHybridUI width:340 height:560