try(destroyDialog voxelFillRaytraceUI)catch()

rollout voxelFillRaytraceUI "Temple Voxel Fill Tool (Raytrace Refined)"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"

    groupBox optionsGroup "Options" width:230 height:78
    checkbox refineBoundaryCheck "Refine Boundary With Medium" checked:true
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48

    groupBox debugGroup "Debug" width:230 height:72
    checkbox debugCheck "Listener Debug" checked:true
    checkbox debugSamplesCheck "Log Sample Decisions" checked:false

    button runFill "Run Raytrace Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn debugLog messageText =
    (
        if debugCheck.checked do format "[VoxelFillRay] %\n" messageText
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
                snapshotNode.name = uniqueName "RaytraceFillTarget"
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

    fn classifyRegion regionMin regionMax raycastTarget templeBounds =
    (
        local samplePoints = getBoundsSamplePoints regionMin regionMax
        local insideCount = 0
        local outsideCount = 0
        local sampleTotal = samplePoints.count

        for samplePoint in samplePoints do
        (
            if evaluatePointInMesh samplePoint raycastTarget templeBounds then insideCount += 1 else outsideCount += 1
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

    fn applyPlacement newBrick sourceBrick =
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

    fn getAxisSampleCount axisMin axisMax stepSize =
    (
        amax 1 ((ceil ((axisMax - axisMin) / stepSize)) as integer)
    )

    fn getAxisSamplePosition sampleIndex axisMin stepSize =
    (
        axisMin + ((sampleIndex as float + 0.5) * stepSize)
    )

    fn makeMediumKey position templeMin mediumSize =
    (
        local cellX = (floor ((position.x - templeMin.x) / mediumSize.x)) as integer
        local cellY = (floor ((position.y - templeMin.y) / mediumSize.y)) as integer
        local cellZ = (floor ((position.z - templeMin.z) / mediumSize.z)) as integer

        (cellX as string) + "|" + (cellY as string) + "|" + (cellZ as string)
    )

    fn estimateTotalSteps templeBounds bigSize mediumSize useMedium =
    (
        local bigCountX = getAxisSampleCount templeBounds[1].x templeBounds[2].x bigSize.x
        local bigCountY = getAxisSampleCount templeBounds[1].y templeBounds[2].y bigSize.y
        local bigCountZ = getAxisSampleCount templeBounds[1].z templeBounds[2].z bigSize.z
        local bigSteps = bigCountX * bigCountY * bigCountZ

        if not useMedium then return bigSteps

        local refineFactor = amax 1 (((bigSize.x / mediumSize.x) as integer) * ((bigSize.y / mediumSize.y) as integer) * ((bigSize.z / mediumSize.z) as integer))
        bigSteps + (bigSteps * refineFactor)
    )

    fn runRaytraceFill temple raycastTarget templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps =
    (
        local boundaryRegions = #()
        local mediumOccupied = dotNetObject "System.Collections.Hashtable"
        local created = 0
        local processed = 0
        local bigCreated = 0
        local mediumCreated = 0
        local bigCountX = getAxisSampleCount templeBounds[1].x templeBounds[2].x bigSize.x
        local bigCountY = getAxisSampleCount templeBounds[1].y templeBounds[2].y bigSize.y
        local bigCountZ = getAxisSampleCount templeBounds[1].z templeBounds[2].z bigSize.z

        debugLog ("Large pass start: counts=" + #(bigCountX, bigCountY, bigCountZ) as string + " bigSize=" + bigSize as string)

        for xIndex = 0 to (bigCountX - 1) while not fillCancelled do
        (
            local centerX = getAxisSamplePosition xIndex templeBounds[1].x bigSize.x

            for yIndex = 0 to (bigCountY - 1) while not fillCancelled do
            (
                local centerY = getAxisSamplePosition yIndex templeBounds[1].y bigSize.y

                for zIndex = 0 to (bigCountZ - 1) while not fillCancelled do
                (
                    local centerZ = getAxisSamplePosition zIndex templeBounds[1].z bigSize.z
                    local regionCenter = [centerX, centerY, centerZ]
                    local regionMin = regionCenter - (bigSize * 0.5)
                    local regionMax = regionCenter + (bigSize * 0.5)
                    local classification = classifyRegion regionMin regionMax raycastTarget templeBounds

                    processed += 1

                    if debugSamplesCheck.checked and classification[1] != #outside do debugLog ("Large sample " + #(xIndex, yIndex, zIndex) as string + " state=" + classification[1] as string + " in=" + classification[2] as string + " out=" + classification[3] as string)

                    case classification[1] of
                    (
                        #inside:
                        (
                            local newBrick = instance bigBrick
                            newBrick.position = regionCenter
                            applyPlacement newBrick bigBrick
                            created += 1
                            bigCreated += 1
                        )
                        #boundary:
                        (
                            if refineBoundaryCheck.checked and mediumBrick != undefined do append boundaryRegions #(regionMin, regionMax)
                        )
                        default:
                        (
                        )
                    )

                    if (mod processed 50) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                )
            )
        )

        debugLog ("Large pass end: created=" + bigCreated as string + " boundary regions=" + boundaryRegions.count as string + " processed=" + processed as string)

        if refineBoundaryCheck.checked and mediumBrick != undefined then
        (
            debugLog ("Medium pass start: boundary regions=" + boundaryRegions.count as string + " mediumSize=" + mediumSize as string)

            for boundaryRegion in boundaryRegions while not fillCancelled do
            (
                local regionMin = boundaryRegion[1]
                local regionMax = boundaryRegion[2]
                local mediumCountX = getAxisSampleCount regionMin.x regionMax.x mediumSize.x
                local mediumCountY = getAxisSampleCount regionMin.y regionMax.y mediumSize.y
                local mediumCountZ = getAxisSampleCount regionMin.z regionMax.z mediumSize.z

                for xIndex = 0 to (mediumCountX - 1) while not fillCancelled do
                (
                    local mediumCenterX = getAxisSamplePosition xIndex regionMin.x mediumSize.x

                    for yIndex = 0 to (mediumCountY - 1) while not fillCancelled do
                    (
                        local mediumCenterY = getAxisSamplePosition yIndex regionMin.y mediumSize.y

                        for zIndex = 0 to (mediumCountZ - 1) while not fillCancelled do
                        (
                            local mediumCenterZ = getAxisSamplePosition zIndex regionMin.z mediumSize.z
                            local mediumCenter = [mediumCenterX, mediumCenterY, mediumCenterZ]
                            local mediumRegionMin = mediumCenter - (mediumSize * 0.5)
                            local mediumRegionMax = mediumCenter + (mediumSize * 0.5)
                            local mediumKey = makeMediumKey mediumCenter templeBounds[1] mediumSize
                            local mediumClassification = undefined

                            processed += 1

                            if not (mediumOccupied.ContainsKey mediumKey) then
                            (
                                mediumClassification = classifyRegion mediumRegionMin mediumRegionMax raycastTarget templeBounds

                                if debugSamplesCheck.checked and mediumClassification[1] == #inside do debugLog ("Medium sample " + mediumKey + " state=inside")

                                if mediumClassification[1] == #inside then
                                (
                                    local newMediumBrick = instance mediumBrick
                                    newMediumBrick.position = mediumCenter
                                    applyPlacement newMediumBrick mediumBrick
                                    mediumOccupied.Add mediumKey true
                                    created += 1
                                    mediumCreated += 1
                                )
                            )

                            if (mod processed 50) == 0 or processed == totalSteps do updateProgress processed totalSteps created
                        )
                    )
                )
            )
        )

        debugLog ("Medium pass end: created=" + mediumCreated as string + " processed=" + processed as string)
        #(created, processed, bigCreated, mediumCreated, boundaryRegions.count)
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
        if templeMesh != undefined and bigBrick != undefined then
        (
            local templeBounds = getTempleBounds templeMesh
            local bigSize = getBrickSize bigBrick
            local useMedium = refineBoundaryCheck.checked and mediumBrick != undefined
            local mediumSize = if useMedium then getBrickSize mediumBrick else [1,1,1]
            local totalSteps = estimateTotalSteps templeBounds bigSize mediumSize useMedium
            local snapshotNode = createTempleSnapshot templeMesh

            if snapshotNode == undefined then
            (
                messageBox "Unable to snapshot the temple mesh."
                resetProgressState "Idle"
            )
            else
            (
                local mediumSummary = if useMedium then (" mediumSize=" + mediumSize as string) else " medium=disabled"

                fillCancelled = false
                runFill.enabled = false
                resetProgressState "Running raytrace fill..."

                debugLog "----- Raytrace Fill Start -----"
                debugLog ("Temple bounds min=" + templeBounds[1] as string + " max=" + templeBounds[2] as string)
                debugLog ("Estimated steps=" + totalSteps as string + " bigSize=" + bigSize as string + mediumSummary)

                local fillResult = runRaytraceFill templeMesh snapshotNode templeBounds bigBrick bigSize mediumBrick mediumSize totalSteps
                updateProgress fillResult[2] totalSteps fillResult[1]
                fillStatus.text = ("Fill complete. Total=" + fillResult[1] as string + " Big=" + fillResult[3] as string + " Medium=" + fillResult[4] as string)

                debugLog ("Fill complete. Total=" + fillResult[1] as string + " big=" + fillResult[3] as string + " medium=" + fillResult[4] as string + " boundaries=" + fillResult[5] as string + " processed=" + fillResult[2] as string)
                debugLog "----- Raytrace Fill End -----"

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

createDialog voxelFillRaytraceUI width:380 height:430