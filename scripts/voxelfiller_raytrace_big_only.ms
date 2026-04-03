try(destroyDialog voxelFillRaytraceBigOnlyUI)catch()

rollout voxelFillRaytraceBigOnlyUI "Temple Voxel Fill Tool (Big Blocks Only)"
(
    local templeMesh
    local bigBrick
    local fillCancelled = false
    local placementDebugLogsRemaining = 0

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"

    groupBox debugGroup "Debug" width:230 height:72
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Rejections" checked:false

    button runFill "Run Big Block Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillBigOnly] %\n" messageText
    )

    fn debugBounds prefix boundsValue =
    (
        debugLog (prefix + " min=" + boundsValue[1] as string + " max=" + boundsValue[2] as string)
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

    fn getBrickCornerOffsets brickObj =
    (
        local bounds = getBrickWorldBounds brickObj
        local center = (bounds[1] + bounds[2]) * 0.5

        #(
            [bounds[1].x, bounds[1].y, bounds[1].z] - center,
            [bounds[2].x, bounds[1].y, bounds[1].z] - center,
            [bounds[1].x, bounds[2].y, bounds[1].z] - center,
            [bounds[2].x, bounds[2].y, bounds[1].z] - center,
            [bounds[1].x, bounds[1].y, bounds[2].z] - center,
            [bounds[2].x, bounds[1].y, bounds[2].z] - center,
            [bounds[1].x, bounds[2].y, bounds[2].z] - center,
            [bounds[2].x, bounds[2].y, bounds[2].z] - center
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
                snapshotNode.name = uniqueName "RaytraceBigOnlyTarget"
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

    fn updateProgress processed totalSteps createdCount =
    (
        local progressValue = if totalSteps > 0 then ((processed as float / totalSteps as float) * 100.0) else 0.0
        fillProgress.value = amin 100 (progressValue as integer)
        fillStatus.text = ("Cells: " + processed as string + " / " + totalSteps as string + " | Bricks: " + createdCount as string)
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

    fn placementCornersInside targetCenter cornerOffsets raycastTarget templeBounds =
    (
        for cornerOffset in cornerOffsets do
        (
            local cornerPoint = targetCenter + cornerOffset
            if not (evaluatePointInMesh cornerPoint raycastTarget templeBounds) do return false
        )

        true
    )

    fn getAxisSampleCount axisMin axisMax stepSize =
    (
        amax 1 ((floor ((axisMax - axisMin) / stepSize)) as integer)
    )

    fn getAxisSamplePosition sampleIndex axisMin halfStep stepSize =
    (
        axisMin + halfStep + ((sampleIndex as float) * stepSize)
    )

    fn logPlacementSample sourceBrick targetCenter cornerOffsets newBrick =
    (
        if placementDebugLogsRemaining > 0 then
        (
            local newBounds = nodeGetBoundingBox newBrick (matrix3 1)
            local newBoundsCenter = (newBounds[1] + newBounds[2]) * 0.5

            debugLog ("Placement source=" + sourceBrick.name + " sourcePos=" + sourceBrick.position as string + " targetCenter=" + targetCenter as string + " finalPos=" + newBrick.position as string)
            debugBounds "Placement newBounds" newBounds
            debugLog ("Placement newBoundsCenter=" + newBoundsCenter as string + " centerDelta=" + (newBoundsCenter - targetCenter) as string)
            debugLog ("Placement firstCorner=" + (targetCenter + cornerOffsets[1]) as string + " lastCorner=" + (targetCenter + cornerOffsets[8]) as string)

            placementDebugLogsRemaining -= 1
        )
    )

    fn runBigBlockFill temple raycastTarget templeBounds sourceBrick brickSize cornerOffsets totalSteps =
    (
        local created = 0
        local processed = 0
        local countX = getAxisSampleCount templeBounds[1].x templeBounds[2].x brickSize.x
        local countY = getAxisSampleCount templeBounds[1].y templeBounds[2].y brickSize.y
        local countZ = getAxisSampleCount templeBounds[1].z templeBounds[2].z brickSize.z
        local halfSize = brickSize * 0.5
        local centerOffset = getBrickCenterOffset sourceBrick

        placementDebugLogsRemaining = 12

        debugLog ("Array counts=" + #(countX, countY, countZ) as string + " brickSize=" + brickSize as string + " centerOffset=" + centerOffset as string)

        for xIndex = 0 to (countX - 1) while not fillCancelled do
        (
            local centerX = getAxisSamplePosition xIndex templeBounds[1].x halfSize.x brickSize.x

            for yIndex = 0 to (countY - 1) while not fillCancelled do
            (
                local centerY = getAxisSamplePosition yIndex templeBounds[1].y halfSize.y brickSize.y

                for zIndex = 0 to (countZ - 1) while not fillCancelled do
                (
                    local centerZ = getAxisSamplePosition zIndex templeBounds[1].z halfSize.z brickSize.z
                    local targetCenter = [centerX, centerY, centerZ]

                    processed += 1

                    if placementCornersInside targetCenter cornerOffsets raycastTarget templeBounds then
                    (
                        local newBrick = instance sourceBrick
                        newBrick.rotation = sourceBrick.rotation
                        newBrick.scale = sourceBrick.scale
                        newBrick.position = targetCenter - centerOffset
                        newBrick.material = sourceBrick.material

                        logPlacementSample sourceBrick targetCenter cornerOffsets newBrick

                        created += 1
                    )
                    else if debugSamplesCheck.checked and placementDebugLogsRemaining > 0 do
                    (
                        debugLog ("Rejected cell=" + #(xIndex, yIndex, zIndex) as string + " targetCenter=" + targetCenter as string)
                    )

                    if (mod processed 25) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

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
        if bigBrick != undefined do
        (
            debugLog ("Picked big brick: " + bigBrick.name + " size=" + (getBrickSize bigBrick) as string)
            debugBounds "Picked big brick bounds" (getBrickWorldBounds bigBrick)
        )
    )

    on runFill pressed do
    (
        if templeMesh != undefined and bigBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local brickSize = getBrickSize bigBrick
            local cornerOffsets = getBrickCornerOffsets bigBrick
            local countX = getAxisSampleCount templeBounds[1].x templeBounds[2].x brickSize.x
            local countY = getAxisSampleCount templeBounds[1].y templeBounds[2].y brickSize.y
            local countZ = getAxisSampleCount templeBounds[1].z templeBounds[2].z brickSize.z
            local totalSteps = countX * countY * countZ
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
                resetProgressState "Running big block fill..."

                debugLog "----- Big Block Fill Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Brick size=" + brickSize as string + " totalSteps=" + totalSteps as string)

                local fillResult = runBigBlockFill templeMesh snapshotNode templeBounds bigBrick brickSize cornerOffsets totalSteps
                updateProgress totalSteps totalSteps fillResult[1]
                fillStatus.text = ("Fill complete. Total=" + fillResult[1] as string)

                debugLog ("Fill complete. Total=" + fillResult[1] as string + " processed=" + fillResult[2] as string)
                debugLog "----- Big Block Fill End -----"

                deleteSnapshot snapshotNode
                runFill.enabled = true
            )
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh and big brick mesh first!"
        )
    )
)

createDialog voxelFillRaytraceBigOnlyUI width:380 height:320