-- Input and output folders
inputFolder  = @"D:\shared\3dModels\groups\"
outputFolder = @"D:\shared\3dModels\objects\"

if doesFileExist outputFolder == false do makeDir outputFolder

fbxFiles = getFiles (inputFolder + "*.fbx")
format "Found % FBX files.\n" fbxFiles.count

for f in fbxFiles do
(
    local fileNameOnly = getFilenameFile f
    format "\nProcessing: %\n" fileNameOnly
    
    resetMaxFile #noPrompt
    
    try(importFile f #noPrompt using:FBXIMP) catch
    (
        format "ERROR: Import failed: %\n" fileNameOnly
        continue
    )
    
    if geometry.count == 0 then
    (
        format "No geometry in: %\n" fileNameOnly
        continue
    )
    
    local obj = geometry[1]
    convertToPoly obj
    
    local counter = 1
    
    while (polyOp.getNumFaces obj) > 0 do
    (
        local elementFaces = polyOp.getElementsUsingFace obj #{1}
        local geometryBeforeDetach = for node in geometry collect node
        
        -- Detach into new node
        polyOp.setFaceSelection obj elementFaces
        polyOp.detachFaces obj elementFaces delete:true asNode:true
        
        local newObj = undefined
        for node in geometry where (findItem geometryBeforeDetach node) == 0 do
        (
            newObj = node
            exit
        )
        
        if newObj == undefined and selection.count > 0 do newObj = selection[1]
        
        if isValidNode newObj then
        (
            -- Pivot to the detached mesh bottom-center in world space
            local bb = nodeGetBoundingBox newObj (matrix3 1)
            local minPt = bb[1]
            local maxPt = bb[2]
            local bottomCenter = point3 ((minPt.x + maxPt.x) / 2.0) ((minPt.y + maxPt.y) / 2.0) minPt.z
            in coordsys world (newObj.pivot = bottomCenter)
            
            -- Move object so pivot is at world origin
            newObj.position = [0,0,0]
            
            -- Rename
            newObj.name = fileNameOnly + "_object" + (formattedPrint counter format:"02d")
            
            -- Export FBX
            local outFile = outputFolder + newObj.name + ".fbx"
            select newObj
            try (exportFile outFile #noPrompt selectedOnly:true using:FBXEXP) catch ()
            
            format "Exported: %\n" newObj.name
            counter += 1
        )
    )
)
messageBox "Done splitting and exporting FBX elements." title:"Process Complete"