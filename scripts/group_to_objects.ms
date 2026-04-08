-- Input and output folders
inputFolder  = @"C:\DB\3dModels\AIModel_groups\"
outputFolder = @"C:\DB\3dModels\AIModel_objects\"

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
    
    -- Detach all elements at once
    local numFaces = polyOp.getNumFaces obj
    local allFaces = #{1..numFaces}
    local processed = #{}
    
    while (allFaces - processed).count > 0 do
    (
        -- Pick one unprocessed face
        local firstFace = (allFaces - processed)[1]
        local elementFaces = polyOp.getElementsUsingFace obj #{firstFace}
        processed += elementFaces
        
        -- Detach into new node
        polyOp.setFaceSelection obj elementFaces
        polyOp.detachFaces obj elementFaces delete:true asNode:true
        local newObj = selection[1]
        
        if isValidNode newObj then
        (
            -- Pivot to bottom center
            local bb = nodeGetBoundingBox newObj newObj.transform
            local minPt = bb[1]
            local maxPt = bb[2]
            local centerX = (minPt.x + maxPt.x)/2
            local centerY = (minPt.y + maxPt.y)/2
            local bottomZ = minPt.z
            in coordsys local newObj.pivot = [centerX, centerY, bottomZ]
            
            -- Move object so pivot is at world origin
            newObj.position = [0,0,0]
            
            -- Rename
            newObj.name = fileNameOnly + "_object" + formattedPrint counter format:"02d"
            
            -- Export FBX
            local outFile = outputFolder + newObj.name + ".fbx"
            try(exportFile outFile #noPrompt selectedOnly:true using:FBXEXP) catch()
            
            format "Exported: %\n" newObj.name
            counter += 1
        )
    )
)
messageBox "Done splitting and exporting FBX elements." title:"Process Complete"