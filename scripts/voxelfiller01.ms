rollout voxelFillUI "Temple Voxel Fill Tool"
(
    local templeMesh
    local bigBrick
    local mediumBrick
    local fillCancelled = false

    button pickTemple "Pick Temple Mesh"
    button pickBigBrick "Pick Big Brick Mesh"
    button pickMediumBrick "Pick Medium Brick Mesh"
    groupBox variationGroup "Variation" width:188 height:120
    checkbox randomRotationCheck "Random Z Rotation" checked:true
    spinner rotMinSpinner "Min Rot" range:[0,0,360] type:#integer fieldwidth:48
    spinner rotMaxSpinner "Max Rot" range:[0,180,360] type:#integer fieldwidth:48
    checkbox randomScaleCheck "Random Scale %" checked:false
    spinner scaleMinSpinner "Min Scale" range:[10,90,300] type:#integer fieldwidth:48
    spinner scaleMaxSpinner "Max Scale" range:[10,110,300] type:#integer fieldwidth:48
    checkbox materialVariationCheck "Material Tint Variation" checked:false
    spinner materialTintSpinner "Tint %" range:[0,8,100] type:#integer fieldwidth:48
    button runFill "Run Voxel Fill"
    progressBar fillProgress "" color:(color 70 150 90)
    label fillStatus "Idle"

    fn getBrickSize brickObj =
    (
        local bb = nodeGetBoundingBox brickObj brickObj.transform
        bb[2] - bb[1] -- returns size vector
    )

    fn getTempleBounds temple =
    (
        nodeGetBoundingBox temple (matrix3 1)
    )

    fn getAxisSampleCount minValue maxValue stepSize =
    (
        local axisLength = amax 0.0 ((maxValue - minValue) as float)
        amax 1 (ceil (axisLength / stepSize))
    )

    fn getAxisSamplePosition sampleIndex minValue maxValue stepSize sampleCount =
    (
        if sampleCount <= 1 then
        (
            (minValue + maxValue) * 0.5
        )
        else
        (
            minValue + (stepSize * 0.5) + (sampleIndex * stepSize)
        )
    )

    fn estimateSampleCount temple voxelSize =
    (
        local bounds = getTempleBounds temple
        local bbMin = bounds[1]
        local bbMax = bounds[2]
        local stepX = amax 0.001 (abs voxelSize.x)
        local stepY = amax 0.001 (abs voxelSize.y)
        local stepZ = amax 0.001 (abs voxelSize.z)
        local xCount = getAxisSampleCount bbMin.x bbMax.x stepX
        local yCount = getAxisSampleCount bbMin.y bbMax.y stepY
        local zCount = getAxisSampleCount bbMin.z bbMax.z stepZ

        xCount * yCount * zCount
    )

    fn countRayHits obj rayOrigin rayDir maxHits:128 epsilon:0.5 =
    (
        local hitCount = 0
        local normalizedDir = normalize rayDir
        local sampleOrigin = rayOrigin
        local hit = intersectRay obj (ray sampleOrigin normalizedDir)

        while hit != undefined and hitCount < maxHits do
        (
            hitCount += 1
            sampleOrigin = hit.pos + (normalizedDir * epsilon)
            hit = intersectRay obj (ray sampleOrigin normalizedDir)
        )

        hitCount
    )

    fn pointInMesh p obj =
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
        local surfaceBias = 0.1

        for dir in directions do
        (
            local hitCount = countRayHits obj (p - (dir * surfaceBias)) dir
            if (mod hitCount 2) == 1 do insideVotes += 1
        )

        insideVotes >= voteThreshold
    )

    fn clampColorChannel value =
    (
        amin 255 (amax 0 value)
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
                (clampColorChannel ((baseDiffuse.r + tintOffset) as integer)) \
                (clampColorChannel ((baseDiffuse.g + tintOffset) as integer)) \
                (clampColorChannel ((baseDiffuse.b + tintOffset) as integer))
        )

        newBrick.material = brickMaterial
        true
    )

    fn applyPlacementVariation newBrick sourceBrick =
    (
        local baseRotation = sourceBrick.rotation
        local baseScale = sourceBrick.scale

        newBrick.rotation = baseRotation
        newBrick.scale = baseScale

        if randomRotationCheck.checked do
        (
            local minRotation = amin rotMinSpinner.value rotMaxSpinner.value
            local maxRotation = amax rotMinSpinner.value rotMaxSpinner.value
            local zRotation = random minRotation maxRotation
            newBrick.rotation = baseRotation * (angleaxis zRotation [0,0,1])
        )

        if randomScaleCheck.checked do
        (
            local minScale = amin scaleMinSpinner.value scaleMaxSpinner.value
            local maxScale = amax scaleMinSpinner.value scaleMaxSpinner.value
            local scaleMultiplier = (random minScale maxScale) / 100.0
            newBrick.scale = [baseScale.x * scaleMultiplier, baseScale.y * scaleMultiplier, baseScale.z * scaleMultiplier]
        )

        if materialVariationCheck.checked then
        (
            applyMaterialVariation newBrick sourceBrick.material materialTintSpinner.value
        )
        else
        (
            newBrick.material = sourceBrick.material
        )
    )

    fn updateProgress processed totalSamples createdCount =
    (
        local progressValue = if totalSamples > 0 then ((processed as float / totalSamples as float) * 100.0) else 0.0
        fillProgress.value = progressValue as integer
        fillStatus.text = ("Samples: " + processed as string + " / " + totalSamples as string + " | Bricks: " + createdCount as string)
        windows.processPostedMessages()
    )

    fn fillMeshWithBricks temple brickObj voxelSize totalSamples processedCount createdCount =
    (
        local bounds = getTempleBounds temple
        local bbMin = bounds[1]
        local bbMax = bounds[2]
        local stepX = amax 0.001 (abs voxelSize.x)
        local stepY = amax 0.001 (abs voxelSize.y)
        local stepZ = amax 0.001 (abs voxelSize.z)
        local xCount = getAxisSampleCount bbMin.x bbMax.x stepX
        local yCount = getAxisSampleCount bbMin.y bbMax.y stepY
        local zCount = getAxisSampleCount bbMin.z bbMax.z stepZ
        local processed = processedCount
        local created = createdCount
        local updateInterval = amax 1 ((totalSamples / 150) as integer)

        for xIndex = 0 to (xCount - 1) while not fillCancelled do
        (
            local x = getAxisSamplePosition xIndex bbMin.x bbMax.x stepX xCount

            for yIndex = 0 to (yCount - 1) while not fillCancelled do
            (
                local y = getAxisSamplePosition yIndex bbMin.y bbMax.y stepY yCount

                for zIndex = 0 to (zCount - 1) while not fillCancelled do
                (
                    local z = getAxisSamplePosition zIndex bbMin.z bbMax.z stepZ zCount
                    processed += 1
                    local p = [x,y,z]
                    if pointInMesh p temple then
                    (
                        local newBrick = instance brickObj
                        newBrick.position = p
                        applyPlacementVariation newBrick brickObj
                        created += 1
                    )

                    if (mod processed updateInterval) == 0 or processed == totalSamples do
                    (
                        updateProgress processed totalSamples created
                    )
                )
            )
        )

        #(processed, created)
    )

    fn collectFillJobs =
    (
        -- Jobs are collected in one place so a fine-detail brick slot can be added later.
        local jobs = #()
        if bigBrick != undefined do append jobs #(bigBrick, getBrickSize bigBrick)
        if mediumBrick != undefined do append jobs #(mediumBrick, getBrickSize mediumBrick)
        jobs
    )

    fn resetProgressState messageText =
    (
        fillProgress.value = 0
        fillStatus.text = messageText
    )

    on pickTemple pressed do templeMesh = pickObject()
    on pickBigBrick pressed do bigBrick = pickObject()
    on pickMediumBrick pressed do mediumBrick = pickObject()

    on runFill pressed do
    (
        local fillJobs = collectFillJobs()

        if templeMesh != undefined and fillJobs.count > 0 then
        (
            local totalSamples = 0
            local processed = 0
            local created = 0

            for fillJob in fillJobs do totalSamples += estimateSampleCount templeMesh fillJob[2]

            fillCancelled = false
            runFill.enabled = false
            resetProgressState "Preparing fill..."

            for fillJob in fillJobs while not fillCancelled do
            (
                local fillResult = fillMeshWithBricks templeMesh fillJob[1] fillJob[2] totalSamples processed created
                processed = fillResult[1]
                created = fillResult[2]
            )

            updateProgress processed totalSamples created
            fillStatus.text = ("Fill complete. Created " + created as string + " bricks.")
            runFill.enabled = true
        )
        else
        (
            resetProgressState "Idle"
            messageBox "Please pick the temple mesh and at least one brick mesh first!"
        )
    )
)

createDialog voxelFillUI width:280 height:440