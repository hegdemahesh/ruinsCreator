try(destroyDialog voxelFillTempleSliceUI)catch()

rollout voxelFillTempleSliceUI "Temple Slice Fill Tool"
(
    local templeMesh
    local primaryBrick
    local secondaryBrick
    local fillCancelled = false
    local placementDebugLogsRemaining = 0
    local rayDebugLogsRemaining = 0
    local rejectionDebugLogsRemaining = 0
    local internalRayStartPadding = 0.03
    local internalSurfaceSampleInset = 0.02

    button pickTemple "Pick Temple Mesh"
    button pickPrimaryBrick "Pick Primary Brick"
    button pickSecondaryBrick "Pick Secondary Brick"

    groupBox optionsGroup "Slice Options" width:340 height:88
    spinner secondaryCountSpinner "Secondary Blocks" range:[0,5000,200] type:#integer fieldwidth:70
    spinner supportSearchSpinner "Secondary Attempts x" range:[1,100,24] type:#integer fieldwidth:70
    checkbox centerTemplatePivotCheck "Center Template Pivot" checked:true

    groupBox debugGroup "Debug" width:340 height:88
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Placement Samples" checked:false

    button runFill "Run Slice Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[TempleSliceFill] %\n" messageText
    )

    fn debugBounds prefix boundsValue =
    (
        debugLog (prefix + " min=" + boundsValue[1] as string + " max=" + boundsValue[2] as string)
    )

    fn setHashValue hashTable key value =
    (
        if not hashTable.ContainsKey key then hashTable.Add key value
    )

    fn hashHasKey hashTable key =
    (
        hashTable.ContainsKey key
    )

    fn getTempleBounds temple =
    (
        nodeGetBoundingBox temple (matrix3 1)
    )

    fn getBrickBounds brickObj =
    (
        nodeGetBoundingBox brickObj (matrix3 1)
    )

    fn getBrickSize brickObj =
    (
        local boundsValue = getBrickBounds brickObj
        boundsValue[2] - boundsValue[1]
    )

    fn getBrickCenter brickObj =
    (
        local boundsValue = getBrickBounds brickObj
        (boundsValue[1] + boundsValue[2]) * 0.5
    )

    fn getBrickCenterOffset brickObj =
    (
        getBrickCenter brickObj - brickObj.position
    )

    fn getCenteredCornerOffsets brickObj =
    (
        local boundsValue = getBrickBounds brickObj
        local centerPoint = (boundsValue[1] + boundsValue[2]) * 0.5

        #(
            [boundsValue[1].x, boundsValue[1].y, boundsValue[1].z] - centerPoint,
            [boundsValue[2].x, boundsValue[1].y, boundsValue[1].z] - centerPoint,
            [boundsValue[1].x, boundsValue[2].y, boundsValue[1].z] - centerPoint,
            [boundsValue[2].x, boundsValue[2].y, boundsValue[1].z] - centerPoint,
            [boundsValue[1].x, boundsValue[1].y, boundsValue[2].z] - centerPoint,
            [boundsValue[2].x, boundsValue[1].y, boundsValue[2].z] - centerPoint,
            [boundsValue[1].x, boundsValue[2].y, boundsValue[2].z] - centerPoint,
            [boundsValue[2].x, boundsValue[2].y, boundsValue[2].z] - centerPoint
        )
    )

    fn expandBounds boundsValue paddingAmount =
    (
        local paddingVector = [paddingAmount, paddingAmount, paddingAmount]
        #(boundsValue[1] - paddingVector, boundsValue[2] + paddingVector)
    )

    fn getRayStartBounds templeBounds =
    (
        expandBounds templeBounds internalRayStartPadding
    )

    fn getOrientedSize baseSize yawAngle =
    (
        local normalizedYaw = mod ((abs yawAngle) as integer) 180

        if normalizedYaw == 90 then [baseSize.y, baseSize.x, baseSize.z] else baseSize
    )

    fn rotateVectorAroundZ sourceVector yawAngle =
    (
        local cosValue = cos yawAngle
        local sinValue = sin yawAngle

        [(sourceVector.x * cosValue) - (sourceVector.y * sinValue), (sourceVector.x * sinValue) + (sourceVector.y * cosValue), sourceVector.z]
    )

    fn getRotatedBoundsFromCenter targetCenter cornerOffsets yawAngle =
    (
        local minPoint = [1e9, 1e9, 1e9]
        local maxPoint = [-1e9, -1e9, -1e9]

        for cornerOffset in cornerOffsets do
        (
            local rotatedCorner = targetCenter + (rotateVectorAroundZ cornerOffset yawAngle)
            minPoint = [amin minPoint.x rotatedCorner.x, amin minPoint.y rotatedCorner.y, amin minPoint.z rotatedCorner.z]
            maxPoint = [amax maxPoint.x rotatedCorner.x, amax maxPoint.y rotatedCorner.y, amax maxPoint.z rotatedCorner.z]
        )

        #(minPoint, maxPoint)
    )

    fn boundsOverlap boundsA boundsB tolerance:0.001 =
    (
        boundsA[1].x < (boundsB[2].x - tolerance) and boundsA[2].x > (boundsB[1].x + tolerance) and \
        boundsA[1].y < (boundsB[2].y - tolerance) and boundsA[2].y > (boundsB[1].y + tolerance) and \
        boundsA[1].z < (boundsB[2].z - tolerance) and boundsA[2].z > (boundsB[1].z + tolerance)
    )

    fn placementOverlaps targetBounds placedBounds =
    (
        for placedBoundsEntry in placedBounds do
        (
            if boundsOverlap targetBounds placedBoundsEntry do return true
        )

        false
    )

    fn makeOccupancyKey x y z =
    (
        (x as string) + "|" + (y as string) + "|" + (z as string)
    )

    fn getOccupancyCellIndex axisValue originValue cellSize =
    (
        (floor ((axisValue - originValue) / cellSize)) as integer
    )

    fn getOccupancyCellRange worldBounds occupancyOrigin occupancyCellSize =
    (
        local minPoint = worldBounds[1]
        local maxPoint = worldBounds[2] - [0.0001, 0.0001, 0.0001]

        #(
            #(
                getOccupancyCellIndex minPoint.x occupancyOrigin.x occupancyCellSize,
                getOccupancyCellIndex minPoint.y occupancyOrigin.y occupancyCellSize,
                getOccupancyCellIndex minPoint.z occupancyOrigin.z occupancyCellSize
            ),
            #(
                getOccupancyCellIndex maxPoint.x occupancyOrigin.x occupancyCellSize,
                getOccupancyCellIndex maxPoint.y occupancyOrigin.y occupancyCellSize,
                getOccupancyCellIndex maxPoint.z occupancyOrigin.z occupancyCellSize
            )
        )
    )

    fn boundsTouchOccupied worldBounds occupiedCells occupancyOrigin occupancyCellSize =
    (
        local cellRange = getOccupancyCellRange worldBounds occupancyOrigin occupancyCellSize

        for x = cellRange[1][1] to cellRange[2][1] do
        (
            for y = cellRange[1][2] to cellRange[2][2] do
            (
                for z = cellRange[1][3] to cellRange[2][3] do
                (
                    if hashHasKey occupiedCells (makeOccupancyKey x y z) do return true
                )
            )
        )

        false
    )

    fn markBoundsOccupied worldBounds occupiedCells occupancyOrigin occupancyCellSize =
    (
        local cellRange = getOccupancyCellRange worldBounds occupancyOrigin occupancyCellSize

        for x = cellRange[1][1] to cellRange[2][1] do
        (
            for y = cellRange[1][2] to cellRange[2][2] do
            (
                for z = cellRange[1][3] to cellRange[2][3] do
                (
                    setHashValue occupiedCells (makeOccupancyKey x y z) true
                )
            )
        )
    )

    fn updateProgress processed totalSteps createdCount =
    (
        local progressValue = if totalSteps > 0 then ((processed as float / totalSteps as float) * 100.0) else 0.0
        fillProgress.value = amin 100 (progressValue as integer)
        fillStatus.text = ("Steps: " + processed as string + " / " + totalSteps as string + " | Blocks: " + createdCount as string)
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
                snapshotNode.name = uniqueName "TempleSliceTarget"
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

    fn createPlacementTemplate sourceBrick prefixName =
    (
        local templateNode = undefined

        try
        (
            templateNode = copy sourceBrick
            if templateNode != undefined do
            (
                templateNode.name = uniqueName prefixName
                if centerTemplatePivotCheck.checked do try(CenterPivot templateNode)catch()
                templateNode.isHidden = true
                templateNode.boxMode = true
            )
        )
        catch
        (
            templateNode = undefined
        )

        templateNode
    )

    fn deleteNodeSafe targetNode =
    (
        if isValidNode targetNode do delete targetNode
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

    fn collectRayHits obj rayOrigin rayDir maxDistance maxHits:128 epsilon:0.5 =
    (
        local hitResults = #()
        local normalizedDir = normalize rayDir
        local sampleOrigin = rayOrigin
        local travelledDistance = 0.0
        local hit = intersectRay obj (ray sampleOrigin normalizedDir)

        while hit != undefined and hitResults.count < maxHits do
        (
            local hitDistance = distance sampleOrigin hit.pos
            local hitNormal = if isProperty hit #dir then (normalize hit.dir) else (if isProperty hit #norm then (normalize hit.norm) else (-normalizedDir))
            travelledDistance += hitDistance

            if travelledDistance > (maxDistance + epsilon) then exit

            append hitResults #(hit.pos, hitNormal, travelledDistance)
            sampleOrigin = hit.pos + (normalizedDir * epsilon)
            travelledDistance += epsilon
            hit = intersectRay obj (ray sampleOrigin normalizedDir)
        )

        hitResults
    )

    fn getFirstRayHit obj rayOrigin rayDir maxDistance =
    (
        local normalizedDir = normalize rayDir
        local hit = intersectRay obj (ray rayOrigin normalizedDir)

        if hit == undefined then return undefined

        local hitDistance = distance rayOrigin hit.pos
        if hitDistance > (maxDistance + 0.0001) then return undefined

        local hitNormal = if isProperty hit #dir then (normalize hit.dir) else (if isProperty hit #norm then (normalize hit.norm) else (-normalizedDir))
        #(hit.pos, hitNormal, hitDistance)
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
        local paddingAmount = (amax boundsSize.x (amax boundsSize.y boundsSize.z)) + 10.0

        for dir in directions do
        (
            local forwardOrigin = p - (dir * paddingAmount)
            local backwardOrigin = p + (dir * paddingAmount)
            local forwardDistance = distance forwardOrigin p
            local backwardDistance = distance backwardOrigin p
            local forwardHitCount = countRayHitsToDistance obj forwardOrigin dir forwardDistance
            local backwardHitCount = countRayHitsToDistance obj backwardOrigin (-dir) backwardDistance

            if ((mod forwardHitCount 2) == 1) or ((mod backwardHitCount 2) == 1) do insideVotes += 1
        )

        insideVotes >= voteThreshold
    )

    fn getBoundsSamplePoints regionMin regionMax =
    (
        local centerPoint = (regionMin + regionMax) * 0.5
        local halfX = (regionMax.x - regionMin.x) * 0.5
        local halfY = (regionMax.y - regionMin.y) * 0.5
        local halfZ = (regionMax.z - regionMin.z) * 0.5

        #(
            centerPoint,
            centerPoint + [halfX, 0, 0],
            centerPoint + [-halfX, 0, 0],
            centerPoint + [0, halfY, 0],
            centerPoint + [0, -halfY, 0],
            centerPoint + [0, 0, halfZ],
            centerPoint + [0, 0, -halfZ],
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

    fn getInsetBounds targetBounds insetAmount =
    (
        local sizeVector = targetBounds[2] - targetBounds[1]
        local insetX = amin insetAmount (amax 0.0 ((sizeVector.x * 0.5) - 0.0001))
        local insetY = amin insetAmount (amax 0.0 ((sizeVector.y * 0.5) - 0.0001))
        local insetZ = amin insetAmount (amax 0.0 ((sizeVector.z * 0.5) - 0.0001))
        local insetVector = [insetX, insetY, insetZ]

        #(targetBounds[1] + insetVector, targetBounds[2] - insetVector)
    )

    fn boundsFitInsideMesh targetBounds raycastTarget templeBounds =
    (
        local targetCenter = (targetBounds[1] + targetBounds[2]) * 0.5
        evaluatePointInMesh targetCenter raycastTarget templeBounds
    )

    fn getAxisSampleCount axisMin axisMax stepSize =
    (
        amax 1 ((ceil ((axisMax - axisMin) / stepSize)) as integer)
    )

    fn getAxisSamplePosition sampleIndex axisMin stepSize =
    (
        axisMin + ((sampleIndex as float + 0.5) * stepSize)
    )

    fn getHitAxisValue hitRecord axisName =
    (
        case axisName of
        (
            #x: hitRecord[1].x
            #y: hitRecord[1].y
            default: 0.0
        )
    )

    fn buildCenterPoint axisName crossValue alongValue zValue =
    (
        case axisName of
        (
            #x: [alongValue, crossValue, zValue]
            #y: [crossValue, alongValue, zValue]
            default: [0, 0, 0]
        )
    )

    fn logPlacementRejection targetCenter targetBounds rejectionReason =
    (
        if rejectionDebugLogsRemaining > 0 then
        (
            debugLog ("Rejected block center=" + targetCenter as string + " reason=" + rejectionReason)
            debugBounds "Rejected bounds" targetBounds
            rejectionDebugLogsRemaining -= 1
        )
    )

    fn getPlacementRejectionReason targetBounds raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds usePlacementChecks =
    (
        if usePlacementChecks then
        (
            if boundsTouchOccupied targetBounds occupiedCells occupancyOrigin occupancyCellSize then return #occupied
            if placementOverlaps targetBounds placedBounds then return #overlap
        )

        if not (boundsFitInsideMesh targetBounds raycastTarget templeBounds) then return #outside
        #ok
    )

    fn registerPlacedBlock newBrick targetBounds isPrimary occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds =
    (
        markBoundsOccupied targetBounds occupiedCells occupancyOrigin occupancyCellSize
        append placedBounds targetBounds
        if isPrimary do append primarySupportBounds targetBounds

        local placementId = "block|" + placedBounds.count as string
        local placementRecord = #(newBrick, targetBounds, isPrimary)
        append placedLookup #(placementId, placementRecord)
        placementId
    )

    fn createPlacedBrick sourceTemplate targetCenter yawAngle =
    (
        local newBrick = instance sourceTemplate
        local centerOffset = getBrickCenterOffset sourceTemplate
        local rotatedOffset = rotateVectorAroundZ centerOffset yawAngle

        newBrick.isHidden = false
        newBrick.boxMode = false
        newBrick.rotation = sourceTemplate.rotation
        if abs yawAngle > 0.001 do rotate newBrick (angleaxis yawAngle [0, 0, 1])
        newBrick.position = targetCenter - rotatedOffset
        newBrick.material = sourceTemplate.material
        newBrick
    )

    fn tryPlaceBlock sourceTemplate targetCenter yawAngle cornerOffsets raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds isPrimary =
    (
        local targetBounds = getRotatedBoundsFromCenter targetCenter cornerOffsets yawAngle
        local usePlacementChecks = not isPrimary
        local rejectionReason = getPlacementRejectionReason targetBounds raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds usePlacementChecks

        if rejectionReason == #ok then
        (
            local newBrick = createPlacedBrick sourceTemplate targetCenter yawAngle
            registerPlacedBlock newBrick targetBounds isPrimary occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds

            if debugSamplesCheck.checked and placementDebugLogsRemaining > 0 then
            (
                debugLog ("Placed block center=" + targetCenter as string + " yaw=" + yawAngle as string + " primary=" + isPrimary as string)
                debugBounds "Placed bounds" targetBounds
                placementDebugLogsRemaining -= 1
            )

            true
        )
        else
        (
            logPlacementRejection targetCenter targetBounds rejectionReason as string
            false
        )
    )

    fn placeSegmentBlocks axisName crossValue sliceZ entryHit exitHit sourceTemplate sourceSize cornerOffsets defaultYaw raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds =
    (
        local createdCount = 0
        local segmentStart = getHitAxisValue entryHit axisName
        local segmentEnd = getHitAxisValue exitHit axisName
        local axisLength = 0.0
        local halfLength = axisLength * 0.5
        local centerValues = #()

        case axisName of
        (
            #x: axisLength = sourceSize.x
            #y: axisLength = sourceSize.y
            default: axisLength = sourceSize.x
        )

        halfLength = axisLength * 0.5

        if segmentEnd <= segmentStart then return 0

        if (segmentEnd - segmentStart) <= axisLength then
        (
            append centerValues ((segmentStart + segmentEnd) * 0.5)
        )
        else
        (
            local centerValue = segmentStart + halfLength

            while centerValue <= ((segmentEnd - halfLength) + 0.0001) do
            (
                append centerValues centerValue
                centerValue += axisLength
            )

            if centerValues.count == 0 do append centerValues ((segmentStart + segmentEnd) * 0.5)
        )

        for index = 1 to centerValues.count do
        (
            local centerValue = centerValues[index]
            local currentYaw = defaultYaw

            local targetCenter = buildCenterPoint axisName crossValue centerValue sliceZ

            if tryPlaceBlock sourceTemplate targetCenter currentYaw cornerOffsets raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds true do createdCount += 1
        )

        createdCount
    )

    fn processAxisRays axisName fillBounds rayBounds sliceZ sourceTemplate sourceSize cornerOffsets defaultYaw raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds totalSteps processedCount createdCount =
    (
        local processed = processedCount
        local created = createdCount
        local forwardDir = if axisName == #x then [1, 0, 0] else [0, 1, 0]
        local backwardDir = -forwardDir
        local crossMin = if axisName == #x then fillBounds[1].y else fillBounds[1].x
        local crossMax = if axisName == #x then fillBounds[2].y else fillBounds[2].x
        local crossStep = if axisName == #x then sourceSize.y else sourceSize.x
        local rayLength = if axisName == #x then (rayBounds[2].x - rayBounds[1].x) else (rayBounds[2].y - rayBounds[1].y)
        local rayCount = getAxisSampleCount crossMin crossMax crossStep

        for rayIndex = 0 to (rayCount - 1) while not fillCancelled do
        (
            local crossValue = getAxisSamplePosition rayIndex crossMin crossStep
            local rayOriginForward = if axisName == #x then [rayBounds[1].x, crossValue, sliceZ] else [crossValue, rayBounds[1].y, sliceZ]
            local rayOriginBackward = if axisName == #x then [rayBounds[2].x, crossValue, sliceZ] else [crossValue, rayBounds[2].y, sliceZ]
            local firstHit = getFirstRayHit raycastTarget rayOriginForward forwardDir rayLength
            local lastHit = getFirstRayHit raycastTarget rayOriginBackward backwardDir rayLength
            local hitCount = 0

            if firstHit != undefined do hitCount += 1
            if lastHit != undefined do hitCount += 1

            if rayDebugLogsRemaining > 0 then
            (
                local firstHitText = if firstHit != undefined then firstHit[1] as string else "none"
                local lastHitText = if lastHit != undefined then lastHit[1] as string else "none"
                debugLog ("Ray axis=" + axisName as string + " sliceZ=" + sliceZ as string + " cross=" + crossValue as string + " hits=" + hitCount as string + " first=" + firstHitText + " last=" + lastHitText)
                rayDebugLogsRemaining -= 1
            )

            if firstHit != undefined and lastHit != undefined then
            (
                created += placeSegmentBlocks axisName crossValue sliceZ firstHit lastHit sourceTemplate sourceSize cornerOffsets defaultYaw raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds
            )

            processed += 1
            if (mod processed 10) == 0 or processed == totalSteps do updateProgress processed totalSteps created
        )

        #(processed, created)
    )

    fn pointWithinBoundsXY pointXY boundsValue =
    (
        pointXY.x >= boundsValue[1].x and pointXY.x <= boundsValue[2].x and pointXY.y >= boundsValue[1].y and pointXY.y <= boundsValue[2].y
    )

    fn getNearestSupportTop pointXY primarySupportBounds maxHeight =
    (
        local bestTop = undefined

        for supportBounds in primarySupportBounds do
        (
            if pointWithinBoundsXY pointXY supportBounds and supportBounds[2].z <= (maxHeight + 0.001) then
            (
                if bestTop == undefined or supportBounds[2].z > bestTop do bestTop = supportBounds[2].z
            )
        )

        bestTop
    )

    fn runSecondaryPlacement secondaryTemplate secondarySize secondaryCornerOffsets secondaryTargetCount paddedTempleBounds raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds totalSteps processedCount createdCount =
    (
        local processed = processedCount
        local created = createdCount
        local placedSecondary = 0
        local maxAttempts = secondaryTargetCount * supportSearchSpinner.value
        local halfSize = secondarySize * 0.5

        while placedSecondary < secondaryTargetCount and processed < (processedCount + maxAttempts) and not fillCancelled do
        (
            local sampleX = random (paddedTempleBounds[1].x + halfSize.x) (paddedTempleBounds[2].x - halfSize.x)
            local sampleY = random (paddedTempleBounds[1].y + halfSize.y) (paddedTempleBounds[2].y - halfSize.y)
            local supportTop = getNearestSupportTop [sampleX, sampleY, 0] primarySupportBounds paddedTempleBounds[2].z

            if supportTop != undefined then
            (
                local centerZ = supportTop + halfSize.z
                local targetCenter = [sampleX, sampleY, centerZ]
                local yawAngle = if (random 0 1) == 0 then 0.0 else 90.0

                if tryPlaceBlock secondaryTemplate targetCenter yawAngle secondaryCornerOffsets raycastTarget templeBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds false then
                (
                    placedSecondary += 1
                    created += 1
                )
            )

            processed += 1
            if (mod processed 10) == 0 or processed == totalSteps do updateProgress processed totalSteps created
        )

        #(processed, created, placedSecondary)
    )

    fn estimateTotalSteps paddedTempleBounds primarySize secondaryTargetCount =
    (
        local sliceCount = getAxisSampleCount paddedTempleBounds[1].z paddedTempleBounds[2].z primarySize.z
        local xRayCount = getAxisSampleCount paddedTempleBounds[1].y paddedTempleBounds[2].y primarySize.y
        local secondarySteps = secondaryTargetCount * supportSearchSpinner.value

        (sliceCount * xRayCount) + secondarySteps
    )

    fn runTempleSliceFill temple raycastTarget baseTempleBounds fillBounds rayBounds primaryTemplate secondaryTemplate =
    (
        local primarySize = getBrickSize primaryTemplate
        local primaryCornerOffsets = getCenteredCornerOffsets primaryTemplate
        local secondarySource = if secondaryTemplate != undefined then secondaryTemplate else primaryTemplate
        local secondarySize = getBrickSize secondarySource
        local secondaryCornerOffsets = getCenteredCornerOffsets secondarySource
        local occupancyCellSize = amax 0.5 (amin primarySize.x (amin primarySize.y (amin primarySize.z (amin secondarySize.x (amin secondarySize.y secondarySize.z)))))
        local occupancyOrigin = fillBounds[1] - [occupancyCellSize, occupancyCellSize, occupancyCellSize]
        local occupiedCells = dotNetObject "System.Collections.Hashtable"
        local placedLookup = #()
        local placedBounds = #()
        local primarySupportBounds = #()
        local totalSteps = estimateTotalSteps fillBounds primarySize secondaryCountSpinner.value
        local processed = 0
        local created = 0
        local sliceCount = getAxisSampleCount fillBounds[1].z fillBounds[2].z primarySize.z
        local primarySummary = 0
        local secondarySummary = 0

        placementDebugLogsRemaining = 16
        rayDebugLogsRemaining = 24
        rejectionDebugLogsRemaining = 24

        debugLog "----- Temple Slice Fill Start -----"
        debugBounds "Temple bounds" baseTempleBounds
        debugBounds "Fill bounds" fillBounds
        debugBounds "Ray bounds" rayBounds
        debugLog ("Internal ray-start padding=" + internalRayStartPadding as string + "m")
        debugLog ("Primary size=" + primarySize as string + " secondary size=" + secondarySize as string + " occupancyCell=" + occupancyCellSize as string)
        debugLog ("Slices=" + sliceCount as string + " xRaysPerSlice=" + (getAxisSampleCount fillBounds[1].y fillBounds[2].y primarySize.y) as string + " secondaryTarget=" + secondaryCountSpinner.value as string)

        for sliceIndex = 0 to (sliceCount - 1) while not fillCancelled do
        (
            local sliceZ = getAxisSamplePosition sliceIndex fillBounds[1].z primarySize.z
            local xPassResult = processAxisRays #x fillBounds rayBounds sliceZ primaryTemplate primarySize primaryCornerOffsets 0.0 raycastTarget baseTempleBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds totalSteps processed created
            processed = xPassResult[1]
            created = xPassResult[2]
        )

        primarySummary = primarySupportBounds.count

        if secondaryCountSpinner.value > 0 and not fillCancelled then
        (
            local secondaryResult = runSecondaryPlacement secondarySource secondarySize secondaryCornerOffsets secondaryCountSpinner.value fillBounds raycastTarget baseTempleBounds occupiedCells occupancyOrigin occupancyCellSize placedBounds placedLookup primarySupportBounds totalSteps processed created
            processed = secondaryResult[1]
            created = secondaryResult[2]
            secondarySummary = secondaryResult[3]
        )

        updateProgress totalSteps totalSteps created
        debugLog ("Fill complete. Total=" + created as string + " primary=" + primarySummary as string + " secondary=" + secondarySummary as string + " stored=" + placedLookup.count as string)
        debugLog "----- Temple Slice Fill End -----"

        #(created, primarySummary, secondarySummary, placedLookup.count)
    )

    on pickTemple pressed do
    (
        templeMesh = pickObject()
        if templeMesh != undefined do debugLog ("Picked temple: " + templeMesh.name)
    )

    on pickPrimaryBrick pressed do
    (
        primaryBrick = pickObject()
        if primaryBrick != undefined do debugLog ("Picked primary brick: " + primaryBrick.name + " size=" + (getBrickSize primaryBrick) as string)
    )

    on pickSecondaryBrick pressed do
    (
        secondaryBrick = pickObject()
        if secondaryBrick != undefined do debugLog ("Picked secondary brick: " + secondaryBrick.name + " size=" + (getBrickSize secondaryBrick) as string)
    )

    on runFill pressed do
    (
        if templeMesh != undefined and primaryBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local fillBounds = templeBounds
            local raycastBounds = getRayStartBounds templeBounds
            local snapshotNode = createTempleSnapshot templeMesh
            local primaryTemplate = createPlacementTemplate primaryBrick "TemplePrimaryTemplate"
            local secondaryTemplate = if secondaryBrick != undefined then createPlacementTemplate secondaryBrick "TempleSecondaryTemplate" else undefined

            if snapshotNode == undefined or primaryTemplate == undefined then
            (
                messageBox "Unable to build the required snapshot or placement template."
                resetProgressState "Idle"
                deleteNodeSafe snapshotNode
                deleteNodeSafe primaryTemplate
                deleteNodeSafe secondaryTemplate
            )
            else
            (
                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Running slice fill..."

                local fillResult = runTempleSliceFill templeMesh snapshotNode templeBounds fillBounds raycastBounds primaryTemplate secondaryTemplate

                fillStatus.text = ("Fill complete. Total=" + fillResult[1] as string + " Primary=" + fillResult[2] as string + " Secondary=" + fillResult[3] as string)

                deleteNodeSafe snapshotNode
                deleteNodeSafe primaryTemplate
                deleteNodeSafe secondaryTemplate
                runFill.enabled = true
            )
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh and primary brick first."
        )
    )
)

createDialog voxelFillTempleSliceUI width:420 height:560